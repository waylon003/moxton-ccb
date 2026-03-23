#!/usr/bin/env pwsh

param(
    [Parameter(Mandatory = $true)]
    [string]$TaskId,

    [Parameter(Mandatory = $true)]
    [string[]]$EvidencePaths,

    [Parameter(Mandatory = $false)]
    [string]$WorkDir = (Get-Location).Path,

    [Parameter(Mandatory = $false)]
    [switch]$EmitJson
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function New-ResultObject {
    param(
        [string]$InputPath,
        [string]$ExpectedPath,
        [string]$RepoLocalCandidate,
        [string]$Status,
        [string]$Message
    )
    [PSCustomObject]@{
        input = $InputPath
        expected = $ExpectedPath
        repo_local_candidate = $RepoLocalCandidate
        status = $Status
        message = $Message
    }
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Split-Path -Parent $scriptDir
$expectedRoot = Join-Path $rootDir (Join-Path '05-verification' $TaskId)
$expectedPrefix = ('05-verification\' + $TaskId + '\').ToLowerInvariant()

$results = New-Object System.Collections.Generic.List[object]
$errors = New-Object System.Collections.Generic.List[string]

foreach ($rawPath in $EvidencePaths) {
    $inputPath = if ($rawPath) { $rawPath.Trim() } else { '' }
    if ([string]::IsNullOrWhiteSpace($inputPath)) {
        $errors.Add('存在空 evidence 路径。') | Out-Null
        $results.Add((New-ResultObject -InputPath $inputPath -ExpectedPath '' -RepoLocalCandidate '' -Status 'invalid' -Message 'empty_evidence_path')) | Out-Null
        continue
    }

    $normalizedInput = $inputPath.Replace('/', '\')
    $expectedPath = ''
    $repoLocalCandidate = ''
    $status = 'ok'
    $message = ''

    if ([System.IO.Path]::IsPathRooted($normalizedInput)) {
        $fullInput = [System.IO.Path]::GetFullPath($normalizedInput)
        $normalizedExpectedRoot = [System.IO.Path]::GetFullPath($expectedRoot).TrimEnd('\')
        if ($fullInput.TrimEnd('\').StartsWith($normalizedExpectedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            $expectedPath = $fullInput
        } else {
            $marker = ('\05-verification\' + $TaskId + '\')
            $idx = $fullInput.IndexOf($marker, [System.StringComparison]::OrdinalIgnoreCase)
            if ($idx -ge 0) {
                $suffix = $fullInput.Substring($idx + $marker.Length)
                $expectedPath = if ($suffix) { Join-Path $expectedRoot $suffix } else { $expectedRoot }
                $repoLocalCandidate = $fullInput
            } else {
                $status = 'invalid'
                $message = 'absolute_path_outside_ccb_verification_root'
                $errors.Add('evidence 使用了 CCB 之外的绝对路径: ' + $inputPath) | Out-Null
                $results.Add((New-ResultObject -InputPath $inputPath -ExpectedPath $fullInput -RepoLocalCandidate '' -Status $status -Message $message)) | Out-Null
                continue
            }
        }
    } else {
        if (-not $normalizedInput.ToLowerInvariant().StartsWith($expectedPrefix)) {
            $status = 'invalid'
            $message = 'relative_path_must_start_with_task_verification_root'
            $errors.Add('evidence 必须以 05-verification/' + $TaskId + '/ 开头: ' + $inputPath) | Out-Null
            $results.Add((New-ResultObject -InputPath $inputPath -ExpectedPath '' -RepoLocalCandidate '' -Status $status -Message $message)) | Out-Null
            continue
        }
        $expectedPath = Join-Path $rootDir $normalizedInput
        $repoLocalCandidate = Join-Path $WorkDir $normalizedInput
    }

    if (Test-Path $expectedPath) {
        $results.Add((New-ResultObject -InputPath $inputPath -ExpectedPath $expectedPath -RepoLocalCandidate $repoLocalCandidate -Status 'ok' -Message 'exists_in_ccb_root')) | Out-Null
        continue
    }

    if ($repoLocalCandidate -and (Test-Path $repoLocalCandidate)) {
        $status = 'invalid'
        $message = 'repo_local_evidence_found_but_ccb_copy_missing'
        $errors.Add('evidence 文件只存在于仓库本地目录，未落盘到 CCB 根目录: ' + $inputPath + ' ; repo_local=' + $repoLocalCandidate + ' ; expected=' + $expectedPath) | Out-Null
        $results.Add((New-ResultObject -InputPath $inputPath -ExpectedPath $expectedPath -RepoLocalCandidate $repoLocalCandidate -Status $status -Message $message)) | Out-Null
        continue
    }

    $status = 'invalid'
    $message = 'missing_evidence_file'
    $errors.Add('evidence 文件不存在: ' + $inputPath + ' ; expected=' + $expectedPath) | Out-Null
    $results.Add((New-ResultObject -InputPath $inputPath -ExpectedPath $expectedPath -RepoLocalCandidate $repoLocalCandidate -Status $status -Message $message)) | Out-Null
}

$summary = [PSCustomObject]@{
    valid = ($errors.Count -eq 0)
    task_id = $TaskId
    expected_root = $expectedRoot
    workdir = $WorkDir
    checked = $results
    errors = $errors
}

if ($EmitJson.IsPresent) {
    Write-Output ($summary | ConvertTo-Json -Depth 8)
} else {
    Write-Host '==========================================' -ForegroundColor Cyan
    Write-Host '  QA Evidence Validation' -ForegroundColor Cyan
    Write-Host '==========================================' -ForegroundColor Cyan
    Write-Host ('TaskId:        ' + $TaskId)
    Write-Host ('Expected Root: ' + $expectedRoot)
    Write-Host ('WorkDir:       ' + $WorkDir)
    Write-Host ''
    foreach ($row in $results) {
        $color = if ($row.status -eq 'ok') { 'Green' } else { 'Yellow' }
        Write-Host ('[' + $row.status.ToUpperInvariant() + '] ' + $row.input) -ForegroundColor $color
        if ($row.expected) { Write-Host ('  expected: ' + $row.expected) -ForegroundColor DarkGray }
        if ($row.repo_local_candidate) { Write-Host ('  repo_local: ' + $row.repo_local_candidate) -ForegroundColor DarkGray }
        if ($row.message) { Write-Host ('  note: ' + $row.message) -ForegroundColor DarkGray }
    }
    if ($errors.Count -gt 0) {
        Write-Host ''
        Write-Host '[FAIL] Evidence validation failed.' -ForegroundColor Red
        $errors | ForEach-Object { Write-Host ('  - ' + $_) -ForegroundColor Yellow }
    } else {
        Write-Host ''
        Write-Host '[OK] All evidence files exist under CCB verification root.' -ForegroundColor Green
    }
}

if ($errors.Count -gt 0) {
    exit 1
}

exit 0