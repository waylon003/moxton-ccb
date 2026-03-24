#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from collections import Counter
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

try:
    from rich.align import Align
    from rich.console import Console, Group
    from rich.layout import Layout
    from rich.live import Live
    from rich.panel import Panel
    from rich.table import Table
    from rich.text import Text
except ImportError:
    print("[FAIL] 缺少 rich 依赖。先执行: python -m pip install rich", file=sys.stderr)
    sys.exit(1)


STATE_STYLES = {
    "assigned": "cyan",
    "waiting_qa": "bright_cyan",
    "in_progress": "yellow",
    "blocked": "bold red",
    "qa_passed": "green",
    "completed": "dim",
    "archiving": "magenta",
    "failed": "red",
    "fail": "red",
    "success": "green",
    "running": "yellow",
    "starting": "yellow",
    "dispatched": "cyan",
    "snapshot": "cyan",
    "error": "bold red",
    "unknown": "white",
}

STATE_LABELS = {
    "assigned": "待派遣开发",
    "waiting_qa": "待派遣 QA",
    "in_progress": "进行中",
    "blocked": "阻塞",
    "qa_passed": "QA 已通过",
    "completed": "已完成",
    "archiving": "归档中",
    "failed": "失败",
    "fail": "失败",
    "success": "成功",
    "running": "运行中",
    "starting": "启动中",
    "dispatched": "已派遣",
    "requeued": "已回退",
    "snapshot": "快照",
    "error": "异常",
    "pending": "待处理",
    "unknown": "未知",
}

MODE_LABELS = {
    "headless": "无头",
    "pane": "窗格",
}

PHASE_LABELS = {
    "headless": "无头",
    "pane": "窗格",
    "spawn": "启动",
    "route": "回传",
    "dev": "开发",
    "qa": "验收",
    "archive": "归档",
    "archiving": "归档中",
    "running": "运行中",
    "starting": "启动中",
    "completed": "已完成",
    "blocked": "阻塞",
    "success": "成功",
    "fail": "失败",
    "failed": "失败",
}

LAYOUT_LABELS = {
    "merged-right": "同窗右栏",
    "standalone": "独立窗口",
}


def humanize_token(value: Any) -> str:
    if value is None:
        return "-"
    raw = str(value).strip()
    if not raw:
        return "-"
    return raw.replace("_", " ")


def normalize_lookup_key(value: Any) -> str:
    raw = humanize_token(value)
    return raw.lower().replace("-", "_").replace(" ", "_")


def localize_state(value: Any) -> str:
    raw = humanize_token(value)
    key = normalize_lookup_key(value)
    return STATE_LABELS.get(key, raw)


def localize_mode(value: Any) -> str:
    raw = humanize_token(value)
    key = normalize_lookup_key(value)
    return MODE_LABELS.get(key, raw)


def localize_phase(value: Any) -> str:
    raw = humanize_token(value)
    key = normalize_lookup_key(value)
    return PHASE_LABELS.get(key, raw)


def localize_layout(value: Any) -> str:
    raw = humanize_token(value)
    key = normalize_lookup_key(value)
    return LAYOUT_LABELS.get(key, raw)


@dataclass
class MonitorPaths:
    root: Path
    task_locks: Path
    attempts: Path
    route_monitor_state: Path
    route_notifier_state: Path
    rich_monitor_state: Path
    delivery_log: Path
    delivery_failures: Path
    worker_panels: Path
    approval_state: Path
    approval_requests: Path
    runtime_runs: Path


class JsonStore:
    @staticmethod
    def load_json(path: Path, default: Any) -> Any:
        if not path.exists():
            return default
        try:
            return json.loads(path.read_text(encoding="utf-8-sig"))
        except Exception:
            return default

    @staticmethod
    def load_jsonl(path: Path, limit: int | None = None) -> list[dict[str, Any]]:
        if not path.exists():
            return []
        try:
            lines = path.read_text(encoding="utf-8-sig").splitlines()
        except Exception:
            return []
        if limit and limit > 0:
            lines = lines[-limit:]
        items: list[dict[str, Any]] = []
        for line in lines:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except Exception:
                continue
            if isinstance(obj, dict):
                items.append(obj)
        return items

    @staticmethod
    def write_json(path: Path, payload: dict[str, Any]) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def wezterm_pane_id() -> str:
    return os.environ.get("WEZTERM_PANE") or os.environ.get("WEZTERM_PANE_ID") or ""


def write_monitor_state(
    paths: MonitorPaths,
    args: argparse.Namespace,
    *,
    started_at: str,
    status: str,
    note: str = "",
    visible_tasks: int = 0,
) -> None:
    payload = {
        "status": status,
        "pid": os.getpid(),
        "monitor_pane_id": wezterm_pane_id(),
        "layout_mode": os.environ.get("CCB_RICH_LAYOUT_MODE") or "standalone",
        "paired_teamlead_pane_id": os.environ.get("CCB_RICH_TEAMLEAD_PANE_ID") or "",
        "started_at": started_at,
        "last_loop_at": datetime.now().astimezone().isoformat(),
        "refresh_seconds": args.refresh,
        "task_filter": args.task or "",
        "all_tasks": bool(args.all_tasks),
        "visible_tasks": int(visible_tasks),
        "script_path": str(Path(__file__).resolve()),
        "python": sys.executable,
        "note": note,
    }
    JsonStore.write_json(paths.rich_monitor_state, payload)


def parse_args() -> argparse.Namespace:
    script_path = Path(__file__).resolve()
    default_root = script_path.parent.parent
    parser = argparse.ArgumentParser(description="Moxton-CCB Rich 监控台（只读）")
    parser.add_argument("--root", type=Path, default=default_root, help="CCB 根目录")
    parser.add_argument("--refresh", type=float, default=2.0, help="刷新间隔（秒）")
    parser.add_argument("--once", action="store_true", help="渲染一次后退出")
    parser.add_argument("--task", help="仅聚焦某个 TASK-ID")
    parser.add_argument("--all-tasks", action="store_true", help="显示全部任务锁，而不是只显示未完成/活跃任务")
    parser.add_argument("--max-deliveries", type=int, default=8, help="最近通知/route 条目数")
    parser.add_argument("--max-attempts", type=int, default=10, help="最近 attempt 条目数")
    parser.add_argument("--max-tasks", type=int, default=14, help="任务表最多显示条数")
    return parser.parse_args()


def build_paths(root: Path) -> MonitorPaths:
    return MonitorPaths(
        root=root,
        task_locks=root / "01-tasks" / "TASK-LOCKS.json",
        attempts=root / "config" / "task-attempt-history.json",
        route_monitor_state=root / "config" / "route-monitor-state.json",
        route_notifier_state=root / "config" / "route-notifier-state.json",
        rich_monitor_state=root / "config" / "rich-monitor-state.json",
        delivery_log=root / "config" / "teamlead-delivery.jsonl",
        delivery_failures=root / "config" / "teamlead-delivery-failures.jsonl",
        worker_panels=root / "config" / "worker-panels.json",
        approval_state=root / "config" / "local-approval-state.json",
        approval_requests=root / "mcp" / "route-server" / "data" / "approval-requests.json",
        runtime_runs=root / "runtime" / "runs",
    )


def now_local() -> datetime:
    return datetime.now().astimezone()


def parse_dt(value: Any) -> datetime | None:
    if not value or not isinstance(value, str):
        return None
    raw = value.strip()
    if not raw:
        return None
    raw = raw.replace("Z", "+00:00")
    match = re.match(r"^(?P<head>.+?)(?P<fraction>\.\d+)?(?P<offset>[+-]\d{2}:\d{2})?$", raw)
    if match:
        fraction = match.group("fraction") or ""
        if fraction and len(fraction) > 7:
            fraction = "." + fraction[1:7]
        raw = f"{match.group('head')}{fraction}{match.group('offset') or ''}"
    try:
        dt = datetime.fromisoformat(raw)
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc).astimezone()
    return dt.astimezone()


def age_text(value: Any) -> str:
    dt = parse_dt(value)
    if not dt:
        return "-"
    delta = now_local() - dt
    secs = int(max(delta.total_seconds(), 0))
    if secs < 60:
        return f"{secs}s"
    mins = secs // 60
    if mins < 60:
        return f"{mins}m"
    hours = mins // 60
    if hours < 48:
        return f"{hours}h"
    days = hours // 24
    return f"{days}d"


def state_style(state: str) -> str:
    return STATE_STYLES.get(normalize_lookup_key(state), "white")


def style_state(state: str) -> str:
    label = localize_state(state)
    return f"[{state_style(state)}]{label}[/]"


def shorten(text: Any, max_len: int = 84) -> str:
    if text is None:
        return ""
    s = str(text).replace("\r", " ").replace("\n", " ").strip()
    if len(s) <= max_len:
        return s
    return s[: max_len - 1] + "…"


def path_tail(value: Any, parts: int = 2) -> str:
    if not value:
        return "-"
    p = Path(str(value))
    wanted = p.parts[-parts:]
    return str(Path(*wanted)) if wanted else p.name


def process_alive(pid: Any) -> bool:
    try:
        pid_int = int(pid)
    except Exception:
        return False
    if pid_int <= 0:
        return False
    try:
        if os.name == "nt":
            import ctypes

            PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
            handle = ctypes.windll.kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid_int)
            if handle == 0:
                return False
            ctypes.windll.kernel32.CloseHandle(handle)
            return True
        os.kill(pid_int, 0)
        return True
    except Exception:
        return False


def load_runtime_snapshots(paths: MonitorPaths) -> dict[str, dict[str, Any]]:
    snapshots: dict[str, dict[str, Any]] = {}
    if not paths.runtime_runs.exists():
        return snapshots
    for task_dir in paths.runtime_runs.iterdir():
        if not task_dir.is_dir():
            continue
        latest: dict[str, Any] | None = None
        latest_key: tuple[float, str] | None = None
        for run_dir in task_dir.iterdir():
            if not run_dir.is_dir():
                continue
            state_path = run_dir / "state.json"
            meta_path = run_dir / "meta.json"
            state = JsonStore.load_json(state_path, {})
            meta = JsonStore.load_json(meta_path, {})
            if not state and not meta:
                continue
            updated = parse_dt(state.get("updated_at") or meta.get("started_at"))
            sort_key = ((updated.timestamp() if updated else run_dir.stat().st_mtime), run_dir.name)
            if latest_key is None or sort_key > latest_key:
                latest_key = sort_key
                latest = {
                    "task_id": state.get("task_id") or meta.get("task_id") or task_dir.name,
                    "run_id": state.get("run_id") or meta.get("run_id") or run_dir.name,
                    "worker": state.get("worker") or meta.get("worker") or "",
                    "engine": state.get("engine") or meta.get("engine") or "",
                    "workdir": state.get("workdir") or meta.get("workdir") or "",
                    "status": state.get("status") or "",
                    "phase": state.get("phase") or "",
                    "started_at": state.get("started_at") or meta.get("started_at") or "",
                    "updated_at": state.get("updated_at") or meta.get("started_at") or "",
                    "note": state.get("note") or "",
                    "exit_code": state.get("exit_code"),
                    "run_dir": str(run_dir),
                    "events_path": str(run_dir / "events.jsonl"),
                    "dispatch_prompt": str(run_dir / "dispatch-prompt.md"),
                }
        if latest:
            snapshots[task_dir.name] = latest
    return snapshots


BLOCKER_LABELS = {
    "runtime_orchestration": "运行编排",
    "env_service": "环境服务",
    "qa_evidence": "证据不合规",
    "code_contract_ui": "代码/契约/UI",
    "review_pending": "等待复审",
    "dispatch_dev": "待派开发",
    "dispatch_qa": "待派 QA",
    "archive_ready": "可归档",
    "observe": "观察中",
    "unknown": "未知",
}

BLOCKER_STYLES = {
    "runtime_orchestration": "bold red",
    "env_service": "bold red",
    "qa_evidence": "yellow",
    "code_contract_ui": "red",
    "review_pending": "green",
    "dispatch_dev": "cyan",
    "dispatch_qa": "bright_cyan",
    "archive_ready": "green",
    "observe": "cyan",
    "unknown": "white",
}


def localize_blocker(value: Any) -> str:
    raw = humanize_token(value)
    key = normalize_lookup_key(value)
    return BLOCKER_LABELS.get(key, raw)


def blocker_style(value: Any) -> str:
    return BLOCKER_STYLES.get(normalize_lookup_key(value), "white")


def style_blocker(value: Any) -> str:
    label = localize_blocker(value)
    return f"[{blocker_style(value)}]{label}[/]"


def coalesce_text(*values: Any) -> str:
    for value in values:
        if value is None:
            continue
        raw = str(value).strip()
        if raw:
            return raw
    return ""


def lower_blob(*values: Any) -> str:
    parts = [str(value).lower() for value in values if value]
    return " ".join(parts)


def delta_text(start: Any, end: Any) -> str:
    start_dt = parse_dt(start)
    end_dt = parse_dt(end)
    if not start_dt or not end_dt:
        return "-"
    secs = int(abs((end_dt - start_dt).total_seconds()))
    if secs < 60:
        return f"{secs}s"
    mins = secs // 60
    if mins < 60:
        return f"{mins}m"
    hours = mins // 60
    if hours < 48:
        return f"{hours}h"
    days = hours // 24
    return f"{days}d"


def infer_task_phase(task: dict[str, Any], runtime: dict[str, Any] | None = None) -> str:
    worker = lower_blob(task.get("worker"), (task.get("route_update") or {}).get("worker"), (runtime or {}).get("worker"))
    state = normalize_lookup_key(task.get("state"))
    if state in {"archiving", "completed"}:
        return "archive"
    if "qa" in worker or state in {"waiting_qa", "qa", "qa_passed"}:
        return "qa"
    return "dev"


def aggregate_delivery_events(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    events: dict[str, dict[str, Any]] = {}
    for row in rows:
        if not isinstance(row, dict):
            continue
        event_id = str(row.get("event_id") or f"{row.get('task')}-{row.get('run_id')}-{row.get('status')}-{row.get('at')}")
        at = parse_dt(row.get("at"))
        attempt = row.get("attempt")
        try:
            attempt_int = int(attempt)
        except Exception:
            attempt_int = 1
        entry = events.get(event_id)
        if entry is None:
            events[event_id] = {
                "event_id": event_id,
                "task": row.get("task") or "-",
                "worker": row.get("worker") or "-",
                "status": row.get("status") or row.get("action") or "-",
                "run_id": row.get("run_id") or "",
                "message": row.get("message") or "",
                "error": row.get("error") or "",
                "sent": row.get("sent"),
                "first_at": row.get("at") or "",
                "last_at": row.get("at") or "",
                "attempts": attempt_int,
                "pane_id": row.get("pane_id") or "",
            }
            continue
        first_at = parse_dt(entry.get("first_at"))
        last_at = parse_dt(entry.get("last_at"))
        if at and (not first_at or at < first_at):
            entry["first_at"] = row.get("at") or entry.get("first_at") or ""
        if at and (not last_at or at >= last_at):
            entry["last_at"] = row.get("at") or entry.get("last_at") or ""
            entry["status"] = row.get("status") or row.get("action") or entry.get("status") or "-"
            entry["message"] = row.get("message") or entry.get("message") or ""
            entry["error"] = row.get("error") or ""
            entry["sent"] = row.get("sent")
            entry["pane_id"] = row.get("pane_id") or entry.get("pane_id") or ""
        entry["attempts"] = max(int(entry.get("attempts") or 1), attempt_int)
    return sorted(events.values(), key=lambda item: parse_dt(item.get("last_at")) or datetime.min.replace(tzinfo=timezone.utc), reverse=True)


def classify_task(task: dict[str, Any], runtime: dict[str, Any] | None, delivery_event: dict[str, Any] | None) -> dict[str, Any]:
    state_key = normalize_lookup_key(task.get("state"))
    runtime_status = normalize_lookup_key((runtime or {}).get("status"))
    phase = infer_task_phase(task, runtime)
    dispatch_mode = normalize_lookup_key((runtime or {}).get("dispatch_mode") or task.get("dispatch_mode") or "")
    pid_alive = bool((runtime or {}).get("pid_alive")) if runtime else False
    route = task.get("route_update") or {}
    reason = coalesce_text(route.get("bodyPreview"), task.get("note"), (runtime or {}).get("note"), (delivery_event or {}).get("error"))
    blob = lower_blob(reason, task.get("note"), (runtime or {}).get("note"), route.get("bodyPreview"))
    env_markers = ("/health", "3033", "connection refused", "service unavailable", "port", "端口", "账号", "凭据", "seed", "env_restored", "health")
    evidence_markers = ("screenshot", "截图", "evidence", "证据", "has_5xx", "json", "结构化", "path", "不存在", "console", "network")
    runtime_markers = ("stale", "drift", "离线", "漂移", "restart-task", "run_id", "run_dir", "pid", "residue", "残留", "headless")
    category = "observe"
    suggestion = "等待新 route"
    priority = 500
    if state_key == "assigned":
        category, suggestion, priority = "dispatch_dev", "执行 dispatch", 60
    elif state_key == "waiting_qa":
        category, suggestion, priority = "dispatch_qa", "执行 dispatch-qa", 70
    elif state_key == "qa_passed":
        category, suggestion, priority = "archive_ready", "人工复审后 archive", 90
    elif state_key == "archiving":
        category, suggestion, priority = "observe", "等待 doc-updater / repo-committer", 110
    elif state_key in {"in_progress", "qa"}:
        if runtime_status in {"failed", "fail", "error"}:
            category, suggestion, priority = "runtime_orchestration", "restart-task 后重派", 18
        elif dispatch_mode == "headless" and runtime_status == "success" and not pid_alive:
            category, suggestion, priority = "observe", "等待 route 收口", 120
        elif runtime and runtime.get("pid") and not pid_alive:
            category, suggestion, priority = "runtime_orchestration", "restart-task 后重派", 20
        elif delivery_event and delivery_event.get("sent") is False:
            category, suggestion, priority = "observe", "route 已收口，检查 notifier 投递失败", 140
    elif state_key in {"blocked", "fail", "failed"}:
        if any(marker in blob for marker in env_markers):
            category, suggestion, priority = "env_service", "先恢复环境/服务，再重派", 22
        elif any(marker in blob for marker in evidence_markers):
            category, suggestion, priority = "qa_evidence", "先补证据，再重派 QA", 24
        elif any(marker in blob for marker in runtime_markers):
            category, suggestion, priority = "runtime_orchestration", "restart-task 后重派", 20
        elif phase == "qa":
            category, suggestion, priority = "code_contract_ui", "回开发修复后再验收", 30
        else:
            category, suggestion, priority = "code_contract_ui", "先人工确认原因，再决定是否回开发", 35
    elif state_key == "completed":
        category, suggestion, priority = "observe", "已完成", 900
    return {
        "task_id": task.get("task_id") or "-",
        "state": task.get("state") or "",
        "phase": phase,
        "category": category,
        "suggestion": suggestion,
        "reason": reason or "-",
        "priority": priority,
        "updated_at": task.get("updated_at") or (runtime or {}).get("updated_at") or "",
        "delivery_sent": None if delivery_event is None else delivery_event.get("sent"),
    }


def build_decision_queue(tasks: list[dict[str, Any]], runtime_map: dict[str, dict[str, Any]], delivery_by_task: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    queue: list[dict[str, Any]] = []
    for task in tasks:
        task_id = task.get("task_id") or ""
        entry = classify_task(task, runtime_map.get(task_id), delivery_by_task.get(task_id))
        actionable = entry["category"] != "observe" or normalize_lookup_key(task.get("state")) in {"blocked", "fail", "failed", "assigned", "waiting_qa", "qa_passed"}
        if actionable:
            queue.append(entry)
    queue.sort(key=lambda item: (item.get("priority", 999), -((parse_dt(item.get("updated_at")) or datetime.min.replace(tzinfo=timezone.utc)).timestamp())))
    return queue


def collect_state(paths: MonitorPaths, args: argparse.Namespace) -> dict[str, Any]:
    locks_doc = JsonStore.load_json(paths.task_locks, {"locks": {}})
    attempts_doc = JsonStore.load_json(paths.attempts, {"attempts": []})
    route_monitor = JsonStore.load_json(paths.route_monitor_state, {})
    route_notifier = JsonStore.load_json(paths.route_notifier_state, {})
    worker_panels = JsonStore.load_json(paths.worker_panels, {"workers": {}})
    approval_state = JsonStore.load_json(paths.approval_state, {})
    approval_requests = JsonStore.load_json(paths.approval_requests, [])
    deliveries = JsonStore.load_jsonl(paths.delivery_log, limit=max(args.max_deliveries * 6, 80))
    failures = JsonStore.load_jsonl(paths.delivery_failures, limit=max(args.max_deliveries * 6, 80))
    runtime_snapshots = load_runtime_snapshots(paths)

    locks: dict[str, Any] = locks_doc.get("locks") or {}
    attempts: list[dict[str, Any]] = attempts_doc.get("attempts") or []
    workers: dict[str, Any] = (worker_panels.get("workers") or {}) if isinstance(worker_panels, dict) else {}

    tasks: list[dict[str, Any]] = []
    for task_id, lock in locks.items():
        if args.task and task_id != args.task:
            continue
        state = str(lock.get("state") or "")
        active = state not in {"completed"}
        if (not args.all_tasks) and (not active):
            continue
        tasks.append(
            {
                "task_id": task_id,
                "state": state,
                "runner": lock.get("runner") or "",
                "worker": lock.get("assigned_worker") or "",
                "dispatch_mode": lock.get("dispatch_mode") or ("headless" if lock.get("headless_run_dir") else "pane" if lock.get("pane_id") else ""),
                "updated_at": lock.get("updated_at") or "",
                "note": lock.get("note") or "",
                "run_id": lock.get("run_id") or "",
                "route_update": lock.get("routeUpdate") or {},
                "pane_id": lock.get("pane_id") or "",
                "headless_run_dir": lock.get("headless_run_dir") or "",
                "headless_pid": lock.get("headless_pid") or 0,
                "raw": lock,
            }
        )

    if not tasks and not args.task:
        for task_id, lock in locks.items():
            tasks.append(
                {
                    "task_id": task_id,
                    "state": str(lock.get("state") or ""),
                    "runner": lock.get("runner") or "",
                    "worker": lock.get("assigned_worker") or "",
                    "dispatch_mode": lock.get("dispatch_mode") or "",
                    "updated_at": lock.get("updated_at") or "",
                    "note": lock.get("note") or "",
                    "run_id": lock.get("run_id") or "",
                    "route_update": lock.get("routeUpdate") or {},
                    "pane_id": lock.get("pane_id") or "",
                    "headless_run_dir": lock.get("headless_run_dir") or "",
                    "headless_pid": lock.get("headless_pid") or 0,
                    "raw": lock,
                }
            )

    tasks.sort(key=lambda item: (parse_dt(item["updated_at"]) or datetime.min.replace(tzinfo=timezone.utc)).timestamp(), reverse=True)
    if args.max_tasks > 0:
        tasks = tasks[: args.max_tasks]

    runtime_rows: list[dict[str, Any]] = []
    for task in tasks:
        task_id = task["task_id"]
        runtime = runtime_snapshots.get(task_id)
        if not runtime and task.get("headless_run_dir"):
            state_path = Path(task["headless_run_dir"]) / "state.json"
            meta_path = Path(task["headless_run_dir"]) / "meta.json"
            state_doc = JsonStore.load_json(state_path, {})
            meta_doc = JsonStore.load_json(meta_path, {})
            if state_doc or meta_doc:
                runtime = {
                    "task_id": task_id,
                    "run_id": state_doc.get("run_id") or meta_doc.get("run_id") or task.get("run_id"),
                    "worker": state_doc.get("worker") or meta_doc.get("worker") or task.get("worker"),
                    "engine": state_doc.get("engine") or meta_doc.get("engine") or task.get("runner"),
                    "workdir": state_doc.get("workdir") or meta_doc.get("workdir") or "",
                    "status": state_doc.get("status") or "",
                    "phase": state_doc.get("phase") or "",
                    "started_at": state_doc.get("started_at") or meta_doc.get("started_at") or "",
                    "updated_at": state_doc.get("updated_at") or meta_doc.get("started_at") or "",
                    "note": state_doc.get("note") or "",
                    "exit_code": state_doc.get("exit_code"),
                    "run_dir": task["headless_run_dir"],
                }
        if runtime:
            pid = task.get("headless_pid") or 0
            runtime_rows.append(
                {
                    **runtime,
                    "pid": pid,
                    "pid_alive": process_alive(pid),
                    "dispatch_mode": task.get("dispatch_mode") or "headless",
                    "lock_state": task.get("state") or "",
                }
            )
        elif task.get("worker") or task.get("dispatch_mode"):
            runtime_rows.append(
                {
                    "task_id": task_id,
                    "run_id": task.get("run_id") or "",
                    "worker": task.get("worker") or "",
                    "engine": task.get("runner") or "",
                    "workdir": "",
                    "status": task.get("state") or "",
                    "phase": task.get("dispatch_mode") or "",
                    "started_at": "",
                    "updated_at": task.get("updated_at") or "",
                    "note": task.get("note") or "",
                    "exit_code": None,
                    "run_dir": task.get("headless_run_dir") or "",
                    "pid": task.get("headless_pid") or 0,
                    "pid_alive": process_alive(task.get("headless_pid") or 0),
                    "dispatch_mode": task.get("dispatch_mode") or "pane",
                    "lock_state": task.get("state") or "",
                }
            )

    runtime_rows.sort(key=lambda item: (parse_dt(item.get("updated_at")) or datetime.min.replace(tzinfo=timezone.utc)).timestamp(), reverse=True)
    runtime_map = {row.get("task_id"): row for row in runtime_rows if row.get("task_id")}
    task_map = {task.get("task_id"): task for task in tasks if task.get("task_id")}

    all_delivery_rows = sorted(deliveries + failures, key=lambda item: parse_dt(item.get("at")) or datetime.min.replace(tzinfo=timezone.utc), reverse=True)
    if args.task:
        all_delivery_rows = [item for item in all_delivery_rows if item.get("task") == args.task]
    delivery_events = aggregate_delivery_events(all_delivery_rows)
    delivery_by_task: dict[str, dict[str, Any]] = {}
    for event in delivery_events:
        task_id = event.get("task") or ""
        if task_id and task_id not in delivery_by_task:
            delivery_by_task[task_id] = event
        task = task_map.get(task_id)
        event["notify_span"] = delta_text(event.get("first_at"), event.get("last_at"))
        event["lock_to_notify_lag"] = delta_text(task.get("updated_at") if task else None, event.get("first_at"))
    recent_deliveries = delivery_events[: args.max_deliveries]

    filtered_attempts = attempts
    if args.task:
        filtered_attempts = [item for item in attempts if item.get("task_id") == args.task]
    recent_attempts = sorted(filtered_attempts, key=lambda item: parse_dt(item.get("started_at")) or datetime.min.replace(tzinfo=timezone.utc), reverse=True)[: args.max_attempts]

    active_approval_count = 0
    if isinstance(approval_requests, list):
        active_approval_count = len([item for item in approval_requests if str(item.get("status") or "pending") == "pending"])

    decision_queue = build_decision_queue(tasks, runtime_map, delivery_by_task)

    return {
        "paths": paths,
        "tasks": tasks,
        "task_map": task_map,
        "runtime_rows": runtime_rows,
        "runtime_map": runtime_map,
        "deliveries": recent_deliveries,
        "delivery_events": delivery_events,
        "delivery_by_task": delivery_by_task,
        "decision_queue": decision_queue,
        "attempts": recent_attempts,
        "route_monitor": route_monitor,
        "route_notifier": route_notifier,
        "workers": workers,
        "approval_state": approval_state,
        "approval_count": active_approval_count,
        "locks_updated_at": locks_doc.get("updated_at") or "",
        "attempts_updated_at": attempts_doc.get("updated_at") or "",
    }


def make_header(state: dict[str, Any], args: argparse.Namespace) -> Panel:
    tasks = state["tasks"]
    counts = Counter(task["state"] or "unknown" for task in tasks)
    runtime_rows = state["runtime_rows"]
    running_headless = sum(1 for row in runtime_rows if row.get("dispatch_mode") == "headless" and row.get("pid_alive"))
    blocked = counts.get("blocked", 0)
    qa_passed = counts.get("qa_passed", 0)
    assigned = counts.get("assigned", 0)
    waiting_qa = counts.get("waiting_qa", 0)
    in_progress = counts.get("in_progress", 0)
    pending_decisions = len(state.get("decision_queue") or [])
    delivery_failures = len([item for item in state.get("delivery_events") or [] if item.get("sent") is False])

    title = Text("Moxton-CCB 指挥看板", style="bold cyan")
    subtitle = Text()
    subtitle.append(f"根目录={state['paths'].root}  ", style="dim")
    subtitle.append(f"刷新={args.refresh:.1f}s  ")
    subtitle.append(f"任务锁={len(tasks)}  ")
    subtitle.append(f"待决策={pending_decisions}  ", style="bold yellow" if pending_decisions else "green")
    subtitle.append(f"无头运行={running_headless}  ", style="yellow" if running_headless else "dim")
    subtitle.append(f"阻塞={blocked}  ", style="red" if blocked else "green")
    subtitle.append(f"通知失败={delivery_failures}  ", style="red" if delivery_failures else "green")
    subtitle.append(f"待开发={assigned}  待 QA={waiting_qa}  QA通过={qa_passed}  进行中={in_progress}")
    if args.task:
        subtitle.append(f"  焦点任务={args.task}", style="bold cyan")
    group = Group(title, subtitle)
    return Panel(group, border_style="cyan")


def make_decision_panel(state: dict[str, Any], *, limit: int = 8) -> Panel:
    table = Table(expand=True, box=None)
    table.add_column("任务", style="bold", no_wrap=True)
    table.add_column("阶段", no_wrap=True)
    table.add_column("分类", no_wrap=True)
    table.add_column("建议", no_wrap=True)
    table.add_column("原因")

    queue = state.get("decision_queue") or []
    if not queue:
        table.add_row("-", "-", style_blocker("observe"), "当前无待决策项", "等待新的 route / runtime 变化")
    else:
        for item in queue[:limit]:
            table.add_row(
                item.get("task_id") or "-",
                localize_phase(item.get("phase") or "-"),
                style_blocker(item.get("category") or "unknown"),
                item.get("suggestion") or "-",
                shorten(item.get("reason") or "-", 72),
            )
    return Panel(table, title="待决策队列 / Team Lead 下一步", border_style="bright_yellow")


def make_tasks_panel(state: dict[str, Any]) -> Panel:
    table = Table(expand=True, box=None)
    table.add_column("任务", style="bold")
    table.add_column("状态", no_wrap=True)
    table.add_column("执行者")
    table.add_column("建议", no_wrap=True)
    table.add_column("摘要")

    tasks = state["tasks"]
    decisions = {item.get("task_id"): item for item in state.get("decision_queue") or []}
    if not tasks:
        table.add_row("-", "-", "-", "-", "没有符合条件的任务")
    for task in tasks:
        route = task.get("route_update") or {}
        summary = route.get("bodyPreview") or task.get("note") or ""
        worker = task.get("worker") or route.get("worker") or "-"
        updated = age_text(task.get("updated_at"))
        task_label = task["task_id"]
        if task.get("run_id"):
            task_label = f"{task_label}\n[dim]{shorten(task.get('run_id'), 34)}[/]"
        decision = decisions.get(task.get("task_id"), {})
        suggestion = decision.get("suggestion") or localize_mode(task.get("dispatch_mode") or ("headless" if task.get("headless_run_dir") else "-"))
        table.add_row(
            task_label,
            f"{style_state(task.get('state') or '')} [dim]{updated}[/]",
            worker,
            suggestion,
            shorten(summary, 64),
        )
    title = f"任务总览 / TASK-LOCKS  更新={age_text(state.get('locks_updated_at'))}"
    return Panel(table, title=title, border_style="blue")


def make_runtime_panel(state: dict[str, Any], *, limit: int = 12) -> Panel:
    table = Table(expand=True, box=None)
    table.add_column("任务", style="bold")
    table.add_column("执行者")
    table.add_column("引擎/模式", no_wrap=True)
    table.add_column("运行态")
    table.add_column("PID")
    table.add_column("心跳")
    table.add_column("备注")

    rows = state["runtime_rows"]
    if not rows:
        table.add_row("-", "-", "-", "-", "-", "-", "当前无活跃运行态")
    for row in rows[:limit]:
        runtime_state = row.get("status") or row.get("lock_state") or "-"
        phase = row.get("phase") or row.get("dispatch_mode") or "-"
        pid = row.get("pid") or 0
        pid_text = "-"
        if pid:
            pid_text = f"{pid} {'存活' if row.get('pid_alive') else '已退出'}"
        note = row.get("note") or path_tail(row.get("run_dir"), 2)
        engine_mode = f"{humanize_token(row.get('engine') or '-')}/{localize_mode(row.get('dispatch_mode') or '-')}"
        runtime_label = f"{style_state(runtime_state)} / {localize_phase(phase)}"
        table.add_row(
            row.get("task_id") or "-",
            row.get("worker") or "-",
            engine_mode,
            runtime_label,
            pid_text,
            age_text(row.get("updated_at")),
            shorten(note, 52),
        )
    return Panel(table, title="Worker / Headless 运行态", border_style="magenta")


def make_delivery_panel(state: dict[str, Any], *, limit: int = 8) -> Panel:
    table = Table(expand=True, box=None)
    table.add_column("时间")
    table.add_column("任务")
    table.add_column("状态")
    table.add_column("投递")
    table.add_column("重试")
    table.add_column("滞后")
    table.add_column("消息")

    rows = state.get("deliveries") or []
    if not rows:
        table.add_row("-", "-", "-", "-", "-", "-", "最近没有 route/notifier 事件")
    for row in rows[:limit]:
        sent = row.get("sent")
        delivery = "已送达" if sent is True else "失败" if sent is False else "-"
        if row.get("error"):
            delivery = f"{delivery}:{shorten(row.get('error'), 16)}"
        table.add_row(
            age_text(row.get("last_at")),
            row.get("task") or "-",
            style_state(row.get("status") or "-"),
            delivery,
            str(row.get("attempts") or 1),
            row.get("lock_to_notify_lag") or "-",
            shorten(row.get("message") or "", 68),
        )
    return Panel(table, title="最近 Route / Team Lead 通知", border_style="green")


def make_attempts_panel(state: dict[str, Any], *, limit: int = 10) -> Panel:
    table = Table(expand=True, box=None)
    table.add_column("开始")
    table.add_column("任务")
    table.add_column("阶段")
    table.add_column("结果")
    table.add_column("原因")

    attempts = state["attempts"]
    if not attempts:
        table.add_row("-", "-", "-", "-", "最近没有 attempt")
    for item in attempts[:limit]:
        table.add_row(
            age_text(item.get("started_at")),
            item.get("task_id") or "-",
            localize_phase(item.get("phase") or "-"),
            style_state(item.get("result") or "-"),
            shorten(item.get("requeue_reason") or item.get("updated_by") or "", 40),
        )
    title = f"最近尝试  更新={age_text(state.get('attempts_updated_at'))}"
    return Panel(table, title=title, border_style="yellow")


def watcher_line(name: str, doc: dict[str, Any]) -> Text:
    text = Text()
    status = str(doc.get("status") or "unknown")
    lag = age_text(doc.get("last_loop_at"))
    pane = doc.get("monitor_pane_id") or doc.get("notifier_pane_id") or "-"
    pid = doc.get("pid") or "-"
    note = shorten(doc.get("note") or "", 70)
    text.append(f"{name}：")
    text.append(localize_state(status), style=state_style(status))
    text.append(f"  间隔={lag}  PID={pid}  Pane={pane}")
    if note:
        text.append(f"  备注={note}", style="dim")
    return text


def make_summary_panel(state: dict[str, Any]) -> Panel:
    workers = state["workers"] or {}
    blocked_tasks = [task for task in state["tasks"] if (task.get("state") or "") == "blocked"]
    alive_runtime = sum(1 for row in state["runtime_rows"] if row.get("pid_alive"))
    failed_deliveries = [row for row in state.get("delivery_events") or [] if row.get("sent") is False]
    lines: list[Any] = [
        watcher_line("route-monitor", state.get("route_monitor") or {}),
        watcher_line("route-notifier", state.get("route_notifier") or {}),
        Text(f"worker注册={len(workers)}  活跃运行态={alive_runtime}  阻塞任务={len(blocked_tasks)}  通知失败={len(failed_deliveries)}"),
    ]

    if failed_deliveries:
        lines.append(Text("通知失败：", style="bold red"))
        for row in failed_deliveries[:3]:
            lines.append(Text(f"- {row.get('task') or '-'} {shorten(row.get('error') or row.get('message') or '', 88)}"))
    else:
        lines.append(Text("通知失败：无", style="green"))

    if blocked_tasks:
        lines.append(Text("阻塞任务：", style="bold red"))
        for task in blocked_tasks[:4]:
            route = task.get("route_update") or {}
            lines.append(Text(f"- {task['task_id']} {shorten(route.get('bodyPreview') or task.get('note') or '', 88)}"))
    else:
        lines.append(Text("阻塞任务：无", style="green"))

    return Panel(Group(*lines), title="监控摘要 / 告警", border_style="red")


def make_focus_panel(state: dict[str, Any], args: argparse.Namespace) -> Panel:
    task_id = args.task
    task = (state.get("task_map") or {}).get(task_id)
    runtime = (state.get("runtime_map") or {}).get(task_id)
    decision = next((item for item in state.get("decision_queue") or [] if item.get("task_id") == task_id), None)
    delivery = (state.get("delivery_by_task") or {}).get(task_id)

    if not task:
        return Panel("未找到焦点任务", title="任务诊断", border_style="yellow")

    lines: list[Any] = []
    lines.append(Text(f"状态：{localize_state(task.get('state') or '-')}    阶段：{localize_phase((decision or {}).get('phase') or infer_task_phase(task, runtime))}", style="bold"))
    if decision:
        lines.append(Text.assemble("分类：", (localize_blocker(decision.get("category") or "unknown"), blocker_style(decision.get("category") or "unknown")), "    建议：", (decision.get("suggestion") or "-", "bold yellow")))
    lines.append(Text(f"执行者：{task.get('worker') or (runtime or {}).get('worker') or '-'}    模式：{localize_mode(task.get('dispatch_mode') or (runtime or {}).get('dispatch_mode') or '-')}    引擎：{(runtime or {}).get('engine') or task.get('runner') or '-'}"))
    lines.append(Text(f"run_id：{task.get('run_id') or (runtime or {}).get('run_id') or '-'}"))
    lines.append(Text(f"任务更新：{age_text(task.get('updated_at'))}    运行心跳：{age_text((runtime or {}).get('updated_at'))}    PID：{(runtime or {}).get('pid') or '-'}"))
    if (runtime or {}).get("run_dir"):
        lines.append(Text(f"run_dir：{(runtime or {}).get('run_dir')}", style="dim"))
    if delivery:
        lines.append(Text(f"最近通知：{age_text(delivery.get('last_at'))}    投递：{'已送达' if delivery.get('sent') is True else '失败' if delivery.get('sent') is False else '-'}    重试：{delivery.get('attempts') or 1}    滞后：{delivery.get('lock_to_notify_lag') or '-'}"))
    summary = coalesce_text((task.get("route_update") or {}).get("bodyPreview"), task.get("note"), (runtime or {}).get("note"), (decision or {}).get("reason"))
    lines.append(Text(f"摘要：{shorten(summary or '-', 220)}"))

    return Panel(Group(*lines), title=f"焦点任务诊断 / {task_id}", border_style="bright_cyan")


def render_dashboard(state: dict[str, Any], args: argparse.Namespace) -> Layout:
    layout = Layout(name="root")
    if args.task:
        layout.split_column(
            Layout(name="header", size=3),
            Layout(name="body"),
            Layout(name="footer", size=12),
        )
        layout["body"].split_row(
            Layout(name="left", ratio=3),
            Layout(name="right", ratio=2),
        )
        layout["left"].split_column(
            Layout(name="focus", size=9),
            Layout(name="runtime"),
        )
        layout["right"].split_column(
            Layout(name="decisions", size=9),
            Layout(name="summary"),
        )
        layout["footer"].split_row(
            Layout(name="deliveries"),
            Layout(name="attempts"),
        )
        layout["header"].update(make_header(state, args))
        layout["focus"].update(make_focus_panel(state, args))
        layout["runtime"].update(make_runtime_panel(state, limit=8))
        layout["decisions"].update(make_decision_panel(state, limit=6))
        layout["summary"].update(make_summary_panel(state))
        layout["deliveries"].update(make_delivery_panel(state, limit=max(8, args.max_deliveries)))
        layout["attempts"].update(make_attempts_panel(state, limit=max(8, args.max_attempts)))
        return layout

    layout.split_column(
        Layout(name="header", size=3),
        Layout(name="body"),
        Layout(name="footer", size=12),
    )
    layout["body"].split_row(
        Layout(name="left", ratio=3),
        Layout(name="right", ratio=2),
    )
    layout["left"].split_column(
        Layout(name="decisions", size=10),
        Layout(name="tasks"),
    )
    layout["right"].split_column(
        Layout(name="runtime", ratio=2),
        Layout(name="summary", ratio=1),
    )
    layout["footer"].split_row(
        Layout(name="deliveries"),
        Layout(name="attempts"),
    )

    layout["header"].update(make_header(state, args))
    layout["decisions"].update(make_decision_panel(state))
    layout["tasks"].update(make_tasks_panel(state))
    layout["runtime"].update(make_runtime_panel(state))
    layout["summary"].update(make_summary_panel(state))
    layout["deliveries"].update(make_delivery_panel(state))
    layout["attempts"].update(make_attempts_panel(state))
    return layout


def main() -> int:
    args = parse_args()
    paths = build_paths(args.root.resolve())
    console = Console()

    started_at = datetime.now().astimezone().isoformat()

    def build() -> Layout:
        state = collect_state(paths, args)
        write_monitor_state(
            paths,
            args,
            started_at=started_at,
            status="running" if not args.once else "snapshot",
            visible_tasks=len(state.get("tasks") or []),
        )
        return render_dashboard(state, args)

    if args.once:
        console.print(build())
        return 0

    write_monitor_state(paths, args, started_at=started_at, status="starting")
    with Live(build(), console=console, refresh_per_second=max(1, int(round(1 / max(args.refresh, 0.2)))), screen=True) as live:
        while True:
            time.sleep(max(args.refresh, 0.2))
            live.update(build())


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(0)