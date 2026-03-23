#!/usr/bin/env pwsh
# Start a headless worker run using codex exec.
# Phase 1 scope: doc-updater / repo-committer.

param(
    [Parameter(Mandatory = $false)]
    [switch]$RunChild,

    [Parameter(Mandatory = $true)]
    [string]$TaskId,

    [Parameter(Mandatory = $true)]
    [string]$WorkerName,

    [Parameter(Mandatory = $true)]
    [string]$WorkDir,

    [Parameter(Mandatory = $false)]
    [ValidateSet('codex', 'gemini')]
    [string]$Engine = 'codex',

    [Parameter(Mandatory = $false)]
    [string]$RunId,

    [Parameter(Mandatory = $false)]
    [string]$TaskFilePath,

    [Parameter(Mandatory = $false)]
    [string]$InlineTaskBody,

    [Parameter(Mandatory = $false)]
    [string]$RunDir,

    [Parameter(Mandatory = $false)]
    [switch]$EmitJson
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
try {
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        chcp 65001 | Out-Null
    }
} catch {}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Split-Path -Parent $scriptDir
$runtimeRoot = Join-Path $rootDir 'runtime'
$runsRoot = Join-Path $runtimeRoot 'runs'

function Write-Utf8NoBomFile([string]$path, [string]$content) {
    $dir = Split-Path -Parent $path
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($path, $content, $utf8NoBom)
}

function Append-Utf8Line([string]$path, [string]$line) {
    if ([string]::IsNullOrWhiteSpace($path) -or [string]::IsNullOrWhiteSpace($line)) { return }
    $dir = Split-Path -Parent $path
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $writer = New-Object System.IO.StreamWriter($path, $true, $utf8NoBom)
    try {
        $writer.WriteLine($line)
    } finally {
        $writer.Dispose()
    }
}

function New-RunId([string]$taskId) {
    $safeTask = if ($taskId) { ($taskId -replace '[^A-Za-z0-9\-]', '-') } else { 'TASK' }
    return ('headless-' + $safeTask + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + (Get-Random -Minimum 1000 -Maximum 9999))
}

function Resolve-RoleDefinitionPath([string]$workerName, [string]$ccbRoot) {
    if (-not $workerName) { return $null }
    $agentsDir = Join-Path $ccbRoot '.claude\agents'
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

function Get-DispatchPrompt {
    param(
        [string]$TaskId,
        [string]$WorkerName,
        [string]$TaskFilePath,
        [string]$InlineTaskBody,
        [string]$RunId,
        [string]$RoleDefinitionPath,
        [string]$ProtocolPath
    )

    $hasTaskFile = -not [string]::IsNullOrWhiteSpace($TaskFilePath)
    $hasInlineBody = -not [string]::IsNullOrWhiteSpace($InlineTaskBody)
    $taskSource = if ($hasTaskFile) { $TaskFilePath } else { '<inline-task-body>' }
    $routeRunId = if ([string]::IsNullOrWhiteSpace($RunId)) { '<none>' } else { $RunId }
    $taskInstruction = if ($hasTaskFile) { '最后读取 task_file 并开始执行' } else { '按 inline_task_body 执行，不需要再读任务文件' }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('[TASK-DISPATCH]')
    $lines.Add('task_id: ' + $TaskId)
    $lines.Add('worker: ' + $WorkerName)
    $lines.Add('route_run_id: ' + $routeRunId)
    $lines.Add('task_file: ' + $taskSource)
    $lines.Add('role_definition: ' + $(if ($RoleDefinitionPath) { $RoleDefinitionPath } else { '<not-mapped>' }))
    $lines.Add('protocol: ' + $ProtocolPath)
    $lines.Add('')
    $lines.Add('执行要求：')
    $lines.Add('1) 先读取 role_definition（若提供）并遵循角色约束')
    $lines.Add('2) 再读取 protocol 并遵循通信/回传协议')
    $lines.Add('3) ' + $taskInstruction)
    $lines.Add('4) 生命周期按 protocol 执行（in_progress 心跳 / blocked 上报 / 完成回传）')
    $lines.Add('5) 禁止子代理（sub-agent/background agent），仅主进程执行')
    $lines.Add('6) 每次调用 report_route / mcp__route__report_route 时都必须携带 run_id: ' + $routeRunId)
    $lines.Add('7) ACK 后必须立即继续执行（不要等待用户“继续/确认”）')
    if ($WorkerName -match '-qa(?:-\d+)?$') {
        $lines.Add('QA 注意：success 回传必须满足 protocol.md 的 QA 回传合同（JSON + checks + evidence）。')
    }
    if ($hasInlineBody) {
        $lines.Add('')
        $lines.Add('inline_task_body:')
        foreach ($line in ($InlineTaskBody -split "`r?`n")) {
            $lines.Add($line)
        }
    }
    $lines.Add('收到后请先通过 report_route(status=in_progress, body 包含 ack=1 + first_step) 完成 ACK，然后立刻继续执行')
    return ($lines -join "`n")
}

function Write-RunState {
    param(
        [string]$Path,
        [hashtable]$Meta,
        [string]$Status,
        [string]$Phase,
        [string]$Note,
        [int]$ExitCode = -1
    )
    $state = [ordered]@{
        task_id = $Meta.task_id
        run_id = $Meta.run_id
        worker = $Meta.worker
        engine = $Meta.engine
        workdir = $Meta.workdir
        status = $Status
        phase = $Phase
        started_at = $Meta.started_at
        updated_at = (Get-Date -Format 'o')
        note = if ($Note) { $Note } else { '' }
        exit_code = $ExitCode
    }
    Write-Utf8NoBomFile -path $Path -content ($state | ConvertTo-Json -Depth 8)
}

if (-not $RunChild.IsPresent) {
    if (-not (Test-Path $WorkDir)) {
        throw ('WorkDir not found: ' + $WorkDir)
    }
    if ($Engine -ne 'codex') {
        throw ('Phase 1 headless runner currently supports codex only. worker=' + $WorkerName + ' engine=' + $Engine)
    }

    $resolvedRunId = if ($RunId) { $RunId } else { New-RunId -taskId $TaskId }
    $safeTask = if ($TaskId) { ($TaskId -replace '[^A-Za-z0-9\-]', '-') } else { 'TASK' }
    $resolvedRunDir = if ($RunDir) { $RunDir } else { Join-Path (Join-Path $runsRoot $safeTask) $resolvedRunId }
    if (-not (Test-Path $resolvedRunDir)) {
        New-Item -ItemType Directory -Path $resolvedRunDir -Force | Out-Null
    }

    $roleDefinitionPath = Resolve-RoleDefinitionPath -workerName $WorkerName -ccbRoot $rootDir
    $protocolPath = Join-Path $rootDir '.claude\agents\protocol.md'
    $promptPath = Join-Path $resolvedRunDir 'dispatch-prompt.md'
    $metaPath = Join-Path $resolvedRunDir 'meta.json'
    $statePath = Join-Path $resolvedRunDir 'state.json'
    $eventsPath = Join-Path $resolvedRunDir 'events.jsonl'
    $stderrPath = Join-Path $resolvedRunDir 'stderr.log'
    $finalMessagePath = Join-Path $resolvedRunDir 'final-message.md'
    $exitCodePath = Join-Path $resolvedRunDir 'exit-code.txt'

    $prompt = Get-DispatchPrompt -TaskId $TaskId -WorkerName $WorkerName -TaskFilePath $TaskFilePath -InlineTaskBody $InlineTaskBody -RunId $resolvedRunId -RoleDefinitionPath $roleDefinitionPath -ProtocolPath $protocolPath
    Write-Utf8NoBomFile -path $promptPath -content $prompt
    if (-not (Test-Path $eventsPath)) { Write-Utf8NoBomFile -path $eventsPath -content '' }
    if (-not (Test-Path $stderrPath)) { Write-Utf8NoBomFile -path $stderrPath -content '' }
    if (-not (Test-Path $finalMessagePath)) { Write-Utf8NoBomFile -path $finalMessagePath -content '' }
    Write-Utf8NoBomFile -path $exitCodePath -content '-1'

    $meta = [ordered]@{
        task_id = $TaskId
        run_id = $resolvedRunId
        worker = $WorkerName
        engine = $Engine
        workdir = $WorkDir
        task_file = if ($TaskFilePath) { $TaskFilePath } else { '' }
        role_definition = if ($roleDefinitionPath) { $roleDefinitionPath } else { '' }
        protocol = if (Test-Path $protocolPath) { $protocolPath } else { '' }
        prompt_file = $promptPath
        started_at = (Get-Date -Format 'o')
        launch_mode = 'headless'
    }
    Write-Utf8NoBomFile -path $metaPath -content ($meta | ConvertTo-Json -Depth 8)
    Write-RunState -Path $statePath -Meta $meta -Status 'starting' -Phase 'spawn' -Note 'Headless run created'
    Append-Utf8Line -path $eventsPath -line (@{ ts = (Get-Date -Format 'o'); event = 'run_created'; task_id = $TaskId; run_id = $resolvedRunId; worker = $WorkerName; summary = 'Headless run created' } | ConvertTo-Json -Compress)

    $argList = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $PSCommandPath,
        '-RunChild',
        '-TaskId', $TaskId,
        '-WorkerName', $WorkerName,
        '-WorkDir', $WorkDir,
        '-Engine', $Engine,
        '-RunId', $resolvedRunId,
        '-RunDir', $resolvedRunDir
    )
    $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -WorkingDirectory $WorkDir -WindowStyle Hidden -PassThru

    Write-RunState -Path $statePath -Meta $meta -Status 'running' -Phase 'exec' -Note ('Process started pid=' + $proc.Id) -ExitCode -1
    Append-Utf8Line -path $eventsPath -line (@{ ts = (Get-Date -Format 'o'); event = 'run_started'; task_id = $TaskId; run_id = $resolvedRunId; worker = $WorkerName; pid = $proc.Id; summary = 'Headless process started' } | ConvertTo-Json -Compress)

    $result = [ordered]@{
        status = 'dispatched'
        message = 'headless_run_started'
        taskId = $TaskId
        worker = $WorkerName
        runId = $resolvedRunId
        runDir = $resolvedRunDir
        pid = [int]$proc.Id
        dispatchMode = 'headless'
        timestamp = (Get-Date -Format 'o')
    }
    if ($EmitJson.IsPresent) {
        Write-Output ($result | ConvertTo-Json -Compress)
    } else {
        Write-Host ('[OK] Headless run started: ' + $TaskId + ' -> ' + $WorkerName + ' pid=' + $proc.Id) -ForegroundColor Green
        Write-Host ('       run_id=' + $resolvedRunId) -ForegroundColor Gray
        Write-Host ('       run_dir=' + $resolvedRunDir) -ForegroundColor Gray
    }
    exit 0
}

if (-not $RunDir -or -not (Test-Path $RunDir)) {
    throw ('RunDir missing for child mode: ' + $RunDir)
}

$metaPath = Join-Path $RunDir 'meta.json'
$statePath = Join-Path $RunDir 'state.json'
$eventsPath = Join-Path $RunDir 'events.jsonl'
$stderrPath = Join-Path $RunDir 'stderr.log'
$promptPath = Join-Path $RunDir 'dispatch-prompt.md'
$finalMessagePath = Join-Path $RunDir 'final-message.md'
$exitCodePath = Join-Path $RunDir 'exit-code.txt'

$meta = Get-Content -Path $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
$metaMap = @{
    task_id = [string]$meta.task_id
    run_id = [string]$meta.run_id
    worker = [string]$meta.worker
    engine = [string]$meta.engine
    workdir = [string]$meta.workdir
    started_at = [string]$meta.started_at
}

Write-RunState -Path $statePath -Meta $metaMap -Status 'running' -Phase 'exec' -Note 'codex exec started' -ExitCode -1
Append-Utf8Line -path $eventsPath -line (@{ ts = (Get-Date -Format 'o'); event = 'exec_begin'; task_id = $metaMap.task_id; run_id = $metaMap.run_id; worker = $metaMap.worker; summary = 'codex exec started' } | ConvertTo-Json -Compress)

if ($metaMap.engine -ne 'codex') {
    $msg = 'Unsupported engine in child mode: ' + $metaMap.engine
    Append-Utf8Line -path $stderrPath -line $msg
    Write-Utf8NoBomFile -path $exitCodePath -content '1'
    Write-RunState -Path $statePath -Meta $metaMap -Status 'failed' -Phase 'exec' -Note $msg -ExitCode 1
    exit 1
}

$verificationDir = Join-Path $rootDir '05-verification'
$codexPath = 'codex'
try {
    $codexCmd = Get-Command codex -ErrorAction Stop
    if ($codexCmd -and $codexCmd.CommandType -eq 'Application' -and $codexCmd.Source) {
        $codexPath = [string]$codexCmd.Source
    }
} catch {}
$cmdLine = '"' + $codexPath + '" exec -C "' + $metaMap.workdir + '" -s danger-full-access --add-dir "' + $rootDir + '" --add-dir "' + $verificationDir + '" --json -o "' + $finalMessagePath + '" - < "' + $promptPath + '" >> "' + $eventsPath + '" 2>> "' + $stderrPath + '"'
cmd.exe /d /c $cmdLine
$exitCode = $LASTEXITCODE
Write-Utf8NoBomFile -path $exitCodePath -content ([string]$exitCode)
Write-Utf8NoBomFile -path $exitCodePath -content ([string]$exitCode)

if ($exitCode -eq 0) {
    Write-RunState -Path $statePath -Meta $metaMap -Status 'success' -Phase 'finished' -Note 'codex exec finished successfully' -ExitCode 0
    Append-Utf8Line -path $eventsPath -line (@{ ts = (Get-Date -Format 'o'); event = 'run_finished'; task_id = $metaMap.task_id; run_id = $metaMap.run_id; worker = $metaMap.worker; exit_code = 0; summary = 'Headless run finished successfully' } | ConvertTo-Json -Compress)
} else {
    Write-RunState -Path $statePath -Meta $metaMap -Status 'failed' -Phase 'finished' -Note ('codex exec exit=' + $exitCode) -ExitCode $exitCode
    Append-Utf8Line -path $eventsPath -line (@{ ts = (Get-Date -Format 'o'); event = 'run_failed'; task_id = $metaMap.task_id; run_id = $metaMap.run_id; worker = $metaMap.worker; exit_code = $exitCode; summary = ('Headless run failed exit=' + $exitCode) } | ConvertTo-Json -Compress)
}

exit $exitCode
