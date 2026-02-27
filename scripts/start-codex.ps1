#!/usr/bin/env pwsh
# Codex 启动脚本
# 用法: .\start-codex.ps1 <仓库目录>
# 示例: .\start-codex.ps1 "E:\moxton-lotapi"
#
# 前置条件: ~/.codex/config.toml 已配置 sandbox_permissions = ["disk-full-read-access"]
# 这使 Codex 可读取 E:\moxton-ccb 下的角色定义、任务文档、API 文档

param(
    [Parameter(Mandatory=$true)]
    [string]$RepoDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path $RepoDir)) {
    Write-Error "仓库目录不存在: $RepoDir"
    exit 1
}

Write-Host "=========================================="
Write-Host "[START] Codex -> $RepoDir"
Write-Host "=========================================="

# 1. 确保 WezTerm 在 PATH 中
$WezTermPath = "D:\WezTerm-windows-20240203-110809-5046fc22"
if ($env:Path -notlike "*$WezTermPath*") {
    Write-Host "[Step 1] Adding WezTerm to PATH..."
    $env:Path += ";$WezTermPath"
}

# 2. 切换到仓库目录（Codex 自动加载该目录的 CLAUDE.md/AGENTS.md）
Write-Host "[Step 2] Switching to workdir: $RepoDir"
Set-Location $RepoDir

# 3. 启动 Codex（通过 CCB 包装器）
Write-Host ""
Write-Host "=========================================="
Write-Host "[RUN] Starting Codex..."
Write-Host "=========================================="
Write-Host ""

& python "C:\Users\26249\AppData\Local\codex-dual\ccb" codex

Write-Host ""
Write-Host "=========================================="
Write-Host "[DONE] Codex exited"
Write-Host "=========================================="
