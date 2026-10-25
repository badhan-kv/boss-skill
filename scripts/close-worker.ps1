# Boss: close a worker's session and tab. Send the wrap-up instruction and wait for its DONE first.
param(
    [Parameter(Mandatory)][string]$Name,
    [string]$Root = (Get-Location).Path
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"

$Root = (Resolve-Path $Root).Path.TrimEnd('\')
$w = Read-Worker $Root $Name
if (-not $w) { throw "No worker '$Name' registered under $Root" }
if (-not $w.hostPid -or -not (Get-Process -Id $w.hostPid -ErrorAction SilentlyContinue)) {
    Set-WorkerField $Root $Name @{ status = 'closed' }
    "Worker '$Name' is not running (already closed)."
    return
}

# Stop only claude (the tab's child process); run-worker.ps1 then exits cleanly and the tab closes.
$kids = Get-CimInstance Win32_Process -Filter "ParentProcessId=$($w.hostPid)" |
    Where-Object { $_.Name -eq 'claude.exe' }
foreach ($k in $kids) { Stop-Process -Id $k.ProcessId -Force -ErrorAction SilentlyContinue }

$deadline = (Get-Date).AddSeconds(15)
while ((Get-Process -Id $w.hostPid -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 300
}
if (Get-Process -Id $w.hostPid -ErrorAction SilentlyContinue) {
    Stop-Process -Id $w.hostPid -Force -ErrorAction SilentlyContinue
    Set-WorkerField $Root $Name @{ status = 'closed'; ended = (Get-Date).ToString('s') }
    "Worker '$Name' tab host did not exit on its own; it was force-stopped (tab may show an exit message)."
} else {
    "Closed worker '$Name'."
}
