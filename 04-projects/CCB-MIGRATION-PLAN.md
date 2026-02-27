# CCB Migration Plan (Claude Team Lead + Codex Workers)

## Target Architecture
- Team Lead: Claude Code in `E:\moxton-ccb` (model: qwen3-max)
- Worker execution: Codex sessions (SHOP-FE / ADMIN-FE / BACKEND / QA)
- Message bridge: CCB (`ask` / `pend` / `ping`)
- Single source of truth: `01-tasks/*` + `01-tasks/TASK-LOCKS.json`

## What Was Migrated
- Copied: `01-tasks`, `02-api`, `03-guides`, `04-projects`, `05-verification`, `scripts`, `.claude`, `CLAUDE.md`
- Removed codex-teamlead artifacts in this workspace:
  - `CODEX.md`
  - `teamlead.cmd`
  - `scripts/team_lead_start.ps1`
  - `04-projects/CODEX-AGENT-TEAMS.md`
  - `04-projects/CODEX-TEAM-BRIEF.md`
  - `.claude/hooks/agent-teams-runner.js`

## Hook Policy
- Agent Teams auto-hook is disabled for this workspace.
- CCB is the only orchestration trigger.

## New Files
- `config/ccb-routing.json`
- `scripts/ccb_start.ps1`
- `05-verification/ccb-runs/`

## Startup Flow
1. Open Claude Code at `E:\moxton-ccb` as Team Lead.
2. Start workers:
   - `powershell -ExecutionPolicy Bypass -File scripts/ccb_start.ps1 -Terminal wt`
3. Team Lead dispatches tasks via CCB (`ask`) and polls results (`pend`).
4. Persist execution evidence to `05-verification/ccb-runs/`.
