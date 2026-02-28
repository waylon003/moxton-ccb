#!/usr/bin/env pwsh
# Worker 退出后通过 MCP report_route 通知 Team Lead
# 由 start-worker.ps1 的 wrapper 自动调用，不要手动执行
# NOTE: 此脚本作为 fallback，正常流程 Worker 应在会话内直接调用 MCP tool
param(
    [Parameter(Mandatory=$true)][string]$TeamLeadPaneId,
    [Parameter(Mandatory=$true)][string]$WorkerName,
    [Parameter(Mandatory=$true)][string]$WorkDir,
    [Parameter(Mandatory=$true)][int]$ExitCode
)

$status = if ($ExitCode -eq 0) { "success" } else { "fail" }

Write-Host ""
Write-Host "Worker exited (Exit Code: $ExitCode)" -ForegroundColor $(if ($ExitCode -eq 0) { "Green" } else { "Red" })
Write-Host "[INFO] Worker should have called MCP report_route before exiting." -ForegroundColor Yellow
Write-Host "[INFO] If not, Team Lead can check inbox via: check_routes" -ForegroundColor Yellow
