# BACKEND-008 Hotfix - Use pageNum (Project Standard)

## Task: Fix user list API to use pageNum instead of page
## Repo: E:\moxton-lotapi

## Root Cause

The project-wide pagination standard is `pageNum` (not `page`).
All other list endpoints use `pageNum`:
- `GET /products?pageNum=1&pageSize=10`
- `GET /orders/admin?pageNum=1&pageSize=10`

But `GET /auth/admin/users` was implemented with `page` parameter, breaking the convention.

## Fix Required

1. In the user list controller (`src/controllers/User.ts` or wherever `getUsers` is):
   - Change the query parameter from `page` to `pageNum`
   - Response should include `pageNum` (not `page`) in the pagination metadata
   - Response format must be: `{ code, data: { list: [...], total, pageNum, pageSize }, success }`

2. Verify by checking how `getProducts` or `getOrders` handles pagination - copy the same pattern.

3. Run `npm run build` to verify (ignore pre-existing errors, just confirm no new ones)

## Report Format

```
[ROUTE]
from: backend-dev
to: team-lead
type: handoff
task: BACKEND-008-hotfix
body:
- Changes made
- Response format confirmed
- Build result
[/ROUTE]
```
