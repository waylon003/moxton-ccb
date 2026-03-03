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

## 固定测试凭据（优先使用）

为避免 QA 在运行期反复走 register/login 试探，后端与前端 QA 优先使用以下固定账号：

- 管理员：`admin` / `admin123`
- 普通用户：`waylon` / `qwe123456`

使用规则：

1. 先尝试固定账号登录获取 token，再执行接口验证。
2. 固定账号登录失败时，再回退到候选账号池轮询（同角色至少再试 1 个）。
3. 仅当“固定账号 + 候选账号”均失败时，回传 `blocked`（`blocker_type=env|data`），不要无限重试。
