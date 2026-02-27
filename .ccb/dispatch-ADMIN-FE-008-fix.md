# ADMIN-FE-008 QA Fix - Pagination Param + Order Count

## Role: Admin Frontend Developer
## Task: ADMIN-FE-008 QA Fix
## Repo: E:\moxton-lotadmin
## Tech Stack: Vue 3 + TypeScript + SoybeanAdmin + Naive UI

## Context

ADMIN-FE-008 (User Management Page) QA failed with 2 issues:

### Issue 1: Pagination parameter mismatch
- Location: `src/views/user/index.vue` lines 86-91, 344-346
- Problem: Frontend uses `pageNum` but backend spec uses `page`
- Backend spec (BACKEND-008): `GET /auth/admin/users?page=1&pageSize=20`
- Fix: Change all `pageNum` references to `page` in the user list page

### Issue 2: Missing related order count in detail drawer
- Location: `src/views/user/modules/user-detail-drawer.vue` lines 78-97
- Problem: Detail drawer only shows basic user info, missing related order count
- Requirement: Show the number of orders associated with the user
- The backend `GET /auth/admin/users/:id` response includes user details. You need to also call `GET /orders/admin?keyword=<userId>` or similar to get order count, OR display an orderCount field if the backend already returns it in user detail.
- If backend does not return orderCount, add a static placeholder field "Related Orders: --" with a TODO comment.

## Fix Steps

1. In `src/views/user/index.vue`:
   - Find all occurrences of `pageNum` and replace with `page`
   - Ensure the API call sends `page` instead of `pageNum`
   - Verify pagination still works correctly

2. In `src/views/user/modules/user-detail-drawer.vue`:
   - Add a "Related Orders" (关联订单数) field to the NDescriptions component
   - If user detail API returns orderCount, display it
   - If not available, add placeholder with TODO

3. Run `pnpm typecheck` to verify no regressions

## Verification

```bash
pnpm typecheck
```

Expected: typecheck passes (exit code 0).

## Report Format

```
[ROUTE]
from: admin-fe-dev
to: team-lead
type: handoff
task: ADMIN-FE-008-fix
body:
- Changed files with details
- pnpm typecheck result
- Any other issues found
[/ROUTE]
```
