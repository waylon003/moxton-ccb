# ADMIN-FE-008 Hotfix - Table Not Rendering

## Task: Debug and fix user management table not rendering
## Repo: E:\moxton-lotadmin

## Problem

User management page: API returns data successfully but the table shows nothing (blank).
The pagination parameter was already fixed (pageNum -> page), but the table still doesn't render.

## Root Cause Investigation

The most likely cause is a data mapping mismatch between:
- Backend API response format for `GET /auth/admin/users`
- Frontend table's expected data structure

## Investigation Steps

1. Check `src/views/user/index.vue` - find the function that calls the user list API
2. Check `src/service/api/user.ts` - find `fetchGetUsers` or similar function, check the return type
3. Check how the API response is transformed before being passed to the table:
   - What field does the table component expect? (e.g., `data`, `list`, `records`)
   - What field does the API response actually contain?
   - Is there a `transform` function in the table hook? Check if it correctly maps the response
4. Common issues to check:
   - Response wrapper: backend returns `{ code, data: { list, total } }` but frontend reads `data.records`
   - Or backend returns flat array but frontend expects `{ list, total }` object
   - Or the `useHookTable` / `useTable` hook has a transform that doesn't match
   - Check if `pageNum` is still referenced in the response transform (line ~104 area mentioned in QA)
5. Also check: does the table column `key` match the actual data field names?

## Fix

Once you identify the mismatch, fix the data mapping so the table renders correctly.

After fixing, run `pnpm typecheck` to verify no regressions.

## Report Format

```
[ROUTE]
from: admin-fe-dev
to: team-lead
type: handoff
task: ADMIN-FE-008-hotfix
body:
- Root cause identified
- Fix applied (which file, which line)
- pnpm typecheck result
[/ROUTE]
```
