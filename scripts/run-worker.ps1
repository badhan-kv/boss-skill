# Runs inside the worker's terminal tab: sets the worker environment and starts claude.
# When claude exits (or close-worker.ps1 stops it) this script exits 0 and the tab closes.
param([Parameter(Mandatory)][string]$Name)
. "$PSScriptRoot\common.ps1"

$Root = (Get-Location).Path
$w = Read-Worker $Root $Name
if (-not $w) { Write-Host "No worker '$Name' registered under $Root"; Read-Host 'Press Enter to close'; exit 1 }

# spawn-worker.ps1 opens the tab with a fresh environment (--reloadEnvironment). As a fallback, in
# case the tab still inherited the boss's command environment, drop what must not carry over: the
# boss's session identity (so this claude registers as its own session and cannot see the boss's
# messaging token), NO_COLOR (turns all colour off) and the non-interactive git/tool settings.
foreach ($v in 'CLAUDECODE', 'CLAUDE_PID', 'CLAUDE_CODE_SESSION_ID', 'CLAUDE_CODE_CHILD_SESSION',
               'CLAUDE_CODE_BRIDGE_SESSION_ID', 'CLAUDE_CODE_ENTRYPOINT', 'CLAUDE_CODE_SESSION_ATTENDED',
               'CLAUDE_CODE_MESSAGING_SOCKET', 'CLAUDE_CODE_MESSAGING_TOKEN', 'NO_COLOR', 'AI_AGENT',
               'GIT_ASKPASS', 'GIT_EDITOR', 'GIT_TERMINAL_PROMPT', 'GCM_INTERACTIVE', 'COREPACK_ENABLE_AUTO_PIN',
               'PSExecutionPolicyPreference') {
    Remove-Item "Env:\$v" -ErrorAction SilentlyContinue
}

$env:AGENT_NAME = $Name
$env:AGENT_BOSS = $w.boss
$env:AGENT_ROOT = $Root
$env:AGENT_SKILL_DIR = $script:SkillDir
$Host.UI.RawUI.WindowTitle = $Name

$consolePid = (Get-CimInstance Win32_Process -Filter "ProcessId=$PID").ParentProcessId
Set-WorkerField $Root $Name @{ status = 'running'; hostPid = $PID; consolePid = $consolePid; started = (Get-Date).ToString('s') }

$role = Get-Content -Raw -Encoding UTF8 (Join-Path $script:SkillDir 'worker-role.md')
$role = $role.Replace('{{NAME}}', $Name).Replace('{{BOSS}}', $w.boss)
$prompt = "You are worker '$Name'. Your boss session is '$($w.boss)'. Read your brief at .agents/briefs/$Name.md and start."

$claudeArgs = @(
    '--name', $Name,
    '--settings', (Join-Path $script:SkillDir 'worker-settings.json'),
    '--append-system-prompt', $role,
    '--permission-mode', $w.permissionMode
)
if ($w.model) { $claudeArgs += @('--model', $w.model) }
$claudeArgs += $prompt

& claude @claudeArgs
$code = $LASTEXITCODE

Set-WorkerField $Root $Name @{ status = 'closed'; ended = (Get-Date).ToString('s'); exitCode = $code }
exit 0
