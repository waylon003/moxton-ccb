#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Task assignment and team-brief helper for moxton-docs.

Examples:
  python scripts/assign_task.py --standard-entry
  python scripts/assign_task.py --list
  python scripts/assign_task.py --scan
  python scripts/assign_task.py --show-lock
  python scripts/assign_task.py --lock codex
  python scripts/assign_task.py --show-task-locks
  python scripts/assign_task.py --lock-task SHOP-FE-001 --task-owner team-lead
  python scripts/assign_task.py --intake "请编写订单支付状态查询接口"
  python scripts/assign_task.py --split-request "Implement Stripe webhook + admin status UI + storefront payment status"
  python scripts/assign_task.py SHOP-FE-001 --provider codex
  python scripts/assign_task.py --team-prompt
  python scripts/assign_task.py --write-brief
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from datetime import datetime, timedelta
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Dict, List, Tuple


# Keep Python's default stdout encoding on Windows.
# Forcing UTF-8 here can produce mojibake when the host console runs in cp936/gbk.


@dataclass(frozen=True)
class RoleConfig:
    code: str
    name: str
    task_dir: str
    template_file: str
    project_status_doc: str
    extra_context_files: Tuple[str, ...]
    project: str
    workdir: str
    codex_dev_prompt: str
    codex_qa_prompt: str
    qa_tooling: str
    qa_primary_commands: Tuple[str, ...]
    qa_fallback_commands: Tuple[str, ...] = ()
    claude_agent: str = "oh-my-claudecode:executor"


@dataclass(frozen=True)
class TaskInfo:
    task_id: str
    title: str
    file_name: str
    task_path: str
    role_code: str
    role_name: str
    project: str
    workdir: str
    codex_dev_prompt: str
    codex_qa_prompt: str
    claude_agent: str


ROLE_CONFIGS: Dict[str, RoleConfig] = {
    "SHOP-FE": RoleConfig(
        code="SHOP-FE",
        name="Shop Frontend",
        task_dir="shop-frontend",
        template_file="tech-spec-shop-frontend.md",
        project_status_doc="04-projects/nuxt-moxton.md",
        extra_context_files=("03-guides/README.md", "03-guides/stripe-elements.md", "03-guides/qa-tooling-stack.md", "02-api/payments.md"),
        project="nuxt-moxton",
        workdir=r"E:\nuxt-moxton",
        codex_dev_prompt=".claude/agents/shop-frontend.md",
        codex_qa_prompt=".claude/agents/shop-fe-qa.md",
        qa_tooling="Primary: @playwright/test + microsoft/playwright-mcp. Fallback: repo smoke checks + targeted manual regression.",
        qa_primary_commands=(
            "pnpm type-check",
            "pnpm build",
            "pnpm exec playwright test <spec-or-grep>  # if playwright tests exist",
        ),
        qa_fallback_commands=(
            "Execute task-focused manual browser regression and capture reproducible steps.",
        ),
    ),
    "ADMIN-FE": RoleConfig(
        code="ADMIN-FE",
        name="Admin Frontend",
        task_dir="admin-frontend",
        template_file="tech-spec-admin-frontend.md",
        project_status_doc="04-projects/moxton-lotadmin.md",
        extra_context_files=("03-guides/qa-tooling-stack.md", "02-api/orders.md", "02-api/offline-orders.md"),
        project="moxton-lotadmin",
        workdir=r"E:\moxton-lotadmin",
        codex_dev_prompt=".claude/agents/admin-frontend.md",
        codex_qa_prompt=".claude/agents/admin-fe-qa.md",
        qa_tooling="Primary: @playwright/test + microsoft/playwright-mcp. Fallback: repo smoke checks + targeted manual regression.",
        qa_primary_commands=(
            "pnpm typecheck",
            "pnpm lint",
            "pnpm build:test",
            "pnpm exec playwright test <spec-or-grep>  # if playwright tests exist",
        ),
        qa_fallback_commands=(
            "Execute task-focused manual browser regression and capture reproducible steps.",
        ),
    ),
    "BACKEND": RoleConfig(
        code="BACKEND",
        name="Backend",
        task_dir="backend",
        template_file="tech-spec-backend.md",
        project_status_doc="04-projects/moxton-lotapi.md",
        extra_context_files=("03-guides/qa-tooling-stack.md", "02-api/README.md", "02-api/CHANGELOG.md"),
        project="moxton-lotapi",
        workdir=r"E:\moxton-lotapi",
        codex_dev_prompt=".claude/agents/backend.md",
        codex_qa_prompt=".claude/agents/backend-qa.md",
        qa_tooling="Primary: Vitest + Supertest (optionally via djankies/vitest-mcp). Fallback: existing node test-*.js scripts.",
        qa_primary_commands=(
            "npm run build",
            "npm run test:api  # Vitest + Supertest entrypoint when configured",
        ),
        qa_fallback_commands=(
            "Run targeted legacy scripts: node test-*.js",
            "Capture request/response evidence for PASS/FAIL.",
        ),
    ),
}

TASK_NAME_RE = re.compile(r"^([A-Z]+(?:-[A-Z]+)?-\d+)-(.+)\.md$")
RUNNER_LOCK_REL = Path("01-tasks") / "ACTIVE-RUNNER.md"
TASK_LOCKS_REL = Path("01-tasks") / "TASK-LOCKS.json"
CCB_RUNS_REL = Path("05-verification") / "ccb-runs"
VALID_RUNNERS = {"codex", "claude", "none"}
VALID_TASK_STATES = {"assigned", "in_progress", "qa", "blocked", "completed"}
VALID_PRIORITIES = {"P0", "P1", "P2", "P3"}
DEFAULT_TASK_LOCK_TTL_HOURS = 24.0

# Phrase-first mapping for Chinese requirement titles -> readable English slugs.
# Longer phrases should come first to avoid partial replacements.
CN_SLUG_PHRASES: Tuple[Tuple[str, str], ...] = (
    ("帮我", ""),
    ("请", ""),
    ("一下", ""),
    ("订单支付状态查询接口", "order-payment-status-query-api"),
    ("支付状态", "payment-status"),
    ("订单状态", "order-status"),
    ("查询接口", "query-api"),
    ("管理后台", "admin"),
    ("独立站", "shop"),
    ("支付回调", "payment-webhook"),
    ("订单历史", "order-history"),
    ("关键字搜索", "keyword-search"),
    ("发货信息", "shipping-info"),
    ("支付意图", "payment-intent"),
    ("订单管理", "order-management"),
    ("购物车", "cart"),
    ("结账", "checkout"),
    ("后端", "backend"),
    ("前端", "frontend"),
    ("接口", "api"),
    ("支付", "payment"),
    ("状态", "status"),
    ("查询", "query"),
    ("修复", "fix"),
    ("新增", "add"),
    ("更新", "update"),
    ("删除", "remove"),
    ("创建", "create"),
    ("编写", "implement"),
    ("订单", "order"),
    ("用户", "user"),
    ("权限", "permission"),
    ("鉴权", "auth"),
    ("商品", "product"),
    ("库存", "inventory"),
    ("价格", "price"),
    ("地址", "address"),
    ("日志", "log"),
)

# Fallback per-character transliteration for common task wording.
CN_CHAR_PINYIN: Dict[str, str] = {
    "请": "qing",
    "编": "bian",
    "写": "xie",
    "订": "ding",
    "单": "dan",
    "支": "zhi",
    "付": "fu",
    "状": "zhuang",
    "态": "tai",
    "查": "cha",
    "询": "xun",
    "接": "jie",
    "口": "kou",
    "创": "chuang",
    "建": "jian",
    "更": "geng",
    "新": "xin",
    "删": "shan",
    "除": "chu",
    "修": "xiu",
    "复": "fu",
    "管": "guan",
    "理": "li",
    "前": "qian",
    "后": "hou",
    "端": "duan",
    "商": "shang",
    "城": "cheng",
    "台": "tai",
    "数": "shu",
    "据": "ju",
    "库": "ku",
    "回": "hui",
    "调": "diao",
}

ROLE_KEYWORDS: Dict[str, List[str]] = {
    "SHOP-FE": [
        "shop", "storefront", "nuxt", "checkout", "cart", "customer", "product page",
        "独立站", "商城前台", "前台", "购物车", "结账", "下单", "支付页", "用户端",
    ],
    "ADMIN-FE": [
        "admin", "dashboard", "backoffice", "console", "table", "list page",
        "管理后台", "后台", "管理员", "运营", "审核", "数据看板", "列表页",
    ],
    "BACKEND": [
        "backend", "api", "koa", "service", "prisma", "mysql", "database", "webhook",
        "后端", "接口", "服务", "数据库", "鉴权", "订单服务", "支付回调", "schema",
    ],
}

INTENT_KEYWORDS: Dict[str, List[str]] = {
    "planning": [
        "需求", "方案", "计划", "开发计划", "拆分", "讨论", "评审",
        "requirement", "plan", "design", "split", "proposal",
    ],
    "create_team": [
        "开始创建团队", "创建团队", "开始开发", "执行开发", "并行开发",
        "start team", "create team", "start development", "execute",
    ],
}


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def lock_file_path(root: Path) -> Path:
    return root / RUNNER_LOCK_REL


def task_locks_file_path(root: Path) -> Path:
    return root / TASK_LOCKS_REL


def normalize_task_id(value: str) -> str:
    return value.strip().upper()


def _transliterate_cn_for_slug(text: str) -> str:
    normalized = text.strip()
    for cn, en in CN_SLUG_PHRASES:
        normalized = normalized.replace(cn, f" {en} ")

    tokens: List[str] = []
    for chunk in re.split(r"[^0-9A-Za-z\u4e00-\u9fff]+", normalized):
        if not chunk:
            continue
        if re.fullmatch(r"[0-9A-Za-z]+", chunk):
            tokens.append(chunk.lower())
            continue

        pinyin_parts: List[str] = []
        for ch in chunk:
            if ch in CN_CHAR_PINYIN:
                pinyin_parts.append(CN_CHAR_PINYIN[ch])
            elif re.fullmatch(r"[0-9A-Za-z]", ch):
                pinyin_parts.append(ch.lower())
            # Unknown CJK chars are skipped intentionally to avoid unreadable slugs.
        if pinyin_parts:
            tokens.append("-".join(pinyin_parts))

    merged = "-".join(tokens)
    merged = re.sub(r"-{2,}", "-", merged).strip("-")
    return merged


def slugify(value: str) -> str:
    slug = _transliterate_cn_for_slug(value)
    if not slug:
        slug = re.sub(r"[^a-zA-Z0-9]+", "-", value.strip().lower())
    slug = re.sub(r"-{2,}", "-", slug).strip("-")
    return slug or "task"


def summarize_request_text(text: str, limit: int = 180) -> str:
    compact = re.sub(r"\s+", " ", text).strip()
    if len(compact) <= limit:
        return compact
    return compact[: limit - 3].rstrip() + "..."


def parse_role_list(value: str) -> List[str]:
    roles = []
    for raw in value.split(","):
        role = normalize_task_id(raw)
        if role in ROLE_CONFIGS:
            roles.append(role)
    # dedupe and keep order
    unique: List[str] = []
    for role in roles:
        if role not in unique:
            unique.append(role)
    return unique


def detect_roles_from_request(text: str) -> tuple[List[str], Dict[str, int]]:
    lowered = text.lower()
    score_map: Dict[str, int] = {code: 0 for code in ROLE_CONFIGS.keys()}

    for role_code, words in ROLE_KEYWORDS.items():
        for word in words:
            if word.lower() in lowered:
                score_map[role_code] += 1

    explicit_hits: List[str] = []
    for role_code, cfg in ROLE_CONFIGS.items():
        if role_code.lower() in lowered or cfg.project.lower() in lowered or cfg.task_dir.lower() in lowered:
            explicit_hits.append(role_code)

    if explicit_hits:
        return explicit_hits, score_map

    selected = [role for role, score in score_map.items() if score > 0]
    return selected, score_map


def detect_intent(text: str) -> str:
    lowered = text.lower()
    best_intent = ""
    best_score = 0
    for intent, words in INTENT_KEYWORDS.items():
        score = 0
        for word in words:
            if word.lower() in lowered:
                score += 1
        if score > best_score:
            best_score = score
            best_intent = intent
    return best_intent if best_score > 0 else "unknown"


def active_role_dir(root: Path, role: RoleConfig) -> Path:
    return root / "01-tasks" / "active" / role.task_dir


def template_file_path(root: Path, role: RoleConfig) -> Path:
    return root / "01-tasks" / "templates" / role.template_file


def next_task_number(root: Path, role: RoleConfig) -> int:
    role_dir = active_role_dir(root, role)
    if not role_dir.exists():
        return 1

    pattern = re.compile(rf"^{re.escape(role.code)}-(\d+)-", re.IGNORECASE)
    max_num = 0
    for file_path in role_dir.glob("*.md"):
        match = pattern.match(file_path.name)
        if not match:
            continue
        try:
            number = int(match.group(1))
        except ValueError:
            continue
        if number > max_num:
            max_num = number
    return max_num + 1


def render_task_from_template(
    template_text: str,
    task_title: str,
    date_str: str,
    priority: str,
    request_text: str,
    role: RoleConfig,
    parent_ref: str,
) -> str:
    rendered = template_text
    rendered = re.sub(r"(?m)^#\s*Tech-Spec:\s*\[.*\]\s*$", f"# Tech-Spec: {task_title}", rendered)
    rendered = rendered.replace("YYYY-MM-DD", date_str)
    rendered = rendered.replace("[P0|P1|P2|P3]", priority)

    # Keep output consistent even if template placeholders are not fully replaced.
    context_block = (
        "\n\n---\n\n"
        "## Team Lead Split Context\n\n"
        f"- Parent Request: {parent_ref}\n"
        f"- Role: {role.code} ({role.name})\n"
        f"- Project: {role.project}\n"
        f"- Request Summary: {summarize_request_text(request_text, 320)}\n"
        "- Split Policy: auto-generated from role template by scripts/assign_task.py\n"
    )
    if "## Team Lead Split Context" not in rendered:
        rendered += context_block
    return rendered.rstrip() + "\n"

def read_task_locks(root: Path) -> Dict[str, Any]:
    path = task_locks_file_path(root)
    if not path.exists():
        return {"version": "1.0", "updated_at": "", "locks": {}, "path": str(path)}

    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {"version": "1.0", "updated_at": "", "locks": {}, "path": str(path)}

    locks = raw.get("locks", {})
    if not isinstance(locks, dict):
        locks = {}

    normalized: Dict[str, Dict[str, str]] = {}
    for task_id, entry in locks.items():
        if not isinstance(entry, dict):
            continue
        normalized[normalize_task_id(str(task_id))] = {
            "runner": str(entry.get("runner", "")).lower(),
            "owner": str(entry.get("owner", "")),
            "state": str(entry.get("state", "assigned")).lower(),
            "updated_at": str(entry.get("updated_at", "")),
            "updated_by": str(entry.get("updated_by", "")),
            "note": str(entry.get("note", "")),
        }

    return {
        "version": "1.0",
        "updated_at": str(raw.get("updated_at", "")),
        "locks": normalized,
        "path": str(path),
    }


def parse_iso_datetime(value: str) -> datetime | None:
    text = (value or "").strip()
    if not text:
        return None
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        dt = datetime.fromisoformat(text)
    except Exception:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=datetime.now().astimezone().tzinfo)
    return dt


def task_lock_age_hours(lock: Dict[str, str]) -> float | None:
    updated_at = parse_iso_datetime(lock.get("updated_at", ""))
    if not updated_at:
        return None
    delta = datetime.now().astimezone() - updated_at
    return max(0.0, delta.total_seconds() / 3600.0)


def is_task_lock_stale(lock: Dict[str, str], ttl_hours: float) -> bool:
    age = task_lock_age_hours(lock)
    if age is None:
        return False
    return age > max(ttl_hours, 0.1)


def stale_task_ids(data: Dict[str, Any], ttl_hours: float) -> List[str]:
    locks: Dict[str, Dict[str, str]] = data.get("locks", {})
    result: List[str] = []
    for task_id, lock in locks.items():
        if is_task_lock_stale(lock, ttl_hours):
            result.append(task_id)
    return sorted(result)


def write_task_locks(root: Path, data: Dict[str, Any]) -> Path:
    path = task_locks_file_path(root)
    payload = {
        "version": "1.0",
        "updated_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "locks": data.get("locks", {}),
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return path


def print_task_locks(data: Dict[str, Any], active_tasks: List[TaskInfo], ttl_hours: float) -> None:
    locks: Dict[str, Dict[str, str]] = data.get("locks", {})
    path = data.get("path", "")
    print("[TASK-LOCKS] task-level locks")
    print(f"  file: {path}")
    if not locks:
        print("  (no locked tasks)")
        return

    active_ids = {t.task_id for t in active_tasks}
    for task_id in sorted(locks.keys()):
        lock = locks[task_id]
        activity_marker = "active-task" if task_id in active_ids else "orphan-task"
        ttl_marker = "expired-lock" if is_task_lock_stale(lock, ttl_hours) else "fresh-lock"
        age_hours = task_lock_age_hours(lock)
        age_text = f"{age_hours:.1f}h" if age_hours is not None else "unknown"
        print(
            f"  - {task_id} [{activity_marker}|{ttl_marker}] "
            f"runner={lock.get('runner','-')} owner={lock.get('owner','-')} "
            f"state={lock.get('state','-')} age={age_text} updated_at={lock.get('updated_at','-')}"
        )


def upsert_task_lock(
    root: Path,
    task_id: str,
    runner: str,
    owner: str,
    state: str,
    note: str,
    by: str = "scripts/assign_task.py",
) -> Path:
    runner = runner.lower()
    state = state.lower()
    if runner not in {"codex", "claude"}:
        raise ValueError("runner must be codex or claude")
    if state not in VALID_TASK_STATES:
        raise ValueError(f"invalid task state: {state}")

    data = read_task_locks(root)
    locks: Dict[str, Dict[str, str]] = data["locks"]
    task_id = normalize_task_id(task_id)
    locks[task_id] = {
        "runner": runner,
        "owner": owner.strip() or "team-lead",
        "state": state,
        "updated_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "updated_by": by,
        "note": note.strip(),
    }
    return write_task_locks(root, data)


def delete_task_lock(root: Path, task_id: str) -> tuple[Path, bool]:
    data = read_task_locks(root)
    locks: Dict[str, Dict[str, str]] = data["locks"]
    task_id = normalize_task_id(task_id)
    existed = task_id in locks
    if existed:
        del locks[task_id]
    path = write_task_locks(root, data)
    return path, existed


def get_task_lock(data: Dict[str, Any], task_id: str) -> Dict[str, str] | None:
    locks: Dict[str, Dict[str, str]] = data.get("locks", {})
    return locks.get(normalize_task_id(task_id))


def ccb_runs_dir(root: Path) -> Path:
    return root / CCB_RUNS_REL


def ensure_ccb_runs_dir(root: Path) -> Path:
    path = ccb_runs_dir(root)
    path.mkdir(parents=True, exist_ok=True)
    return path


def reap_stale_task_locks(root: Path, ttl_hours: float) -> tuple[Path, List[str]]:
    data = read_task_locks(root)
    locks: Dict[str, Dict[str, str]] = data.get("locks", {})
    removed: List[str] = []
    for task_id in sorted(list(locks.keys())):
        lock = locks.get(task_id, {})
        if is_task_lock_stale(lock, ttl_hours):
            removed.append(task_id)
            del locks[task_id]
    path = write_task_locks(root, data)
    return path, removed


def read_runner_lock(root: Path) -> Dict[str, str]:
    path = lock_file_path(root)
    if not path.exists():
        return {"runner": "none", "updated_at": "", "updated_by": "", "note": "", "path": str(path)}

    try:
        text = path.read_text(encoding="utf-8")
    except Exception:
        return {"runner": "none", "updated_at": "", "updated_by": "", "note": "", "path": str(path)}

    def _field(name: str) -> str:
        match = re.search(rf"(?im)^\s*{re.escape(name)}\s*:\s*(.+?)\s*$", text)
        return (match.group(1).strip() if match else "")

    runner = _field("runner").lower()
    if runner not in VALID_RUNNERS:
        runner = "none"

    return {
        "runner": runner,
        "updated_at": _field("updated_at"),
        "updated_by": _field("updated_by"),
        "note": _field("note"),
        "path": str(path),
    }


def write_runner_lock(root: Path, runner: str, note: str) -> Path:
    runner = runner.lower()
    if runner not in VALID_RUNNERS:
        raise ValueError(f"invalid runner: {runner}")

    path = lock_file_path(root)
    timestamp = datetime.now().astimezone().isoformat(timespec="seconds")
    content = (
        "# Active Runner Lock\n\n"
        "Use this lock to avoid dual-trigger between Codex and Claude workflows.\n\n"
        f"runner: {runner}\n"
        f"updated_at: {timestamp}\n"
        "updated_by: scripts/assign_task.py\n"
        f"note: {note.strip() or 'manual update'}\n"
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    return path


def print_runner_lock(lock: Dict[str, str]) -> None:
    print("[LOCK] Active runner lock")
    print(f"  runner: {lock['runner']}")
    print(f"  updated_at: {lock['updated_at'] or '-'}")
    print(f"  updated_by: {lock['updated_by'] or '-'}")
    print(f"  note: {lock['note'] or '-'}")
    print(f"  file: {lock['path']}")


def read_package_scripts(repo_path: Path) -> Dict[str, str]:
    pkg_path = repo_path / "package.json"
    if not pkg_path.exists():
        return {}
    try:
        payload = json.loads(pkg_path.read_text(encoding="utf-8"))
    except Exception:
        return {}
    scripts = payload.get("scripts", {})
    return scripts if isinstance(scripts, dict) else {}


def run_doctor(
    root: Path,
    tasks: List[TaskInfo],
    runner_lock: Dict[str, str],
    task_locks: Dict[str, Any],
    ttl_hours: float,
) -> int:
    warnings = 0
    failures = 0

    def ok(msg: str) -> None:
        print(f"[OK] {msg}")

    def warn(msg: str) -> None:
        nonlocal warnings
        warnings += 1
        print(f"[WARN] {msg}")

    def fail(msg: str) -> None:
        nonlocal failures
        failures += 1
        print(f"[FAIL] {msg}")

    print("[DOCTOR] Team Lead preflight")
    print(f"  root: {root}")
    print(f"  task-lock ttl: {ttl_hours:.1f}h")

    if runner_lock.get("runner") in VALID_RUNNERS:
        ok(f"runner lock readable ({runner_lock.get('runner')})")
    else:
        fail("runner lock invalid or unreadable")
    if runner_lock.get("runner") == "none":
        warn("runner lock is 'none'; set with --lock claude (CCB) or --lock codex before execution")

    stale_ids = stale_task_ids(task_locks, ttl_hours)
    if stale_ids:
        warn(f"stale task locks detected: {', '.join(stale_ids)} (use --reap-stale-locks)")
    else:
        ok("no stale task locks")

    locked_ids = set(task_locks.get("locks", {}).keys())
    unlocked_active = [t.task_id for t in tasks if t.task_id not in locked_ids]
    if unlocked_active:
        warn(f"active tasks without lock: {', '.join(unlocked_active)}")
    else:
        ok("all active tasks are task-locked")

    required_docs = [
        root / "01-tasks" / "STATUS.md",
        root / "04-projects" / "COORDINATION.md",
        root / "04-projects" / "DEPENDENCIES.md",
        root / ".claude" / "agents" / "team-lead.md",
        root / ".claude" / "agents" / "protocol.md",
        root / ".claude" / "agents" / "doc-updater.md",
    ]
    for doc in required_docs:
        if doc.exists():
            ok(f"exists: {doc}")
        else:
            fail(f"missing required file: {doc}")

    for role in ROLE_CONFIGS.values():
        template = template_file_path(root, role)
        if template.exists():
            ok(f"{role.code} template ready ({template})")
        else:
            fail(f"{role.code} template missing ({template})")

        project_status = root / role.project_status_doc
        if project_status.exists():
            ok(f"{role.code} project status doc ready ({project_status})")
        else:
            warn(f"{role.code} project status doc missing ({project_status})")

        for prompt in (role.codex_dev_prompt, role.codex_qa_prompt):
            prompt_path = root / prompt
            if prompt_path.exists():
                ok(f"{role.code} prompt ready ({prompt_path})")
            else:
                fail(f"{role.code} prompt missing ({prompt_path})")

        repo_path = Path(role.workdir)
        if repo_path.exists():
            ok(f"{role.code} repo reachable ({repo_path})")
        else:
            fail(f"{role.code} repo missing ({repo_path})")
            continue

        repo_agents = repo_path / "AGENTS.md"
        if repo_agents.exists():
            ok(f"{role.code} repo AGENTS.md present")
        else:
            warn(f"{role.code} repo AGENTS.md missing")

        scripts = read_package_scripts(repo_path)
        if not scripts:
            warn(f"{role.code} package scripts unreadable or package.json missing")
        else:
            required_script = "test:api" if role.code == "BACKEND" else "test:e2e"
            if required_script in scripts:
                ok(f"{role.code} QA script present ({required_script})")
            else:
                warn(f"{role.code} QA script missing ({required_script})")

    codex_bin = shutil.which("codex.cmd") or shutil.which("codex")
    if codex_bin:
        ok(f"codex binary found ({codex_bin})")
    else:
        warn("codex binary not found in PATH")

    codex_config = Path.home() / ".codex" / "config.toml"
    if codex_config.exists():
        cfg_text = codex_config.read_text(encoding="utf-8", errors="ignore")
        has_playwright = "[mcp_servers.playwright]" in cfg_text
        has_vitest = "[mcp_servers.vitest]" in cfg_text
        if has_playwright:
            ok("MCP entry found: playwright")
        else:
            warn("MCP entry missing: playwright")
        if has_vitest:
            ok("MCP entry found: vitest")
        else:
            warn("MCP entry missing: vitest")
    else:
        warn(f"codex config missing: {codex_config}")

    print(f"[DOCTOR] summary: failures={failures} warnings={warnings}")
    return 1 if failures else 0


def extract_task_info(file_path: Path, role: RoleConfig) -> TaskInfo | None:
    match = TASK_NAME_RE.match(file_path.name)
    if not match:
        return None

    task_id, raw_title = match.groups()
    task_id = task_id.upper()

    if role.code == "BACKEND":
        if not (task_id.startswith("BACKEND-") or task_id.startswith("BUG-")):
            return None
    elif not task_id.startswith(role.code):
        return None

    return TaskInfo(
        task_id=task_id,
        title=raw_title.replace("-", " "),
        file_name=file_path.name,
        task_path=str(file_path),
        role_code=role.code,
        role_name=role.name,
        project=role.project,
        workdir=role.workdir,
        codex_dev_prompt=role.codex_dev_prompt,
        codex_qa_prompt=role.codex_qa_prompt,
        claude_agent=role.claude_agent,
    )


def scan_active_tasks(root: Path) -> List[TaskInfo]:
    tasks: List[TaskInfo] = []
    base = root / "01-tasks" / "active"

    for role in ROLE_CONFIGS.values():
        role_dir = base / role.task_dir
        if not role_dir.exists():
            continue

        for file_path in sorted(role_dir.glob("*.md")):
            task = extract_task_info(file_path, role)
            if task:
                tasks.append(task)

    tasks.sort(key=lambda t: (t.role_code, t.task_id, t.file_name))
    return tasks


def sync_status_md(root: Path, tasks: List[TaskInfo]) -> None:
    """Rewrite STATUS.md to reflect the actual active/ and completed/ directories."""
    base = root / "01-tasks"
    status_path = base / "STATUS.md"

    # Count completed tasks per role
    completed: Dict[str, List[Tuple[str, str, str]]] = {code: [] for code in ROLE_CONFIGS}
    for role in ROLE_CONFIGS.values():
        cdir = base / "completed" / role.task_dir
        if not cdir.exists():
            continue
        for fp in sorted(cdir.glob("*.md")):
            m = TASK_NAME_RE.match(fp.name)
            if m:
                tid, raw = m.groups()
                completed[role.code].append((tid.upper(), raw.replace("-", " "), fp.name))

    # Group active tasks per role
    active_grouped: Dict[str, List[TaskInfo]] = {code: [] for code in ROLE_CONFIGS}
    for t in tasks:
        active_grouped[t.role_code].append(t)

    total_active = len(tasks)
    total_completed = sum(len(v) for v in completed.values())
    now = datetime.now().astimezone().strftime("%Y-%m-%d")

    lines: List[str] = []
    lines.append("\ufeff# 任务状态总览")
    lines.append("")
    lines.append(f"**更新时间**: {now}")
    lines.append(f"**活跃任务**: {total_active} 个")
    lines.append("")

    # Project mapping
    lines.append("## 项目映射")
    lines.append("")
    lines.append("| 角色 | 标识 | 项目 | 仓库路径 |")
    lines.append("|------|------|------|----------|")
    role_labels = {"SHOP-FE": "独立站前端", "ADMIN-FE": "管理后台前端", "BACKEND": "后端"}
    for code, role in ROLE_CONFIGS.items():
        lines.append(f"| {role_labels.get(code, code)} | `{code}` | {role.project} | `{role.workdir}` |")
    lines.append("")

    # Stats table
    lines.append("## 任务统计")
    lines.append("")
    lines.append("| 角色 | backlog | active | completed | 总计 |")
    lines.append("|------|---------|--------|-----------|------|")
    for code in ROLE_CONFIGS:
        a = len(active_grouped[code])
        c = len(completed[code])
        lines.append(f"| {code} | 0 | {a} | {c} | {a + c} |")
    lines.append(f"| **TOTAL** | **0** | **{total_active}** | **{total_completed}** | **{total_active + total_completed}** |")
    lines.append("")

    # Directory structure
    lines.append("## 目录结构")
    lines.append("")
    lines.append("```")
    lines.append("01-tasks/")
    lines.append("|-- active/")
    lines.append("|   |-- shop-frontend/")
    lines.append("|   |-- admin-frontend/")
    lines.append("|   `-- backend/")
    lines.append("|-- backlog/")
    lines.append("|   |-- shop-frontend/")
    lines.append("|   |-- admin-frontend/")
    lines.append("|   `-- backend/")
    lines.append("|-- completed/")
    lines.append("|   |-- shop-frontend/")
    lines.append("|   |-- admin-frontend/")
    lines.append("|   `-- backend/")
    lines.append("`-- templates/")
    lines.append("```")
    lines.append("")

    # Active tasks
    lines.append("## 当前活跃任务")
    lines.append("")
    if not tasks:
        lines.append("当前没有 `active` 任务。")
    else:
        role_order = {"BACKEND": "后端", "ADMIN-FE": "管理后台前端", "SHOP-FE": "独立站前端"}
        for code, label in role_order.items():
            group = active_grouped.get(code, [])
            if not group:
                continue
            lines.append(f"### {label} ({code})")
            lines.append("")
            lines.append("| 任务ID | 标题 |")
            lines.append("|--------|------|")
            for t in group:
                rel = f"./active/{ROLE_CONFIGS[code].task_dir}/{t.file_name}"
                lines.append(f"| [{t.task_id}]({rel}) | {t.title} |")
            lines.append("")
    lines.append("")

    # Backlog
    lines.append("## backlog 任务")
    lines.append("")
    lines.append("当前没有 `backlog` 任务。")
    lines.append("")

    # Completed tasks
    lines.append("## 已完成任务")
    lines.append("")
    role_order_completed = [
        ("SHOP-FE", "独立站前端"),
        ("ADMIN-FE", "管理后台前端"),
        ("BACKEND", "后端"),
    ]
    for code, label in role_order_completed:
        group = completed.get(code, [])
        if not group:
            continue
        lines.append(f"### {label} ({code})")
        lines.append("")
        lines.append("| 任务ID | 标题 |")
        lines.append("|--------|------|")
        for tid, title, fname in group:
            rel = f"./completed/{ROLE_CONFIGS[code].task_dir}/{fname}"
            lines.append(f"| [{tid}]({rel}) | {title} |")
        lines.append("")

    status_path.write_text("\n".join(lines), encoding="utf-8")


def group_tasks(tasks: List[TaskInfo]) -> Dict[str, List[TaskInfo]]:
    grouped: Dict[str, List[TaskInfo]] = {code: [] for code in ROLE_CONFIGS.keys()}
    for task in tasks:
        grouped[task.role_code].append(task)
    return grouped


def print_list(tasks: List[TaskInfo]) -> None:
    print(f"\n[LIST] Active tasks: {len(tasks)}")
    print("-" * 72)
    if not tasks:
        print("No active tasks found.")
        return

    for task in tasks:
        print(f"[{task.task_id}] {task.title}")
        print(f"  role={task.role_code} project={task.project}")
        print(f"  file={task.file_name}")


def print_scan(tasks: List[TaskInfo], task_locks: Dict[str, Any], ttl_hours: float) -> None:
    grouped = group_tasks(tasks)
    print("\n[SCAN] Suggested role assignments")
    print("-" * 72)

    if not tasks:
        print("No active tasks found under 01-tasks/active/*.")
        return

    for role_code, role_tasks in grouped.items():
        if not role_tasks:
            continue
        role = ROLE_CONFIGS[role_code]
        print(f"\n[{role.code}] {role.name} -> {role.project}")
        print(f"  workdir: {role.workdir}")
        for task in role_tasks:
            lock = get_task_lock(task_locks, task.task_id)
            if lock:
                stale = "stale" if is_task_lock_stale(lock, ttl_hours) else "fresh"
                lock_text = (
                    f" [locked:{lock.get('runner')}:{lock.get('owner')}:{lock.get('state')}:{stale}]"
                )
            else:
                lock_text = " [unlocked]"
            print(f"  - {task.task_id}: {task.title}{lock_text}")


def find_task(tasks: List[TaskInfo], query: str) -> TaskInfo | None:
    normalized = query.strip().upper()
    for task in tasks:
        if task.task_id == normalized:
            return task
    return None


def context_packet_for_task(task: TaskInfo, root: Path) -> List[str]:
    role = ROLE_CONFIGS[task.role_code]
    common = [
        root / "01-tasks" / "STATUS.md",
        root / "04-projects" / "COORDINATION.md",
        root / "04-projects" / "DEPENDENCIES.md",
        root / role.project_status_doc,
        Path(task.task_path),
        Path(task.workdir) / "AGENTS.md",
    ]
    extra = [root / rel for rel in role.extra_context_files]
    all_paths = common + extra

    result: List[str] = []
    for path in all_paths:
        result.append(str(path))
    return result


def create_split_tasks(
    root: Path,
    request_text: str,
    title: str,
    priority: str,
    role_codes: List[str],
    preview: bool,
    parent_ref: str,
) -> List[Path]:
    created: List[Path] = []
    date_str = datetime.now().astimezone().date().isoformat()
    base_slug = slugify(title)

    for role_code in role_codes:
        role = ROLE_CONFIGS[role_code]
        template_path = template_file_path(root, role)
        if not template_path.exists():
            raise FileNotFoundError(f"missing template: {template_path}")

        template_text = template_path.read_text(encoding="utf-8")
        next_num = next_task_number(root, role)
        task_id = f"{role.code}-{next_num:03d}"
        file_name = f"{task_id}-{base_slug}.md"
        out_path = active_role_dir(root, role) / file_name
        task_title = f"{title} - {role.name}"
        content = render_task_from_template(
            template_text=template_text,
            task_title=task_title,
            date_str=date_str,
            priority=priority,
            request_text=request_text,
            role=role,
            parent_ref=parent_ref,
        )

        if not preview:
            out_path.parent.mkdir(parents=True, exist_ok=True)
            out_path.write_text(content, encoding="utf-8")
        created.append(out_path)

    return created


def build_codex_single_prompt(task: TaskInfo, root: Path) -> str:
    role = ROLE_CONFIGS[task.role_code]
    context_packet = context_packet_for_task(task, root)
    return f"""Use this in codex-cli (Team Lead session):

Task: {task.task_id} ({task.title})
Task file: {task.task_path}
Target repo: {task.workdir}

Required flow:
1) Use native Multi-agents mode.
2) Spawn one developer sub-agent for role `{task.role_code}`.
3) Developer agent uses prompt file `{task.codex_dev_prompt}`.
4) Developer implements in `{task.workdir}` and reports changed files + test evidence.
5) Spawn one QA sub-agent with `{task.codex_qa_prompt}` for verification.
6) QA reports pass/fail with reproducible steps.
7) Route cross-role communication through Team Lead relay.
8) Do not move task to `completed/` until user confirms.

Optional Context References (pull on demand if needed):
{chr(10).join(f"- {p}" for p in context_packet)}

QA Baseline For Role `{task.role_code}`:
- Tooling: {role.qa_tooling}
- Primary commands:
{chr(10).join(f"  - {cmd}" for cmd in role.qa_primary_commands)}
- Fallback:
{chr(10).join(f"  - {cmd}" for cmd in role.qa_fallback_commands)}
"""


def build_claude_single_prompt(task: TaskInfo) -> str:
    return f"""Execute in Claude Code:

Task(
  subagent_type='{task.claude_agent}',
  prompt='Read and implement task: {task.task_path}\\nWorkdir: {task.workdir}',
  model='sonnet'
)
"""


def build_codex_team_prompt(tasks: List[TaskInfo], root: Path) -> str:
    grouped = group_tasks(tasks)
    active_roles = [code for code, items in grouped.items() if items]

    if not active_roles:
        return "No active tasks found. Create files under 01-tasks/active/* first."

    lines: List[str] = []
    lines.append("Codex Team bootstrap prompt:")
    lines.append("")
    lines.append("You are the Team Lead coordinator in E:\\moxton-docs.")
    lines.append("Use native Multi-agents mode and run role agents in parallel.")
    lines.append("Follow team-lead prompt file: .claude/agents/team-lead.md")
    lines.append("Follow messaging protocol: .claude/agents/protocol.md")
    lines.append("Run MCP preflight once: codex mcp list")
    lines.append("Ensure runner lock is codex: python scripts/assign_task.py --lock codex")
    lines.append("Ensure task-level lock before dispatch:")
    lines.append("  python scripts/assign_task.py --lock-task <TASK-ID> --task-owner team-lead")
    lines.append("")
    lines.append("Execution requirements:")
    lines.append("1) Create one dev sub-agent and one QA sub-agent per active role.")
    lines.append("2) Dev agents implement code in their target repo workdir.")
    lines.append("3) QA agents verify implementation and produce test evidence.")
    lines.append("4) If MCP servers are enabled, QA should prefer MCP tools (`playwright`, `vitest`).")
    lines.append("5) Team Lead relays cross-agent messages (no direct peer chat).")
    lines.append("6) Use a strict route envelope for every inter-agent message.")
    lines.append("7) Team Lead is coordination-only: never edit code repos, never run repo tests.")
    lines.append("8) Team Lead may inspect code repos in read-only mode for analysis.")
    lines.append("9) If asked to code directly, Team Lead must refuse and delegate to role dev agent.")
    lines.append("10) Permission requests go to Team Lead first; Team Lead auto-approves low-risk actions.")
    lines.append("11) Escalate to user only for high-risk/destructive/uncertain actions.")
    lines.append("12) Ask user before kickoff: 是否现在开始创建团队执行这些任务？")
    lines.append("13) Ask user before moving any task file to completed.")
    lines.append("14) If backend/API changes occur, trigger doc-updater for 02-api sync.")
    lines.append("15) Downstream agents may pull role context references from moxton-docs on demand.")
    lines.append("16) Team Lead should avoid force-feeding large context packets by default.")
    lines.append("")
    lines.append("Route envelope format:")
    lines.append("[ROUTE]")
    lines.append("from: <agent-name>")
    lines.append("to: <target-agent|team-lead>")
    lines.append("type: <status|question|blocker|handoff|review>")
    lines.append("task: <TASK-ID>")
    lines.append("body: <message>")
    lines.append("[/ROUTE]")
    lines.append("")
    lines.append("Relay loop:")
    lines.append("A) parse route envelopes from any agent message")
    lines.append("B) if target is another agent, forward via Team Lead")
    lines.append("C) acknowledge sender with relay status")
    lines.append("D) keep processing until all role tasks are QA PASS or blocked")
    lines.append("E) when backend contract changes, assign doc-updater before final closure")
    lines.append("")
    lines.append("Role assignments:")

    for role_code in active_roles:
        role = ROLE_CONFIGS[role_code]
        role_tasks = grouped[role_code]
        lines.append(f"- {role.code} ({role.name})")
        lines.append(f"  repo: {role.workdir}")
        lines.append(f"  dev prompt: {role.codex_dev_prompt}")
        lines.append(f"  qa prompt: {role.codex_qa_prompt}")
        lines.append(f"  qa tooling: {role.qa_tooling}")
        lines.append("  qa primary commands:")
        for cmd in role.qa_primary_commands:
            lines.append(f"    - {cmd}")
        if role.qa_fallback_commands:
            lines.append("  qa fallback commands:")
            for cmd in role.qa_fallback_commands:
                lines.append(f"    - {cmd}")
        lines.append("  task files:")
        for task in role_tasks:
            relative = str(Path(task.task_path).resolve().relative_to(root))
            lines.append(f"    - {relative}")
        lines.append("  optional context references:")
        lines.append(f"    - {root / '01-tasks' / 'STATUS.md'}")
        lines.append(f"    - {root / '04-projects' / 'COORDINATION.md'}")
        lines.append(f"    - {root / '04-projects' / 'DEPENDENCIES.md'}")
        lines.append(f"    - {root / role.project_status_doc}")
        for rel in role.extra_context_files:
            lines.append(f"    - {root / rel}")
        lines.append(f"    - {Path(role.workdir) / 'AGENTS.md'}")
        lines.append("")

    lines.append("Support role:")
    lines.append("- DOC-UPDATER (docs sync)")
    lines.append("  prompt: .claude/agents/doc-updater.md")
    lines.append("  trigger: backend/API contract changes")
    lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def print_standard_entry(tasks: List[TaskInfo], root: Path) -> None:
    if tasks:
        print("[TEAM-LEAD MODE] EXECUTION")
        print("  active tasks detected under 01-tasks/active/*")
        print("  standard action:")
        print("  1) keep Team Lead identity")
        print("  2) create/monitor team and execute existing tasks")
        print("  3) ask user: 是否现在开始创建团队执行这些任务？")
        print("  commands:")
        print("    python scripts/assign_task.py --scan")
        print("    python scripts/assign_task.py --write-brief")
        return

    print("[TEAM-LEAD MODE] PLANNING")
    print("  no active tasks detected")
    print("  standard action:")
    print("  1) discuss requirement and produce development plan")
    print("  2) split by templates into role task files")
    print("  3) ask user: 是否现在开始创建团队执行这些任务？")
    print("  commands:")
    print("    python scripts/assign_task.py --split-request \"<requirement text>\"")


def run_intake(
    root: Path,
    tasks: List[TaskInfo],
    runner_lock: Dict[str, str],
    args: argparse.Namespace,
    intake_text: str,
) -> int:
    text = intake_text.strip()
    if not text:
        print("[ERROR] --intake requires non-empty text.")
        return 1

    intent = detect_intent(text)

    if tasks:
        print("[INTAKE] mode=EXECUTION")
        print(f"  active_tasks: {len(tasks)}")
        print(f"  intent: {intent}")
        if intent != "create_team":
            print("  note: unfinished tasks exist, so Team Lead stays in execution mode.")
            print("  action: continue dispatch/monitor for current active tasks.")
            print("[TEAM-LEAD] 请确认：是否现在开始创建团队执行这些任务？")
            return 0

        active_runner = runner_lock.get("runner", "none")
        if active_runner not in ("none", "codex"):
            print(
                f"[LOCKED] runner is '{active_runner}', team brief generation requires codex flow. "
                "Switch with: python scripts/assign_task.py --lock codex"
            )
            return 2
        if active_runner == "none":
            print("[WARN] runner lock is 'none'. Recommended: python scripts/assign_task.py --lock codex")

        output_path = root / "04-projects" / "CODEX-TEAM-BRIEF.md"
        write_codex_brief(output_path, tasks, root)
        print(f"[OK] wrote brief: {output_path}")
        print("[TEAM-LEAD] 请确认：是否现在开始创建团队执行这些任务？")
        return 0

    print("[INTAKE] mode=PLANNING")
    print(f"  intent: {intent}")

    title = (args.split_title or summarize_request_text(text, 48)).strip()
    title = title if title else "cross-project-task"
    priority = args.split_priority.upper()
    parent_ref = args.split_parent.strip() or f"REQ-{datetime.now().astimezone().strftime('%Y%m%d-%H%M%S')}"

    if args.split_roles:
        role_codes = parse_role_list(args.split_roles)
        role_scores: Dict[str, int] = {code: 0 for code in ROLE_CONFIGS.keys()}
    else:
        role_codes, role_scores = detect_roles_from_request(text)

    if not role_codes:
        print("[ERROR] unable to detect target roles from intake text.")
        print("        pass explicit roles with --split-roles SHOP-FE,ADMIN-FE,BACKEND")
        return 1

    if args.split_preview:
        print("[SPLIT] preview mode (no files written)")
    else:
        print("[SPLIT] creating template-based task files")
    print(f"  title: {title}")
    print(f"  priority: {priority}")
    print(f"  parent_ref: {parent_ref}")
    print(f"  roles: {', '.join(role_codes)}")
    if not args.split_roles:
        print("  role_scores:")
        for code in ROLE_CONFIGS.keys():
            print(f"    - {code}: {role_scores.get(code, 0)}")

    created_paths = create_split_tasks(
        root=root,
        request_text=text,
        title=title,
        priority=priority,
        role_codes=role_codes,
        preview=args.split_preview,
        parent_ref=parent_ref,
    )

    for file_path in created_paths:
        print(f"  - {file_path}")

    if not args.split_preview and not args.split_no_lock:
        lock_runner = runner_lock["runner"]
        if lock_runner in {"codex", "claude"}:
            for file_path in created_paths:
                task_match = TASK_NAME_RE.match(file_path.name)
                if not task_match:
                    continue
                task_id = normalize_task_id(task_match.group(1))
                upsert_task_lock(
                    root,
                    task_id=task_id,
                    runner=lock_runner,
                    owner="team-lead",
                    state="assigned",
                    note=f"auto-locked on split: {parent_ref}",
                )
            print(f"[OK] auto-locked generated tasks for runner '{lock_runner}'")
        else:
            print("[WARN] runner lock is none; generated tasks were not auto-locked.")
            print("       set runner lock and use --lock-task for each task.")

    if not args.split_preview:
        print("[TEAM-LEAD] 请确认：是否现在开始创建团队执行这些任务？")
    return 0


def write_codex_brief(path: Path, tasks: List[TaskInfo], root: Path) -> None:
    grouped = group_tasks(tasks)
    lock = read_runner_lock(root)
    task_locks = read_task_locks(root)
    lines: List[str] = []
    lines.append("# Codex Agent Team Brief")
    lines.append("")
    lines.append("This file is generated by `python scripts/assign_task.py --write-brief`.")
    lines.append("Use it in codex-cli to bootstrap a Team Lead + parallel sub-agent workflow.")
    lines.append("")
    lines.append("## Team Lead")
    lines.append("- Workdir: `E:\\moxton-docs`")
    lines.append("- Prompt file: `.claude/agents/team-lead.md`")
    lines.append("- Protocol: `.claude/agents/protocol.md`")
    lines.append(f"- Active runner lock: `{lock['runner']}` (`01-tasks/ACTIVE-RUNNER.md`)")
    lines.append(f"- Task lock file: `01-tasks/TASK-LOCKS.json` (locked tasks: `{len(task_locks.get('locks', {}))}`)")
    lines.append("- Rule: coordinate only; ask user before moving tasks to `completed/`")
    lines.append("")
    lines.append("## Active Roles")

    any_role = False
    for role_code, role_tasks in grouped.items():
        if not role_tasks:
            continue
        any_role = True
        role = ROLE_CONFIGS[role_code]
        lines.append(f"### {role.code} - {role.name}")
        lines.append(f"- Repo: `{role.workdir}`")
        lines.append(f"- Dev prompt: `{role.codex_dev_prompt}`")
        lines.append(f"- QA prompt: `{role.codex_qa_prompt}`")
        lines.append(f"- QA tooling: `{role.qa_tooling}`")
        lines.append("- QA primary commands:")
        for cmd in role.qa_primary_commands:
            lines.append(f"  - `{cmd}`")
        if role.qa_fallback_commands:
            lines.append("- QA fallback commands:")
            for cmd in role.qa_fallback_commands:
                lines.append(f"  - `{cmd}`")
        lines.append("- Tasks:")
        for task in role_tasks:
            relative = str(Path(task.task_path).resolve().relative_to(root))
            lines.append(f"  - `{relative}` ({task.task_id})")
        lines.append("")

    if not any_role:
        lines.append("- No active tasks found in `01-tasks/active/*`.")
        lines.append("")

    lines.append("## Codex Starter Prompt")
    lines.append("Paste this into codex-cli:")
    lines.append("")
    lines.append("```text")
    lines.append(build_codex_team_prompt(tasks, root).rstrip())
    lines.append("```")
    lines.append("")

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines), encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Moxton task assignment helper")
    parser.add_argument("task_id", nargs="?", help="Task ID, e.g. SHOP-FE-001")
    parser.add_argument(
        "--standard-entry",
        action="store_true",
        help="Show Team Lead standard two-mode entry (execution/planning)",
    )
    parser.add_argument("--list", action="store_true", help="List active tasks")
    parser.add_argument("--scan", action="store_true", help="Scan and show assignment suggestions")
    parser.add_argument(
        "--team-prompt",
        action="store_true",
        help="Print codex team bootstrap prompt for all active tasks",
    )
    parser.add_argument(
        "--write-brief",
        nargs="?",
        const="04-projects/CODEX-TEAM-BRIEF.md",
        help="Write markdown team brief (default path: 04-projects/CODEX-TEAM-BRIEF.md)",
    )
    parser.add_argument(
        "--show-lock",
        action="store_true",
        help="Show active runner lock from 01-tasks/ACTIVE-RUNNER.md",
    )
    parser.add_argument(
        "--lock",
        choices=["codex", "claude", "none"],
        help="Set active runner lock to avoid dual-trigger between workflows",
    )
    parser.add_argument(
        "--lock-note",
        default="",
        help="Optional note when updating runner lock",
    )
    parser.add_argument(
        "--show-task-locks",
        action="store_true",
        help="Show task-level locks from 01-tasks/TASK-LOCKS.json",
    )
    parser.add_argument(
        "--task-lock-ttl-hours",
        type=float,
        default=DEFAULT_TASK_LOCK_TTL_HOURS,
        help="Task lock TTL in hours (used by stale-lock checks and doctor)",
    )
    parser.add_argument(
        "--reap-stale-locks",
        action="store_true",
        help="Remove stale task locks older than --task-lock-ttl-hours",
    )
    parser.add_argument(
        "--lock-task",
        help="Lock one task ID (e.g. SHOP-FE-001) for current runner or --task-runner",
    )
    parser.add_argument(
        "--unlock-task",
        help="Unlock one task ID",
    )
    parser.add_argument(
        "--task-runner",
        choices=["codex", "claude"],
        help="Runner for task lock (defaults to current active runner lock)",
    )
    parser.add_argument(
        "--task-owner",
        default="team-lead",
        help="Task lock owner (e.g. team-lead, backend-dev, admin-fe-qa)",
    )
    parser.add_argument(
        "--task-state",
        choices=sorted(VALID_TASK_STATES),
        default="assigned",
        help="Task lock state when using --lock-task",
    )
    parser.add_argument(
        "--force-unlock",
        action="store_true",
        help="Force unlock even when runner mismatch",
    )
    parser.add_argument(
        "--split-request",
        help="Split one high-level request into role task files using templates",
    )
    parser.add_argument(
        "--intake",
        help="Natural-language Team Lead intake; auto-select planning/execution mode",
    )
    parser.add_argument(
        "--intake-file",
        help="Read intake text from file",
    )
    parser.add_argument(
        "--split-request-file",
        help="Read split request text from file",
    )
    parser.add_argument(
        "--split-title",
        help="Title used for generated task files",
    )
    parser.add_argument(
        "--split-priority",
        choices=sorted(VALID_PRIORITIES),
        default="P1",
        help="Priority for generated tasks",
    )
    parser.add_argument(
        "--split-roles",
        help="Optional explicit roles, comma-separated: SHOP-FE,ADMIN-FE,BACKEND",
    )
    parser.add_argument(
        "--split-parent",
        default="",
        help="Optional parent request identifier",
    )
    parser.add_argument(
        "--split-preview",
        action="store_true",
        help="Preview generated task paths without writing files",
    )
    parser.add_argument(
        "--split-no-lock",
        action="store_true",
        help="Do not auto-lock generated tasks",
    )
    parser.add_argument(
        "--doctor",
        action="store_true",
        help="Run one-shot readiness checks for Team Lead orchestration",
    )
    parser.add_argument("--json", action="store_true", help="Print scan result as JSON")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = repo_root()
    tasks = scan_active_tasks(root)
    sync_status_md(root, tasks)
    runner_lock = read_runner_lock(root)
    task_locks = read_task_locks(root)

    did_work = False
    exit_code = 0

    if args.lock:
        path = write_runner_lock(root, args.lock, args.lock_note)
        print(f"[OK] updated runner lock: {path}")
        runner_lock = read_runner_lock(root)
        print_runner_lock(runner_lock)
        did_work = True

    if args.show_lock:
        print_runner_lock(runner_lock)
        did_work = True

    if args.reap_stale_locks:
        path, removed = reap_stale_task_locks(root, args.task_lock_ttl_hours)
        if removed:
            print(
                f"[OK] removed stale task locks ({len(removed)}) with ttl={args.task_lock_ttl_hours:.1f}h: "
                + ", ".join(removed)
            )
        else:
            print(f"[OK] no stale task locks to remove (ttl={args.task_lock_ttl_hours:.1f}h)")
        print(f"  file: {path}")
        task_locks = read_task_locks(root)
        did_work = True

    if args.lock_task:
        task_id = normalize_task_id(args.lock_task)
        task = find_task(tasks, task_id)
        if not task:
            print(f"[ERROR] task not found in active dirs: {task_id}")
            return 1

        lock_runner = (args.task_runner or runner_lock["runner"]).lower()
        if lock_runner not in {"codex", "claude"}:
            print(
                "[ERROR] cannot infer task lock runner. "
                "Set runner lock first or pass --task-runner codex|claude."
            )
            return 1

        existing = get_task_lock(task_locks, task_id)
        if existing and is_task_lock_stale(existing, args.task_lock_ttl_hours):
            stale_age = task_lock_age_hours(existing)
            stale_age_text = f"{stale_age:.1f}h" if stale_age is not None else "unknown"
            print(
                f"[WARN] replacing stale lock for {task_id} "
                f"(runner={existing.get('runner')} age={stale_age_text})"
            )
            delete_task_lock(root, task_id)
            task_locks = read_task_locks(root)
            existing = None
        if existing and existing.get("runner") != lock_runner:
            print(
                f"[LOCKED] task {task_id} already locked by runner '{existing.get('runner')}'. "
                "Use --unlock-task with runner owner first."
            )
            return 2

        path = upsert_task_lock(
            root,
            task_id=task_id,
            runner=lock_runner,
            owner=args.task_owner,
            state=args.task_state,
            note=args.lock_note,
        )
        print(
            f"[OK] task locked: {task_id} runner={lock_runner} "
            f"owner={args.task_owner} state={args.task_state} file={path}"
        )
        task_locks = read_task_locks(root)
        did_work = True

    if args.unlock_task:
        task_id = normalize_task_id(args.unlock_task)
        existing = get_task_lock(task_locks, task_id)
        if not existing:
            path, _ = delete_task_lock(root, task_id)
            print(f"[OK] task already unlocked: {task_id} file={path}")
            task_locks = read_task_locks(root)
            did_work = True
        else:
            lock_runner = existing.get("runner", "")
            active_runner = runner_lock["runner"]
            if (
                lock_runner in {"codex", "claude"}
                and active_runner not in {"none", lock_runner}
                and not args.force_unlock
            ):
                print(
                    f"[LOCKED] task {task_id} is owned by runner '{lock_runner}', "
                    f"active runner is '{active_runner}'. Use --force-unlock to override."
                )
                return 2
            path, _ = delete_task_lock(root, task_id)
            print(f"[OK] task unlocked: {task_id} file={path}")
            task_locks = read_task_locks(root)
            did_work = True

    if args.show_task_locks:
        print_task_locks(task_locks, tasks, args.task_lock_ttl_hours)
        did_work = True

    intake_text = ""
    if args.intake:
        intake_text = args.intake.strip()
    elif args.intake_file:
        intake_path = Path(args.intake_file)
        if not intake_path.is_absolute():
            intake_path = root / intake_path
        if not intake_path.exists():
            print(f"[ERROR] intake file not found: {intake_path}")
            return 1
        intake_text = intake_path.read_text(encoding="utf-8").strip()

    if intake_text:
        intake_code = run_intake(
            root=root,
            tasks=tasks,
            runner_lock=runner_lock,
            args=args,
            intake_text=intake_text,
        )
        if intake_code != 0:
            return intake_code
        tasks = scan_active_tasks(root)
        sync_status_md(root, tasks)
        task_locks = read_task_locks(root)
        did_work = True

    split_request_text = ""
    if args.split_request:
        split_request_text = args.split_request.strip()
    elif args.split_request_file:
        req_path = Path(args.split_request_file)
        if not req_path.is_absolute():
            req_path = root / req_path
        if not req_path.exists():
            print(f"[ERROR] split request file not found: {req_path}")
            return 1
        split_request_text = req_path.read_text(encoding="utf-8").strip()

    if split_request_text:
        title = (args.split_title or summarize_request_text(split_request_text, 48)).strip()
        title = title if title else "cross-project-task"
        priority = args.split_priority.upper()
        parent_ref = args.split_parent.strip() or f"REQ-{datetime.now().astimezone().strftime('%Y%m%d-%H%M%S')}"

        if args.split_roles:
            role_codes = parse_role_list(args.split_roles)
            role_scores: Dict[str, int] = {code: 0 for code in ROLE_CONFIGS.keys()}
        else:
            role_codes, role_scores = detect_roles_from_request(split_request_text)

        if not role_codes:
            print("[ERROR] unable to detect target roles from request.")
            print("        pass explicit roles with --split-roles SHOP-FE,ADMIN-FE,BACKEND")
            return 1

        if args.split_preview:
            print("[SPLIT] preview mode (no files written)")
        else:
            print("[SPLIT] creating template-based task files")
        print(f"  title: {title}")
        print(f"  priority: {priority}")
        print(f"  parent_ref: {parent_ref}")
        print(f"  roles: {', '.join(role_codes)}")
        if not args.split_roles:
            print("  role_scores:")
            for code in ROLE_CONFIGS.keys():
                print(f"    - {code}: {role_scores.get(code, 0)}")

        created_paths = create_split_tasks(
            root=root,
            request_text=split_request_text,
            title=title,
            priority=priority,
            role_codes=role_codes,
            preview=args.split_preview,
            parent_ref=parent_ref,
        )

        for file_path in created_paths:
            print(f"  - {file_path}")

        if not args.split_preview and not args.split_no_lock:
            lock_runner = runner_lock["runner"]
            if lock_runner in {"codex", "claude"}:
                for file_path in created_paths:
                    task_match = TASK_NAME_RE.match(file_path.name)
                    if not task_match:
                        continue
                    task_id = normalize_task_id(task_match.group(1))
                    upsert_task_lock(
                        root,
                        task_id=task_id,
                        runner=lock_runner,
                        owner="team-lead",
                        state="assigned",
                        note=f"auto-locked on split: {parent_ref}",
                    )
                print(f"[OK] auto-locked generated tasks for runner '{lock_runner}'")
            else:
                print("[WARN] runner lock is none; generated tasks were not auto-locked.")
                print("       set runner lock and use --lock-task for each task.")

        # Refresh in-memory snapshots after split.
        tasks = scan_active_tasks(root)
        task_locks = read_task_locks(root)
        if not args.split_preview:
            print("[TEAM-LEAD] 请确认：是否现在开始创建团队执行这些任务？")
        did_work = True

    if args.standard_entry:
        print_standard_entry(tasks, root)
        did_work = True

    if args.doctor:
        doctor_code = run_doctor(
            root=root,
            tasks=tasks,
            runner_lock=runner_lock,
            task_locks=task_locks,
            ttl_hours=args.task_lock_ttl_hours,
        )
        exit_code = max(exit_code, doctor_code)
        did_work = True

    codex_action = bool(args.team_prompt or args.write_brief is not None or (args.task_id and args.provider == "codex"))
    claude_action = bool(args.task_id and args.provider == "claude")
    ccb_action = bool(args.dispatch_ccb or args.poll_ccb)

    required_runner = "codex" if codex_action else ("claude" if (claude_action or ccb_action) else "")
    active_runner = runner_lock["runner"]

    if required_runner and active_runner not in ("none", required_runner):
        print(
            f"[LOCKED] runner is '{active_runner}', this action requires '{required_runner}'. "
            f"Switch with: python scripts/assign_task.py --lock {required_runner}"
        )
        return 2

    if required_runner and active_runner == "none":
        print(
            f"[WARN] runner lock is 'none'. Recommended: "
            f"python scripts/assign_task.py --lock {required_runner}"
        )

    if args.list:
        print_list(tasks)
        did_work = True

    if args.scan:
        print_scan(tasks, task_locks, args.task_lock_ttl_hours)
        did_work = True

    if args.json:
        print(json.dumps([asdict(task) for task in tasks], ensure_ascii=False, indent=2))
        did_work = True

    if args.team_prompt:
        print(build_codex_team_prompt(tasks, root))
        did_work = True

    if args.write_brief is not None:
        output_path = Path(args.write_brief)
        if not output_path.is_absolute():
            output_path = root / output_path
        write_codex_brief(output_path, tasks, root)
        print(f"[OK] wrote brief: {output_path}")
        did_work = True

    if args.task_id:
        task = find_task(tasks, args.task_id)
        if not task:
            print(f"[ERROR] task not found in active dirs: {args.task_id}")
            return 1

        existing = get_task_lock(task_locks, task.task_id)
        if not existing:
            print(
                f"[LOCKED] task {task.task_id} is not locked yet. "
                f"Lock first: python scripts/assign_task.py --lock-task {task.task_id} "
                f"--task-owner team-lead"
            )
            return 2
        if is_task_lock_stale(existing, args.task_lock_ttl_hours):
            stale_age = task_lock_age_hours(existing)
            stale_age_text = f"{stale_age:.1f}h" if stale_age is not None else "unknown"
            print(
                f"[LOCKED] task {task.task_id} has a stale lock "
                f"(runner={existing.get('runner')} age={stale_age_text}). "
                f"Re-lock first: python scripts/assign_task.py --lock-task {task.task_id} --task-owner team-lead"
            )
            return 2

        expected_runner = args.provider
        if existing.get("runner") != expected_runner:
            print(
                f"[LOCKED] task {task.task_id} locked by runner '{existing.get('runner')}', "
                f"but provider is '{expected_runner}'."
            )
            return 2

        print(f"[ASSIGN] {task.task_id} -> {task.project}")
        print(
            f"[ASSIGN] lock owner={existing.get('owner')} "
            f"state={existing.get('state')} runner={existing.get('runner')}"
        )
        print("-" * 72)
        if args.provider == "codex":
            print(build_codex_single_prompt(task, root))
        else:
            print(build_claude_single_prompt(task))
        did_work = True

    if not did_work:
        print("Usage examples:")
        print("  python scripts/assign_task.py --standard-entry")
        print("  python scripts/assign_task.py --show-lock")
        print("  python scripts/assign_task.py --lock codex")
        print("  python scripts/assign_task.py --lock claude")
        print("  python scripts/assign_task.py --show-task-locks")
        print("  python scripts/assign_task.py --lock-task SHOP-FE-001 --task-owner team-lead")
        print("  python scripts/assign_task.py --unlock-task SHOP-FE-001")
        print("  python scripts/assign_task.py --dispatch-ccb <TASK-ID>")
        print("  python scripts/assign_task.py --poll-ccb --ccb-worker <WORKER-NAME>")
        print("  python scripts/assign_task.py --intake \"请编写xx接口\"")
        print("  python scripts/assign_task.py --split-request \"<requirement text>\"")
        print("  python scripts/assign_task.py --split-request-file req.md --split-roles SHOP-FE,ADMIN-FE")
        print("  python scripts/assign_task.py --list")
        print("  python scripts/assign_task.py --scan")
        print("  python scripts/assign_task.py SHOP-FE-001 --provider codex")
        print("  python scripts/assign_task.py --team-prompt")
        print("  python scripts/assign_task.py --write-brief")
        print("  python scripts/assign_task.py --doctor")
        print("  python scripts/assign_task.py --show-task-locks --task-lock-ttl-hours 24")
        print("  python scripts/assign_task.py --reap-stale-locks --task-lock-ttl-hours 24")
        return 0

    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
