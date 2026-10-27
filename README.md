# boss skill

Run a project as a small team: one **boss** session keeps the big picture and splits the work;
each task runs in a **worker** session in its own terminal window: a Windows Terminal tab on
Windows, a tmux window on Linux. Workers do and document the detailed work and report or escalate
to the boss; the boss reports to the user.

## Requirements and install
One skill for both systems; the boss picks the script set for the machine it runs on.

| | Windows | Linux |
|---|---|---|
| Needs | Git for Windows (Git Bash), Windows Terminal, PowerShell 5.1+ | tmux, jq, bash |
| Install | `powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1` | `bash install.sh` |

Both: Claude Code (`claude` on PATH) and the `wrapup` skill in `~/.claude/skills/wrapup` (workers
read it when they wrap up). Run the installer from a clone of this repo. It installs missing
requirements (winget on Windows; apt, dnf, pacman or brew on Linux), then copies the skill to
`~/.claude/skills/boss`, keeping that folder's runtime `state/`. Run it again after a `git pull`.

Git Bash is required on Windows because Claude Code runs the skill's hook and the worker status
line through it; `scripts/run-for-os.sh` then starts the `.ps1` script on Windows or the `.sh`
script on Linux, so those commands are the same on both.

## Use
In a Claude Code session started in the project folder, type:

```
/boss <what the team should work on>
```

The boss reads CHECKPOINT/BACKLOG, agrees the task split with you, then spawns workers.

- **Managing**: talk to the boss. It answers workers' questions when it can and brings you the
  rest, including permission prompts (approve those in the named worker's tab or window).
- **Mode**: workers start in the boss's permission mode at the time they are spawned.
- **Finishing**: type `/wrapup` in the boss. All workers wrap up at the same time (each documents
  its work first, editing only its own sections) and each is closed as it finishes; then the boss
  wraps itself up. Close the boss yourself.

Worker status line: worker name, task and context use. The boss's own status line can show a gold
`BOSS` marker when `.agents/boss.json` names its session (see `scripts/statusline.*`).

### Windows
- **Watching**: click any worker tab (coloured, titled with the worker's name). Opening a worker
  does not switch you away from your tab.

### Linux
- **Where it runs**: local terminal sessions and SSH sessions alike. Smoothest with the boss
  started inside tmux: workers then open as windows in the same tmux session, and the boss survives
  a dropped SSH connection.
- **Watching**: workers live in the boss's tmux session if the boss runs inside tmux, otherwise in
  a detached session `boss-<project>`: `tmux attach -t boss-<project>`. Switch windows with
  Ctrl-b n / p / w. Window names are the worker names, coloured like their status line.
- **SSH auto-attach** (optional): add to `~/.bashrc`:
  `[ -f "$HOME/.claude/skills/boss/scripts/ssh-login.sh" ] && . "$HOME/.claude/skills/boss/scripts/ssh-login.sh"`.
  On an interactive SSH login outside tmux it reopens windows for running workers and attaches
  (Ctrl-b d returns to the shell; `BOSS_AUTO_ATTACH=0` turns it off). Projects are remembered in
  `state/roots.txt` when a worker is spawned there.
- **Worker tabs on a Windows PC over SSH** (optional): copy `ssh-client/boss-ssh.ps1` to the PC
  (`$HOME\`) and connect with `powershell -ExecutionPolicy Bypass -File boss-ssh.ps1 [user@host]`
  instead of plain `ssh`, or add `ssh-client/profile-snippet.ps1` to the PowerShell profile so
  plain `ssh <user@host>` does that (edit the host in both files). Run inside Windows Terminal, the
  SSH session stays in the current tab and every running worker, and each worker the boss spawns
  from it, gets a tab in the same window titled with the worker name; focus returns to the first
  tab (`-BossTab N` for another; Windows Terminal cannot open background tabs). From a classic
  console window the SSH session moves to the first tab of a new Windows Terminal window.
  Without Windows Terminal each worker gets its own PowerShell window. A worker's tab closes when
  the worker ends; closing it leaves the worker running (`scripts/tab-feed.sh` +
  `scripts/attach-tab.sh`). Needs key-based SSH login. Spawns outside SSH are unaffected.
- **Background sessions**: a worker moved into a Claude background session keeps its window,
  which reattaches (`claude attach`). `scripts/open-windows.sh [--root DIR] [--attach]` reopens
  missing windows; `close-worker.sh` stops background sessions too.

## Files
- `SKILL.md`: boss role and procedure (`/boss`), plus the hook that records the boss's mode.
- `worker-role.md`: worker rules (appended to each worker's system prompt).
- `worker-settings.json`: worker-only status line and hooks (passed with `--settings`).
- `scripts/run-for-os.sh`: runs the `.ps1` or `.sh` script of a given name for this OS.
- `scripts/*.ps1` (Windows) and `scripts/*.sh` (Linux): spawn/run/close/list workers, event
  watcher, hooks, status line; Linux also the tmux window helpers and the SSH tab feed.
- `ssh-client/`: for a Windows PC that connects to the Linux machine over SSH (`boss-ssh.ps1`,
  `profile-snippet.ps1`).
- `install.ps1`, `install.sh`: installers.
- Per project, `.agents/` (gitignored) holds the runtime state: worker registry, briefs, task
  files, status-line snapshots, events, `boss.json`.

Design, decisions and test history: `BACKLOG.md`.
