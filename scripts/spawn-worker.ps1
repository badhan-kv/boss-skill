# Open a worker session in a new Windows Terminal tab.
# The brief must already exist at <Root>\.agents\briefs\<Name>.md.
param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Task,
    [Parameter(Mandatory)][string]$Boss,
    [string]$Root = (Get-Location).Path,
    # Default: the boss's current mode (recorded by the boss skill's hook), else auto.
    [ValidateSet('', 'auto', 'acceptEdits', 'manual', 'plan', 'dontAsk', 'bypassPermissions')]
    [string]$PermissionMode = '',
    [string]$Model = ''
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"

if ($Name -notmatch '^[a-z0-9][a-z0-9-]{0,39}$') {
    throw "Worker name must be lowercase letters, digits and hyphens (max 40), e.g. worker-api"
}
$Root = (Resolve-Path $Root).Path.TrimEnd('\')
$brief = Join-Path (Get-AgentsDir $Root) "briefs\$Name.md"
if (-not (Test-Path $brief)) { throw "Brief not found: $brief (write it before spawning)" }

$existing = Read-Worker $Root $Name
if ($existing -and $existing.status -eq 'running' -and $existing.hostPid -and
    (Get-Process -Id $existing.hostPid -ErrorAction SilentlyContinue)) {
    throw "Worker '$Name' is already running (host PID $($existing.hostPid))"
}

if (-not $PermissionMode) { $PermissionMode = Get-BossPermissionMode $Root }
if (-not $PermissionMode) { $PermissionMode = 'auto' }
$color = Get-FreeWorkerColor $Root

New-Item -ItemType Directory -Force (Join-Path (Get-AgentsDir $Root) 'events') | Out-Null
Write-Utf8NoBom (Join-Path (Get-AgentsDir $Root) "tasks\$Name.txt") $Task
Ensure-AgentsIgnored $Root

Save-Worker $Root ([pscustomobject]@{
    name           = $Name
    task           = $Task
    boss           = $Boss
    root           = $Root
    permissionMode = $PermissionMode
    color          = $color
    model          = $Model
    status         = 'starting'
    hostPid        = $null
    created        = (Get-Date).ToString('s')
})

# wt.exe treats ';' as a command separator, so none of these values may contain one.
$runner = Join-Path $PSScriptRoot 'run-worker.ps1'
# --reloadEnvironment: give the tab a fresh environment like a normally opened tab. Without it the
# tab inherits the boss's command environment (NO_COLOR=1 turns all colour off in the worker,
# plus the boss's session identity and git prompt settings).
$wtArgs = "-w 0 new-tab --reloadEnvironment --title `"$Name`" --tabColor `"$color`" -d `"$Root`" powershell -NoProfile -ExecutionPolicy Bypass -File `"$runner`" -Name $Name"
# Windows Terminal always focuses a new tab; switch straight back to the tab the user was on.
$back = Get-SelectedTabIndex
if ($null -ne $back) { $wtArgs += " ; focus-tab -t $back" }
Start-Process -FilePath 'wt.exe' -ArgumentList $wtArgs

# Wait for the tab to start and register its PID.
$deadline = (Get-Date).AddSeconds(20)
do {
    Start-Sleep -Milliseconds 500
    $w = Read-Worker $Root $Name
} while ($w.status -eq 'starting' -and (Get-Date) -lt $deadline)

if ($w.status -eq 'running') { "Spawned worker '$Name' (host PID $($w.hostPid)) in a new tab: mode $PermissionMode, colour $color." }
else { "WARNING: worker '$Name' did not report running within 20s (status: $($w.status)). Check the tabs." }
