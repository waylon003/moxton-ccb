#!/usr/bin/env pwsh
# route-watcher.ps1 - 监听 route inbox，检测到新 route 后输出并退出
# 供 Claude Code background task 使用
# Exit codes: 0=route found, 1=timeout, 2=script error
param(
    [int]$PollInterval = 5,
    [int]$Timeout = 600,
    [string]$FilterTask
)

$inboxPath = Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) "mcp\route-server\data\route-inbox.json"
$elapsed = 0
$parseFailCount = 0

try {
    while ($elapsed -lt $Timeout) {
        if (Test-Path $inboxPath) {
            $inbox = $null
            for ($retry = 0; $retry -lt 3; $retry++) {
                try {
                    $inbox = Get-Content $inboxPath -Raw -Encoding UTF8 | ConvertFrom-Json
                    $parseFailCount = 0
                    break
                } catch {
                    Start-Sleep -Milliseconds 200
                }
            }
            if (-not $inbox) {
                $parseFailCount++
                if ($parseFailCount -ge 5) {
                    Write-Output "[ROUTE-ERROR] inbox JSON parse failed 5 consecutive cycles"
                    exit 2
                }
            } elseif ($inbox) {
                $pending = @($inbox.routes | Where-Object { -not $_.processed })
                if ($FilterTask) {
                    $pending = @($pending | Where-Object { $_.task -eq $FilterTask })
                }
                if ($pending.Count -gt 0) {
                    foreach ($r in $pending) {
                        $rid = if ($r.id) { $r.id } else { "unknown" }
                        Write-Output "[ROUTE-READY] route_id=$rid task=$($r.task) from=$($r.from) status=$($r.status) body=$($r.body)"
                    }
                    exit 0
                }
            }
        }
        Start-Sleep -Seconds $PollInterval
        $elapsed += $PollInterval
    }
} catch {
    Write-Output "[ROUTE-ERROR] $($_.Exception.Message)"
    exit 2
}

Write-Output "[ROUTE-TIMEOUT] No routes after ${Timeout}s for task=$FilterTask"
exit 1
