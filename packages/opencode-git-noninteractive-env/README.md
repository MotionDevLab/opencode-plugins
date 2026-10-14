# opencode-git-noninteractive-env

> **OpenCode V1 only.** V2's Bash tool ignores legacy `shell.env` hooks
> ([anomalyco/opencode#41117](https://github.com/anomalyco/opencode/issues/41117)).
> The V2 port uses `ctx.shell.hook("create.before", ...)` and matches git on
> `event.command` directly. That port is tracked separately and is NOT in this
> package.

Replaces Oh My OpenAgent 5.1.29's `non-interactive-env` hook, which prefixes
commands with `VAR=value` — a syntax error in Windows PowerShell 5.1. Same
variables (`CI`, `GIT_TERMINAL_PROMPT=0`, `GCM_INTERACTIVE=never`,
`GIT_EDITOR=:`, `GIT_PAGER=cat`, …), delivered via OpenCode's `shell.env`
hook, scoped to `bash`-tool calls matching `/\bgit\b/`.

## Install

```jsonc
// opencode.jsonc
{
  "plugin": [
    "@motiondevlab/opencode-git-noninteractive-env@0.1.0"
  ]
}
```

Required companion setting — this plugin and the entry below are a **pair**:

```jsonc
// ~/.omo/omo.jsonc, inside the [opencode] block
{
  "opencode": {
    "disabled_hooks": ["non-interactive-env"]
  }
}
```

Then **restart OpenCode** (plugins load once at startup).

## Coupled-pair warning

- Deleting only this plugin loses non-interactive protection (git may hang on prompts).
- Deleting only the `disabled_hooks` entry restores the `VAR=value` prefix errors under PowerShell 5.1.
- Remove as a pair, and only if leaving Oh My OpenAgent or upstream fixes the prefix hook.

## Verify

Run `git status` via the bash tool under `pwsh`: no prefix error, and
non-interactive vars present in the spawned environment.
