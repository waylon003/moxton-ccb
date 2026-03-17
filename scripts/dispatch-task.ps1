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

    [Parameter(Mandatory=$false)]
    [string]$TaskFilePath,

    [Parameter(Mandatory=$false)]
    [string]$InlineTaskBody,

    [Parameter(Mandatory=$false)]
    [string]$WorkerName,

    [Parameter(Mandatory=$false)]
    [ValidateSet("codex", "gemini")]
    [string]$Engine = "codex",

    [Parameter(Mandatory=$false)]
    [string]$RunId,

    [Parameter(Mandatory=$false)]
    [string]$TeamLeadPaneId = $env:TEAM_LEAD_PANE_ID
)

$ErrorActionPreference = "Stop"
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Normalize-PaneId([string]$value) {
    if (-not $value) { return $null }
    $trimmed = $value.Trim()
    if ($trimmed -match '(\d+)') {
        return $Matches[1]
    }
    return $null
}

function Invoke-WezTermSendText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PaneId,
        [Parameter(Mandatory = $true)]
        [string]$Text,
        [int]$Retries = 2
    )

    $lastError = ""
    $preferPaste = ($Text.Length -gt 180 -or $Text.Contains("`n") -or $Text.Contains("`r"))
    $modes = if ($preferPaste) {
        @(
            @{ noPaste = $false; label = "plain" },
            @{ noPaste = $true; label = "no-paste" }
        )
    } else {
        @(
            @{ noPaste = $true; label = "no-paste" },
            @{ noPaste = $false; label = "plain" }
        )
    }

    foreach ($mode in $modes) {
        for ($i = 1; $i -le $Retries; $i++) {
            try {
                if ($mode.noPaste) {
                    $output = wezterm cli send-text --pane-id $PaneId --no-paste $Text 2>&1
                } else {
                    $output = wezterm cli send-text --pane-id $PaneId $Text 2>&1
                }
                if ($LASTEXITCODE -eq 0) {
                    return
                }
                $lastError = ($output | Out-String).Trim()
            } catch {
                $lastError = $_.Exception.Message
            }
            Start-Sleep -Milliseconds 120
        }
    }

    throw ("wezterm send-text failed (pane=" + $PaneId + "): " + $lastError)
}

function Send-PayloadInChunks {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PaneId,
        [Parameter(Mandatory = $true)]
        [string]$Payload
    )

    # 小消息一次发送，避免无意义分块
    if ($Payload.Length -le 1800) {
        Invoke-WezTermSendText -PaneId $PaneId -Text $Payload
        return
    }

    # 长消息分块发送，避免一次参数过长导致 send-text 失败
    $chunkSize = 1500
    for ($offset = 0; $offset -lt $Payload.Length; $offset += $chunkSize) {
        $len = [Math]::Min($chunkSize, $Payload.Length - $offset)
        $chunk = $Payload.Substring($offset, $len)
        Invoke-WezTermSendText -PaneId $PaneId -Text $chunk
        Start-Sleep -Milliseconds 40
    }
}

function Get-PaneTextSafe([string]$PaneId) {
    try {
        return (wezterm cli get-text --pane-id $PaneId 2>$null)
    } catch {
        return ""
    }
}

function Get-LatestWorkerReadyName([string]$paneText) {
    if (-not $paneText) { return $null }
    $matches = [regex]::Matches($paneText, 'Worker ready:\s*([^\(\r\n]+)')
    if ($matches.Count -eq 0) { return $null }
    $latest = $matches[$matches.Count - 1].Groups[1].Value
    if (-not $latest) { return $null }
    return $latest.Trim()
}

function Get-PaneFingerprint([string]$paneText) {
    if (-not $paneText) { return "" }
    $tail = (($paneText -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 20) -join "`n")
    return $tail
}

function Ensure-SubmittedAfterPaste {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PaneId,
        [Parameter(Mandatory = $true)]
        [string]$Engine
    )

    # Gemini 对“粘贴后立刻回车”较敏感：若仍停留在 [Pasted Text: ...]，补发回车
    $maxRetry = if ($Engine -eq "gemini") { 6 } else { 2 }
    for ($i = 0; $i -lt $maxRetry; $i++) {
        $pane = Get-PaneTextSafe -PaneId $PaneId
        $hasPastedMarker = $pane -match '\[Pasted Text:\s*\d+\s*lines\]'
        if (-not $hasPastedMarker) {
            return
        }

        Start-Sleep -Milliseconds 200
        # 先 no-paste 回车
        Invoke-WezTermSendText -PaneId $PaneId -Text "`r"
        Start-Sleep -Milliseconds 180
        # 再 plain 回车兜底
        wezterm cli send-text --pane-id $PaneId "`r" 2>$null | Out-Null
        Start-Sleep -Milliseconds 220
    }
}

function Invoke-WezTermSubmit {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PaneId,
        [Parameter(Mandatory = $true)]
        [string]$Engine
    )

    # 某些 CLI（尤其 Gemini）对回车序列比较敏感：按 CR/LF/CRLF 多次尝试提交。
    $sequences = if ($Engine -eq "gemini") {
        @("`r", "`n", "`r`n")
    } else {
        @("`r", "`r`n")
    }

    foreach ($seq in $sequences) {
        try {
            wezterm cli send-text --pane-id $PaneId --no-paste $seq 2>$null | Out-Null
        } catch {}
        Start-Sleep -Milliseconds 120
        try {
            wezterm cli send-text --pane-id $PaneId $seq 2>$null | Out-Null
        } catch {}
        Start-Sleep -Milliseconds 180
    }
}

function Get-HasAckForTask([string]$paneText, [string]$taskId) {
    if (-not $paneText -or -not $taskId) { return $false }
    return ($paneText -match ('ACK\s+' + [regex]::Escape($taskId)))
}

function Get-HasProgressSignal([string]$paneText) {
    if (-not $paneText) { return $false }
    $patterns = @(
        "report_route",
        "mcp__route__report_route",
        "in_progress",
        "blocked",
        "completed",
        "qa_passed"
    )
    foreach ($p in $patterns) {
        if ($paneText -match $p) { return $true }
    }
    return $false
}

function Maybe-PostAckNudge {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PaneId,
        [Parameter(Mandatory = $true)]
        [string]$TaskId,
        [Parameter(Mandatory = $true)]
        [string]$Engine
    )

    $enable = $env:TEAMLEAD_ACK_NUDGE
    if ($enable -and $enable.Trim() -eq "0") { return }

    $nudge = "continue; read role_definition/protocol/task_file; begin execution now; report_route(in_progress) and proceed per protocol."

    # First nudge after short grace period if still no progress.
    Start-Sleep -Seconds 6
    $paneText = Get-PaneTextSafe -PaneId $PaneId
    if (-not (Get-HasProgressSignal -paneText $paneText)) {
        Send-PayloadInChunks -PaneId $PaneId -Payload $nudge
        Start-Sleep -Milliseconds 200
        Invoke-WezTermSubmit -PaneId $PaneId -Engine $Engine
    } else {
        return
    }

    # Second nudge only if ACK appears but still no progress (covers "ACK then idle").
    $ackWait = 0
    while ($ackWait -lt 24) {
        $paneText = Get-PaneTextSafe -PaneId $PaneId
        if (Get-HasProgressSignal -paneText $paneText) { return }
        if (Get-HasAckForTask -paneText $paneText -taskId $TaskId) {
            Send-PayloadInChunks -PaneId $PaneId -Payload $nudge
            Start-Sleep -Milliseconds 200
            Invoke-WezTermSubmit -PaneId $PaneId -Engine $Engine
            return
        }
        Start-Sleep -Seconds 3
        $ackWait += 3
    }
}

function Resolve-RoleDefinitionPath([string]$workerName, [string]$ccbRoot) {
    if (-not $workerName) { return $null }
    $agentsDir = Join-Path $ccbRoot ".claude\agents"
    $roleFile = switch -Regex ($workerName) {
        '^backend-dev(?:-\d+)?$' { 'backend.md'; break }
        '^backend-qa(?:-\d+)?$' { 'backend-qa.md'; break }
        '^shop-fe-dev(?:-\d+)?$' { 'shop-frontend.md'; break }
        '^shop-fe-qa(?:-\d+)?$' { 'shop-fe-qa.md'; break }
        '^admin-fe-dev(?:-\d+)?$' { 'admin-frontend.md'; break }
        '^admin-fe-qa(?:-\d+)?$' { 'admin-fe-qa.md'; break }
        '^(?:repo-)?committer(?:-\d+)?$' { 'repo-committer.md'; break }
        '^[a-z-]*committer(?:-\d+)?$' { 'repo-committer.md'; break }
        '^doc-updater(?:-\d+)?$' { 'doc-updater.md'; break }
        default { $null }
    }
    if (-not $roleFile) { return $null }
    $full = Join-Path $agentsDir $roleFile
    if (Test-Path $full) { return $full }
    return $null
}

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

    $WorkerPaneId = Normalize-PaneId ([string]$foundPaneId)
    if (-not $WorkerPaneId) {
        Write-Error "无法解析 Worker pane id。worker-registry 返回: $foundPaneId"
        exit 1
    }
    Write-Host "✅ 找到 Worker: $WorkerName -> pane $WorkerPaneId" -ForegroundColor Green
}
else {
    # 直接提供了 PaneId，如果也提供了 WorkerName，用于显示
    $WorkerPaneId = Normalize-PaneId $WorkerPaneId
    if (-not $WorkerPaneId) {
        Write-Error "无效的 WorkerPaneId: $WorkerPaneId"
        exit 1
    }
    if (-not $WorkerName) {
        $WorkerName = "unknown"
    }
}

# 验证任务文件存在
$hasTaskFile = -not [string]::IsNullOrWhiteSpace($TaskFilePath)
$hasInlineBody = -not [string]::IsNullOrWhiteSpace($InlineTaskBody)
if (-not $hasTaskFile -and -not $hasInlineBody) {
    Write-Error "必须提供 -TaskFilePath 或 -InlineTaskBody。"
    exit 1
}
if ($hasTaskFile -and -not (Test-Path $TaskFilePath)) {
    Write-Error "任务文件不存在: $TaskFilePath"
    exit 1
}

# 构建派遣指令（尽量短，优先保证送达稳定）
$ccbRoot = Split-Path -Parent $PSScriptRoot
$roleDefinitionPath = Resolve-RoleDefinitionPath -workerName $WorkerName -ccbRoot $ccbRoot
$protocolPath = Join-Path $ccbRoot ".claude\agents\protocol.md"
if (-not $roleDefinitionPath) {
    Write-Host ('[WARN] Role definition file not mapped for worker=' + $WorkerName + '. Continue with protocol + task file only.') -ForegroundColor Yellow
}
if (-not (Test-Path $protocolPath)) {
    Write-Host ('[WARN] Protocol file missing: ' + $protocolPath) -ForegroundColor Yellow
}

$qaHint = ""
if ($WorkerName -match "-qa(?:-\d+)?$") {
    $qaHint = @"
QA 注意：success 回传必须满足 protocol.md 的 QA 回传合同（JSON + checks + evidence）。
"@
}
$taskSource = if ($hasTaskFile) { $TaskFilePath } else { "<inline-task-body>" }
$routeRunId = if ([string]::IsNullOrWhiteSpace($RunId)) { "<none>" } else { $RunId }
$inlineSection = if ($hasInlineBody) {
@"

inline_task_body:
$InlineTaskBody
"@
} else {
    ""
}

$fullTask = @"
[TASK-DISPATCH]
task_id: $TaskId
worker: $WorkerName
route_run_id: $routeRunId
task_file: $taskSource
role_definition: $(if ($roleDefinitionPath) { $roleDefinitionPath } else { "<not-mapped>" })
protocol: $protocolPath

执行要求：
1) 先读取 role_definition（若提供）并遵循角色约束
2) 再读取 protocol 并遵循通信/回传协议
3) $(if ($hasTaskFile) { "最后读取 task_file 并开始执行" } else { "按 inline_task_body 执行，不需要再读任务文件" })
4) 生命周期按 protocol 执行（in_progress 心跳 / blocked 上报 / 完成回传）
5) 禁止子代理（sub-agent/background agent），仅主进程执行
6) 每次调用 `report_route` / `mcp__route__report_route` 时都必须携带 `run_id: "$routeRunId"`
7) ACK 后必须立即继续执行（不要等待用户“继续/确认”）
$qaHint
$inlineSection
收到后请先通过 report_route(status=in_progress, body 包含 ack=1 + first_step) 完成 ACK，然后立刻继续执行
"@

if ($Engine -eq "gemini") {
    # Gemini 对多行粘贴提交不稳定：改为单行派遣，降低“文本留在输入框”概率。
    $inlineHint = if ($hasInlineBody) { " inline_task_body_present=true" } else { "" }
    $fullTask = "[TASK-DISPATCH] task_id=$TaskId route_run_id=$routeRunId role_definition=$(if ($roleDefinitionPath) { $roleDefinitionPath } else { "<not-mapped>" }) protocol=$protocolPath task_file=$taskSource$inlineHint; 按顺序读取 role_definition -> protocol -> $(if ($hasTaskFile) { "task_file" } else { "inline_task_body" }); 每次 report_route/mcp__route__report_route 必须携带 run_id=$routeRunId; 按 protocol 生命周期回传; 禁止子代理; ACK 必须用 report_route(status=in_progress, body含ack=1+first_step) 后立即继续执行(不要等待用户继续)"
}

# 发送到 Worker
Write-Host ""
Write-Host "派遣任务 $TaskId 到 Worker..."
Write-Host "   Worker: $WorkerName"
Write-Host "   Worker Pane: $WorkerPaneId"
Write-Host "   Engine: $Engine"
Write-Host "   Task file: $taskSource"
Write-Host ""

# 派遣前快速校验 pane 归属，避免发到错误 pane
$initialPaneText = Get-PaneTextSafe -PaneId $WorkerPaneId
$latestWorkerReady = Get-LatestWorkerReadyName -paneText $initialPaneText
if ($WorkerName -and $latestWorkerReady -and $latestWorkerReady -ne $WorkerName) {
    Write-Host ('[FAIL] Pane ownership mismatch: expected worker=' + $WorkerName + ', pane=' + $WorkerPaneId + ', actual=' + $latestWorkerReady) -ForegroundColor Red
    Write-Host '       Refuse to dispatch. Please restart worker / refresh registry first.' -ForegroundColor Yellow
    exit 1
}

# 等待 Worker CLI 就绪（避免 CLI 未加载完就发送导致内容丢失）
$readyPatterns = if ($Engine -eq "gemini") {
    @("Type your message", "? for shortcuts", "Gemini", "Press /")
} else {
    @("codex>", "Codex is ready", "full-auto", "OpenAI Codex", "model:", "directory:", "/model to change", "gpt-5.3-codex", "Build faster with Codex")
}

$maxWait = 60
$waited = 0
$ready = $false

Write-Host "Waiting for $Engine CLI to be ready..." -ForegroundColor Yellow
while ($waited -lt $maxWait) {
    try {
        $paneText = Get-PaneTextSafe -PaneId $WorkerPaneId
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
    $tail = if ($paneText) { ($paneText -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 8) -join " | " } else { "(empty)" }
    Write-Host ('[FAIL] Worker CLI not ready after ' + $maxWait + 's, aborting dispatch') -ForegroundColor Red
    Write-Host ('       Pane tail: ' + $tail) -ForegroundColor Yellow
    exit 1
}

# 发送任务指令，然后单独发回车确保提交
try {
    Send-PayloadInChunks -PaneId $WorkerPaneId -Payload $fullTask
    Start-Sleep -Milliseconds 400
    Invoke-WezTermSubmit -PaneId $WorkerPaneId -Engine $Engine
    Ensure-SubmittedAfterPaste -PaneId $WorkerPaneId -Engine $Engine
} catch {
    Write-Host ('[FAIL] ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}

# 送达确认：必须在 pane 中看到任务标识，防止“发送成功但未入 CLI 输入”
$deliveryConfirmed = $false
$deliveryWait = 0
$deliveryMaxWait = 40
$taskFileName = if ($hasTaskFile) { [System.IO.Path]::GetFileName($TaskFilePath) } else { "" }
while ($deliveryWait -lt $deliveryMaxWait) {
    $paneAfterDispatch = Get-PaneTextSafe -PaneId $WorkerPaneId
    if (
        $paneAfterDispatch -match [regex]::Escape($TaskId) -or
        $paneAfterDispatch -match [regex]::Escape("当前任务ID: $TaskId") -or
        ($taskFileName -and $paneAfterDispatch -match [regex]::Escape($taskFileName)) -or
        $paneAfterDispatch -match [regex]::Escape("ACK $TaskId")
    ) {
        $deliveryConfirmed = $true
        break
    }
    Start-Sleep -Seconds 2
    $deliveryWait += 2
}

if (-not $deliveryConfirmed) {
    $tail = (($paneAfterDispatch -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 8) -join " | ")
    Write-Host ('[FAIL] Dispatch delivery not confirmed for task ' + $TaskId + ' (pane=' + $WorkerPaneId + ')') -ForegroundColor Red
    Write-Host ('       Pane tail: ' + $tail) -ForegroundColor Yellow
    Write-Host '       Do not update task lock. Retry dispatch or restart worker.' -ForegroundColor Yellow
    exit 1
}

Maybe-PostAckNudge -PaneId $WorkerPaneId -TaskId $TaskId -Engine $Engine

Write-Host "Task dispatched." -ForegroundColor Green
