// Replaces Oh My OpenAgent 5.1.29's non-interactive-env command prefix.
// Environment values go to the spawned process through OpenCode's shell.env
// hook, so PowerShell 5.1, PowerShell 7, cmd, and Bash need no syntax changes.
// Enable with disabled_hooks: ["non-interactive-env"] in the [opencode]
// block of ~/.omo/omo.jsonc (OpenAgent 5.1.29's canonical configuration).
// Local plugins load after configured npm plugins. Restart OpenCode to load.
//
// OPENCODE V1 ONLY. V2's Bash tool ignores legacy shell.env hooks
// (anomalyco/opencode#41117); the V2 port uses ctx.shell.hook("create.before")
// and matches git on event.command directly. That port is tracked separately
// and intentionally NOT implemented here.
const gitEnvironment = Object.freeze({
  CI: "true",
  DEBIAN_FRONTEND: "noninteractive",
  GIT_TERMINAL_PROMPT: "0",
  GCM_INTERACTIVE: "never",
  HOMEBREW_NO_AUTO_UPDATE: "1",
  GIT_EDITOR: ":",
  EDITOR: ":",
  VISUAL: "",
  GIT_SEQUENCE_EDITOR: ":",
  GIT_MERGE_AUTOEDIT: "no",
  GIT_PAGER: "cat",
  PAGER: "cat",
  npm_config_yes: "true",
  PIP_NO_INPUT: "1",
  YARN_ENABLE_IMMUTABLE_INSTALLS: "false",
});

export default async function GitNonInteractiveEnvironment() {
  const pending = new Map();
  const keyFor = ({ sessionID, callID }) =>
    typeof sessionID === "string" && sessionID &&
    typeof callID === "string" && callID
      ? JSON.stringify([sessionID, callID])
      : undefined;

  return {
    "tool.execute.before": async (input, output) => {
      const key = keyFor(input);
      if (!key) return;
      // Reused call IDs must not retain an earlier Git classification.
      pending.delete(key);
      if (input.tool?.toLowerCase() !== "bash" ||
          typeof output.args?.command !== "string" ||
          !/\bgit\b/.test(output.args.command)) return;
      const now = Date.now();
      for (const [candidate, entry] of pending) {
        if (now - entry.time > 30 * 60 * 1000) pending.delete(candidate);
      }
      if (pending.size >= 4096) pending.delete(pending.keys().next().value);
      pending.set(key, { time: now, sessionID: input.sessionID });
    },
    "shell.env": async (input, output) => {
      const key = keyFor(input);
      if (key && pending.has(key)) Object.assign(output.env, gitEnvironment);
    },
    "tool.execute.after": async (input) => {
      const key = keyFor(input);
      if (key) pending.delete(key);
    },
    event: async ({ event }) => {
      if (event.type !== "session.deleted") return;
      const sessionID = event.properties?.info?.id;
      if (!sessionID) return;
      for (const [key, entry] of pending) {
        if (entry.sessionID === sessionID) pending.delete(key);
      }
    },
  };
}
