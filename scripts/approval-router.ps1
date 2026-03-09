#!/usr/bin/env pwsh
# approval-router.ps1 - 监听 Worker 权限提示，低风险自动批准，高风险转发 Team Lead
# Exit codes:
#   0 = handled (single-shot) or graceful stop (continuous with max handled reached)
#   1 = timeout/no approval
#   2 = script error
param(
    [Parameter(Mandatory=$true)]
    [string]$WorkerPaneId,

    [Parameter(Mandatory=$true)]
    [string]$WorkerName,

    [Parameter(Mandatory=$true)]
    [string]$TaskId,

    [Parameter(Mandatory=$true)]
    [string]$TeamLeadPaneId,

    [int]$PollInterval = 2,
    [int]$Timeout = 600,
    [string]$PolicyPath,
    [int]$RequestTtlSeconds = 600,
    [int]$ResolvedRetentionHours = 168,
    [int]$PromptStableCycles = 2,
    [int]$ReplayApproveWindowSeconds = 0,
    [int]$EscalationCooldownSeconds = 12,
    [int]$DecisionCooldownSeconds = 8,
    [int]$WakeCooldownSeconds = 12,

    [switch]$Continuous,
    [int]$MaxHandled = 0
)

$ErrorActionPreference = "Stop"
[Console]::InputEncoding = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Split-Path -Parent $scriptDir
$inboxPath = Join-Path $rootDir "mcp\route-server\data\route-inbox.json"
$locksPath = Join-Path $rootDir "01-tasks\TASK-LOCKS.json"
$requestsPath = Join-Path $rootDir "mcp\route-server\data\approval-requests.json"
$routerLockPath = Join-Path $rootDir "mcp\route-server\data\approval-router.lock"
if (-not $PolicyPath) {
    $PolicyPath = Join-Path $rootDir "config\approval-policy.json"
}

function Read-JsonRetry($path, $maxRetry = 3) {
    for ($i = 0; $i -lt $maxRetry; $i++) {
        try {
            if (-not (Test-Path $path)) { return $null }
            return (Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json)
        } catch {
            Start-Sleep -Milliseconds 200
        }
    }
    return $null
}

function Get-WeztermPanes {
    try {
        $raw = wezterm cli list --format json 2>$null
        if (-not $raw) { return @() }
        $parsed = $raw | ConvertFrom-Json
        return @($parsed)
    } catch {
        return @()
    }
}

function Resolve-TeamLeadPaneId([string]$preferredPaneId) {
    $panes = Get-WeztermPanes
    if ($preferredPaneId) {
        $matched = $panes | Where-Object { ([string]$_.pane_id) -eq ([string]$preferredPaneId) } | Select-Object -First 1
        if ($matched) { return [string]$matched.pane_id }
    }
    $fallback = $panes | Where-Object { $_.title -like '*claude*' -or $_.title -like '* Claude*' } | Select-Object -First 1
    if ($fallback) { return [string]$fallback.pane_id }
    return $null
}

function Notify-TeamLeadWake([string]$message) {
    $targetPane = Resolve-TeamLeadPaneId -preferredPaneId $TeamLeadPaneId
    if (-not $targetPane) { return $false }
    try {
        wezterm cli send-text --pane-id $targetPane --no-paste $message | Out-Null
        Start-Sleep -Milliseconds 80
        wezterm cli send-text --pane-id $targetPane --no-paste "`r" | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Write-JsonUtf8($path, $data) {
    $dir = Split-Path -Parent $path
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $json = ($data | ConvertTo-Json -Depth 20)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($path, $json, $utf8NoBom)
}

function ConvertTo-UtcDateSafe($value) {
    if (-not $value) { return $null }
    try {
        return ([DateTimeOffset]::Parse($value.ToString())).UtcDateTime
    } catch {
        return $null
    }
}

function Invoke-WithFileLock([string]$lockPath, [scriptblock]$Script, [int]$TimeoutMs = 10000, [int]$RetryMs = 100) {
    $dir = Split-Path -Parent $lockPath
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        $fs = $null
        try {
            $fs = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            try {
                return & $Script
            } finally {
                if ($fs) { $fs.Dispose() }
            }
        } catch [System.IO.IOException] {
            if ($fs) { $fs.Dispose() }
            if ($sw.ElapsedMilliseconds -ge $TimeoutMs) {
                throw "Timeout acquiring approval router lock: $lockPath"
            }
            Start-Sleep -Milliseconds $RetryMs
        }
    }
}

function Get-ShortHash([string]$text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
        $hash = $sha.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($hash) -replace '-', '').ToLower().Substring(0, 16)
    } finally {
        $sha.Dispose()
    }
}

function To-AsciiPreview([string]$text, [int]$maxLen = 180) {
    if (-not $text) { return "" }
    # 仅保留可打印 ASCII，避免 TUI 控制字符/边框字符污染日志与 route body
    $ascii = ($text -replace '[^\x20-\x7E]', ' ')
    $ascii = ($ascii -replace '\s+', ' ').Trim()
    if ($ascii.Length -gt $maxLen) {
        return $ascii.Substring(0, $maxLen)
    }
    return $ascii
}

function Contains-Any([string]$text, $patterns) {
    if (-not $text -or -not $patterns) { return $false }
    foreach ($pat in $patterns) {
        $needle = [string]$pat
        if (-not $needle) { continue }
        if ($text.IndexOf($needle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
    }
    return $false
}

function Is-ApprovalPrompt([string]$tail, $policyPatterns) {
    if (-not $tail) { return $false }
    if (Contains-Any -text $tail -patterns $policyPatterns) { return $true }

    # Built-in fallback patterns for Codex/Gemini prompt variants
    $fallback = @(
        "Would you like to run the following command?",
        "Do you want to run the following command?",
        "Do you want to proceed?",
        "Run this command?",
        "Would you like to make the following edits?",
        "Press enter to confirm or esc to cancel",
        "Yes, proceed",
        "[y/N]",
        "(y/n)",
        "press y",
        "Allow this action",
        "Allow execution of:",
        "Action Required",
        "approval required",
        "requires approval",
        "needs approval",
        "是否运行以下命令",
        "是否允许",
        "需要审批"
    )
    return (Contains-Any -text $tail -patterns $fallback)
}

function Get-ApprovalPatterns($policyPatterns) {
    $fallback = @(
        "Would you like to run the following command?",
        "Do you want to run the following command?",
        "Do you want to proceed?",
        "Run this command?",
        "Would you like to make the following edits?",
        "Press enter to confirm or esc to cancel",
        "Yes, proceed",
        "[y/N]",
        "(y/n)",
        "press y",
        "Allow this action",
        "Allow execution of:",
        "Action Required",
        "approval required",
        "requires approval",
        "needs approval",
        "是否运行以下命令",
        "是否允许",
        "需要审批"
    )
    $all = @()
    if ($policyPatterns) { $all += @($policyPatterns) }
    $all += $fallback
    return $all
}

function Extract-ApprovalSnippetLines($tailLines, $policyPatterns) {
    $lines = @($tailLines)
    if ($lines.Count -eq 0) { return @() }
    $allPatterns = Get-ApprovalPatterns -policyPatterns $policyPatterns
    $idx = -1
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        if (Contains-Any -text ([string]$lines[$i]) -patterns $allPatterns) {
            $idx = $i
            break
        }
    }

    if ($idx -ge 0) {
        $start = [Math]::Max(0, $idx - 1)
        $count = [Math]::Min(14, $lines.Count - $start)
        return @($lines[$start..($start + $count - 1)])
    }

    return @($lines | Select-Object -Last 10)
}

function Normalize-ApprovalSnippet([string]$text) {
    if (-not $text) { return "" }
    $t = $text.ToLowerInvariant()
    $t = [regex]::Replace($t, '\s+', ' ')
    $t = [regex]::Replace($t, '[^\p{L}\p{Nd}\s:_/\-\.\(\)\[\]\{\}\|]', '')
    return $t.Trim()
}

function Get-RecentResolvedApproval([string]$fingerprint, [int]$withinSeconds = 45) {
    return Invoke-WithFileLock -lockPath $routerLockPath -Script {
        $store = Read-JsonRetry -path $requestsPath
        if (-not $store -or -not $store.requests) { return $null }

        $nowUtc = [DateTime]::UtcNow
        $matches = @(
            $store.requests |
            Where-Object {
                ($_.status -eq "resolved") -and
                ($_.decision -eq "approve") -and
                (($_.task -eq $TaskId) -or ($_.task_id -eq $TaskId)) -and
                (($_.worker -eq $WorkerName) -or ($_.worker_name -eq $WorkerName)) -and
                ($_.worker_pane_id -eq $WorkerPaneId)
            } |
            Sort-Object resolved_at -Descending
        )
        foreach ($req in $matches) {
            $resolvedUtc = ConvertTo-UtcDateSafe $req.resolved_at
            if (-not $resolvedUtc) { continue }
            $age = ($nowUtc - $resolvedUtc).TotalSeconds
            if ($age -gt $withinSeconds) { continue }
            $fp = if ($req.snippet_fingerprint) { [string]$req.snippet_fingerprint } else { "" }
            if ($fingerprint -and $fp -and $fingerprint -eq $fp) {
                return $req
            }
        }
        return $null
    }
}

function Get-ExistingPendingRequest {
    return Invoke-WithFileLock -lockPath $routerLockPath -Script {
        $store = Read-JsonRetry -path $requestsPath
        if (-not $store -or -not $store.requests) { return $null }
        $matches = @(
            $store.requests |
            Where-Object {
                $_.status -eq "pending" -and
                (($_.task -eq $TaskId) -or ($_.task_id -eq $TaskId)) -and
                (($_.worker -eq $WorkerName) -or ($_.worker_name -eq $WorkerName)) -and
                $_.worker_pane_id -eq $WorkerPaneId
            } |
            Sort-Object created_at -Descending
        )
        if ($matches.Count -gt 0) { return $matches[0] }
        return $null
    }
}

function Ensure-RequestsFile {
    Invoke-WithFileLock -lockPath $routerLockPath -Script {
        if (Test-Path $requestsPath) { return }
        $initial = @{
            version = "1.0"
            updated_at = (Get-Date -Format "o")
            requests = @()
        }
        Write-JsonUtf8 -path $requestsPath -data $initial
    } | Out-Null
}

function Cleanup-ApprovalRequests {
    return Invoke-WithFileLock -lockPath $routerLockPath -Script {
        $store = Read-JsonRetry -path $requestsPath
        if (-not $store) {
            $store = @{ version = "1.0"; updated_at = (Get-Date -Format "o"); requests = @() }
        }
        if (-not $store.requests) {
            $store.requests = @()
        }

        $nowUtc = (Get-Date).ToUniversalTime()
        $changed = $false
        $expiredCount = 0
        $stalePendingCount = 0
        $prunedCount = 0
        $kept = New-Object System.Collections.Generic.List[object]

        foreach ($req in @($store.requests)) {
            $status = if ($null -eq $req.status) { "" } else { [string]$req.status }

            # NOTE:
            # pending 不能在清理阶段静默过期；否则 worker 仍卡在审批提示。
            # 这里只统计 stale pending，真正超时决策在主循环中执行并回写给 worker。
            if ($status -eq "pending" -and $RequestTtlSeconds -gt 0) {
                $createdUtc = ConvertTo-UtcDateSafe $req.created_at
                if ($createdUtc) {
                    $ageSec = ($nowUtc - $createdUtc).TotalSeconds
                    if ($ageSec -ge $RequestTtlSeconds) {
                        $stalePendingCount++
                    }
                }
            }

            if ($status -eq "resolved" -and $ResolvedRetentionHours -gt 0) {
                $resolvedUtc = ConvertTo-UtcDateSafe $req.resolved_at
                if ($resolvedUtc) {
                    $ageHours = ($nowUtc - $resolvedUtc).TotalHours
                    if ($ageHours -ge $ResolvedRetentionHours) {
                        $prunedCount++
                        $changed = $true
                        continue
                    }
                }
            }

            $kept.Add($req) | Out-Null
        }

        if ($changed) {
            $store.requests = @($kept.ToArray())
            $store.updated_at = Get-Date -Format "o"
            Write-JsonUtf8 -path $requestsPath -data $store
        }

        return @{
            expired = $expiredCount
            pruned = $prunedCount
            stale_pending = $stalePendingCount
            changed = $changed
        }
    }
}

function Save-ApprovalRequest($request) {
    Invoke-WithFileLock -lockPath $routerLockPath -Script {
        $store = Read-JsonRetry -path $requestsPath
        if (-not $store) {
            $store = @{ version = "1.0"; updated_at = (Get-Date -Format "o"); requests = @() }
        }
        if (-not $store.requests) {
            $store.requests = @()
        }
        $store.requests = @($store.requests) + $request
        $store.updated_at = Get-Date -Format "o"
        Write-JsonUtf8 -path $requestsPath -data $store
    } | Out-Null
}

function Resolve-ApprovalRequest([string]$requestId, [string]$decision, [string]$resolvedBy, [string]$note) {
    return Invoke-WithFileLock -lockPath $routerLockPath -Script {
        $store = Read-JsonRetry -path $requestsPath
        if (-not $store -or -not $store.requests) { return $false }
        $updated = $false
        foreach ($req in @($store.requests)) {
            if ($req.id -eq $requestId -and $req.status -eq "pending") {
                $req.status = "resolved"
                $req.decision = $decision
                $req.resolved_at = Get-Date -Format "o"
                $req.resolved_by = $resolvedBy
                if ($note) {
                    if (-not $req.PSObject.Properties['note']) {
                        $req | Add-Member -NotePropertyName note -NotePropertyValue $note -Force
                    } else {
                        $req.note = $note
                    }
                }
                $updated = $true
                break
            }
        }
        if ($updated) {
            $store.updated_at = Get-Date -Format "o"
            Write-JsonUtf8 -path $requestsPath -data $store
        }
        return $updated
    }
}

function Get-CurrentTaskRunId {
    $locks = Read-JsonRetry -path $locksPath
    if (-not $locks -or -not $locks.locks) { return "" }
    if ($locks.locks.PSObject.Properties.Name -notcontains $TaskId) { return "" }
    $lock = $locks.locks.$TaskId
    if (-not $lock) { return "" }
    if ($lock.PSObject.Properties.Name -contains "run_id" -and $lock.run_id) {
        return [string]$lock.run_id
    }
    return ""
}

function Append-RouteInbox([string]$status, [string]$body) {
    $currentRunId = Get-CurrentTaskRunId
    $routeId = Get-ShortHash("$WorkerName|$TaskId|$status|$currentRunId|$body|$(Get-Date -Format o)")
    return Invoke-WithFileLock -lockPath $routerLockPath -Script {
        $inbox = Read-JsonRetry -path $inboxPath
        if (-not $inbox) {
            $inbox = @{
                version = "1.0"
                updated_at = (Get-Date -Format "o")
                routes = @()
            }
        }
        if (-not $inbox.routes) {
            $inbox.routes = @()
        }
        $route = @{
            id = $routeId
            from = $WorkerName
            to = "team-lead"
            type = "status"
            task = $TaskId
            status = $status
            body = $body
            run_id = $currentRunId
            created_at = (Get-Date -Format "o")
            processed = $false
            processed_at = $null
        }
        $inbox.routes = @($inbox.routes) + $route
        $inbox.updated_at = Get-Date -Format "o"
        Write-JsonUtf8 -path $inboxPath -data $inbox
        return $routeId
    }
}

function Get-ApprovalPromptType([string]$analysisText) {
    if (-not $analysisText) { return "command_approval" }
    $text = [string]$analysisText
    if (
        $text.IndexOf("Question 1/1", [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        ($text.IndexOf("Approve Once", [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -and
         $text.IndexOf("Approve this Session", [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
    ) {
        return "menu_choice"
    }
    if (
        $text.IndexOf("Would you like to make the following edits?", [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $text.IndexOf("Press enter to confirm or esc to cancel", [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $text.IndexOf("Yes, proceed", [System.StringComparison]::OrdinalIgnoreCase) -ge 0
    ) {
        return "edit_confirm"
    }
    return "command_approval"
}

function Send-DecisionToWorker([string]$decisionKey, [string]$promptType = "command_approval") {
    if ($promptType -eq "menu_choice") {
        if ($decisionKey -eq "y") {
            # Menu-style approval UI (1=Approve Once) uses Enter to submit highlighted option.
            wezterm cli send-text --pane-id $WorkerPaneId --no-paste "`r" | Out-Null
            return
        }
        # Menu-style deny uses option 3 (Deny Once).
        wezterm cli send-text --pane-id $WorkerPaneId --no-paste "3" | Out-Null
        Start-Sleep -Milliseconds 120
        wezterm cli send-text --pane-id $WorkerPaneId --no-paste "`r" | Out-Null
        return
    }

    if ($promptType -eq "edit_confirm") {
        if ($decisionKey -eq "y") {
            wezterm cli send-text --pane-id $WorkerPaneId --no-paste "`r" | Out-Null
            return
        }
        wezterm cli send-text --pane-id $WorkerPaneId --no-paste "`e" | Out-Null
        return
    }

    wezterm cli send-text --pane-id $WorkerPaneId --no-paste $decisionKey | Out-Null
    Start-Sleep -Milliseconds 150
    wezterm cli send-text --pane-id $WorkerPaneId --no-paste "`r" | Out-Null
}

try {
    $policy = Read-JsonRetry -path $PolicyPath
    if (-not $policy) {
        $policy = @{
            allowed_mcp_patterns = @(
                "report_route",
                "check_routes",
                "clear_route",
                "mcp__route__report_route",
                "mcp__route__check_routes",
                "mcp__route__clear_route",
                "route.report_route",
                "route.check_routes",
                "route.clear_route",
                "mcp__vitest__",
                "mcp__vitest__set_project_root",
                "mcp__vitest__list_tests",
                "mcp__vitest__run_tests",
                "mcp__vitest__analyze_coverage",
                "vitest.set_project_root",
                "vitest.list_tests",
                "vitest.run_tests",
                "vitest.analyze_coverage",
                "vitest MCP server wants to run the tool ""set_project_root""",
                "vitest MCP server wants to run the tool ""list_tests""",
                "vitest MCP server wants to run the tool ""run_tests""",
                "vitest MCP server wants to run the tool ""analyze_coverage""",
                "mcp__context7__",
                "mcp__context7__resolve-library-id",
                "mcp__context7__query-docs",
                "context7.resolve-library-id",
                "context7.query-docs",
                "context7 MCP server wants to run the tool ""resolve-library-id""",
                "context7 MCP server wants to run the tool ""query-docs""",
                "mcp__playwright__browser_",
                "playwright.browser_",
                "tool ""browser_""",
                "playwright MCP server wants to run the tool ""browser_"""
            )
            approval_prompt_patterns = @("Approval needed", "requires approval", "permission", "approve")
            low_risk_patterns = @("mcp__vitest__", "mcp__playwright__", "mcp__context7__", "mcp__route__", "git status", "git diff", "rg ", "pnpm type-check", "pnpm build", "npm run build", "node test-", "curl ", "Invoke-WebRequest")
            high_risk_patterns = @("rm ", "Remove-Item", "git reset", "git clean", "npm install", "pnpm add", "pip install")
        }
    }

    $elapsed = 0
    $handled = 0
    $lastPromptFingerprint = ""
    $promptStableCount = 0
    $lastDecisionFingerprint = ""
    $lastDecisionAt = [DateTime]::MinValue
    $lastEscalatedFingerprint = ""
    $lastEscalatedAt = [DateTime]::MinValue
    $lastWakeFingerprint = ""
    $lastWakeAt = [DateTime]::MinValue
    $lastCleanupAt = [DateTime]::MinValue
    while ($true) {
        # 周期性自动清理：pending 超时过期 + 已处理历史裁剪
        if (($RequestTtlSeconds -gt 0 -or $ResolvedRetentionHours -gt 0) -and (((Get-Date) - $lastCleanupAt).TotalSeconds -ge 30)) {
            $cleanup = Cleanup-ApprovalRequests
            if ($cleanup.changed) {
                Write-Output ("[APPROVAL-CLEANUP] expired=" + $cleanup.expired + " pruned=" + $cleanup.pruned)
            } elseif ($cleanup.stale_pending -gt 0) {
                Write-Output ("[APPROVAL-STALE-PENDING] count=" + $cleanup.stale_pending + " task=" + $TaskId + " worker=" + $WorkerName)
            }
            $lastCleanupAt = Get-Date
        }

        if ($Timeout -gt 0 -and $elapsed -ge $Timeout) {
            Write-Output ("[APPROVAL-TIMEOUT] No approval prompt after " + $Timeout + "s task=" + $TaskId)
            exit 1
        }

        $handledThisCycle = $false
        $currentPromptFingerprint = ""
        $paneText = wezterm cli get-text --pane-id $WorkerPaneId 2>$null
        if ($paneText) {
            $tailLines = @($paneText -split "`r?`n" | Where-Object { $_.Trim() -ne "" } | Select-Object -Last 80)
            $tail = $tailLines -join "`n"
            if (Is-ApprovalPrompt -tail $tail -policyPatterns $policy.approval_prompt_patterns) {
                $snippetLines = @(Extract-ApprovalSnippetLines -tailLines $tailLines -policyPatterns $policy.approval_prompt_patterns)
                $snippet = ($snippetLines -join " | ")
                if ($snippet.Length -gt 500) {
                    $snippet = $snippet.Substring(0, 500)
                }
                $normalizedSnippet = Normalize-ApprovalSnippet $snippet
                $fingerprint = Get-ShortHash($normalizedSnippet)
                $currentPromptFingerprint = $fingerprint

                if ($currentPromptFingerprint -eq $lastPromptFingerprint) {
                    $promptStableCount++
                } else {
                    $promptStableCount = 1
                }

                # 防抖：要求同一审批上下文连续出现，避免因界面刷新造成误判
                if ($promptStableCount -lt [Math]::Max(1, $PromptStableCycles)) {
                    $lastPromptFingerprint = $currentPromptFingerprint
                    Start-Sleep -Milliseconds 250
                    continue
                }

                $decisionNow = Get-Date
                if (
                    $DecisionCooldownSeconds -gt 0 -and
                    $fingerprint -eq $lastDecisionFingerprint -and
                    (($decisionNow - $lastDecisionAt).TotalSeconds -lt $DecisionCooldownSeconds)
                ) {
                    Write-Output ("[APPROVAL-DENOISE-SKIP] task=" + $TaskId + " worker=" + $WorkerName + " fp=" + $fingerprint + " reason=decision_cooldown")
                    $handledThisCycle = $true
                    $lastPromptFingerprint = $currentPromptFingerprint
                    Start-Sleep -Milliseconds 250
                    continue
                }

                # 风险判定仅使用审批片段本身，避免被聊天上下文中的无关关键词（如 curl）污染。
                $analysisText = ($snippetLines -join "`n")
                $promptType = Get-ApprovalPromptType -analysisText $analysisText
                $risk = "unknown"
                # 优先命中“允许的 MCP 工具”白名单（例如指定 Playwright/Vitest/route 工具）。
                if ($policy.allowed_mcp_patterns -and (Contains-Any -text $analysisText -patterns $policy.allowed_mcp_patterns)) {
                    $risk = "low"
                # route 回调是协作主链路，默认自动批准，避免 Team Lead 被无效审批打断。
                } elseif ($analysisText.IndexOf("report_route", [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    $risk = "low"
                } elseif (Contains-Any -text $analysisText -patterns $policy.high_risk_patterns) {
                    $risk = "high"
                } elseif (Contains-Any -text $analysisText -patterns $policy.low_risk_patterns) {
                    $risk = "low"
                }

                if ($risk -eq "low") {
                    Send-DecisionToWorker -decisionKey "y" -promptType $promptType
                    Write-Output ("[APPROVAL-AUTO] task=" + $TaskId + " worker=" + $WorkerName + " risk=low")
                    $lastDecisionFingerprint = $fingerprint
                    $lastDecisionAt = Get-Date
                    $handled++
                    $handledThisCycle = $true
                    if (-not $Continuous) {
                        exit 0
                    }
                    $lastPromptFingerprint = $currentPromptFingerprint
                    continue
                }

                $existingPending = Get-ExistingPendingRequest
                if ($existingPending) {
                    $createdUtc = ConvertTo-UtcDateSafe $existingPending.created_at
                    $ageSec = 0
                    if ($createdUtc) {
                        $ageSec = [int](([DateTime]::UtcNow - $createdUtc).TotalSeconds)
                    }
                    if ($RequestTtlSeconds -gt 0 -and $ageSec -ge $RequestTtlSeconds) {
                        $denySent = $false
                        try {
                            Send-DecisionToWorker -decisionKey "n" -promptType $promptType
                            $denySent = $true
                        } catch {}

                        $decision = if ($denySent) { "timeout_deny" } else { "timeout_offline" }
                        $note = if ($denySent) { "Auto denied due to TTL" } else { "Auto timeout while worker pane unavailable" }
                        $resolved = Resolve-ApprovalRequest -requestId ([string]$existingPending.id) -decision $decision -resolvedBy "approval-router/auto-timeout" -note $note
                        if ($resolved) {
                            $body = "[APPROVAL_TIMEOUT] request_id=$($existingPending.id) worker=$WorkerName pane=$WorkerPaneId decision=$decision"
                            $routeId = Append-RouteInbox -status "blocked" -body $body
                            Write-Output ("[APPROVAL-TIMEOUT] request_id=" + $existingPending.id + " route_id=" + $routeId + " decision=" + $decision)
                            $lastDecisionFingerprint = $fingerprint
                            $lastDecisionAt = Get-Date
                            $handled++
                            $handledThisCycle = $true
                            if (-not $Continuous) {
                                exit 0
                            }
                            $lastPromptFingerprint = $currentPromptFingerprint
                            continue
                        }
                    }
                    Write-Output ("[APPROVAL-PENDING] request_id=" + $existingPending.id + " task=" + $TaskId + " worker=" + $WorkerName + " pane=" + $WorkerPaneId)
                    $handledThisCycle = $true
                    if (-not $Continuous) {
                        exit 0
                    }
                    $lastPromptFingerprint = $currentPromptFingerprint
                    continue
                }

                # 若刚刚批准过同一指纹，判定为重放提示，自动再次批准，避免 Team Lead 连续确认
                if ($ReplayApproveWindowSeconds -gt 0) {
                    $recentApproved = Get-RecentResolvedApproval -fingerprint $fingerprint -withinSeconds $ReplayApproveWindowSeconds
                    if ($recentApproved) {
                        $recentPromptType = if ($recentApproved.prompt_type) { [string]$recentApproved.prompt_type } else { $promptType }
                        Send-DecisionToWorker -decisionKey "y" -promptType $recentPromptType
                        Write-Output ("[APPROVAL-REPLAY-AUTO] task=" + $TaskId + " worker=" + $WorkerName + " request_id=" + [string]$recentApproved.id)
                        $lastDecisionFingerprint = $fingerprint
                        $lastDecisionAt = Get-Date
                        $handled++
                        $handledThisCycle = $true
                        if (-not $Continuous) {
                            exit 0
                        }
                        $lastPromptFingerprint = $currentPromptFingerprint
                        continue
                    }
                }

                # 节流：同一指纹短时间内最多升级一次，避免 blocked 风暴
                $now = Get-Date
                if ($fingerprint -eq $lastEscalatedFingerprint -and ((($now) - $lastEscalatedAt).TotalSeconds -lt $EscalationCooldownSeconds)) {
                    Write-Output ("[APPROVAL-DENOISE-SKIP] task=" + $TaskId + " worker=" + $WorkerName + " fp=" + $fingerprint)
                    $handledThisCycle = $true
                    $lastPromptFingerprint = $currentPromptFingerprint
                    Start-Sleep -Milliseconds 250
                    continue
                }

                $requestId = "APR-" + (Get-Date -Format "yyyyMMddHHmmss") + "-" + (Get-Random -Minimum 1000 -Maximum 9999)
                $snippetPreview = To-AsciiPreview -text $snippet -maxLen 180
                $request = @{
                    id = $requestId
                    task = $TaskId
                    worker = $WorkerName
                    worker_pane_id = $WorkerPaneId
                    team_lead_pane_id = $TeamLeadPaneId
                    risk = if ($risk -eq "unknown") { "high" } else { $risk }
                    snippet_preview = $snippetPreview
                    snippet_fingerprint = $fingerprint
                    prompt_type = $promptType
                    status = "pending"
                    created_at = Get-Date -Format "o"
                    resolved_at = $null
                    decision = $null
                    resolved_by = $null
                }
                Save-ApprovalRequest -request $request

                # route body 只保留结构化字段，禁止拼接原始 snippet，避免中文/控制字符乱码
                $body = "[APPROVAL_REQUEST] request_id=$requestId worker=$WorkerName pane=$WorkerPaneId risk=$($request.risk) fp=$fingerprint"
                $routeId = Append-RouteInbox -status "blocked" -body $body

                $nowWake = Get-Date
                $shouldWake = $true
                if ($WakeCooldownSeconds -gt 0 -and $fingerprint -eq $lastWakeFingerprint -and ((($nowWake) - $lastWakeAt).TotalSeconds -lt $WakeCooldownSeconds)) {
                    $shouldWake = $false
                }
                if ($shouldWake) {
                    $wakeMessage = "[APR] id=$requestId task=$TaskId worker=$WorkerName risk=$($request.risk) action=approve-request"
                    $wakeSent = Notify-TeamLeadWake -message $wakeMessage
                    if ($wakeSent) {
                        $lastWakeFingerprint = $fingerprint
                        $lastWakeAt = $nowWake
                    }
                }

                $lastEscalatedFingerprint = $fingerprint
                $lastEscalatedAt = Get-Date
                $lastDecisionFingerprint = $fingerprint
                $lastDecisionAt = Get-Date

                Write-Output ("[APPROVAL-ESCALATED] request_id=" + $requestId + " route_id=" + $routeId + " task=" + $TaskId)
                $handled++
                $handledThisCycle = $true
                if (-not $Continuous) {
                    exit 0
                }
            }
        }

        $lastPromptFingerprint = $currentPromptFingerprint

        if ($Continuous -and $MaxHandled -gt 0 -and $handled -ge $MaxHandled) {
            Write-Output ("[APPROVAL-CONTINUOUS-STOP] handled=" + $handled + " task=" + $TaskId)
            exit 0
        }

        if ($handledThisCycle) {
            $elapsed = 0
            Start-Sleep -Milliseconds 250
            continue
        }

        Start-Sleep -Seconds $PollInterval
        $elapsed += $PollInterval
    }
} catch {
    Write-Output ("[APPROVAL-ERROR] " + $_.Exception.Message)
    exit 2
}
