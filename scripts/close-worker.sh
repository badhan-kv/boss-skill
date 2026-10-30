#!/usr/bin/env bash
# Boss: close a worker's session and tmux window. Send the wrap-up instruction and wait for its DONE first.
# Usage: close-worker.sh --name N [--root DIR]
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

name= root=$PWD
while [ $# -gt 0 ]; do
    case $1 in
        --name) name=$2; shift 2 ;;
        --root) root=$2; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done
[ -n "$name" ] || { echo "Need --name" >&2; exit 2; }
root=$(cd "$root" && pwd)
w=$(read_worker "$root" "$name") || { echo "No worker '$name' registered under $root" >&2; exit 1; }
hostpid=$(jq -r '.hostPid // empty' <<<"$w")
win=$(jq -r '.tmuxWindow // empty' <<<"$w")

# A worker moved into a Claude background session: stop that session (its window's attach loop
# then ends and the window closes).
if bg=$(bg_session_id "$root" "$name"); then
    claude stop "$bg" >/dev/null 2>&1
    for _ in $(seq 1 30); do bg_session_id "$root" "$name" >/dev/null || break; sleep 1; done
    if bg_session_id "$root" "$name" >/dev/null; then
        echo "Worker '$name' (background session $bg) did not stop; check 'claude agents'." >&2
        exit 1
    fi
    worker_alive "$w" || { [ -n "$win" ] && tmux kill-window -t "$win" 2>/dev/null; }
    set_worker "$root" "$name" '.status="closed" | .ended=$t' --arg t "$(date +%Y-%m-%dT%H:%M:%S)"
    echo "Closed worker '$name' (background session $bg)."
    exit 0
fi

if ! worker_alive "$w"; then
    set_worker "$root" "$name" '.status="closed"'
    echo "Worker '$name' is not running (already closed)."
    exit 0
fi

# Stop only claude (the window script's child); run-worker.sh then exits cleanly and the window closes.
pkill -TERM -P "$hostpid"
for _ in $(seq 1 50); do worker_alive "$w" || break; sleep 0.3; done
if worker_alive "$w"; then
    pkill -KILL -P "$hostpid"; kill -TERM "$hostpid" 2>/dev/null
    [ -n "$win" ] && tmux kill-window -t "$win" 2>/dev/null
    set_worker "$root" "$name" '.status="closed" | .ended=$t' --arg t "$(date +%Y-%m-%dT%H:%M:%S)"
    echo "Worker '$name' did not exit on its own; it was force-stopped."
else
    echo "Closed worker '$name'."
fi
