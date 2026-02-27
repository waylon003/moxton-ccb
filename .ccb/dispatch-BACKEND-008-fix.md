# BACKEND-008 QA Fix - Cart.ts TS6133 Error

## Role: Backend Developer
## Task: BACKEND-008 QA Fix
## Repo: E:\moxton-lotapi

## Context

BACKEND-008 (Admin User Management API) QA failed due to a regression error:
- `npm run build` fails with: `src/controllers/Cart.ts(3,1): error TS6133: 'CartModel' is declared but its value is never read`

The actual BACKEND-008 implementation (user management API) is correct and verified. This is a pre-existing TS error in Cart.ts that blocks build.

## Fix Required

1. Open `src/controllers/Cart.ts`
2. Find the unused `CartModel` import on line 3
3. Remove the unused import (or prefix with `_` if needed elsewhere)
4. Run `npm run build` to verify the fix resolves the error

## Verification

```bash
npm run build
```

Expected: Build succeeds with no TS6133 error for Cart.ts.

## Report Format

After fixing, report:
```
[ROUTE]
from: backend-dev
to: team-lead
type: handoff
task: BACKEND-008-fix
body:
- Changed files
- npm run build result
- Any other errors found
[/ROUTE]
```
