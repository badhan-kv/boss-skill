# Sourced from ~/.bashrc. On an interactive SSH login outside tmux, reopen worker windows for
# every project that has running workers and attach to the first such tmux session.
# Ctrl-b d detaches back to the login shell. Set BOSS_AUTO_ATTACH=0 to turn it off.
if [[ $- == *i* ]] && [ -n "${SSH_CONNECTION:-}" ] && [ -z "${TMUX:-}" ] && [ -t 0 ] && [ -t 1 ] \
    && [ "${BOSS_AUTO_ATTACH:-1}" != 0 ] && command -v tmux >/dev/null && command -v jq >/dev/null; then
    _boss_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    if [ -s "$_boss_dir/state/roots.txt" ]; then
        _boss_target=
        while IFS= read -r _boss_root; do
            [ -d "$_boss_root/.agents/workers" ] || continue
            bash "$_boss_dir/scripts/open-windows.sh" --root "$_boss_root" >/dev/null 2>&1
            _boss_sess="boss-$(basename "$_boss_root" | tr -c "A-Za-z0-9_\n-" "_" | tr -d "\n")"
            # Attach only when the session has a worker window besides "home".
            if [ -z "$_boss_target" ] && [ "$(tmux list-windows -t "=$_boss_sess" -F '#W' 2>/dev/null \
                | grep -cvx home)" -gt 0 ]; then
                _boss_target=$_boss_sess
            fi
        done < "$_boss_dir/state/roots.txt"
        [ -n "$_boss_target" ] && tmux attach -t "=$_boss_target"
    fi
    unset _boss_dir _boss_root _boss_sess _boss_target
fi
