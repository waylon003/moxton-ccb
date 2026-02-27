# QA Identity Pool

- Snapshot date: 2026-02-25
- Source DB: `moxton-lotapi-defult`
- Note: this file lists identity candidates for QA routing only. It does not store passwords.

## Admin Candidate

- username: `admin`
- email: `admin@moxton.com`
- role: `admin`
- status: `1` (active)

## Non-admin User Candidates

- `testadmin` / `testadmin@moxton.com` / role=`user` / status=`1`
- `newadmin` / `newadmin@moxton.com` / role=`user` / status=`1`
- `testuser4` / `test4@moxton.com` / role=`user` / status=`1`
- `testuser3` / `test3@moxton.com` / role=`user` / status=`1`
- `testuser2` / `test2@moxton.com` / role=`user` / status=`1`
- `demouser` / `demo@moxton.com` / role=`user` / status=`1`
- `testuser` / `test@example.com` / role=`user` / status=`1`

## Guest Data Candidates

- Guest online orders: 13 records (`DELIVERED=5`, `CANCELLED=8`)
- Example guest order ids:
  - `cmlf1637x0000vflcsapxdjnh`
  - `cmlezsoxt0000vfkko1h3sqxh`
  - `cmlewtwux0000vfl0ljf2bj8h`
- Example guest session ids:
  - `qa-test-guest-1770614386`
  - `test-verify-order-123`
  - `mizvc9cv_gr4srg4b4w_AABJRU5E`

## QA Usage Rules

1. For admin permission checks, use at least one admin and one non-admin identity.
2. If login fails for one account, try another same-role candidate before marking FAIL.
3. If all same-role candidates fail login, mark as `data/env blocker` (not immediate feature regression).
4. Record the exact identity used in QA report evidence.
