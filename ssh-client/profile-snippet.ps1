# Add to your PowerShell profile (notepad $PROFILE): plain "ssh kbadhan@ew-sim" then goes through
# boss-ssh.ps1, so boss workers get their own tabs. Any other ssh use is unchanged.
function ssh {
    if ($args.Count -eq 1 -and $args[0] -eq 'kbadhan@ew-sim') {
        powershell -NoProfile -ExecutionPolicy Bypass -File "$HOME\boss-ssh.ps1" $args[0]
    } else {
        ssh.exe @args
    }
}
