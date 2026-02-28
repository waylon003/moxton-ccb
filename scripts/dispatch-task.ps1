#!/usr/bin/env pwsh
# 派遣任务到 Worker（支持 Worker Pane Registry）
# Worker 通过文件路径自行读取任务内容，避免 send-text 超长截断
# 用法:
#   .\dispatch-task.ps1 -WorkerPaneId 42 -WorkerName "backend-dev" -TaskId "BACKEND-008" -TaskFilePath "E:\moxton-ccb\01-tasks\active\backend\BACKEND-008-xxx.md"

param(
    [Parameter(Mandatory=$false)]
    [string]$WorkerPaneId,

    [Parameter(Mandatory=$true)]
    [string]$TaskId,

    [Parameter(Mandatory=$true)]
    [string]$TaskFilePath,

    [Parameter(Mandatory=$false)]
    [string]$WorkerName,

    [Parameter(Mandatory=$false)]
    [ValidateSet("codex", "gemini")]
    [string]$Engine = "codex",

    [Parameter(Mandatory=$false)]
    [string]$TeamLeadPaneId = $env:TEAM_LEAD_PANE_ID
)

$ErrorActionPreference = "Stop"
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 验证环境
if (-not $TeamLeadPaneId) {
    Write-Error "TEAM_LEAD_PANE_ID 未设置。请先运行: `$env:TEAM_LEAD_PANE_ID = (wezterm cli list --format json | ConvertFrom-Json | Where-Object { `$_.title -like '*claude*' } | Select-Object -First 1).pane_id"
    exit 1
}

# 如果没有直接提供 PaneId，尝试从 Registry 获取
if (-not $WorkerPaneId) {
    if (-not $WorkerName) {
        Write-Error "必须提供 -WorkerPaneId 或 -WorkerName。`n用法: .\dispatch-task.ps1 -WorkerName 'backend-dev' -TaskId 'xxx' -TaskFilePath 'path/to/task.md'"
        exit 1
    }

    Write-Host "🔍 从 Worker Pane Registry 查找 $WorkerName ..." -ForegroundColor Cyan

    $registryScript = Join-Path $PSScriptRoot "worker-registry.ps1"
    $foundPaneId = & $registryScript -Action get -WorkerName $WorkerName 2>&1

    if (-not $foundPaneId) {
        Write-Error "Worker '$WorkerName' 未在 Registry 中找到。请先启动 Worker:`n  .\scripts\start-worker.ps1 -WorkDir '...' -WorkerName '$WorkerName' -Engine codex"
        exit 1
    }

    $WorkerPaneId = $foundPaneId
    Write-Host "✅ 找到 Worker: $WorkerName -> pane $WorkerPaneId" -ForegroundColor Green
}
else {
    # 直接提供了 PaneId，如果也提供了 WorkerName，用于显示
    if (-not $WorkerName) {
        $WorkerName = "unknown"
    }
}

# 验证任务文件存在
if (-not (Test-Path $TaskFilePath)) {
    Write-Error "任务文件不存在: $TaskFilePath"
    exit 1
}

# 构建派遣指令（短内容：协议头 + 文件路径引用 + 完成提醒）
$qaGateSection = ""
if ($WorkerName -like "*-qa") {
    $qaGateSection = @"
===================================================================
  QA HARD GATE
===================================================================

你是 QA Worker。本次回传若 status=success，必须在 body 中提供以下证据：
1) 控制台错误检查（0 errors 或错误详情）
2) 截图证据（关键页面/问题点）
3) 网络响应证据（关键接口 URL + status + 是否4xx/5xx）
4) 失败路径验证（至少一个 500/异常，且不透出后端原文）

缺少任一项 -> 只能 report_route status=blocked，禁止填写 success。

===================================================================
"@
}

$fullTask = @"
===================================================================
  PROTOCOL REMINDER
===================================================================

你在接受任务前必须确认：

1. 任务完成后，必须调用 MCP tool report_route 通知 Team Lead
2. 禁止不调用 report_route 就声明完成！
3. 文档规则：
   - 项目 API 契约：按任务文件中引用的 02-api/*.md 路径查阅
   - 外部框架/库：优先用 context7 MCP 查询；不可用时查官方文档并注明来源
   - 禁止凭记忆假设任何 API 行为
4. 禁止使用子代理（sub-agent / background agent）！所有工作必须在主进程完成。
   子代理的审批交互在 pane 中不稳定，会导致任务卡死。

当前任务ID: $TaskId
Worker: $WorkerName

===================================================================
  TASK CONTENT
===================================================================

请读取以下文件获取完整任务内容，严格按照文件中的要求执行：

$TaskFilePath

===================================================================
  COMPLETION REMINDER
===================================================================

任务完成后，必须调用 MCP tool report_route，参数如下：

  from: "$WorkerName"
  task: "$TaskId"
  status: success（或 fail / blocked）
  body: <填写：修改的文件、执行的命令、测试结果>

这是强制要求。不调用 report_route 就声明完成视为违规。

===================================================================
$qaGateSection
"@

$fullTask += @"
===================================================================
"@

# 发送到 Worker
Write-Host ""
Write-Host "派遣任务 $TaskId 到 Worker..."
Write-Host "   Worker: $WorkerName"
Write-Host "   Worker Pane: $WorkerPaneId"
Write-Host "   Engine: $Engine"
Write-Host "   Task file: $TaskFilePath"
Write-Host ""

# 等待 Worker CLI 就绪（避免 CLI 未加载完就发送导致内容丢失）
$readyPatterns = if ($Engine -eq "gemini") {
    @("Type your message", "? for shortcuts")
} else {
    @("codex>", "Codex is ready", "full-auto", "OpenAI Codex")
}

$maxWait = 60
$waited = 0
$ready = $false

Write-Host "Waiting for $Engine CLI to be ready..." -ForegroundColor Yellow
while ($waited -lt $maxWait) {
    try {
        $paneText = wezterm cli get-text --pane-id $WorkerPaneId 2>$null
        foreach ($pattern in $readyPatterns) {
            if ($paneText -match [regex]::Escape($pattern)) {
                Write-Host ('[OK] Worker CLI ready (matched: ' + $pattern + ')') -ForegroundColor Green
                $ready = $true
                break
            }
        }
    } catch {}
    if ($ready) { break }
    Start-Sleep -Seconds 2
    $waited += 2
    if ($waited % 10 -eq 0) {
        $lastLines = if ($paneText) { ($paneText -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 3) -join " | " } else { "(empty)" }
        Write-Host ('  ... still waiting (' + $waited + 's) pane text: ' + $lastLines) -ForegroundColor DarkGray
    }
}

if (-not $ready) {
    Write-Host ('[FAIL] Worker CLI not ready after ' + $maxWait + 's, aborting dispatch') -ForegroundColor Red
    exit 1
}

# 发送任务指令，然后单独发回车确保提交
wezterm cli send-text --pane-id $WorkerPaneId --no-paste "$fullTask"
if ($LASTEXITCODE -ne 0) {
    Write-Host '[FAIL] wezterm send-text failed' -ForegroundColor Red
    exit 1
}

# 短暂延迟后单独发回车，确保 CLI 正确接收提交
Start-Sleep -Milliseconds 500
wezterm cli send-text --pane-id $WorkerPaneId --no-paste "`r"

Write-Host "Task dispatched." -ForegroundColor Green
