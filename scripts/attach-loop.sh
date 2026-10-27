#!/usr/bin/env bash
# Runs in a worker's tmux window: attach to the worker's Claude background session and reattach
# whenever the attach returns, until the session ends. Then mark the worker closed.
# Usage: attach-loop.sh ROOT NAME
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
root=$1 name=$2
printf '\033]2;%s\007' "$name"
while bg=$(bg_session_id "$root" "$name"); do
    set_worker "$root" "$name" '.status="background" | .bgId=$id' --arg id "$bg"
    claude attach "$bg" || sleep 2
done
set_worker "$root" "$name" '.status="closed" | .ended=$t' --arg t "$(date +%Y-%m-%dT%H:%M:%S)"
