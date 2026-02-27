#!/usr/bin/env pwsh
# Team Lead 启动交互脚本 - 自动检测模式并询问用户

param(
    [Parameter(Mandatory=$false)]
    [string]$TeamLeadPaneId = $env:TEAM_LEAD_PANE_ID
)

$ErrorActionPreference = "Stop"

# 获取项目根目录
$scriptDir = $PSScriptRoot
$rootDir = Split-Path $scriptDir -Parent

# 设置 WezTerm 路径
$env:PATH += ";D:\WezTerm-windows-20240203-110809-5046fc22"

# 如果没有设置 TeamLeadPaneId，自动获取
if (-not $TeamLeadPaneId) {
    try {
        $panes = wezterm cli list --format json 2>$null | ConvertFrom-Json
        $teamLeadPane = $panes | Where-Object { $_.title -like '*claude*' -or $_.title -like '* Claude*' } | Select-Object -First 1
        if ($teamLeadPane) {
            $env:TEAM_LEAD_PANE_ID = $teamLeadPane.pane_id
            $TeamLeadPaneId = $teamLeadPane.pane_id
        }
    }
    catch {
        Write-Error "无法获取 Team Lead Pane ID。请手动设置: `$env:TEAM_LEAD_PANE_ID = <pane_id>"
        exit 1
    }
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "     Moxton Team Lead 启动向导" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

# 检测当前任务状态
Set-Location $rootDir
$taskStatus = python scripts\assign_task.py --list 2>&1
$activeTaskCount = 0

# 解析活跃任务数量
if ($taskStatus -match '\[([A-Z]+-\d+)\]') {
    $matches = [regex]::Matches($taskStatus, '\[([A-Z]+-\d+)\]')
    $activeTaskCount = $matches.Count
}

Write-Host "📊 当前活跃任务数: $activeTaskCount" -ForegroundColor Yellow
Write-Host ""

# 显示任务摘要
if ($activeTaskCount -gt 0) {
    Write-Host "活跃任务列表:" -ForegroundColor White
    $taskStatus | Select-String -Pattern '\[([A-Z]+-\d+)\].*' | Select-Object -First 5 | ForEach-Object {
        Write-Host "  $_" -ForegroundColor Gray
    }
    Write-Host ""
}

# 模式选择
Write-Host "请选择工作模式:" -ForegroundColor Green
Write-Host ""

if ($activeTaskCount -gt 0) {
    Write-Host "  [1] 🚀 执行现有任务 ($activeTaskCount 个等待执行)" -ForegroundColor Cyan
}
else {
    Write-Host "  [1] 🚀 执行现有任务 (暂无)" -ForegroundColor DarkGray
}

Write-Host "  [2] 📝 规划新任务 (需求讨论 + 拆分)" -ForegroundColor Cyan

if ($activeTaskCount -gt 0) {
    Write-Host "  [3] 📋 查看任务详情和编排计划" -ForegroundColor Cyan
}

Write-Host "  [4] 🔧 管理 Workers (启动/查看/清理)" -ForegroundColor Cyan
Write-Host "  [5] 📊 查看系统状态" -ForegroundColor Cyan
Write-Host ""

# 获取用户选择
$choice = Read-Host "请输入选项 (1-5)"

switch ($choice) {
    "1" {
        if ($activeTaskCount -eq 0) {
            Write-Host "⚠️  没有活跃任务，请先规划新任务。" -ForegroundColor Yellow
            exit 0
        }

        Write-Host ""
        Write-Host "🚀 进入执行模式..." -ForegroundColor Green
        Write-Host ""

        # 检查是否有执行计划
        $wavePlans = Get-ChildItem -Path "$rootDir\01-tasks\WAVE*-EXECUTION-PLAN.md" -ErrorAction SilentlyContinue | Sort-Object Name -Descending

        if ($wavePlans) {
            $latestPlan = $wavePlans | Select-Object -First 1
            Write-Host "发现执行计划: $($latestPlan.Name)" -ForegroundColor Cyan
            $executeChoice = Read-Host "是否使用此计划自动编排执行? (y/n)"

            if ($executeChoice -eq "y" -or $executeChoice -eq "Y") {
                # 调用并行编排脚本
                & "$scriptDir\dispatch-wave.ps1" -WavePlan $latestPlan.FullName -TeamLeadPaneId $TeamLeadPaneId
                exit 0
            }
        }

        # 否则显示标准执行提示
        Write-Host ""
        Write-Host "执行选项:" -ForegroundColor Yellow
        Write-Host "  1. 自动并行执行所有任务"
        Write-Host "  2. 手动逐个分派任务"
        Write-Host "  3. 查看任务详情后再决定"
        Write-Host ""

        $execChoice = Read-Host "请选择 (1-3)"
        switch ($execChoice) {
            "1" {
                # 自动生成执行计划并执行
                Write-Host "正在生成执行计划..." -ForegroundColor Cyan
                python scripts\assign_task.py --write-brief
                $newPlans = Get-ChildItem -Path "$rootDir\04-projects\CODEX-TEAM-BRIEF.md" -ErrorAction SilentlyContinue
                if ($newPlans) {
                    Write-Host "执行计划已生成: 04-projects\CODEX-TEAM-BRIEF.md"
                    Write-Host "建议: 查看计划后运行 .\scripts\dispatch-wave.ps1 -WavePlan '04-projects\CODEX-TEAM-BRIEF.md'"
                }
            }
            "2" {
                Write-Host ""
                Write-Host "手动分派示例:" -ForegroundColor Cyan
                Write-Host '  .\scripts\dispatch-task.ps1 -WorkerName "backend-dev" -TaskId "BACKEND-001" -TaskContent "内容"' -ForegroundColor White
                Write-Host ""
                Write-Host "可用 Workers:" -ForegroundColor Yellow
                & "$scriptDir\worker-registry.ps1" -Action list
            }
            "3" {
                python scripts\assign_task.py --scan
            }
        }
    }

    "2" {
        Write-Host ""
        Write-Host "📝 进入规划模式..." -ForegroundColor Green
        Write-Host ""

        $requirement = Read-Host "请描述你的需求 (或按 Enter 打开编辑器)"

        if ([string]::IsNullOrWhiteSpace($requirement)) {
            # 打开编辑器让用户输入
            $tempFile = [System.IO.Path]::GetTempFileName()
            Set-Content -Path $tempFile -Value @"
# 需求描述
请在此描述你的需求，保存后关闭编辑器即可。

示例格式:
- 目标: 实现用户管理功能
- 涉及: 后端 API + 管理后台页面
- 优先级: 高

"@
            notepad $tempFile
            Write-Host "请在编辑器中输入需求，保存后按 Enter 继续..." -ForegroundColor Yellow
            Read-Host
            $requirement = Get-Content $tempFile -Raw
            Remove-Item $tempFile -ErrorAction SilentlyContinue
        }

        if (-not [string]::IsNullOrWhiteSpace($requirement)) {
            Write-Host ""
            Write-Host "正在分析需求并生成任务..." -ForegroundColor Cyan
            python scripts\assign_task.py --intake "$requirement"
        }
    }

    "3" {
        if ($activeTaskCount -eq 0) {
            Write-Host "⚠️  没有活跃任务" -ForegroundColor Yellow
            exit 0
        }

        Write-Host ""
        python scripts\assign_task.py --scan
        Write-Host ""

        # 检查是否有编排计划
        $wavePlans = Get-ChildItem -Path "$rootDir\01-tasks\WAVE*-EXECUTION-PLAN.md" -ErrorAction SilentlyContinue
        if ($wavePlans) {
            Write-Host "现有执行计划:" -ForegroundColor Cyan
            $wavePlans | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor White }
            Write-Host ""
            $viewPlan = Read-Host "是否查看最新计划? (y/n)"
            if ($viewPlan -eq "y") {
                $latest = $wavePlans | Sort-Object Name -Descending | Select-Object -First 1
                Get-Content $latest.FullName -Head 50 | ForEach-Object { Write-Host $_ }
            }
        }
    }

    "4" {
        Write-Host ""
        Write-Host "🔧 Worker 管理" -ForegroundColor Green
        Write-Host ""
        Write-Host "  [1] 列出已注册 Workers"
        Write-Host "  [2] 启动新 Worker"
        Write-Host "  [3] 健康检查 (清理失效)"
        Write-Host "  [4] 清理所有 Worker 注册"
        Write-Host ""

        $workerChoice = Read-Host "请选择 (1-4)"
        switch ($workerChoice) {
            "1" { & "$scriptDir\worker-registry.ps1" -Action list }
            "2" {
                Write-Host ""
                Write-Host "启动 Worker:" -ForegroundColor Cyan
                $workDir = Read-Host "工作目录 (如 E:\moxton-lotapi)"
                $workerName = Read-Host "Worker 名称 (如 backend-dev)"
                $engine = Read-Host "引擎 (codex/gemini)"

                if ($workDir -and $workerName -and $engine) {
                    & "$scriptDir\start-worker.ps1" -WorkDir $workDir -WorkerName $workerName -Engine $engine -TeamLeadPaneId $TeamLeadPaneId
                }
            }
            "3" { & "$scriptDir\worker-registry.ps1" -Action health-check }
            "4" {
                $confirm = Read-Host "确定要清理所有 Worker 注册? (yes/no)"
                if ($confirm -eq "yes") {
                    & "$scriptDir\worker-registry.ps1" -Action clean
                }
            }
        }
    }

    "5" {
        Write-Host ""
        Write-Host "📊 系统状态" -ForegroundColor Green
        Write-Host ""

        Write-Host "任务状态:" -ForegroundColor Cyan
        python scripts\assign_task.py --show-task-locks | Select-Object -First 20

        Write-Host ""
        Write-Host "Worker 注册表:" -ForegroundColor Cyan
        & "$scriptDir\worker-registry.ps1" -Action list

        Write-Host ""
        Write-Host "运行诊断:" -ForegroundColor Cyan
        python scripts\assign_task.py --doctor
    }

    default {
        Write-Host "⚠️  无效选项，退出。" -ForegroundColor Yellow
        exit 0
    }
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "启动向导完成。" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""
