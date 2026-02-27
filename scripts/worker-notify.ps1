#!/usr/bin/env pwsh
# Worker 退出后发送 [ROUTE] 通知给 Team Lead
# 由 start-worker.ps1 的 wrapper 自动调用，不要手动执行
param(
    [Parameter(Mandatory=$true)][string]$TeamLeadPaneId,
    [Parameter(Mandatory=$true)][string]$WorkerName,
    [Parameter(Mandatory=$true)][string]$WorkDir,
    [Parameter(Mandatory=$true)][int]$ExitCode
)

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$status = if ($ExitCode -eq 0) { "success" } else { "fail" }

$msg = @"
[ROUTE]
from: $WorkerName
to: team-lead
type: status
task: UNKNOWN
status: $status
timestamp: $timestamp
exit_code: $ExitCode
body:
  Worker $WorkerName exited with code $ExitCode
  WorkDir: $WorkDir
[/ROUTE]
"@

Write-Host ""
Write-Host "Worker exited (Exit Code: $ExitCode)" -ForegroundColor $(if ($ExitCode -eq 0) { "Green" } else { "Red" })
Write-Host "Sending notification to Team Lead..." -ForegroundColor Cyan

wezterm cli send-text --pane-id $TeamLeadPaneId --no-paste $msg
Start-Sleep -Milliseconds 200
wezterm cli send-text --pane-id $TeamLeadPaneId --no-paste ([string][char]13)

Write-Host "Notification sent." -ForegroundColor Green
