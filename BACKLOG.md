# Boss skill — backlog

Goal: `/boss <instructions>` turns a session into a coordinator ("boss") that keeps the big picture
and delegates tasks to worker sessions, each running in its own Windows Terminal tab. Workers do
the detailed work, document it, report and escalate to the boss; the boss reports to the user.
Two levels only for now (boss → workers). Workers may use ordinary in-session subagents.

## Design (decided 2026-10-25)
- One skill folder `~/.claude/skills/boss/`; nothing in global CLAUDE.md or settings.
- Workers: interactive `claude` sessions launched by `scripts/spawn-worker.ps1` via
  `wt.exe -w 0 new-tab`, each running `scripts/run-worker.ps1`, which sets env vars
  (`AGENT_NAME`, `AGENT_BOSS`, `AGENT_ROOT`, `AGENT_SKILL_DIR`), records its PID, and starts
  `claude --name <worker> --settings worker-settings.json --append-system-prompt <worker-role.md>`.
- Worker-only settings (`worker-settings.json`, passed with `--settings`): status line (worker
  name + task + context %) and hooks (permission prompt / dialog, API error) that write event files.
- Communication: cross-session messaging (`SendMessage`) worker ↔ boss. Workers prefer the boss;
  worker ↔ worker only when needed.
- Escalation of things a worker cannot message about itself (permission prompt, API error): hook →
  `.agents/events/*.json` → boss's background watcher (`scripts/watch-events.ps1` under Monitor).
  One file per event, so simultaneous events are never lost; the boss batches them for the user.
- The boss cannot approve a worker's permission prompt (blocked by design); it tells the user
  which tab needs attention. Workers default to auto mode, so prompts are rare.
- Closing: boss sends a wrap-up instruction → worker runs the `wrapup` skill, replies DONE → boss
  runs `scripts/close-worker.ps1`, which stops the worker's `claude` process; `run-worker.ps1`
  exits cleanly and the tab closes. The user closes the boss.
- Docs: workers document their own nitty-gritty. Shared docs are changed only with Edit (never a
  whole-file Write); each agent edits its own story's section. CHECKPOINT.md has one `## <agent>`
  section per agent; the boss owns `## boss`.
- Per-project runtime state in `.agents/` (gitignored): `workers/<name>.json` registry,
  `briefs/<name>.md`, `events/`.

## Background and options weighed (2026-10-25)
- Purpose: keep the coordinating session's context small (it holds the big picture only) so more
  of a large project fits in one session, while workers handle the detail, in parallel where
  possible. The user wants to watch every worker live in its own tab and manage everything from
  the boss.
- Built-in Claude Code agent teams (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`) were considered and
  not used: split panes need tmux or iTerm2 (not supported in Windows Terminal), teammates cannot
  have their own teammates, teams do not survive a session resume, and the lead is fixed.
  Cross-session messaging between ordinary sessions (`SendMessage`/`ListAgents`, named pipe on
  Windows) gives separate tabs and named addressing instead.
- Levels: two for now (boss -> workers). Workers may use ordinary in-session subagents for
  subtasks; a third level of visible sessions was deferred.
- Shared docs: the user wanted workers to document their own details (the boss does not know
  them) rather than the boss being the only writer. Options weighed: check-out/check-in locking
  vs edit discipline. Tested: the Edit tool replaces an exact text snippet in the file as it is on
  disk, so two agents editing different places both keep their changes; if the snippet changed,
  the Edit fails and the agent re-reads. Chosen: Edit-only on shared docs (never a whole-file
  Write), each agent edits its own story's section, one CHECKPOINT section per agent. A locking
  hook can be added later if real conflicts appear.
- Wrap-up: a slash command sent from another session arrives as plain text and never runs, so the
  boss sends a WRAPUP instruction and the worker runs the `wrapup` skill itself. For that the
  `wrapup` skill no longer has `disable-model-invocation`; its description limits it to the user
  typing `/wrapup` or a boss's wrap-up instruction.
  Changed 2026-10-27: see the change entry under story 5 (skill kept manual-only; workers read and
  follow its "Team mode" section; all workers wrap up at once).
- Permissions: a message from another session can never approve a permission prompt (by design),
  so the boss reports which worker tab needs the user. The user mostly runs auto mode, so prompts
  are rare.
- Simultaneous events/questions: one event file per event and a queue of incoming messages per
  session, so nothing is lost; the boss gives the user one combined list tagged by worker.
- Closing: only the boss closes workers (after `DONE wrapup`); only the user closes the boss.

## Windows Terminal / environment gotchas (found 2026-10-25)
- `wt.exe` treats `;` as a separator between its own commands, also inside a tab's command line:
  values passed to `spawn-worker.ps1` and any test command lines must not contain `;`.
- A tab opened from a Claude command inherits that command's environment unless
  `--reloadEnvironment` is given (`NO_COLOR=1`, session identity, git prompt settings).
- Windows Terminal cannot recolour an existing tab from a program, and always focuses a new tab
  (worked around with `focus-tab -t <index>`).
- All tabs share one Windows Terminal process, so a tab's closing cannot be seen from process
  IDs; the open tab titles can be listed with UI Automation
  (`CASCADIA_HOSTING_WINDOW_CLASS` window, `TabItem` elements).
- Windows PowerShell 5.1 shows UTF-8 files without a BOM wrongly with plain `Get-Content`
  (use `-Encoding UTF8`); the files themselves are fine.
- Auto mode blocks commands that look like weakening security (e.g. a worker running a script with
  `-ExecutionPolicy Bypass`), so workers update their status line by writing a file instead.
- Testing a boss from another Claude session: launch it with `wt new-tab --reloadEnvironment`,
  otherwise it inherits the launching session's identity and `NO_COLOR`.

## Stories
1. [x] Launcher: `spawn-worker.ps1`, `run-worker.ps1`, shared helpers; worker opens in a named tab.
   - Change 2026-10-25 (found in trial): a tab opened with `wt.exe` inherits the boss's environment,
     including its session identity (`CLAUDE_CODE_SESSION_ID`, `CLAUDE_CODE_CHILD_SESSION`,
     `CLAUDE_CODE_MESSAGING_SOCKET`/`_TOKEN`, `CLAUDECODE`, `CLAUDE_PID`, ...). The worker then
     ran as a child of the boss: no entry in `~/.claude/sessions/`, so it could not be messaged
     by name, and it could see the boss's messaging token. Previously `run-worker.ps1` passed the
     environment through unchanged; now it removes those variables before starting `claude`.
     Verified: the next worker registered as `worker-y` and was messaged by name.
2. [x] Worker status line: name + task (+ context %); `set-task.ps1` to change the task.
   - Change 2026-10-25 (found in trial): auto mode blocked workers running `set-task.ps1`
     (`powershell -ExecutionPolicy Bypass ...`, classified as weakening security). Previously the
     task was changed by that script (above). Now the worker overwrites its own
     `.agents/tasks/<name>.txt` with its file tools; the status line shows that file's first line,
     falling back to the task given at spawn. `set-task.ps1` was removed. Verified in trial.
3. [x] Escalation events: `notify-boss.ps1` hook, `watch-events.ps1` watcher, `worker-settings.json`.
   - Change 2026-10-25 (found in trial): permission prompts were caught with the `Notification`
     hook (`permission_prompt` matcher). The live trial showed it works, but its text is only
     "Claude needs your permission" (no tool or command), and the docs say it fires only after
     the prompt has waited ~6 s. Now permission prompts use the `PermissionRequest` hook, which
     fires as the prompt appears and carries `tool_name`/`tool_input`; the event reads e.g.
     `wants to use Bash: npm install left-pad`. The hook prints nothing, so the dialog is
     unchanged. `Notification` is kept only for elicitation dialogs.
4. [x] Roles: `SKILL.md` (boss, `/boss <instructions>`), `worker-role.md`.
5. [x] Wrap-up and close: `close-worker.ps1`, `list-workers.ps1`; `wrapup` skill team-mode section.
   - Change 2026-10-27 (found in tests on the Linux machine): the published `wrapup` skill
     (private-claude-skills repo) still had `disable-model-invocation: true` and no team-mode
     section, so workers could not run it and wrapped up by hand. Its step 2 ("overwrite
     CHECKPOINT.md") and step 1 (create `DECISIONS.md` if missing) would also clash with other
     workers wrapping up at the same time. Previously (see "Background and options weighed",
     Wrap-up bullet): the boss sent `WRAPUP: run the wrapup skill now`, and the skill was to be
     model-invocable. Now `wrapup` keeps `disable-model-invocation` (only the user starts it) and
     gets a "Team mode" section; WRAPUP and `worker-role.md` tell the worker to read
     `~/.claude/skills/wrapup/SKILL.md` and follow it as a worker. Worker rules: Edit only (never a
     whole-file Write) on shared files, own sections only, own `## <name>` CHECKPOINT section only,
     no new shared files (notes without a fitting doc go to `.agents/wrapup/<name>.md`), never
     commit. Boss rules: send WRAPUP to all workers at once (not one at a time, so wrap-up is fast
     enough before shutting the computer down), close each as `DONE wrapup` arrives, then fold
     worker notes in and write CHECKPOINT with only `## boss`. One-at-a-time wrap-up was weighed
     and rejected as too slow.
6. [x] End-to-end trial on a throwaway project (boss + 2 workers), user watching the tabs.
   - Result 2026-10-25: boss started with `/boss` in its own tab, found its name, started the
     watcher, added Stories 3-4 and spawned worker-m (manual mode) and worker-s in parallel.
     worker-s finished, wrapped up and was closed while worker-m waited on permission prompts;
     both prompts reached the boss as events. Both workers documented decisions and verification
     under their stories; the boss folded worker sections into `## boss` in CHECKPOINT.md.
     Earlier component trial (this session as boss): DONE/QUESTION messages, answer by name,
     WRAPUP running the wrapup skill, close-worker. Still to confirm by the user: the status line
     and the tabs closing themselves.
   - Known: a stopped worker leaves its `~/.claude/sessions/<pid>.json`; Claude Code ignores it
     (dead PID) and it does not show in the session list.
   - Trial 2 result 2026-10-25 (calculator: worker-a core module, worker-b command line, both in
     `acceptEdits` mode, user ran `/wrapup` in the boss): verified the status line in both tabs
     (from `.agents/statusline/`), live `PermissionRequest` events naming the command, two workers
     waiting on the user at once, worker-b's division-by-zero question passed by the boss to the
     user and the answer relayed, workers agreeing the interface directly, append-only change
     entries under each story, `/wrapup` in the boss wrapping up and closing both workers first,
     and both worker tabs closing by themselves (checked with UI Automation tab list). Final
     CHECKPOINT had only `## boss`; no AI mentions in project files.
   - Change 2026-10-25 (for verification): `statusline.ps1` now also saves its last line (no
     colours) to `.agents/statusline/<name>.txt`, and `run-worker.ps1` records `consolePid`.
     Previously neither was saved. `consolePid` turned out to be the shared Windows Terminal
     process, so it cannot tell whether one tab closed; tab closing is checked by listing
     Windows Terminal tab titles with UI Automation instead.
   - Note: approvals the user makes with "always allow" in a worker tab are saved by Claude Code
     to the project's `.claude/settings.local.json` (normal behaviour, not part of this skill).
7. [ ] Colour coding, no tab jump, workers in the boss's permission mode (requested 2026-10-25).
   - Worker colours: each worker gets the first free colour of an 8-colour palette (`common.ps1`),
     used for its tab (`wt new-tab --tabColor`) and its name in the status line (true-colour ANSI).
     Stored as `color` in the worker registry.
   - Boss colour: Windows Terminal has no supported way for a program to recolour an existing tab
     (no `wt` command, no escape sequence), and Claude Code hook `terminalSequence` only allows
     title/notification sequences. The user chose: a gold `BOSS` marker in the user's own
     status line (`~/.claude/statusline.ps1`), shown when `.agents/boss.json` names this session.
     Rejected: user colours the tab by hand, boss opening in a new gold tab, automating the tab
     colour menu with UI Automation (unsupported, fragile).
   - No tab jump: Windows Terminal always focuses a new tab and has no background option, so
     `spawn-worker.ps1` reads the selected tab index (UI Automation, foreground Terminal window)
     and appends `; focus-tab -t <index>` to the same `wt` command.
   - Same mode: the boss skill registers a `PreToolUse` hook (`record-boss-mode.ps1`, matcher
     `PowerShell|Bash`) that writes the boss's `permission_mode` and session id to
     `.agents/boss.json` before each command. `spawn-worker.ps1` uses it when `-PermissionMode`
     is not given (hooks report Manual as `default`, mapped to the CLI's `manual`); falls back to
     `auto`. Previously workers always started in `auto` unless the boss passed a mode.
   - Verified: unit tests (mode mapping, colour pick, selected tab, status line, BOSS marker only
     for the boss's session id); live spawn from a session in auto mode kept the user on the same
     tab (index 2 before and after) and started the worker in auto with colour #1E88E5.
     Live `/boss` in acceptEdits: the worker was spawned in acceptEdits (mode inheritance works).
   - Change 2026-10-25 (found in test): the user saw no colour at all in boss and worker tabs
     (status line and even the Claude Code logo white), while this session showed colour. Cause
     (verified): Claude Code runs its tool commands with `NO_COLOR=1` (plus `AI_AGENT`,
     `GIT_ASKPASS`, `GIT_EDITOR`, `GIT_TERMINAL_PROMPT=0`, `GCM_INTERACTIVE`, ...), and `wt new-tab`
     with a command line inherits the caller's environment by default, so every tab opened from a
     Claude command ran without colour. Previously `run-worker.ps1` only removed the session
     identity variables (story 1 change entry). Now `spawn-worker.ps1` opens the tab with
     `--reloadEnvironment` (fresh environment like a normally opened tab; tested: none of those
     variables reach the tab, and `claude` is on the saved user PATH), and `run-worker.ps1` also
     removes `NO_COLOR` and the git/tool variables as a fallback.
   - Verified 2026-10-25: no tab jump confirmed by the user watching a live spawn (worker-f), and
     by the selected tab index (2 before and after). Colour after the `--reloadEnvironment` fix:
     waiting for the user's check (gold BOSS, blue/green worker tabs and names).
   - Verified 2026-10-25 (mode test in `boss-test-mode`): boss started in acceptEdits, recorded
     as acceptEdits, worker-g spawned in acceptEdits; the user switched the boss to auto with
     Shift+Tab, the record changed to auto, worker-h spawned in auto. worker-g kept the mode it
     started with. (The earlier unexplained switch to auto in the worker-d test was the user
     changing a tab's mode.)
