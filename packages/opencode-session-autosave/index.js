// opencode-session-autosave -- automatic background session checkpoints.
// No model call, no quota, never blocks a turn. Manual /snapshot-session stays
// the intent-based layer (milestones); this plugin is the time-based safety net.
//
// Triggers (all fire-and-forget, best effort):
//   session.idle    -> autosave, at most every autoMin per session (default 15, live 5)
//   session.error   -> emergency save, at most every emergencyMin per session (default 10, live 5)
//   pre-compaction  -> always (full fidelity before lossy summarization)
//   session.compacted -> post-compaction safety copy
// Backups: %USERPROFILE%\.local\share\opencode\backups\opencode-{auto,emergency,precompact,postcompact}-<session>-*.json
// Retention (enforced in autosave-worker.ps1 delete-after-write): auto keep-3-per-session + 7d,
//   emergency keep-2-per-session + 7d; precompact/postcompact/snapshot-session/rescue uncapped.
// Log: same dir, autosave.log. Master toggle: OPENCODE_AUTOSAVE=0 disables everything;
//   an empty AUTOSAVE_OFF file in the backups dir also pauses. Tuning:
//   autosave-config.json {"autoMin":N,"emergencyMin":N} is live, no restart needed.
// Launch: spawn powershell worker with detached:false + stdio:ignore + unref.
//   detached:true was removed 2026-09-23: WindowsPowerShell 5.1 exits in ~100ms
//   code 0 without running the worker (proven matrix: detached:false STARTs +
//   exports in ~9s, detached:true never logs START). Plugin edits require an
//   opencode restart (loaded once at startup).
// Recovery: backups are opencode-export JSON snapshots, NOT auto-restored.
//   Sessions persist in opencode.db across restarts; use a backup only when a
//   session is stuck/throttled/deleted: scripts/Rescue-StuckSession.ps1 -SessionId ses_xxx
//   (re-exports, clears router pin for router sessions, copies the best
//   opencode -s <id> --fork ... command to clipboard).
import { spawn } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

const AUTO_MS = 15 * 60 * 1000;
const EMERGENCY_MS = 10 * 60 * 1000;
const CONFIG_FILE = path.join(os.homedir(), ".local", "share", "opencode", "backups", "autosave-config.json");
// Package-relative worker (sibling of this file). Older local installs used
// ~/.config/opencode/autosave-worker.ps1; the npm package ships its own copy.
const PKG_DIR = path.dirname(fileURLToPath(import.meta.url));
const WORKER = path.join(PKG_DIR, "autosave-worker.ps1");
const POWERSHELL = path.join(process.env.SystemRoot || "C:\\Windows", "System32", "WindowsPowerShell", "v1.0", "powershell.exe");

// Slash commands bundled under ./commands are self-installed (write-if-missing)
// into the global commands dir. OpenCode V1 does not extract commands from npm
// plugin packages, so the plugin does it on load (supermemory precedent).
// Existing files are never overwritten: user edits always win.
const BUNDLED_COMMANDS = ["autosave.md", "snapshot-session.md"];

function ensureCommands(client) {
  try {
    const destDir = path.join(os.homedir(), ".config", "opencode", "commands");
    fs.mkdirSync(destDir, { recursive: true });
    for (const name of BUNDLED_COMMANDS) {
      try {
        const dest = path.join(destDir, name);
        if (fs.existsSync(dest)) continue;
        const src = path.join(PKG_DIR, "commands", name);
        fs.copyFileSync(src, dest);
        PLSLog(client, "info", "autosave command installed", { name });
      } catch {
        // one command failing must not block the other
      }
    }
  } catch {
    // command install must never break a turn
  }
}

const lastAuto = new Map();
const lastEmergency = new Map();

function enabled() {
  try {
    if (fs.existsSync(path.join(os.homedir(), ".local", "share", "opencode", "backups", "AUTOSAVE_OFF"))) return false;
  } catch {
    // flag check must never break a turn
  }
  const v = (process.env.OPENCODE_AUTOSAVE || "1").toLowerCase();
  return v !== "0" && v !== "off" && v !== "false";
}

function sessionOf(input) {
  try {
    return (
      input?.event?.properties?.sessionID ||
      input?.event?.properties?.sessionId ||
      input?.properties?.sessionID ||
      input?.sessionID ||
      input?.sessionId ||
      input?.input?.sessionID ||
      null
    );
  } catch {
    return null;
  }
}

function launch(client, sessionID, kind) {
  try {
    // Fire-and-forget WITHOUT detached: detached:true makes WindowsPowerShell 5.1
    // exit in ~100ms code 0 without running the worker (proven 2026-09-23 matrix:
    // detached:false STARTs + exports in ~9s, detached:true never logs START).
    // Worker self-logs to autosave.log, so stdio is ignore; unref keeps turns non-blocking.
    const child = spawn(POWERSHELL, ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", WORKER, "-SessionId", sessionID, "-Kind", kind], {
      detached: false,
      stdio: "ignore",
      windowsHide: true,
    });
    child.on("error", (err) => PLSLog(client, "warn", "autosave spawn failed", { sessionID, kind, error: String(err) }));
    child.unref();
    PLSLog(client, "info", "autosave launched", { sessionID, kind, pid: child.pid });
  } catch (err) {
    PLSLog(client, "warn", "autosave spawn failed", { sessionID, kind, error: String(err) });
  }
}

function PLSLog(client, level, message, extra) {
  try {
    client?.app?.log({ body: { service: "session-autosave", level, message, extra: extra || {} } });
  } catch {
    // logging must never break a turn
  }
}

function readConfig() {
  // Live config, no restart needed. Invalid/missing -> defaults. Clamped to sane ranges.
  const cfg = { autoMs: AUTO_MS, emergencyMs: EMERGENCY_MS };
  try {
    const raw = JSON.parse(fs.readFileSync(CONFIG_FILE, "utf8"));
    const a = Math.round(Number(raw.autoMin));
    const e = Math.round(Number(raw.emergencyMin));
    if (Number.isFinite(a)) cfg.autoMs = Math.min(120, Math.max(2, a)) * 60 * 1000;
    if (Number.isFinite(e)) cfg.emergencyMs = Math.min(60, Math.max(2, e)) * 60 * 1000;
  } catch {
    // defaults stand
  }
  return cfg;
}

function throttled(map, key, windowMs) {
  const now = Date.now();
  if (map.size > 1000) map.clear(); // long-uptime hygiene: worst case one extra save
  const last = map.get(key) || 0;
  if (now - last < windowMs) return true;
  map.set(key, now);
  return false;
}

export const SessionAutosavePlugin = async ({ client }) => {
  try {
    PLSLog(client, "info", "session-autosave loaded", { autoMs: AUTO_MS, emergencyMs: EMERGENCY_MS });
  } catch {
    // ignore
  }
  ensureCommands(client);
  return {
    event: async (input) => {
      try {
        if (!enabled()) return;
        const cfg = readConfig();
        const type = input?.event?.type;
        const sessionID = sessionOf(input);
        if (!sessionID) return;
        if (type === "session.idle") {
          if (!throttled(lastAuto, sessionID, cfg.autoMs)) launch(client, sessionID, "auto");
        } else if (type === "session.error") {
          if (!throttled(lastEmergency, sessionID, cfg.emergencyMs)) launch(client, sessionID, "emergency");
        } else if (type === "session.compacted") {
          launch(client, sessionID, "postcompact");
        }
      } catch {
        // hooks must never throw
      }
    },
    "experimental.session.compacting": async (input, output) => {
      try {
        if (!enabled()) return;
        const sessionID = sessionOf(input) || sessionOf({ event: input });
        if (!sessionID) return;
        launch(input?.client || client, sessionID, "precompact");
        // NOTE: output untouched on purpose -- no compaction prompt changes.
      } catch {
        // hooks must never throw
      }
    },
  };
};
