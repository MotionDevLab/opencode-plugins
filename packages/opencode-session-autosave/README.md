# opencode-session-autosave

Automatic background session checkpoints for OpenCode. Time-based safety net;
manual `/snapshot-session` stays the intent-based layer (milestones).

## What it does

Fire-and-forget `opencode export` snapshots, no model call, no quota, never
blocks a turn:

| Trigger | Kind | Throttle |
|---|---|---|
| `session.idle` | `auto` | at most every 15 min per session |
| `session.error` | `emergency` | at most every 10 min per session |
| pre-compaction | `precompact` | always |
| `session.compacted` | `postcompact` | always |

Backups: `%USERPROFILE%\.local\share\opencode\backups\opencode-<kind>-<session>-<stamp>.json`.
Log: `autosave.log` in the same dir. Retention is enforced in the worker
(delete-after-write): auto keep-3-per-session + 7d, emergency keep-2 + 7d,
precompact/postcompact/snapshot/rescue uncapped.

Backups are JSON snapshots, NOT auto-restored. Sessions persist in
`opencode.db` across restarts; use a backup only when a session is
stuck/throttled/deleted.

## Install

```jsonc
// opencode.jsonc
{
  "plugin": [
    "@motiondevlab/opencode-session-autosave@0.1.0"
  ]
}
```

Then **restart OpenCode** (plugins load once at startup). The plugin logs
`session-autosave loaded` on start and self-installs the `/autosave` and
`/snapshot-session` commands (write-if-missing into
`~/.config/opencode/commands/` — your edits are never overwritten).

## Controls (no restart needed)

- `/autosave` — status + intervals + recent log lines.
- `/autosave on` / `/autosave off` — switch via the `AUTOSAVE_OFF` flag file.
- `/autosave interval auto 5` — tune via `autosave-config.json`
  (`{"autoMin":N,"emergencyMin":N}`, clamps 2–120 / 2–60).
- `OPENCODE_AUTOSAVE=0` env var also disables everything. Either off-switch wins.

## Recovery

```powershell
packages/opencode-session-autosave/scripts/Rescue-StuckSession.ps1 -SessionId ses_xxx
```

Re-exports a JSON backup, clears the router pin for router sessions, and copies
the best `opencode -s <id> --fork ...` command to the clipboard.

## Notes

- Windows worker scripts are **ASCII only** (PowerShell 5.1 misreads UTF-8
  without BOM). Keep it that way.
- The worker is resolved package-relative (sibling of `index.js`).
- Hooks never throw; the worker never throws to the caller.
