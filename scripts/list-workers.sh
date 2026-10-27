#!/usr/bin/env bash
# Boss: list registered workers with their task and whether their process is still alive.
# Usage: list-workers.sh [--root DIR]
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
root=$PWD
[ "${1:-}" = --root ] && root=$2

shopt -s nullglob
files=("$root"/.agents/workers/*.json)
[ ${#files[@]} -gt 0 ] || { echo 'No workers registered.'; exit 0; }
printf '%-24s %-10s %-6s %s\n' NAME STATUS ALIVE TASK
for f in "${files[@]}"; do
    pid=$(jq -r '.hostPid // empty' "$f")
    pid_alive "$pid" && alive=yes || alive=no
    printf '%-24s %-10s %-6s %s\n' "$(jq -r .name "$f")" "$(jq -r .status "$f")" "$alive" "$(jq -r .task "$f")"
done
