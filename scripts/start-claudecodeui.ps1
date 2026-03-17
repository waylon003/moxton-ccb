#!/usr/bin/env pwsh
# 启动 Claude Code UI（cloudcli）
# 用法:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/start-claudecodeui.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/start-claudecodeui.ps1 -Port 3001
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/start-claudecodeui.ps1 -Public
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/start-claudecodeui.ps1 -UseWezTerm
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/start-claudecodeui.ps1 -DatabasePath "C:\Users\26249\.cloudcli\cloudcli.db"

param(
    [Parameter(Mandatory=$false)]
    [int]$Port = 3001,

    [Parameter(Mandatory=$false)]
    [string]$BindHost = "127.0.0.1",

    [Parameter(Mandatory=$false)]
    [string]$NodeVersion = "20.12.2",

    [Parameter(Mandatory=$false)]
    [string]$DatabasePath,

    [Parameter(Mandatory=$false)]
    [switch]$Public,

    [Parameter(Mandatory=$false)]
    [switch]$UseWezTerm
)

$ErrorActionPreference = "Stop"

if ($Public) {
    $BindHost = "0.0.0.0"
}

$nvm = Get-Command nvm -ErrorAction SilentlyContinue
$useNvm = $false
if ($nvm -and -not [string]::IsNullOrWhiteSpace($NodeVersion)) {
    $useNvm = $true
}

function Ensure-NodeVersion {
    param([string]$Version)
    if (-not $useNvm) { return }
    & nvm use $Version | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host ("[FAIL] nvm use failed: " + $Version) -ForegroundColor Red
        exit 1
    }
}

function Resolve-Cloudcli {
    $cmd = Get-Command cloudcli -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd }

    $prefix = $null
    try { $prefix = (npm config get prefix 2>$null).Trim() } catch {}
    $candidates = @()
    if ($prefix) {
        $candidates += @(
            (Join-Path $prefix "cloudcli.cmd"),
            (Join-Path $prefix "cloudcli.ps1"),
            (Join-Path $prefix "cloudcli")
        )
    }
    $candidates += @(
        "C:\nvm4w\nodejs\cloudcli.cmd",
        "C:\nvm4w\nodejs\cloudcli.ps1",
        "C:\Users\26249\AppData\Roaming\npm\cloudcli.cmd",
        "C:\Users\26249\AppData\Roaming\npm\cloudcli.ps1"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) {
            return (Get-Command $c -ErrorAction SilentlyContinue)
        }
    }

    Write-Host "[FAIL] cloudcli not found. Install under the active Node version:" -ForegroundColor Red
    Write-Host "       npm i -g @siteboon/claude-code-ui@latest" -ForegroundColor Yellow
    exit 1
}

$env:PORT = "$Port"
$env:HOST = "$BindHost"

$args = @()
if ($DatabasePath) {
    $args += @("--database-path", $DatabasePath)
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Claude Code UI (cloudcli)" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ("Host: " + $BindHost)
Write-Host ("Port: " + $Port)
if ($useNvm) {
    Write-Host ("Node: " + $NodeVersion)
}
if ($DatabasePath) {
    Write-Host ("DB:   " + $DatabasePath)
}
Write-Host ""

if ($UseWezTerm) {
    $launchCmd = ""
    if ($useNvm) {
        $launchCmd += 'nvm use ' + $NodeVersion + '; '
    }
    $launchCmd += '$env:PORT=' + "'" + $Port + "'" + '; $env:HOST=' + "'" + $BindHost + "'" + '; cloudcli'
    if ($DatabasePath) {
        $launchCmd += ' --database-path "' + $DatabasePath + '"'
    }

    $spawnArgs = @(
        "cli", "spawn",
        "powershell", "-NoExit", "-Command", $launchCmd
    )

    Write-Host "[INFO] Starting in WezTerm pane..." -ForegroundColor Cyan
    & wezterm @spawnArgs 2>$null | Out-Null
    Write-Host "[OK] UI started (WezTerm pane)." -ForegroundColor Green
} else {
    Write-Host "[INFO] Starting in current terminal..." -ForegroundColor Cyan
    if ($useNvm) {
        Ensure-NodeVersion -Version $NodeVersion
        $cloudcli = Resolve-Cloudcli
        & $cloudcli.Source @args
    } else {
        $cloudcli = Resolve-Cloudcli
        & $cloudcli.Source @args
    }
}

Write-Host ""
Write-Host ("Open: http://" + $BindHost + ":" + $Port) -ForegroundColor Green
Write-Host ""
