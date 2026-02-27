Param(
    [string]$Config = ".ccb\ccb.config"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

Write-Host "[CCB-START] Starting CCB with config: $Config"

$ccbPath = Get-Command ccb -ErrorAction SilentlyContinue
if (-not $ccbPath) {
    Write-Error "CCB not found. Please install CCB first."
    exit 1
}

& ccb

Write-Host "[CCB-START] CCB started successfully"
Write-Host "  Use 'ask <worker> <message>' to send tasks"
Write-Host "  Use 'pend <worker>' to wait for responses"
Write-Host "  Use 'ping <worker>' to check status"
