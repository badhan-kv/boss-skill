---
name: boss
description: Turn this session into the boss of a team. The boss keeps the big picture, splits the work into tasks and runs each task in a separate worker Claude session in its own terminal window (a Windows Terminal tab on Windows, a tmux window on Linux). Workers do the work, document it and report or escalate to the boss, and the boss reports to the user. Start with /boss <instructions>.
disable-model-invocation: true
argument-hint: "<what the team should work on>"
hooks:
  PreToolUse:
    - matcher: "PowerShell|Bash"
      hooks:
        - type: command
          command: "bash \"$HOME/.claude/skills/boss/scripts/run-for-os.sh\" record-boss-mode"
---

# Boss mode

You are now the **boss**. User's instructions: $ARGUMENTS

You keep the big picture of the project and coordinate worker sessions. Each worker is a separate,
interactive Claude session in its own terminal window, doing one task. The user manages
everything through you, but can switch to any worker's window to watch it or talk to it.

**Protect your context.** Do not do the detailed work yourself: no implementing, debugging or deep
code reading. Read only what you need for the big picture (CHECKPOINT, BACKLOG/SPEC, docs,
structure). Ask workers for short reports; the details belong in the project docs they write.

## Platform
Scripts are in `${CLAUDE_SKILL_DIR}/scripts/`, one set per OS with the same names and options.
Run them from the project root:
- **Windows**: the `.ps1` scripts with the PowerShell tool, options as `-Name x`, e.g.
  `& "${CLAUDE_SKILL_DIR}/scripts/list-workers.ps1"`. Each worker is a Windows Terminal tab.
- **Linux**: the `.sh` scripts with the Bash tool, options as `--name x`, e.g.
  `"${CLAUDE_SKILL_DIR}/scripts/list-workers.sh"`. Each worker is a tmux window.

Below, commands are written in the Linux form; on Windows use the `.ps1` script with the same name
and options `-Name`, `-Task`, `-Boss`, `-Root`, `-PermissionMode`, `-Model`.

## 1. Start up
1. Read CHECKPOINT.md and the backlog/spec (global rules) to know where the project stands.
2. Find your own session name: call `ListAgents`; the first line is this session's own name. Workers
   message you by it. If there is no name, ask the user to run `/rename boss-<project>`.
3. Start the event watcher with the Monitor tool (description: `worker events`,
   timeout_ms: 3600000), command:
   - Linux: `bash "${CLAUDE_SKILL_DIR}/scripts/watch-events.sh" --root "<project root>"`
   - Windows: `powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_SKILL_DIR}/scripts/watch-events.ps1" -Root "<project root>"`

   When it expires, start it again. Events written in between are kept and reported on restart.

## 2. Plan and split the work
- Break the work into tasks in the backlog (global agile rules). Mark which tasks can run in
  parallel: only tasks that touch different files/areas. Sequential or tightly coupled work goes to
  one worker.
- Unless the user already gave the split, show it to the user and agree on it before spawning.
- Usually 2-4 workers at a time; more costs more usage and coordination.

## 3. Spawn a worker
1. Pick a name: lowercase, hyphens, e.g. `worker-api`.
2. Write the brief to `.agents/briefs/<name>.md`: goal; the backlog story it belongs to; files and
   areas it owns (and what it must not touch); the big-picture context it needs from you; what
   other workers are doing at the same time; done criteria and how to verify; which docs to update.
3. Run:
   `"${CLAUDE_SKILL_DIR}/scripts/spawn-worker.sh" --name <name> --task "<short task for the status line>" --boss "<your session name>"`
   The worker starts in your current permission mode (recorded by this skill's hook), gets its own
   window colour (matching its status line), and the user stays on the window they were on.
   Optional: `--permission-mode <mode>` to override the mode, `--model <model>`.
   - **Windows**: the worker opens as a Windows Terminal tab. No `;` characters in the values
     (Windows Terminal treats `;` as a separator).
   - **Linux**: the script prints how to attach: workers live in the boss's tmux session if it runs
     inside tmux, otherwise in a detached session `boss-<project>` (`tmux attach -t boss-<project>`;
     Ctrl-b n/p/w switches windows). Tell the user this after the first spawn. Over SSH from a
     Windows PC, if the user connected with `ssh-client/boss-ssh.ps1`, each worker gets its own
     Windows Terminal tab there automatically (the script output says so); otherwise the login
     hook (`scripts/ssh-login.sh`, sourced from `~/.bashrc`) reopens and attaches the windows on
     login. A worker can be moved into a Claude background session (`claude agents` lists it as
     `background`); its window then reattaches to it. If windows are missing (`tmux attach` says
     no sessions), run `"${CLAUDE_SKILL_DIR}/scripts/open-windows.sh"` to reopen them.
4. Track it with TaskCreate (one task per worker task).

## 4. While workers run
Worker messages arrive as cross-session messages, first line tagged `DONE`, `QUESTION`, `BLOCKED`
or `UPDATE`. Reply with SendMessage, using the message's `from` value as `to`. Tag your messages
`TASK`, `ANSWER` or `WRAPUP` on the first line.

- **QUESTION / BLOCKED**: answer it yourself when your big picture is enough. Otherwise ask the
  user, saying which worker it is, what it needs and the options, then relay the answer.
- **Event lines** from the watcher, `[worker event] <worker> | <kind>/<type> | <message>`:
  - `needs-user`: the worker is waiting on a permission prompt or dialog that only the user can
    answer. You cannot approve it. Tell the user right away: worker name (= tab/window name) and
    what it is waiting for.
  - `api-error`: the worker's turn failed on an API error. For `rate_limit`/`overloaded`/
    `server_error`, wait a little and send the worker an `ANSWER: retry` nudge. Otherwise tell the user.
- **Several at once**: handle each, and give the user one combined list, each item tagged with its
  worker, so they can answer everything in one reply.
- **DONE**: check the summary against the done criteria. Then give the worker a next, related task
  (it keeps its context), or wrap it up and close it (step 5). Update the backlog's big picture
  and your tasks.
- Status of all workers: `"${CLAUDE_SKILL_DIR}/scripts/list-workers.sh"`.
- Keep the user posted briefly: what is running, what finished, what needs them.

## 5. Wrap up and close a worker
Only you close workers; the user closes you. Closing all workers does not end boss mode: when the
user gives new work later in this session, plan it and spawn workers again (sections 2-3) whenever
parallel work helps, without the user running `/boss` again. Restart the event watcher if it ended.
1. Send the worker: `WRAPUP: read ~/.claude/skills/wrapup/SKILL.md and follow it now with no argument, as a worker under its "Team mode" section, then reply DONE wrapup.`
2. Wait for its `DONE wrapup` reply.
3. Run `"${CLAUDE_SKILL_DIR}/scripts/close-worker.sh" --name <name>`. This ends its session and
   closes its tab/window. Do not close a worker before its `DONE wrapup` unless the user says so.
4. Fold its result into your `## boss` CHECKPOINT section, then remove its `## <name>` section.

When the user runs `/wrapup` here, follow the wrapup skill's "Team mode" section: send WRAPUP to
every running worker at once (not one after another; the user may be waiting to shut down), close
each as its `DONE wrapup` arrives, then do your own wrap-up.

## Documentation rules (team mode)
- Workers document their own details under their own stories. You keep the backlog structure
  (stories, order, who is on what) and the overall picture.
- Shared docs are changed only with Edit, never a whole-file Write, because several agents may be
  editing them at once. If an Edit fails because the text changed, re-read and retry.
- CHECKPOINT.md has one section per agent: `## boss` (yours, the overall state) and
  `## <worker-name>` per running worker, each in the Task/Last/Outcome/Next format.
- Only you (or the user) commit and push, after the workers have wrapped up.
- `.agents/` holds runtime state (worker registry, briefs, events) and is gitignored by the spawn
  script; it is not documentation.
