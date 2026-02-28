#!/usr/bin/env pwsh
# 统一编码规范：
# - *.ps1 -> UTF-8 with BOM
# - *.json -> UTF-8 without BOM
#
# 用法：
#   pwsh -File scripts/normalize-encoding.ps1            # 仅预览
#   pwsh -File scripts/normalize-encoding.ps1 -Apply     # 实际写入

param(
    [switch]$Apply,
    [string]$Root = (Split-Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = "Stop"

function Has-Utf8Bom([byte[]]$bytes) {
    return ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
}

function Decode-Utf8BestEffort([byte[]]$bytes) {
    $hasBom = Has-Utf8Bom -bytes $bytes
    if ($hasBom) {
        return [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    }
    return [System.Text.Encoding]::UTF8.GetString($bytes)
}

function Write-Utf8([string]$path, [string]$content, [bool]$emitBom) {
    $enc = New-Object System.Text.UTF8Encoding($emitBom)
    [System.IO.File]::WriteAllText($path, $content, $enc)
}

function Is-ExcludedPath([string]$fullPath) {
    $parts = $fullPath -split '[\\/]'
    $exclude = @(".git", "node_modules", ".nuxt", ".output", "dist", "coverage", "__pycache__")
    foreach ($p in $parts) {
        if ($exclude -contains $p) { return $true }
    }
    return $false
}

$all = Get-ChildItem -Path $Root -Recurse -File -Include *.ps1,*.json -ErrorAction SilentlyContinue |
    Where-Object { -not (Is-ExcludedPath -fullPath $_.FullName) }

$changes = New-Object System.Collections.Generic.List[object]

foreach ($f in $all) {
    $ext = $f.Extension.ToLowerInvariant()
    $targetBom = $false
    if ($ext -eq ".ps1") { $targetBom = $true }
    elseif ($ext -eq ".json") { $targetBom = $false }
    else { continue }

    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    $hasBom = Has-Utf8Bom -bytes $bytes
    if ($hasBom -eq $targetBom) { continue }

    $text = Decode-Utf8BestEffort -bytes $bytes
    if ($text.Contains([char]0xFFFD)) {
        Write-Host ("[SKIP] " + $f.FullName + " (decode replacement char detected)") -ForegroundColor Yellow
        continue
    }

    $changes.Add([pscustomobject]@{
        Path = $f.FullName
        Type = $ext
        From = if ($hasBom) { "utf8-bom" } else { "utf8" }
        To   = if ($targetBom) { "utf8-bom" } else { "utf8" }
    }) | Out-Null

    if ($Apply) {
        Write-Utf8 -path $f.FullName -content $text -emitBom $targetBom
    }
}

if ($changes.Count -eq 0) {
    Write-Host "[OK] No encoding changes needed." -ForegroundColor Green
    exit 0
}

Write-Host ""
Write-Host ("[INFO] Files requiring normalization: " + $changes.Count) -ForegroundColor Cyan
$changes | Select-Object Type, From, To, Path | Format-Table -AutoSize

if ($Apply) {
    Write-Host ""
    Write-Host ("[OK] Applied encoding normalization to " + $changes.Count + " files.") -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "[DRY-RUN] Re-run with -Apply to write changes." -ForegroundColor Yellow
}
