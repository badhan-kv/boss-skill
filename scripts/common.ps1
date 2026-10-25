# Shared helpers for the boss skill scripts. Dot-source this file.

$script:SkillDir = Split-Path -Parent $PSScriptRoot

function Write-Utf8NoBom([string]$Path, [string]$Text) {
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding $false))
}

function Get-AgentsDir([string]$Root) { Join-Path $Root '.agents' }

function Get-WorkerFile([string]$Root, [string]$Name) {
    Join-Path (Get-AgentsDir $Root) "workers\$Name.json"
}

function Read-Worker([string]$Root, [string]$Name) {
    $f = Get-WorkerFile $Root $Name
    if (-not (Test-Path $f)) { return $null }
    Get-Content -Raw -Encoding UTF8 $f | ConvertFrom-Json
}

function Save-Worker([string]$Root, $Worker) {
    Write-Utf8NoBom (Get-WorkerFile $Root $Worker.name) ($Worker | ConvertTo-Json -Depth 5)
}

function Set-WorkerField([string]$Root, [string]$Name, [hashtable]$Fields) {
    $w = Read-Worker $Root $Name
    if (-not $w) { throw "No worker '$Name' registered under $Root\.agents\workers" }
    foreach ($k in $Fields.Keys) {
        if ($w.PSObject.Properties[$k]) { $w.$k = $Fields[$k] }
        else { $w | Add-Member -NotePropertyName $k -NotePropertyValue $Fields[$k] }
    }
    Save-Worker $Root $w
}

# Colour coding: the boss is gold; each worker gets the first palette colour no running worker uses.
$script:BossColor = '#FFB300'
$script:WorkerPalette = @('#1E88E5', '#43A047', '#8E24AA', '#F4511E', '#00ACC1', '#D81B60', '#7CB342', '#5E35B1')

function Get-FreeWorkerColor([string]$Root) {
    $used = @()
    $dir = Join-Path (Get-AgentsDir $Root) 'workers'
    if (Test-Path $dir) {
        foreach ($f in Get-ChildItem $dir -Filter '*.json') {
            $w = Get-Content -Raw -Encoding UTF8 $f.FullName | ConvertFrom-Json
            if ($w.color -and $w.status -ne 'closed') { $used += $w.color }
        }
    }
    foreach ($c in $script:WorkerPalette) { if ($used -notcontains $c) { return $c } }
    $script:WorkerPalette[$used.Count % $script:WorkerPalette.Count]
}

# ANSI true-colour foreground escape for a '#RRGGBB' colour.
function Get-AnsiColor([string]$Hex) {
    $h = $Hex.TrimStart('#')
    "$([char]27)[1;38;2;{0};{1};{2}m" -f [Convert]::ToInt32($h.Substring(0, 2), 16),
        [Convert]::ToInt32($h.Substring(2, 2), 16), [Convert]::ToInt32($h.Substring(4, 2), 16)
}

# Permission mode the boss is in now (recorded by the boss skill's hook), as a claude CLI value.
function Get-BossPermissionMode([string]$Root) {
    $f = Join-Path (Get-AgentsDir $Root) 'boss.json'
    if (-not (Test-Path $f)) { return $null }
    $m = (Get-Content -Raw -Encoding UTF8 $f | ConvertFrom-Json).permissionMode
    if ($m -eq 'default') { return 'manual' }   # hooks report Manual as 'default'
    $m
}

# Index of the selected tab in the foreground Windows Terminal window (the one 'wt -w 0' targets),
# so a new worker tab can hand focus straight back to it. $null if it cannot be read.
function Get-SelectedTabIndex {
    try {
        Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
        Add-Type -Namespace BossSkill -Name Win -MemberDefinition '[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();' -ErrorAction SilentlyContinue
        $ae = [Windows.Automation.AutomationElement]
        $wtCond = New-Object Windows.Automation.PropertyCondition($ae::ClassNameProperty, 'CASCADIA_HOSTING_WINDOW_CLASS')
        $tabCond = New-Object Windows.Automation.PropertyCondition($ae::ControlTypeProperty, [Windows.Automation.ControlType]::TabItem)
        $windows = @($ae::RootElement.FindAll([Windows.Automation.TreeScope]::Children, $wtCond))
        if (-not $windows) { return $null }
        $fg = [BossSkill.Win]::GetForegroundWindow().ToInt64()
        $win = $windows | Where-Object { $_.Current.NativeWindowHandle -eq $fg } | Select-Object -First 1
        if (-not $win) { $win = $windows[0] }
        $i = 0
        foreach ($t in $win.FindAll([Windows.Automation.TreeScope]::Descendants, $tabCond)) {
            if ($t.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Current.IsSelected) { return $i }
            $i++
        }
    } catch {}
    $null
}

# Make sure .agents/ is ignored when the project is a git repo or already has a .gitignore.
function Ensure-AgentsIgnored([string]$Root) {
    $gi = Join-Path $Root '.gitignore'
    $isRepo = Test-Path (Join-Path $Root '.git')
    if (-not $isRepo -and -not (Test-Path $gi)) { return }
    if ((Test-Path $gi) -and (Select-String -Path $gi -Pattern '^\.agents/?$' -Quiet)) { return }
    Add-Content -Path $gi -Value '.agents/' -Encoding UTF8
}
