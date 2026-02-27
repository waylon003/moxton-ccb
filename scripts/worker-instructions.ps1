# Worker Instructions Generator
# 生成 Codex/Gemini 启动时的强制指令

param(
    [Parameter(Mandatory=$true)]
    [string]$WorkerName,

    [Parameter(Mandatory=$true)]
    [string]$WorkDir,

    [Parameter(Mandatory=$true)]
    [string]$TeamLeadPaneId,

    [Parameter(Mandatory=$false)]
    [ValidateSet("codex", "gemini")]
    [string]$Engine = "codex"
)

$instructions = @"
╔══════════════════════════════════════════════════════════════════╗
║                    ⚠️ 强制通信协议 ⚠️                              ║
╠══════════════════════════════════════════════════════════════════╣
║ 你是: $WorkerName                                                  ║
║ 工作目录: $WorkDir                                                ║
║ Team Lead Pane ID: $TeamLeadPaneId                                 ║
╠══════════════════════════════════════════════════════════════════╣
║                                                                  ║
║  【铁律】完成任务后必须通知 Team Lead，否则视为任务未完成！          ║
║                                                                  ║
║  通知格式（严格遵循）：                                             ║
║  ```                                                             ║
║  [ROUTE]                                                         ║
║  from: $WorkerName                                                 ║
║  to: team-lead                                                   ║
║  type: status                                                    ║
║  task: <TASK-ID>                                                 ║
║  status: <success|fail|blocked>                                  ║
║  body: |                                                         ║
║    <详细结果摘要，包含：                                            ║
║    - 修改的文件                                                    ║
║    - 执行的命令及结果                                              ║
║    - 遇到的问题或阻塞项>                                           ║
║  [/ROUTE]                                                        ║
║  ```                                                             ║
║                                                                  ║
║  发送命令：                                                        ║
║  ```powershell                                                   ║
"@

if ($Engine -eq "codex") {
    $instructions += @"
║  wezterm cli send-text --pane-id `$env:TEAM_LEAD_PANE_ID `             ║
║    --no-paste "[ROUTE]...[/ROUTE]"                               ║
║  wezterm cli send-text --pane-id `$env:TEAM_LEAD_PANE_ID `             ║
║    --no-paste `"``r`"                                              ║
"@
} else {
    $instructions += @"
║  wezterm cli send-text --pane-id $TeamLeadPaneId `               ║
║    --no-paste "[ROUTE]...[/ROUTE]"                               ║
║  wezterm cli send-text --pane-id $TeamLeadPaneId `               ║
║    --no-paste "`r"                                               ║
"@
}

$instructions += @"
║  ```                                                             ║
║                                                                  ║
║  ⚠️ 禁止行为：                                                     ║
║  - 未发送 [ROUTE] 通知就声明任务完成                                ║
║  - 省略 status 或 body 字段                                        ║
║  - 使用非标准的通知格式                                             ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝

"

return $instructions
