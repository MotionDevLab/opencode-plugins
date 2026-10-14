# opencode-plugins

Self-made OpenCode plugins (MotionDevLab), published as npm packages from this
monorepo. Convention reference: `opencode-go-multi-auth` (separate repo —
reference only, not maintained here).

| Package | Status | Install |
|---|---|---|
| [`opencode-session-autosave`](packages/opencode-session-autosave/) | V1, stable | `@motiondevlab/opencode-session-autosave@0.1.0` |
| [`opencode-git-noninteractive-env`](packages/opencode-git-noninteractive-env/) | **V1 only** (V2 needs a `create.before` rewrite, see package README) | `@motiondevlab/opencode-git-noninteractive-env@0.1.0` |

## Fresh-machine install

1. Add the entries to the `plugin` array in `opencode.jsonc` (snippets in each
   package README).
2. Autosave: nothing else — `/autosave` + `/snapshot-session` self-install on
   first load. Git-env: add `"disabled_hooks": ["non-interactive-env"]` to the
   `[opencode]` block of `~/.omo/omo.jsonc`.
3. **Restart OpenCode** after install or update (plugins load once at startup).

## Install mechanics

Each package publishes to npm from this monorepo (`files` allowlist in each
`package.json`; `.opencode-plugin/plugin.json` manifest alongside). OpenCode's
V1 `plugin` array accepts npm specs, and npm git-deps do NOT install monorepo
subdirectories — hence one npm package per plugin rather than git-URL installs.

OpenCode V1 does NOT extract commands from npm plugin packages, so
`opencode-session-autosave` self-installs its bundled commands on load
(write-if-missing; user edits win). Precedent: `opencode-supermemory` CLI.

## Maintainer: publishing

```bash
npm whoami            # must be logged in (npm adduser)
npm run publish:all   # TODO: release script (per-package npm publish + git tag)
```

No secrets in this repo — scan `*.ps1`, `*.jsonc`, `*.md` for tokens before push.
PowerShell worker scripts stay **ASCII only** (5.1 misreads UTF-8 without BOM).

## License

MIT — see [LICENSE](LICENSE).
