# SHOP-FE-002/003 QA Fix - Type Check Regression + i18n

## Role: Shop Frontend Developer
## Task: SHOP-FE-002 & SHOP-FE-003 QA Fix
## Repo: E:\nuxt-moxton
## Tech Stack: Nuxt 3 + Vue 3 + TypeScript + Pinia + @nuxtjs/i18n

## Context

SHOP-FE-002 (Login/Register) and SHOP-FE-003 (Account Center) QA failed with:

### Issue 1: type-check regression (BLOCKING)
- `pnpm type-check` fails with multiple TS errors
- These are regression errors introduced by the new account center pages
- Fix ALL type errors to make `pnpm type-check` pass

### Issue 2: i18n hardcoded text in account center pages
- Account center pages have hardcoded Chinese text instead of using i18n
- Affected files:
  - `pages/account.vue`
  - `pages/account/profile.vue`
  - `pages/account/orders/index.vue`
  - `pages/account/orders/[id].vue`
  - `pages/account/password.vue`
  - `pages/account/addresses.vue`
  - `pages/account/consultations.vue`
- Also check: `pages/login.vue` and `pages/register.vue`

## i18n Rules (CRITICAL)

- All user-visible text MUST use i18n keys, NO hardcoded Chinese or English
- Translation files: `i18n/locales/en.ts` and `i18n/locales/zh.ts`
- Use `$t('key')` in templates or `const { t } = useI18n()` in script setup
- Key naming convention: use dot notation, e.g. `account.profile.title`, `account.orders.empty`
- Add keys to BOTH en.ts and zh.ts

## Fix Steps

1. Run `pnpm type-check` first to see all current errors
2. Fix ALL type errors one by one
3. Then go through each account center page and replace hardcoded text with i18n keys
4. Add all new i18n keys to `i18n/locales/en.ts` and `i18n/locales/zh.ts`
5. Also check login.vue and register.vue for hardcoded text
6. Run `pnpm type-check` again to verify clean

## Verification

```bash
pnpm type-check
```

Expected: type-check passes with exit code 0.

## Report Format

```
[ROUTE]
from: shop-fe-dev
to: team-lead
type: handoff
task: SHOP-FE-002-003-fix
body:
- Changed files with details
- i18n keys added (list)
- pnpm type-check result
- Any other issues found
[/ROUTE]
```
