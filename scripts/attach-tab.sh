#!/usr/bin/env bash
# Runs in a terminal tab on the PC (started by boss-ssh.ps1 over SSH): shows one worker window in
# a tmux session of its own, so each tab stays on its worker. The tab ends when the worker window
# closes; closing the tab removes the view session but leaves the worker running.
# Usage: attach-tab.sh SESSION WINDOW_ID NAME
sess=$1 wid=$2 name=$3
tmux list-windows -a -F '#{window_id}' 2>/dev/null | grep -qxF "$wid" || { echo "Worker window $name ($wid) is gone."; sleep 3; exit 0; }
view="tab-$name-$$"
tmux new-session -d -s "$view" -n tmp
tmux link-window -s "$wid" -t "$view:"
tmux kill-window -t "$view:tmp"
# Set only once attached: on an unattached session it would end the session at once.
exec tmux attach -t "=$view" \; set-option destroy-unattached on
