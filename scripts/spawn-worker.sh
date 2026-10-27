#!/usr/bin/env bash
# Open a worker session in a new tmux window.
# The brief must already exist at <root>/.agents/briefs/<name>.md.
# Usage: spawn-worker.sh --name N --task T --boss B [--root DIR] [--permission-mode M] [--model X]
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

name= task= boss= root=$PWD mode= model=
while [ $# -gt 0 ]; do
    case $1 in
        --name) name=$2; shift 2 ;;
        --task) task=$2; shift 2 ;;
        --boss) boss=$2; shift 2 ;;
        --root) root=$2; shift 2 ;;
        --permission-mode) mode=$2; shift 2 ;;
        --model) model=$2; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done
[ -n "$name" ] && [ -n "$task" ] && [ -n "$boss" ] || { echo "Need --name, --task and --boss" >&2; exit 2; }
[[ $name =~ ^[a-z0-9][a-z0-9-]{0,39}$ ]] || { echo "Worker name must be lowercase letters, digits and hyphens (max 40), e.g. worker-api" >&2; exit 2; }
case "$mode" in ''|auto|acceptEdits|manual|plan|dontAsk|bypassPermissions) ;; *) echo "Bad permission mode: $mode" >&2; exit 2 ;; esac

root=$(cd "$root" && pwd)
brief="$root/.agents/briefs/$name.md"
[ -f "$brief" ] || { echo "Brief not found: $brief (write it before spawning)" >&2; exit 1; }
command -v tmux >/dev/null || { echo "tmux is required" >&2; exit 1; }

if existing=$(read_worker "$root" "$name"); then
    if [ "$(jq -r .status <<<"$existing")" = running ] && pid_alive "$(jq -r .hostPid <<<"$existing")"; then
        echo "Worker '$name' is already running (host PID $(jq -r .hostPid <<<"$existing"))" >&2; exit 1
    fi
fi

[ -n "$mode" ] || mode=$(boss_permission_mode "$root")
[ -n "$mode" ] || mode=auto
color=$(free_worker_color "$root")

mkdir -p "$root/.agents/events" "$root/.agents/tasks"
printf '%s\n' "$task" > "$root/.agents/tasks/$name.txt"
ensure_agents_ignored "$root"
remember_root "$root"

save_worker "$root" "$name" "$(jq -n --arg name "$name" --arg task "$task" --arg boss "$boss" \
    --arg root "$root" --arg mode "$mode" --arg color "$color" --arg model "$model" \
    --arg created "$(date +%Y-%m-%dT%H:%M:%S)" \
    '{name:$name, task:$task, boss:$boss, root:$root, permissionMode:$mode, color:$color,
      model:$model, status:"starting", hostPid:null, created:$created}')"

# Where to put the window: the boss's own tmux session if it runs in one, else a detached
# session "boss-<project>" the user can attach to.
if [ -n "${TMUX:-}" ]; then
    sess=$(tmux display-message -p '#S')
    attach_hint="Windows are in your current tmux session ($sess)."
else
    sess=$(boss_tmux_session "$root")
    tmux has-session -t "=$sess" 2>/dev/null || tmux new-session -d -s "$sess" -n home -c "$root"
    attach_hint="Attach with: tmux attach -t $sess   (switch windows: Ctrl-b n / p / w)"
    [ -n "${BOSS_TAB_ID:-}" ] && attach_hint+=$'\n'"Over SSH, boss-ssh.ps1 on the PC opens a terminal tab for it."
fi

runner="$SKILL_DIR/scripts/run-worker.sh"
# -d: do not switch the user away from the window they are on.
wid=$(tmux new-window -d -P -F '#{window_id}' -t "=$sess:" -n "$name" -c "$root" \
    "bash $(printf '%q' "$runner") $(printf '%q' "$name")")
tmux set-window-option -t "$wid" automatic-rename off >/dev/null
tmux set-window-option -t "$wid" window-status-style "fg=$color,bold" >/dev/null
tmux set-window-option -t "$wid" window-status-current-style "fg=black,bg=$color,bold" >/dev/null
set_worker "$root" "$name" '.tmuxSession=$s | .tmuxWindow=$w' --arg s "$sess" --arg w "$wid"
request_remote_tab "$sess" "$wid" "$name"

# Wait for the window to start and register its PID.
for _ in $(seq 1 40); do
    sleep 0.5
    status=$(read_worker "$root" "$name" | jq -r .status)
    [ "$status" = starting ] || break
done
if [ "$status" = running ]; then
    echo "Spawned worker '$name' (host PID $(read_worker "$root" "$name" | jq -r .hostPid)) in tmux window $sess:$name: mode $mode, colour $color."
    echo "$attach_hint"
else
    echo "WARNING: worker '$name' did not report running within 20s (status: $status). Check tmux session $sess."
fi
