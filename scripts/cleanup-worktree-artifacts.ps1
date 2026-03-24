#!/usr/bin/env pwsh

param(
    [Parameter(Mandatory = $true)]
    [string]$RepoPath,

    [Parameter(Mandatory = $false)]
    [switch]$AllowTracked,

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
$auditScript = Join-Path $scriptDir 'audit-worktree-artifacts.ps1'

function Exit-WithResult([int]$Code, [string]$Status, [string]$Message, [hashtable]$Extra = @{}) {
    if ($EmitJson.IsPresent) {
        $payload = @{
            status = $Status
            message = $Message
            repo = $RepoPath
            timestamp = (Get-Date -Format 'o')
        }
        foreach ($k in $Extra.Keys) {
            $payload[$k] = $Extra[$k]
        }
        $payload | ConvertTo-Json -Depth 8 -Compress
    }
    exit $Code
}

if (-not (Test-Path $auditScript)) {
    Exit-WithResult -Code 1 -Status 'blocked' -Message 'artifact_audit_script_missing'
}

$auditJson = & $auditScript -RepoPath $RepoPath -EmitJson
if ($LASTEXITCODE -ne 0) {
    Exit-WithResult -Code 1 -Status 'blocked' -Message 'artifact_audit_failed'
}

try {
    $audit = $auditJson | ConvertFrom-Json
} catch {
    Exit-WithResult -Code 1 -Status 'blocked' -Message 'artifact_audit_invalid_json'
}

$artifactCandidates = @()
if ($audit.artifact_candidates) {
    $artifactCandidates = @($audit.artifact_candidates)
}

if (@($artifactCandidates).Count -eq 0) {
    Exit-WithResult -Code 0 -Status 'noop' -Message 'no_artifacts_found'
}

$tracked = @()
$untracked = @()
foreach ($entry in $artifactCandidates) {
    $path = [string]$entry.path
    $status = [string]$entry.status
    if ([string]::IsNullOrWhiteSpace($path)) { continue }
    if ($status -eq '??') {
        $untracked += $path
    } else {
        $tracked += $path
    }
}

if (@($tracked).Count -gt 0 -and -not $AllowTracked.IsPresent) {
    Exit-WithResult -Code 0 -Status 'blocked' -Message 'tracked_artifacts_require_allow_tracked' -Extra @{
        tracked = @($tracked)
        untracked = @($untracked)
    }
}

$restored = @()
$deleted = @()
$missing = @()

foreach ($path in $tracked) {
    & git -C $RepoPath restore --worktree --source=HEAD -- $path
    if ($LASTEXITCODE -ne 0) {
        Exit-WithResult -Code 1 -Status 'blocked' -Message 'git_restore_failed' -Extra @{ path = $path }
    }
    $restored += $path
}

foreach ($path in $untracked) {
    $fullPath = Join-Path $RepoPath $path
    if (-not (Test-Path -LiteralPath $fullPath)) {
        $missing += $path
        continue
    }
    Remove-Item -LiteralPath $fullPath -Recurse -Force
    $deleted += $path
}

Exit-WithResult -Code 0 -Status 'cleaned' -Message 'artifact_cleanup_applied' -Extra @{
    restored = @($restored)
    deleted = @($deleted)
    missing = @($missing)
}
