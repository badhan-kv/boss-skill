#!/usr/bin/env bash
# Runs inside the worker's tmux window: sets the worker environment and starts claude.
# When claude exits (or close-worker.sh stops it) this script exits and the window closes.
# Usage: run-worker.sh NAME   (cwd = project root)
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

name=$1
root=$PWD
w=$(read_worker "$root" "$name") || { echo "No worker '$name' registered under $root"; read -r -p 'Press Enter to close'; exit 1; }

# Drop what must not carry over from the boss's command environment: its session identity (so this
# claude registers as its own session and cannot see the boss's messaging token), NO_COLOR (turns
# all colour off) and the non-interactive git/tool settings.
unset CLAUDECODE CLAUDE_PID CLAUDE_CODE_SESSION_ID CLAUDE_CODE_CHILD_SESSION \
      CLAUDE_CODE_BRIDGE_SESSION_ID CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_SESSION_ATTENDED \
      CLAUDE_CODE_MESSAGING_SOCKET CLAUDE_CODE_MESSAGING_TOKEN NO_COLOR AI_AGENT \
      GIT_ASKPASS GIT_EDITOR GIT_TERMINAL_PROMPT GCM_INTERACTIVE COREPACK_ENABLE_AUTO_PIN

boss=$(jq -r .boss <<<"$w")
mode=$(jq -r .permissionMode <<<"$w")
model=$(jq -r '.model // empty' <<<"$w")

export AGENT_NAME=$name AGENT_BOSS=$boss AGENT_ROOT=$root AGENT_SKILL_DIR=$SKILL_DIR
printf '\033]2;%s\007' "$name"

set_worker "$root" "$name" '.status="running" | .hostPid=$pid | .hostStart=$st | .started=$t' \
    --argjson pid $$ --arg st "$(pid_start $$)" --arg t "$(date +%Y-%m-%dT%H:%M:%S)"

role=$(<"$SKILL_DIR/worker-role.md")
role=${role//\{\{NAME\}\}/$name}
role=${role//\{\{BOSS\}\}/$boss}
prompt="You are worker '$name'. Your boss session is '$boss'. Read your brief at .agents/briefs/$name.md and start."

args=(--name "$name" --settings "$SKILL_DIR/worker-settings.json"
      --append-system-prompt "$role" --permission-mode "$mode")
[ -n "$model" ] && args+=(--model "$model")
args+=("$prompt")

claude "${args[@]}"
code=$?

# If the session was moved into a Claude background session, keep this window: attach to it
# until it ends, so the user still finds the worker here.
sleep 2
if bg_session_id "$root" "$name" >/dev/null; then
    exec bash "$SKILL_DIR/scripts/attach-loop.sh" "$root" "$name"
fi

set_worker "$root" "$name" '.status="closed" | .ended=$t | .exitCode=$c' \
    --arg t "$(date +%Y-%m-%dT%H:%M:%S)" --argjson c "$code"
exit 0
