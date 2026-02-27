# ADMIN-FE-008 Hotfix 2 - Revert to pageNum (Project Standard)

## Task: Fix user table to match project-wide pagination convention
## Repo: E:\moxton-lotadmin

## Root Cause

The project-wide pagination standard (used by products, orders, etc.) is:
- Query param: `pageNum` (NOT `page`)
- Response format: `{ data: { list: [...], total, pageNum, pageSize } }`

Example from products API: `GET /products?pageNum=1&pageSize=10`

The previous "fix" incorrectly changed `pageNum` to `page`, breaking the convention.

## Fix Required

1. In `src/views/user/index.vue`:
   - Revert `page` back to `pageNum` in `searchParams`, `getQueryParams`, and pagination callback
   - Make sure the API call sends `pageNum` (not `page`)
   - The table transform should read `data.list` and `data.total` from response (standard format)
   - Remove any multi-shape normalization hacks - just use the standard format like other pages

2. Check how other working admin pages (products, orders) handle their table transform:
   - Look at `src/views/product/index.vue` or `src/views/order/index.vue` for reference
   - Copy the same pattern for the user table

3. In `src/service/api/user.ts`:
   - Revert `UserListParams.page` back to `pageNum`
   - Make sure the API path and params match the standard

4. Run `pnpm typecheck` to verify

## Key Reference

Look at how the product list page works - it uses `pageNum` and the standard `data.list` response. The user page should work exactly the same way.

## Report Format

```
[ROUTE]
from: admin-fe-dev
to: team-lead
type: handoff
task: ADMIN-FE-008-hotfix2
body:
- Changes made
- Reference page used
- pnpm typecheck result
[/ROUTE]
```
