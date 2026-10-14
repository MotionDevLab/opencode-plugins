---
description: Autosave status and controls - minutes, plain words, no restart needed
---

# Session autosave control

All values are MINUTES. Two knobs:

- `auto` — idle autosave, at most once every N minutes per session.
  Default 15. Lower = safer, more disk. Range 2–120.
- `emergency` — error autosave, at most once every N minutes per session.
  Caps disk spam during throttle storms. Default 10. Range 2–60.

Pre/post-compaction saves always run (no interval — compaction is rare and precious).

Usage:
- `/autosave` — status
- `/autosave on` / `/autosave off` — switch (takes effect immediately)
- `/autosave interval auto 5` — save idle sessions every 5 minutes
- `/autosave interval emergency 20` — error saves at most every 20 minutes

The words typed after /autosave are the arguments: first word, second word, third word.
Example: in `/autosave interval auto 5`, first word is "interval", second is "auto", third is "5".

Mechanics (no restart needed for any of this):
- ON/OFF: empty flag file `%USERPROFILE%\.local\share\opencode\backups\AUTOSAVE_OFF`
  (present = OFF). The `OPENCODE_AUTOSAVE=0` env var also disables; either off-switch wins.
- Intervals: file `%USERPROFILE%\.local\share\opencode\backups\autosave-config.json`,
  shape `{"autoMin":15,"emergencyMin":10}`. Missing file or bad values = defaults.
  The `interval` subcommand reads the file if present (else defaults), sets the
  named key, writes back compact JSON.

Steps:

1. If the first word is `off`, create the flag file and report `autosave OFF`.
   If the first word is `on`, delete it (if present) and report `autosave ON`.
   If the first word is `interval` with the second word `auto` or `emergency`
   and the third word a number, validate (whole minutes, clamped to the ranges
   above), update the config file, and report e.g. `auto = every 5 minutes`.
   If no words or anything else, change nothing (status only).

2. Always report status in plain words, one line each (PowerShell):
- autosave ON or OFF (flag file + env value)
- idle autosave: every N minutes (or "default 15" if no config file)
- error autosave: at most every N minutes per session
- compaction saves: always on, not affected by intervals
- backups: counts and total MB per kind (`opencode-auto-*`, `opencode-emergency-*`, `opencode-precompact-*`, `opencode-postcompact-*`, `opencode-snapshot-session-*`, `opencode-rescue-*`) in the backups dir
- retention: one line, e.g. `retention: auto keep-3-per-session + 7d, emergency keep-2 + 7d, others uncapped, last run deleted N files` — get N from the latest `retention_deleted=` value in `autosave.log` (0 if none yet; it appears on the `OK bytes=...` lines)
- last 3 lines of `autosave.log` (proof the plugin is alive)

Examples of what good status output looks like:
`autosave ON — idle save every 15 minutes, error save at most every 10 minutes, compaction saves always on.`

Never print message contents or API keys.
