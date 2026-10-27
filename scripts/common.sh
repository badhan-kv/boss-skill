#!/usr/bin/env bash
# Shared helpers for the boss skill scripts. Source this file.

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

agents_dir() { echo "$1/.agents"; }
worker_file() { echo "$1/.agents/workers/$2.json"; }

# read_worker ROOT NAME -> prints the registry JSON, returns 1 if missing.
read_worker() {
    local f; f=$(worker_file "$1" "$2")
    [ -f "$f" ] && cat "$f"
}

# save_worker ROOT NAME JSON
save_worker() {
    local f; f=$(worker_file "$1" "$2")
    mkdir -p "$(dirname "$f")"
    printf '%s\n' "$3" > "$f"
}

# set_worker ROOT NAME JQ_FILTER [jq args...] -> updates the registry entry in place.
set_worker() {
    local root=$1 name=$2 filter=$3; shift 3
    local f tmp; f=$(worker_file "$root" "$name")
    [ -f "$f" ] || { echo "No worker '$name' registered under $root/.agents/workers" >&2; return 1; }
    tmp=$(mktemp) && jq "$@" "$filter" "$f" > "$tmp" && mv "$tmp" "$f"
}

# Colour coding: the boss is gold; each worker gets the first palette colour no running worker uses.
BOSS_COLOR='#FFB300'
WORKER_PALETTE=('#1E88E5' '#43A047' '#8E24AA' '#F4511E' '#00ACC1' '#D81B60' '#7CB342' '#5E35B1')

free_worker_color() {
    local root=$1 used="" f c
    for f in "$root"/.agents/workers/*.json; do
        [ -f "$f" ] || continue
        used+=" $(jq -r 'select(.status != "closed") | .color // empty' "$f")"
    done
    for c in "${WORKER_PALETTE[@]}"; do
        case " $used " in *" $c "*) ;; *) echo "$c"; return ;; esac
    done
    local n; n=$(echo $used | wc -w)
    echo "${WORKER_PALETTE[$((n % ${#WORKER_PALETTE[@]}))]}"
}

# Permission mode the boss is in now (recorded by the boss skill's hook), as a claude CLI value.
boss_permission_mode() {
    local f="$1/.agents/boss.json" m
    [ -f "$f" ] || return 0
    m=$(jq -r '.permissionMode // empty' "$f")
    [ "$m" = default ] && m=manual   # hooks report Manual as 'default'
    echo "$m"
}

# Make sure .agents/ is ignored when the project is a git repo or already has a .gitignore.
ensure_agents_ignored() {
    local root=$1 gi="$1/.gitignore"
    [ -e "$root/.git" ] || [ -f "$gi" ] || return 0
    grep -qE '^\.agents/?$' "$gi" 2>/dev/null && return 0
    echo '.agents/' >> "$gi"
}

pid_alive() { [ -n "$1" ] && [ "$1" != null ] && kill -0 "$1" 2>/dev/null; }

# A worker session can be moved into a Claude background session (e.g. by a /bg-style command);
# its claude in the tmux window then exits. bg_session_id ROOT NAME prints the id of the live
# background session with that exact name started under ROOT, or returns 1.
bg_session_id() {
    local id
    id=$(claude agents --json 2>/dev/null | jq -r --arg n "$2" --arg c "$1" \
        'map(select(.kind == "background" and .name == $n and .cwd == $c)) | .[0].id // empty' 2>/dev/null)
    [ -n "$id" ] && echo "$id"
}

# tmux session that holds the workers when the boss does not run inside tmux.
boss_tmux_session() { echo "boss-$(basename "$1" | tr -c "A-Za-z0-9_\n-" "_" | tr -d "\n")"; }

# Project roots that have had workers, for the SSH login hook.
ROOTS_FILE="$SKILL_DIR/state/roots.txt"
remember_root() {
    mkdir -p "$(dirname "$ROOTS_FILE")"
    grep -qxF "$1" "$ROOTS_FILE" 2>/dev/null || echo "$1" >> "$ROOTS_FILE"
}

# Terminal tabs on the PC the user SSHes in from: boss-ssh.ps1 on that PC starts the SSH session
# with BOSS_TAB_ID set (a random id per connection, so it works over any network path). A worker
# window spawned from that session (outside tmux) is queued here; tab-feed.sh, run over SSH by the
# same boss-ssh.ps1 with the same id, passes it on. Without BOSS_TAB_ID nothing is queued.
TAB_REQ_DIR="$SKILL_DIR/state/tab-requests"
# request_remote_tab SESS WINDOW_ID NAME
request_remote_tab() {
    [ -n "${BOSS_TAB_ID:-}" ] && [ -z "${TMUX:-}" ] || return 0
    mkdir -p "$TAB_REQ_DIR"
    local f; f="$TAB_REQ_DIR/$(date +%s%N)-$3"
    printf '%s\t%s\t%s\t%s\n' "$BOSS_TAB_ID" "$1" "$2" "$3" > "$f.tmp" && mv "$f.tmp" "$f"
}
