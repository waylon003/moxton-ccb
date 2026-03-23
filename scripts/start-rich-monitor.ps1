param(
    [Parameter(Mandatory = $false)]
    [double]$Refresh = 2,

    [Parameter(Mandatory = $false)]
    [string]$TaskId,

    [Parameter(Mandatory = $false)]
    [switch]$AllTasks,

    [Parameter(Mandatory = $false)]
    [switch]$Once
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Split-Path -Parent $scriptDir
$python = if ($env:PYTHON) { $env:PYTHON } else { 'python' }
$monitorScript = Join-Path $scriptDir 'rich-monitor.py'

$args = @($monitorScript, '--root', $rootDir, '--refresh', [string]$Refresh)
if ($TaskId) { $args += @('--task', $TaskId) }
if ($AllTasks.IsPresent) { $args += '--all-tasks' }
if ($Once.IsPresent) { $args += '--once' }

& $python @args
exit $LASTEXITCODE
