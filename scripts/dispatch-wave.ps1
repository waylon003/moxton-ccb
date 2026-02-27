#!/usr/bin/env pwsh
# 波浪式并行任务编排执行器
# 自动读取 WAVE-EXECUTION-PLAN.md 并并行分派任务

param(
    [Parameter(Mandatory=$false)]
    [string]$WavePlan = "",

    [Parameter(Mandatory=$false)]
    [string]$TeamLeadPaneId = $env:TEAM_LEAD_PANE_ID,

    [Parameter(Mandatory=$false)]
    [switch]$DryRun,

    [Parameter(Mandatory=$false)]
    [int]$MaxParallel = 3
)

$ErrorActionPreference = "Stop"

# 获取项目根目录
$scriptDir = $PSScriptRoot
$rootDir = Split-Path $scriptDir -Parent

# 验证环境
if (-not $TeamLeadPaneId) {
    Write-Error "TEAM_LEAD_PANE_ID 未设置。请先运行启动向导。"
    exit 1
}

# 如果没有指定计划，查找最新的
if (-not $WavePlan) {
    $plans = Get-ChildItem -Path "$rootDir\01-tasks\WAVE*-EXECUTION-PLAN.md" -ErrorAction SilentlyContinue | Sort-Object Name -Descending
    if (-not $plans) {
        Write-Error "未找到 WAVE-EXECUTION-PLAN.md。请先创建执行计划或手动指定。"
        exit 1
    }
    $WavePlan = $plans | Select-Object -First 1 -ExpandProperty FullName
}

if (-not (Test-Path $WavePlan)) {
    Write-Error "执行计划文件不存在: $WavePlan"
    exit 1
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "      波浪式并行任务编排执行器" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "计划文件: $WavePlan" -ForegroundColor White
Write-Host "最大并行: $MaxParallel" -ForegroundColor White
if ($DryRun) {
    Write-Host "模式: 模拟运行 (Dry Run)" -ForegroundColor Yellow
}
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

# 解析执行计划
$planContent = Get-Content $WavePlan -Raw

# 提取阶段信息
$phases = @()
$phasePattern = '## 阶段\s*(\d+)[:：]\s*(.+?)\n+(.*?)(?=## 阶段|$)'
$phaseMatches = [regex]::Matches($planContent, $phasePattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

foreach ($match in $phaseMatches) {
    $phaseNum = $match.Groups[1].Value
    $phaseName = $match.Groups[2].Value.Trim()
    $phaseContent = $match.Groups[3].Value

    # 提取该阶段的任务
    $tasks = @()
    $taskPattern = '-\s*任务[:：]\s*(\S+).*(?:开发[:：]|worker[:：])\s*(\S+)'
    $taskMatches = [regex]::Matches($phaseContent, $taskPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    foreach ($tm in $taskMatches) {
        $tasks += @{
            taskId = $tm.Groups[1].Value
            worker = $tm.Groups[2].Value
        }
    }

    # 提取 QA 任务
    $qaPattern = '-\s*QA[:：]\s*(\S+).*(?:验收|验证)[:：]\s*(\S+)'
    $qaMatches = [regex]::Matches($phaseContent, $qaPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    $qaTasks = @()
    foreach ($qm in $qaMatches) {
        $qaTasks += @{
            taskId = $qm.Groups[1].Value
            worker = $qm.Groups[2].Value
        }
    }

    $phases += @{
        number = $phaseNum
        name = $phaseName
        tasks = $tasks
        qaTasks = $qaTasks
    }
}

if ($phases.Count -eq 0) {
    Write-Warning "未能从计划文件中解析出阶段信息。尝试简化解析..."

    # 简化解析：直接找任务列表
    $simpleTaskPattern = '(BACKEND|SHOP-FE|ADMIN-FE)-\d+'
    $simpleMatches = [regex]::Matches($planContent, $simpleTaskPattern)

    $allTasks = $simpleMatches | ForEach-Object { $_.Value } | Select-Object -Unique

    if ($allTasks.Count -eq 0) {
        Write-Error "无法解析任务列表"
        exit 1
    }

    # 创建一个阶段包含所有任务
    $tasks = @()
    foreach ($t in $allTasks) {
        # 推断 worker
        $worker = if ($t -match 'BACKEND') { 'backend-dev' }
                  elseif ($t -match 'SHOP-FE') { 'shop-fe-dev' }
                  elseif ($t -match 'ADMIN-FE') { 'admin-fe-dev' }
                  else { 'unknown' }
        $tasks += @{ taskId = $t; worker = $worker }
    }

    $phases += @{
        number = 1
        name = "所有任务"
        tasks = $tasks
        qaTasks = @()
    }
}

# 显示解析结果
Write-Host "解析到 $($phases.Count) 个执行阶段:" -ForegroundColor Green
foreach ($p in $phases) {
    Write-Host ""
    Write-Host "阶段 $($p.number): $($p.name)" -ForegroundColor Yellow
    Write-Host "  开发任务: $($p.tasks.Count) 个" -ForegroundColor White
    foreach ($t in $p.tasks) {
        Write-Host "    - $($t.taskId) -> $($t.worker)" -ForegroundColor Gray
    }
    if ($p.qaTasks.Count -gt 0) {
        Write-Host "  QA 任务: $($p.qaTasks.Count) 个" -ForegroundColor White
        foreach ($q in $p.qaTasks) {
            Write-Host "    - $($q.taskId) -> $($q.worker)" -ForegroundColor Gray
        }
    }
}

Write-Host ""

# 确认执行
if (-not $DryRun) {
    $confirm = Read-Host "确认开始执行? (yes/no/dryrun)"
    if ($confirm -eq "dryrun") {
        $DryRun = $true
    }
    elseif ($confirm -ne "yes") {
        Write-Host "执行已取消" -ForegroundColor Yellow
        exit 0
    }
}

# 执行阶段
foreach ($phase in $phases) {
    Write-Host ""
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host "执行阶段 $($phase.number): $($phase.name)" -ForegroundColor Cyan
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host ""

    $phaseTasks = $phase.tasks

    if ($phaseTasks.Count -eq 0) {
        Write-Host "  本阶段无任务，跳过" -ForegroundColor Gray
        continue
    }

    # 分批并行执行（考虑 MaxParallel）
    $batches = [Math]::Ceiling($phaseTasks.Count / $MaxParallel)

    for ($batch = 0; $batch -lt $batches; $batch++) {
        $batchTasks = $phaseTasks | Select-Object -Skip ($batch * $MaxParallel) -First $MaxParallel

        Write-Host "  批次 $($batch + 1)/$batches (并行 $($batchTasks.Count) 个任务)" -ForegroundColor Yellow
        Write-Host ""

        foreach ($task in $batchTasks) {
            $taskFile = "$rootDir\01-tasks\active\*\$($task.taskId)*.md"
            $taskFiles = Get-ChildItem -Path $taskFile -ErrorAction SilentlyContinue

            if (-not $taskFiles) {
                Write-Warning "任务文件未找到: $($task.taskId)"
                continue
            }

            $taskContent = Get-Content $taskFiles[0].FullName -Raw

            if ($DryRun) {
                Write-Host "    [模拟] 将分派 $($task.taskId) -> $($task.worker)" -ForegroundColor Gray
            }
            else {
                Write-Host "    分派 $($task.taskId) -> $($task.worker)..." -ForegroundColor Green

                try {
                    # 检查 worker 是否已注册
                    $registryScript = "$scriptDir\worker-registry.ps1"
                    $paneId = & $registryScript -Action get -WorkerName $task.worker 2>$null

                    if (-not $paneId) {
                        Write-Warning "Worker $($task.worker) 未启动，跳过任务 $($task.taskId)"
                        continue
                    }

                    # 分派任务
                    & "$scriptDir\dispatch-task.ps1" `
                        -WorkerPaneId $paneId `
                        -WorkerName $task.worker `
                        -TaskId $task.taskId `
                        -TaskContent $taskContent `
                        -TeamLeadPaneId $TeamLeadPaneId

                    Write-Host "      ✅ 已分派" -ForegroundColor Green
                }
                catch {
                    Write-Error "分派失败: $_"
                }
            }
        }

        if ($batch -lt $batches - 1) {
            Write-Host ""
            Write-Host "  等待当前批次完成或按 Enter 继续下一批次..." -ForegroundColor Yellow
            # 可以添加超时逻辑或检测完成逻辑
            Start-Sleep -Seconds 2
        }
    }

    # 阶段完成后，启动 QA 任务（如果有）
    if ($phase.qaTasks.Count -gt 0) {
        Write-Host ""
        Write-Host "阶段 $($phase.number) 开发任务已分派，准备 QA 验收..." -ForegroundColor Yellow
        Write-Host ""

        if (-not $DryRun) {
            $startQA = Read-Host "是否立即启动 QA 任务? (y/n)"
            if ($startQA -eq "y") {
                foreach ($qa in $phase.qaTasks) {
                    Write-Host "  启动 QA: $($qa.taskId) -> $($qa.worker)" -ForegroundColor Cyan
                    # 实际 QA 分派逻辑...
                }
            }
        }
    }
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "执行计划分派完成" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "提示: 运行以下命令监控任务状态:" -ForegroundColor Yellow
Write-Host "  .\scripts\route-monitor.ps1 -Continuous" -ForegroundColor White
Write-Host ""
