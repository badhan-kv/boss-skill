# boss skill

Run a project as a small team: one **boss** session keeps the big picture and splits the work;
each task runs in a **worker** session in its own Windows Terminal tab. Workers do and document
the detailed work and report or escalate to the boss; the boss reports to the user.

## Use
In a Claude Code session started normally in the project folder (Windows Terminal), type:

```
/boss <what the team should work on>
```

The boss reads CHECKPOINT/BACKLOG, agrees the task split with you, then spawns workers.

- **Watching**: click any worker tab (coloured, titled with the worker's name; the status line
  shows name, task and context use). Opening a worker does not switch you away from your tab.
- **Managing**: talk to the boss. It answers workers' questions when it can and brings you the
  rest, including permission prompts (approve those in the named worker's tab).
- **Mode**: workers start in the boss's permission mode at the time they are spawned.
- **Finishing**: type `/wrapup` in the boss. All workers wrap up at the same time (each documents
  its work first, editing only its own sections) and each is closed as it finishes; then the boss
  wraps itself up. Close the boss tab yourself.

The boss's status line shows a gold `BOSS` marker (from `~/.claude/statusline.ps1`).

## Files
- `SKILL.md`: boss role and procedure (`/boss`), plus the hook that records the boss's mode.
- `worker-role.md`: worker rules (appended to each worker's system prompt).
- `worker-settings.json`: worker-only status line and hooks (passed with `--settings`).
- `scripts/`: `spawn-worker.ps1`, `run-worker.ps1`, `close-worker.ps1`, `list-workers.ps1`,
  `watch-events.ps1`, `notify-boss.ps1`, `record-boss-mode.ps1`, `statusline.ps1`, `common.ps1`.
- Per project, `.agents/` (gitignored) holds the runtime state: worker registry, briefs, task
  files, status-line snapshots, events, `boss.json`.

Design, decisions and test history: `BACKLOG.md`.
