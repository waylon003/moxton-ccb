#!/usr/bin/env pwsh

param(
    [Parameter(Mandatory = $true)]
    [string]$RepoPath,

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

function Normalize-RepoRelativePath([string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) { return '' }
    $trimmed = [string]$value.Trim()
    if ($trimmed.Contains(' -> ')) {
        $parts = $trimmed -split ' -> '
        $trimmed = $parts[$parts.Length - 1]
    }
    return (($trimmed -replace '\\', '/') -replace '^[./]+', '')
}

function Test-ArtifactCandidate([string]$relativePath) {
    if ([string]::IsNullOrWhiteSpace($relativePath)) { return $false }
    foreach ($pattern in @(
        '(^|/)\.golutra(/|$)',
        '(^|/)\.ccb-tmp(/|$)',
        '(^|/)tmp/ccb(/|$)',
        '(^|/)\.tmp-[^/]+(/|$)',
        '(^|/)playwright-report(/|$)',
        '(^|/)test-results(/|$)',
        '(^|/)05-verification(/|$)',
        '(^|/)tmp-[^/]+\.(err|out|log)$',
        '(^|/)(network-[^/]+\.(txt|json))$',
        '(^|/)(shop-fe-[^/]+\.(png|txt|json))$',
        '(^|/)(SHOP-FE-[^/]+\.(png|txt|json))$',
        '(^|/)(BACKEND-[^/]+\.(png|txt|json|log))$',
        '(^|/)(ADMIN-FE-[^/]+\.(png|txt|json))$'
    )) {
        if ($relativePath -match $pattern) { return $true }
    }
    return $false
}

if (-not (Test-Path $RepoPath)) {
    throw ('RepoPath not found: ' + $RepoPath)
}

$gitRoot = @(& git -C $RepoPath rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or $gitRoot.Count -eq 0) {
    throw ('Not a git repository: ' + $RepoPath)
}
$gitRoot = ([string]$gitRoot[0]).Trim()
$branchLines = @(& git -C $RepoPath rev-parse --abbrev-ref HEAD 2>$null)
if ($LASTEXITCODE -ne 0 -or $branchLines.Count -eq 0) {
    $branch = ''
} else {
    $branch = ([string]$branchLines[0]).Trim()
}
$statusLines = @(& git -C $RepoPath status --porcelain=v1 --untracked-files=all)
if ($LASTEXITCODE -ne 0) {
    throw ('git status failed: ' + $RepoPath)
}

$artifactCandidates = @()
$possibleRealChanges = @()

foreach ($line in $statusLines) {
    $raw = [string]$line
    if ([string]::IsNullOrWhiteSpace($raw)) { continue }
    if ($raw.Length -lt 4) { continue }

    $status = ([string]$raw.Substring(0, 2)).Trim()
    $relativePath = Normalize-RepoRelativePath -value ([string]$raw.Substring(3))
    if ([string]::IsNullOrWhiteSpace($relativePath)) { continue }

    $entry = [pscustomobject]@{
        status = $status
        path = $relativePath
    }

    if (Test-ArtifactCandidate -relativePath $relativePath) {
        $artifactCandidates += $entry
    } else {
        $possibleRealChanges += $entry
    }
}

$result = [pscustomobject]@{
    status = 'ok'
    repo = $gitRoot
    branch = $branch
    scanned_at = (Get-Date -Format 'o')
    artifact_count = @($artifactCandidates).Count
    real_change_count = @($possibleRealChanges).Count
    artifact_candidates = @($artifactCandidates)
    possible_real_changes = @($possibleRealChanges)
}

if ($EmitJson.IsPresent) {
    $result | ConvertTo-Json -Depth 8 -Compress
    exit 0
}

Write-Host ''
Write-Host '==============================================' -ForegroundColor Cyan
Write-Host '       Worktree Artifact Audit' -ForegroundColor Cyan
Write-Host '==============================================' -ForegroundColor Cyan
Write-Host ('Repo:   ' + $gitRoot) -ForegroundColor White
if ($branch) {
    Write-Host ('Branch: ' + $branch) -ForegroundColor White
}
Write-Host ('Artifact candidates: ' + @($artifactCandidates).Count) -ForegroundColor Yellow
Write-Host ('Possible real changes: ' + @($possibleRealChanges).Count) -ForegroundColor Green

if (@($artifactCandidates).Count -gt 0) {
    Write-Host ''
    Write-Host '--- Artifact Candidates ---' -ForegroundColor Yellow
    foreach ($item in $artifactCandidates) {
        Write-Host ('  [' + $item.status + '] ' + $item.path) -ForegroundColor Yellow
    }
}

if (@($possibleRealChanges).Count -gt 0) {
    Write-Host ''
    Write-Host '--- Possible Real Changes ---' -ForegroundColor Green
    foreach ($item in $possibleRealChanges) {
        Write-Host ('  [' + $item.status + '] ' + $item.path) -ForegroundColor Green
    }
}
