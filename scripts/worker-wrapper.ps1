#!/usr/bin/env pwsh
# Worker Wrapper - 强制回执机制
# 用法: .\scripts\worker-wrapper.ps1 -Engine codex -WorkDir "E:\moxton-lotapi" -WorkerName "backend-dev"

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("codex", "gemini")]
    [string]$Engine,

    [Parameter(Mandatory=$true)]
    [string]$WorkDir,

    [Parameter(Mandatory=$true)]
    [string]$WorkerName,

    [Parameter(Mandatory=$false)]
    [string]$TeamLeadPaneId = $env:TEAM_LEAD_PANE_ID,

    [Parameter(Mandatory=$false)]
    [int]$TimeoutSeconds = 3600
)

$ErrorActionPreference = "Stop"

# 颜色输出函数
function Write-Info { param([string]$msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Success { param([string]$msg) Write-Host "[SUCCESS] $msg" -ForegroundColor Green }
function Write-Warn { param([string]$msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Error { param([string]$msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

# 验证环境
if (-not $TeamLeadPaneId) {
    Write-Error "TEAM_LEAD_PANE_ID 未设置。请先设置环境变量或在参数中指定。"
    exit 1
}

# 验证 WezTerm
$wezterm = Get-Command wezterm -ErrorAction SilentlyContinue
if (-not $wezterm) {
    # 尝试常见路径
    $commonPaths = @(
        "D:\WezTerm-windows-20240203-110809-5046fc22\wezterm.exe",
        "$env:LOCALAPPDATA\Programs\WezTerm\wezterm.exe",
        "$env:PROGRAMFILES\WezTerm\wezterm.exe"
    )
    foreach ($path in $commonPaths) {
        if (Test-Path $path) {
            $env:PATH += ";$(Split-Path $path -Parent)"
            break
        }
    }
}

# 发送通知到 Team Lead 的函数
function Send-NotificationToTeamLead {
    param(
        [string]$Status,
        [string]$TaskId,
        [string]$Body
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $message = @"
[ROUTE]
from: $WorkerName
to: team-lead
type: status
task: $TaskId
status: $Status
timestamp: $timestamp
body: |
  $Body
[/ROUTE]
"@

    try {
        # 发送消息内容
        $messageBytes = [System.Text.Encoding]::UTF8.GetBytes($message)
        $message | & wezterm cli send-text --pane-id $TeamLeadPaneId --no-paste 2>$null

        # 发送回车
        $crBytes = [System.Text.Encoding]::UTF8.GetBytes("`r")
        [System.Text.Encoding]::UTF8.GetString($crBytes) | & wezterm cli send-text --pane-id $TeamLeadPaneId --no-paste 2>$null

        Write-Success "通知已发送到 Team Lead (pane_id=$TeamLeadPaneId)"
        return $true
    }
    catch {
        Write-Error "发送通知失败: $_"
        return $false
    }
}

# 显示启动横幅
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                    Worker Wrapper 启动                           ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "║  Worker: $WorkerName" -ForegroundColor Cyan
Write-Host "║  Engine: $Engine" -ForegroundColor Cyan
Write-Host "║  WorkDir: $WorkDir" -ForegroundColor Cyan
Write-Host "║  Team Lead Pane ID: $TeamLeadPaneId" -ForegroundColor Cyan
Write-Host "║  Timeout: $TimeoutSeconds seconds" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# 设置环境变量供子进程使用
$env:TEAM_LEAD_PANE_ID = $TeamLeadPaneId
$env:WORKER_NAME = $WorkerName

# 创建临时目录存放输出
$tempDir = Join-Path $env:TEMP "worker-wrapper-$WorkerName-$(Get-Random)"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
$outputFile = Join-Path $tempDir "output.log"
$errorFile = Join-Path $tempDir "error.log"

Write-Info "临时输出目录: $tempDir"

# 根据引擎启动相应进程
try {
    $process = $null
    $psi = New-Object System.Diagnostics.ProcessStartInfo

    if ($Engine -eq "codex") {
        $psi.FileName = "codex"
        $psi.Arguments = "--full-auto"
    }
    else {
        # Gemini
        $psi.FileName = "gemini"
        $psi.Arguments = ""
    }

    $psi.WorkingDirectory = $WorkDir
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $psi.CreateNoWindow = $false

    Write-Info "启动 $Engine 进程..."
    $process = [System.Diagnostics.Process]::Start($psi)

    Write-Info "进程已启动 (PID: $($process.Id))"
    Write-Info "等待任务完成或超时 ($TimeoutSeconds 秒)..."
    Write-Host ""

    # 启动后台任务读取输出
    $outputReader = $process.StandardOutput
    $errorReader = $process.StandardError

    $outputJob = Start-Job {
        param($reader, $file)
        while ($null -ne ($line = $reader.ReadLine())) {
            "$line" | Out-File -FilePath $file -Append -Encoding UTF8
            Write-Host "[OUT] $line" -ForegroundColor Gray
        }
    } -ArgumentList $outputReader, $outputFile

    $errorJob = Start-Job {
        param($reader, $file)
        while ($null -ne ($line = $reader.ReadLine())) {
            "$line" | Out-File -FilePath $file -Append -Encoding UTF8
            Write-Host "[ERR] $line" -ForegroundColor Red
        }
    } -ArgumentList $errorReader, $errorFile

    # 等待进程完成（带超时）
    $completed = $process.WaitForExit($TimeoutSeconds * 1000)

    if (-not $completed) {
        Write-Warn "任务执行超时 (${TimeoutSeconds}秒)，强制终止进程..."
        $process.Kill()
        $process.WaitForExit(5000) | Out-Null

        # 发送超时通知
        $output = ""
        if (Test-Path $outputFile) {
            $output = Get-Content $outputFile -Raw -ErrorAction SilentlyContinue
        }
        Send-NotificationToTeamLead `
            -Status "timeout" `
            -TaskId "UNKNOWN" `
            -Body "任务执行超时 (${TimeoutSeconds}秒) 被强制终止。`n`n输出摘要:`n$output".Substring(0, [Math]::Min(500, $output.Length))
    }
    else {
        $exitCode = $process.ExitCode
        Write-Info "进程已退出 (Exit Code: $exitCode)"

        # 等待一下让输出读取完成
        Start-Sleep -Seconds 2

        # 读取输出
        $output = ""
        $error = ""

        if (Test-Path $outputFile) {
            $output = Get-Content $outputFile -Raw -ErrorAction SilentlyContinue
        }
        if (Test-Path $errorFile) {
            $error = Get-Content $errorFile -Raw -ErrorAction SilentlyContinue
        }

        # 尝试从输出中提取任务ID
        $taskId = "UNKNOWN"
        if ($output -match 'task[:\s]+([A-Z]+-\d+)') {
            $taskId = $matches[1]
        }
        elseif ($output -match 'TASK-ID[:\s]+([A-Z]+-\d+)') {
            $taskId = $matches[1]
        }

        # 确定状态
        $status = if ($exitCode -eq 0) { "success" } else { "fail" }

        # 构建通知内容
        $bodyLines = @(
            "Worker: $WorkerName"
            "Exit Code: $exitCode"
            ""
            "标准输出摘要:"
        )

        if ($output) {
            $lines = $output -split "`n"
            $lastLines = $lines | Select-Object -Last 20
            $bodyLines += $lastLines
        }
        else {
            $bodyLines += "(无标准输出)"
        }

        if ($error) {
            $bodyLines += ""
            $bodyLines += "错误输出:"
            $errLines = $error -split "`n"
            $bodyLines += $errLines | Select-Object -Last 10
        }

        $body = $bodyLines -join "`n"

        # 发送完成通知
        Send-NotificationToTeamLead -Status $status -TaskId $taskId -Body $body
    }
}
catch {
    Write-Error "执行过程中发生异常: $_"

    # 发送错误通知
    Send-NotificationToTeamLead `
        -Status "error" `
        -TaskId "UNKNOWN" `
        -Body "Worker 执行过程中发生异常:`n$_`n`nStackTrace:`n$($_.ScriptStackTrace)"
}
finally {
    # 清理资源
    if ($process -and -not $process.HasExited) {
        try {
            $process.Kill()
        }
        catch { }
    }

    if ($outputJob) {
        Stop-Job $outputJob -ErrorAction SilentlyContinue
        Remove-Job $outputJob -ErrorAction SilentlyContinue
    }

    if ($errorJob) {
        Stop-Job $errorJob -ErrorAction SilentlyContinue
        Remove-Job $errorJob -ErrorAction SilentlyContinue
    }

    # 清理临时文件
    if (Test-Path $tempDir) {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host ""
    Write-Info "Worker Wrapper 结束"
}
