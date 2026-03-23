param(
    [Parameter(Mandatory = $false)]
    [double]$Refresh = 2,

    [Parameter(Mandatory = $false)]
    [string]$TaskId,

    [Parameter(Mandatory = $false)]
    [switch]$AllTasks,

    [Parameter(Mandatory = $false)]
    [switch]$Once,

    [Parameter(Mandatory = $false)]
    [string]$TeamLeadPaneId,

    [Parameter(Mandatory = $false)]
    [ValidateSet('standalone', 'merged-right')]
    [string]$LayoutMode = 'standalone',

    [Parameter(Mandatory = $false)]
    [string]$PairedTeamLeadPaneId,

    [Parameter(Mandatory = $false)]
    [int]$SplitPercent = 38,

    [Parameter(Mandatory = $false)]
    [switch]$RunChild
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Split-Path -Parent $scriptDir
$python = if ($env:PYTHON) { $env:PYTHON } else { 'python' }
$monitorScript = Join-Path $scriptDir 'rich-monitor.py'

function Normalize-PaneId([string]$value) {
    if (-not $value) { return $null }
    $trimmed = $value.Trim()
    if ($trimmed -match '(\d+)') {
        return $Matches[1]
    }
    return $null
}

function New-ChildArgumentList {
    $childArgs = @(
        '-RunChild',
        '-LayoutMode', $LayoutMode,
        '-SplitPercent', [string]$SplitPercent,
        '-Refresh', [string]$Refresh
    )
    if ($TaskId) { $childArgs += @('-TaskId', $TaskId) }
    if ($AllTasks.IsPresent) { $childArgs += '-AllTasks' }
    if ($Once.IsPresent) { $childArgs += '-Once' }
    if ($PairedTeamLeadPaneId) { $childArgs += @('-PairedTeamLeadPaneId', $PairedTeamLeadPaneId) }
    return $childArgs
}

if (-not $RunChild.IsPresent) {
    $normalizedTeamLeadPaneId = Normalize-PaneId($TeamLeadPaneId)
    if ($normalizedTeamLeadPaneId) {
        $childArgs = @(
            'cli', 'split-pane',
            '--pane-id', $normalizedTeamLeadPaneId,
            '--horizontal',
            '--percent', [string]$SplitPercent,
            '--cwd', $rootDir,
            'powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass',
            '-File', $MyInvocation.MyCommand.Path
        )
        $LayoutMode = 'merged-right'
        $PairedTeamLeadPaneId = $normalizedTeamLeadPaneId
        $childArgs += @(New-ChildArgumentList)

        $spawnOutput = & wezterm @childArgs 2>&1
        $newPaneId = Normalize-PaneId([string]$spawnOutput)
        if ($LASTEXITCODE -ne 0 -or -not $newPaneId) {
            Write-Error ('Rich 看板右侧分栏启动失败：' + [string]$spawnOutput)
            exit 1
        }

        Write-Host ('[OK] Rich 看板已附着到 Team Lead 右侧窗格：pane ' + $newPaneId) -ForegroundColor Green
        exit 0
    }
}

$env:CCB_RICH_LAYOUT_MODE = $LayoutMode
$env:CCB_RICH_TEAMLEAD_PANE_ID = if ($PairedTeamLeadPaneId) { $PairedTeamLeadPaneId } else { '' }

$args = @($monitorScript, '--root', $rootDir, '--refresh', [string]$Refresh)
if ($TaskId) { $args += @('--task', $TaskId) }
if ($AllTasks.IsPresent) { $args += '--all-tasks' }
if ($Once.IsPresent) { $args += '--once' }

& $python @args
exit $LASTEXITCODE
