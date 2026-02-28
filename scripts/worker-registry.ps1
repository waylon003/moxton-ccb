#!/usr/bin/env pwsh
# Worker Pane Registry Manager
# 管理 Worker -> Pane ID 的映射关系

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("register", "unregister", "get", "list", "health-check", "clean")]
    [string]$Action = "list",

    [Parameter(Mandatory=$false)]
    [string]$WorkerName,

    [Parameter(Mandatory=$false)]
    [string]$PaneId,

    [Parameter(Mandatory=$false)]
    [string]$WorkDir,

    [Parameter(Mandatory=$false)]
    [ValidateSet("codex", "gemini")]
    [string]$Engine,

    [Parameter(Mandatory=$false)]
    [string]$RegistryPath = "$PSScriptRoot\..\config\worker-panels.json"
)

$ErrorActionPreference = "Stop"

function Write-Utf8NoBomFile([string]$path, [string]$content) {
    $dir = Split-Path -Parent $path
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($path, $content, $utf8NoBom)
}

# 确保配置目录存在
$registryDir = Split-Path $RegistryPath -Parent
if (-not (Test-Path $registryDir)) {
    New-Item -ItemType Directory -Path $registryDir -Force | Out-Null
}

# 初始化注册表（如果不存在）
function Initialize-Registry {
    if (-not (Test-Path $RegistryPath)) {
        $initialData = @{
            workers = @{}
            updated_at = (Get-Date -Format "o")
        }
        $json = ($initialData | ConvertTo-Json -Depth 10)
        Write-Utf8NoBomFile -path $RegistryPath -content $json
    }
}

# 读取注册表
function Read-Registry {
    Initialize-Registry
    $content = Get-Content $RegistryPath -Raw -Encoding UTF8
    return $content | ConvertFrom-Json
}

# 写入注册表
function Write-Registry($data) {
    $data.updated_at = Get-Date -Format "o"
    $json = ($data | ConvertTo-Json -Depth 10)
    Write-Utf8NoBomFile -path $RegistryPath -content $json
}

# 验证 pane 是否还存在
function Test-PaneExists($testPaneId) {
    try {
        $panes = wezterm cli list --format json 2>$null | ConvertFrom-Json
        return $panes | Where-Object { $_.pane_id -eq $testPaneId }
    }
    catch {
        return $null
    }
}

# 执行动作
switch ($Action) {
    "register" {
        if (-not $WorkerName -or -not $PaneId) {
            Write-Error "register 需要 -WorkerName 和 -PaneId"
            exit 1
        }

        $registry = Read-Registry

        # 将 PSCustomObject 转换为 Hashtable 以便修改
        $workers = @{}
        if ($registry.workers) {
            $registry.workers.PSObject.Properties | ForEach-Object {
                $workers[$_.Name] = $_.Value
            }
        }

        $workers[$WorkerName] = @{
            pane_id = $PaneId
            work_dir = $WorkDir
            engine = $Engine
            registered_at = Get-Date -Format "o"
            last_seen = Get-Date -Format "o"
            status = "active"
        }

        $registry.workers = $workers
        Write-Registry $registry
        Write-Host "Registered: $WorkerName -> pane $PaneId" -ForegroundColor Green
    }

    "unregister" {
        if (-not $WorkerName) {
            Write-Error "unregister 需要 -WorkerName"
            exit 1
        }

        $registry = Read-Registry
        $workers = @{}
        $found = $false

        if ($registry.workers) {
            $registry.workers.PSObject.Properties | ForEach-Object {
                if ($_.Name -ne $WorkerName) {
                    $workers[$_.Name] = $_.Value
                }
                else {
                    $found = $true
                }
            }
        }

        if ($found) {
            $registry.workers = $workers
            Write-Registry $registry
            Write-Host "Unregistered: $WorkerName" -ForegroundColor Green
        }
        else {
            Write-Host "Worker not found: $WorkerName" -ForegroundColor Yellow
        }
    }

    "get" {
        if (-not $WorkerName) {
            Write-Error "get 需要 -WorkerName"
            exit 1
        }

        $registry = Read-Registry
        $worker = $null

        if ($registry.workers) {
            $registry.workers.PSObject.Properties | ForEach-Object {
                if ($_.Name -eq $WorkerName) {
                    $worker = $_.Value
                }
            }
        }

        if ($worker) {
            # 验证 pane 是否还存在
            $paneInfo = Test-PaneExists $worker.pane_id
            if ($paneInfo) {
                $worker.status = "active"
                $worker.last_seen = Get-Date -Format "o"

                # 更新 registry
                $workers = @{}
                $registry.workers.PSObject.Properties | ForEach-Object {
                    $workers[$_.Name] = $_.Value
                }
                $workers[$WorkerName] = $worker
                $registry.workers = $workers
                Write-Registry $registry

                # 输出 pane_id（用于捕获）
                Write-Output $worker.pane_id
            }
            else {
                Write-Host "Worker $WorkerName 的 pane 已不存在" -ForegroundColor Yellow
                exit 1
            }
        }
        else {
            Write-Host "Worker not found: $WorkerName" -ForegroundColor Yellow
            exit 1
        }
    }

    "list" {
        $registry = Read-Registry
        Write-Host ""
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host "         Worker Pane Registry" -ForegroundColor Cyan
        Write-Host "==============================================" -ForegroundColor Cyan

        $hasWorkers = $false
        if ($registry.workers) {
            $registry.workers.PSObject.Properties | ForEach-Object {
                $hasWorkers = $true
                $w = $_.Value
                $name = $_.Name.PadRight(15)
                $pane = $w.pane_id.ToString().PadRight(6)
                $engine = ($w.engine).PadRight(8)
                $status = $w.status

                if ($status -eq "active") {
                    Write-Host "  $name pane=$pane engine=$engine status=$status" -ForegroundColor White
                }
                else {
                    Write-Host "  $name pane=$pane engine=$engine status=$status" -ForegroundColor DarkGray
                }
            }
        }

        if (-not $hasWorkers) {
            Write-Host "  (No workers registered)" -ForegroundColor Gray
        }

        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host "Last updated: $($registry.updated_at)" -ForegroundColor Gray
        Write-Host ""
    }

    "health-check" {
        $registry = Read-Registry
        $updated = $false
        $workers = @{}

        if ($registry.workers) {
            $registry.workers.PSObject.Properties | ForEach-Object {
                $name = $_.Name
                $w = $_.Value
                $paneInfo = Test-PaneExists $w.pane_id

                if ($paneInfo) {
                    $w.status = "active"
                    $w.last_seen = Get-Date -Format "o"
                    $workers[$name] = $w
                    Write-Host "OK $name`: active (pane $($w.pane_id))" -ForegroundColor Green
                }
                else {
                    Write-Host "FAIL $name`: pane not found (removing)" -ForegroundColor Red
                    $updated = $true
                }
            }

            if ($updated) {
                $registry.workers = $workers
                Write-Registry $registry
                Write-Host "Registry cleaned" -ForegroundColor Green
            }
        }
    }

    "clean" {
        $registry = Read-Registry
        $registry.workers = @{}
        Write-Registry $registry
        Write-Host "Registry cleared" -ForegroundColor Green
    }
}
