#!/usr/bin/env pwsh
# 启动 Worker - Pane 直接模型（修复版）
# 用法: .\start-worker.ps1 -WorkDir "E:\moxton-lotapi" -WorkerName "backend-dev" -Engine codex
#
# 说明：
# - 默认创建独立窗口
# - Worker 直接在 pane 中运行，dispatch-task 发送的文本可直接到达
# - 使用 -Split 参数可创建左右分屏（不推荐）

param(
    [Parameter(Mandatory=$true)]
    [string]$WorkDir,

    [Parameter(Mandatory=$true)]
    [string]$WorkerName,

    [Parameter(Mandatory=$false)]
    [string]$TeamLeadPaneId = $env:TEAM_LEAD_PANE_ID,

    [Parameter(Mandatory=$false)]
    [ValidateSet("codex", "gemini")]
    [string]$Engine = "codex",

    [Parameter(Mandatory=$false)]
    [int]$TimeoutSeconds = 3600,

    [Parameter(Mandatory=$false)]
    [switch]$Split  # 启用分屏模式（默认是独立窗口）
)

$ErrorActionPreference = "Stop"

# 验证 TeamLeadPaneId
if (-not $TeamLeadPaneId) {
    Write-Error "TEAM_LEAD_PANE_ID 未设置。请先设置环境变量。`n示例: `$env:TEAM_LEAD_PANE_ID = (wezterm cli list --format json | ConvertFrom-Json | Where-Object { `$_.title -like '*claude*' } | Select-Object -First 1).pane_id"
    exit 1
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "启动 Worker (Pane 直接模型)" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Worker: $WorkerName"
Write-Host "Engine: $Engine"
Write-Host "WorkDir: $WorkDir"
Write-Host "Team Lead Pane: $TeamLeadPaneId"
Write-Host "Timeout: $TimeoutSeconds seconds"

if ($Split) {
    Write-Host "模式: 左右分屏" -ForegroundColor Yellow
} else {
    Write-Host "模式: 独立窗口 (推荐)" -ForegroundColor Green
}
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# 构建引擎启动命令
$ccbRoot = Split-Path -Parent $PSScriptRoot
$engineCommand = if ($Engine -eq "codex") {
    # qa: on-request（模型自主决策是否请求审批）
    # committer: never（避免 git 提交流程卡在交互审批）
    # 其他 dev: untrusted（只自动批准可信命令）
    $approvalFlag = if ($WorkerName -like "*-qa") {
        "on-request"
    } elseif ($WorkerName -like "*-committer") {
        "never"
    } else {
        "untrusted"
    }
    $codexCmd = "codex -a $approvalFlag --sandbox workspace-write --add-dir '$ccbRoot'"
    # 前端 worker 启用 js_repl，支持实时调试前端页面
    if ($WorkerName -like "shop-fe-*" -or $WorkerName -like "admin-fe-*") {
        $codexCmd += " --enable js_repl"
    }
    $codexCmd
} else {
    # Gemini: 去掉 --yolo，默认启用 auto_edit（低风险编辑自动批准）
    $geminiCmd = "gemini --approval-mode auto_edit --include-directories '$ccbRoot'"
    if ($env:GEMINI_ALLOWED_TOOLS) {
        $geminiCmd += " --allowed-tools ""$($env:GEMINI_ALLOWED_TOOLS)"""
    }
    $geminiCmd
}

# 生成 wrapper 脚本到临时文件（避免 EncodedCommand 编码问题）
$wrapperPath = Join-Path $env:TEMP "moxton-worker-$WorkerName.ps1"
$notifyScript = Join-Path $PSScriptRoot "worker-notify.ps1"

$wrapperContent = @"
# Worker wrapper for $WorkerName
`$env:TEAM_LEAD_PANE_ID = "$TeamLeadPaneId"
`$env:WORKER_NAME = "$WorkerName"
`$env:WORKER_ENGINE = "$Engine"
`$env:WORKER_START_TIME = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
`$env:WORKER_TIMEOUT = "$TimeoutSeconds"

Write-Host ""
Write-Host "Worker ready: $WorkerName ($Engine)" -ForegroundColor Cyan
Write-Host "WorkDir: $WorkDir" -ForegroundColor Cyan
Write-Host "Team Lead Pane: $TeamLeadPaneId" -ForegroundColor Cyan
Write-Host "Waiting for task dispatch..." -ForegroundColor Yellow
Write-Host ""

cd "$WorkDir"
$engineCommand

`$ec = `$LASTEXITCODE
& "$notifyScript" -TeamLeadPaneId "$TeamLeadPaneId" -WorkerName "$WorkerName" -WorkDir "$WorkDir" -ExitCode `$ec
"@

Set-Content -Path $wrapperPath -Value $wrapperContent -Encoding UTF8
Write-Host "Wrapper: $wrapperPath" -ForegroundColor DarkGray

# 编码 wrapper 调用命令（极简，只调用文件）
$launchCmd = "& '$wrapperPath'"
$encodedEnvSetup = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($launchCmd))

try {
    if ($Split) {
        # 左右分屏模式
        $splitArgs = @(
            "cli", "split-pane",
            "--pane-id", $TeamLeadPaneId,
            "--horizontal",
            "--percent", "50",
            "--cwd", $WorkDir,
            "powershell", "-NoExit", "-EncodedCommand", $encodedEnvSetup
        )

        Write-Host "执行: wezterm $($splitArgs -join ' ')" -ForegroundColor DarkGray
        $newPaneId = & wezterm @splitArgs 2>&1

        if ($LASTEXITCODE -ne 0 -or -not $newPaneId) {
            Write-Error "创建 pane 失败。Exit code: $LASTEXITCODE"
            exit 1
        }

        Start-Sleep -Seconds 2
        Write-Host "✅ Worker 分屏已启动: $WorkerName -> pane $newPaneId" -ForegroundColor Green
    }
    else {
        # 独立窗口模式（默认）- 不指定 window-id 即创建新窗口
        $spawnArgs = @(
            "cli", "spawn",
            "--cwd", $WorkDir,
            "powershell", "-NoExit", "-EncodedCommand", $encodedEnvSetup
        )

        Write-Host "执行: wezterm $($spawnArgs -join ' ')" -ForegroundColor DarkGray
        $newPaneId = & wezterm @spawnArgs 2>&1

        if ($LASTEXITCODE -ne 0 -or -not $newPaneId) {
            Write-Error "创建窗口失败。Exit code: $LASTEXITCODE"
            exit 1
        }

        Start-Sleep -Seconds 2
        Write-Host "✅ Worker 独立窗口已启动: $WorkerName -> pane $newPaneId" -ForegroundColor Green
    }

    # 注册到 Worker Pane Registry
    $registryScript = Join-Path $PSScriptRoot "worker-registry.ps1"
    if (Test-Path $registryScript) {
        & $registryScript -Action register -WorkerName $WorkerName -PaneId $newPaneId -WorkDir $WorkDir -Engine $Engine
    }

    Write-Host ""
    Write-Host "使用以下命令分派任务:" -ForegroundColor Yellow
    Write-Host "  .\scripts\dispatch-task.ps1 -WorkerName `"$WorkerName`" -TaskId `"<TASK-ID>`" -TaskFilePath `"<路径>`"" -ForegroundColor White
    Write-Host ""
    Write-Host "📋 Worker 信息:" -ForegroundColor Cyan
    Write-Host "   Name: $WorkerName" -ForegroundColor Gray
    Write-Host "   Pane ID: $newPaneId" -ForegroundColor Gray
    Write-Host "   Engine: $Engine" -ForegroundColor Gray
}
catch {
    Write-Error "启动 Worker 失败: $_"
    exit 1
}
