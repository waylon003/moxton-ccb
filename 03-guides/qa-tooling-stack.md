# QA Tooling Stack (Codex Team Lead)

This guide defines the default QA stack used by Codex role agents.

## Principles
- Use deterministic automation first.
- Keep `PASS/FAIL` tied to reproducible commands and evidence.
- Use exploratory browser agents as supplemental checks, not as final acceptance authority.
- In Codex sessions, run `codex mcp list` and prefer MCP tools when available.

## SHOP-FE (`E:\nuxt-moxton`)
- Primary:
  - `@playwright/test`
  - `microsoft/playwright-mcp` for browser control and evidence collection
- Baseline commands:
  - `pnpm type-check`
  - `pnpm build`
  - `pnpm exec playwright test <spec-or-grep>` (if tests exist)
- Fallback:
  - targeted manual regression with explicit reproduction steps and screenshots/logs

## ADMIN-FE (`E:\moxton-lotadmin`)
- Primary:
  - `@playwright/test`
  - `microsoft/playwright-mcp`
- Baseline commands:
  - `pnpm typecheck`
  - `pnpm lint`
  - `pnpm build:test` (or `pnpm build` when needed)
  - `pnpm exec playwright test <spec-or-grep>` (if tests exist)
- Fallback:
  - targeted manual regression with reproducible evidence

## BACKEND (`E:\moxton-lotapi`)
- Primary:
  - `Vitest + Supertest`
  - optional `djankies/vitest-mcp` as execution/diagnostic interface for agent workflows
- Baseline commands:
  - `npm run build`
  - `npm run test:api` (when configured)
- Transitional fallback:
  - run targeted legacy scripts in repo root, e.g. `node test-order-payment.js`
  - attach request/response evidence and risk notes

## Notes On `browser-use`
- `browser-use` is useful for exploratory or dynamic web scenarios.
- Do not use `browser-use` as the only acceptance signal for release.
- Final acceptance remains command-backed and reproducible.

## MCP Preflight
- Verify the session has:
  - `playwright` (`@playwright/mcp`)
  - `vitest` (`@djankies/vitest-mcp`)
- If MCP is unavailable, execute equivalent shell commands and include full output in QA evidence.
