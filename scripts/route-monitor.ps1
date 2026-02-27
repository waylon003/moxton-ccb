#!/usr/bin/env pwsh
# [ROUTE] 消息监控器 - 自动解析 Worker 回执并更新任务锁
# 用法: .\route-monitor.ps1 -TeamLeadPaneId <id> [-Continuous]

param(
    [Parameter(Mandatory=$false)]
    [string]$TeamLeadPaneId = $env:TEAM_LEAD_PANE_ID,

    [Parameter(Mandatory=$false)]
    [switch]$Continuous,

    [Parameter(Mandatory=$false)]
    [int]$PollIntervalSeconds = 5
)

$ErrorActionPreference = "Stop"

# 验证环境
if (-not $TeamLeadPaneId) {
    Write-Error "TEAM_LEAD_PANE_ID 未设置。请先设置环境变量。"
    exit 1
}

# 获取项目根目录
$scriptDir = Split-Path $PSScriptRoot -Parent
$assignTaskScript = Join-Path $scriptDir "scripts\assign_task.py"

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "       [ROUTE] 消息监控器启动" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "Team Lead Pane ID: $TeamLeadPaneId" -ForegroundColor Cyan
if ($Continuous) {
    Write-Host "模式: 持续监控" -ForegroundColor Cyan
}
else {
    Write-Host "模式: 单次检查" -ForegroundColor Cyan
}
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

# 存储已处理的 ROUTE 消息（避免重复处理）
$processedRoutes = @{}

function Update-TaskLockFromRoute {
    param(
        [string]$TaskId,
        [string]$Status,
        [string]$WorkerName,
        [string]$Body
    )

    Write-Host "更新任务锁: $TaskId -> $Status" -ForegroundColor Yellow

    # 状态映射
    $lockState = switch ($Status.ToLower()) {
        "success" { "completed" }
        "fail" { "blocked" }
        "blocked" { "blocked" }
        "in_progress" { "in_progress" }
        "qa" { "qa" }
        default { $Status }
    }

    try {
        # 实际更新 TASK-LOCKS.json
        $locksFile = Join-Path $scriptDir "01-tasks\TASK-LOCKS.json"
        if (Test-Path $locksFile) {
            $locks = Get-Content $locksFile -Raw | ConvertFrom-Json

            if ($locks.locks.$TaskId) {
                $locks.locks.$TaskId.state = $lockState
                $locks.locks.$TaskId.updated_at = Get-Date -Format "o"
                $locks.locks.$TaskId.routeUpdate = @{
                    worker = $WorkerName
                    timestamp = Get-Date -Format "o"
                    bodyPreview = if ($Body.Length -gt 100) { $Body.Substring(0, 100) + "..." } else { $Body }
                }

                $locks | ConvertTo-Json -Depth 10 | Set-Content $locksFile -Encoding UTF8
                Write-Host "  任务锁已更新: $TaskId -> $lockState" -ForegroundColor Green

                # 如果状态是 completed，提示可以归档
                if ($lockState -eq "completed") {
                    Write-Host "  提示: 任务已完成，可以归档到 completed/ 目录" -ForegroundColor Cyan
                }
            }
            else {
                Write-Host "  警告: 任务 $TaskId 未找到锁记录，跳过更新" -ForegroundColor Yellow
            }
        }
    }
    catch {
        Write-Host "  错误: 更新任务锁失败: $_" -ForegroundColor Red
    }
}

function Parse-RouteMessage {
    param([string]$text)

    # 匹配 [ROUTE] ... [/ROUTE] 块
    $routePattern = '\[ROUTE\]\s*(.*?)\s*\[/ROUTE\]'
    $matchResults = [regex]::Matches($text, $routePattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

    foreach ($match in $matchResults) {
        $routeContent = $match.Groups[1].Value

        # 解析各个字段 - 使用局部变量避免 $matches 冲突
        $localFrom = ""
        $localTo = ""
        $localType = ""
        $localTask = ""
        $localStatus = ""

        if ($routeContent -match 'from:\s*(\S+)') {
            $localFrom = $matches[1]
        }
        if ($routeContent -match 'to:\s*(\S+)') {
            $localTo = $matches[1]
        }
        if ($routeContent -match 'type:\s*(\S+)') {
            $localType = $matches[1]
        }
        if ($routeContent -match 'task:\s*(\S+)') {
            $localTask = $matches[1]
        }
        if ($routeContent -match 'status:\s*(\S+)') {
            $localStatus = $matches[1]
        }

        # 提取 body（多行）
        $localBody = ""
        if ($routeContent -match 'body:\s*\|?\s*\r?\n(.*)') {
            $localBody = $matches[1].Trim()
        }

        # 生成唯一标识（用于去重）- 使用分钟级精度避免吞消息
        $routeId = "$localFrom-$localTask-$localStatus-$(Get-Date -Format 'yyyyMMddHHmm')"

        if (-not $processedRoutes.ContainsKey($routeId)) {
            $processedRoutes[$routeId] = Get-Date

            [PSCustomObject]@{
                From = $localFrom
                To = $localTo
                Type = $localType
                Task = $localTask
                Status = $localStatus
                Body = $localBody
                RouteId = $routeId
            }
        }
    }
}

function Show-RouteNotification {
    param([PSCustomObject]$route)

    $color = "Yellow"
    if ($route.Status -eq "success") {
        $color = "Green"
    }
    elseif ($route.Status -eq "fail") {
        $color = "Red"
    }

    Write-Host ""
    Write-Host "==============================================" -ForegroundColor $color
    Write-Host "  [ROUTE] 消息收到" -ForegroundColor White
    Write-Host "==============================================" -ForegroundColor $color
    Write-Host "  From:   $($route.From)" -ForegroundColor White
    Write-Host "  To:     $($route.To)" -ForegroundColor White
    Write-Host "  Task:   $($route.Task)" -ForegroundColor White
    Write-Host "  Status: $($route.Status)" -ForegroundColor White
    Write-Host "  Type:   $($route.Type)" -ForegroundColor White
    Write-Host "==============================================" -ForegroundColor $color
    Write-Host ""
}

# 主监控循环
do {
    try {
        # 获取 Team Lead pane 的最新输出
        $output = wezterm cli get-text --pane-id $TeamLeadPaneId 2>&1

        if ($output -match '\[ROUTE\]') {
            $routes = Parse-RouteMessage -text $output

            foreach ($route in $routes) {
                Show-RouteNotification -route $route

                # 自动更新任务锁
                if ($route.Task -and $route.Status) {
                    Update-TaskLockFromRoute `
                        -TaskId $route.Task `
                        -Status $route.Status `
                        -WorkerName $route.From `
                        -Body $route.Body

                    # 如果 Backend 任务成功完成，检查是否需要触发 Doc-Updater
                    if ($route.Status -eq "success" -and $route.Task -match "^BACKEND-") {
                        Write-Host ""
                        Write-Host "检测到 Backend 任务完成，检查是否需要更新 API 文档..." -ForegroundColor Cyan

                        $docTriggerScript = Join-Path $scriptDir "trigger-doc-updater.ps1"
                        if (Test-Path $docTriggerScript) {
                            Start-Job -ScriptBlock {
                                param($script, $task, $pane)
                                & $script -TaskId $task -TeamLeadPaneId $pane
                            } -ArgumentList $docTriggerScript, $route.Task, $TeamLeadPaneId | Out-Null

                            Write-Host "  Doc-Updater 检查已触发 (后台运行)" -ForegroundColor Green
                        }
                    }
                }

                # 如果消息类型是 blocker，特别标记
                if ($route.Type -eq "blocker") {
                    Write-Host "BLOCKER 收到！需要 Team Lead 介入协调。" -ForegroundColor Red -BackgroundColor Black
                }
            }
        }
    }
    catch {
        Write-Host "监控出错: $_" -ForegroundColor Yellow
    }

    if ($Continuous) {
        Write-Host "." -NoNewline -ForegroundColor Gray
        Start-Sleep -Seconds $PollIntervalSeconds
    }
} while ($Continuous)

Write-Host ""
Write-Host "监控结束。" -ForegroundColor Cyan
