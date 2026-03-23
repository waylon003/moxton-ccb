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
    "success": "green",
    "running": "yellow",
    "dispatched": "cyan",
}


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
    return STATE_STYLES.get((state or "").strip().lower(), "white")


def style_state(state: str) -> str:
    label = state or "-"
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


def collect_state(paths: MonitorPaths, args: argparse.Namespace) -> dict[str, Any]:
    locks_doc = JsonStore.load_json(paths.task_locks, {"locks": {}})
    attempts_doc = JsonStore.load_json(paths.attempts, {"attempts": []})
    route_monitor = JsonStore.load_json(paths.route_monitor_state, {})
    route_notifier = JsonStore.load_json(paths.route_notifier_state, {})
    worker_panels = JsonStore.load_json(paths.worker_panels, {"workers": {}})
    approval_state = JsonStore.load_json(paths.approval_state, {})
    approval_requests = JsonStore.load_json(paths.approval_requests, [])
    deliveries = JsonStore.load_jsonl(paths.delivery_log, limit=max(args.max_deliveries * 3, 40))
    failures = JsonStore.load_jsonl(paths.delivery_failures, limit=max(args.max_deliveries * 3, 40))
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

    recent_deliveries = sorted(deliveries + failures, key=lambda item: parse_dt(item.get("at")) or datetime.min.replace(tzinfo=timezone.utc), reverse=True)
    if args.task:
        recent_deliveries = [item for item in recent_deliveries if item.get("task") == args.task]
    recent_deliveries = recent_deliveries[: args.max_deliveries]

    filtered_attempts = attempts
    if args.task:
        filtered_attempts = [item for item in attempts if item.get("task_id") == args.task]
    recent_attempts = sorted(filtered_attempts, key=lambda item: parse_dt(item.get("started_at")) or datetime.min.replace(tzinfo=timezone.utc), reverse=True)[: args.max_attempts]

    active_approval_count = 0
    if isinstance(approval_requests, list):
        active_approval_count = len([item for item in approval_requests if str(item.get("status") or "pending") == "pending"])

    return {
        "paths": paths,
        "tasks": tasks,
        "runtime_rows": runtime_rows,
        "deliveries": recent_deliveries,
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
    title = Text("Moxton-CCB Rich 监控台", style="bold cyan")
    subtitle = Text()
    subtitle.append(f"root={state['paths'].root}  ")
    subtitle.append(f"refresh={args.refresh:.1f}s  ")
    subtitle.append(f"locks={len(tasks)}  ")
    subtitle.append(f"running_headless={running_headless}  ", style="yellow")
    subtitle.append(f"blocked={blocked}  ", style="red" if blocked else "green")
    subtitle.append(f"assigned={assigned}  waiting_qa={waiting_qa}  qa_passed={qa_passed}  in_progress={in_progress}")
    group = Group(title, subtitle)
    return Panel(group, border_style="cyan")


def make_tasks_panel(state: dict[str, Any]) -> Panel:
    table = Table(expand=True, box=None)
    table.add_column("Task", style="bold")
    table.add_column("State", no_wrap=True)
    table.add_column("Worker")
    table.add_column("Mode", no_wrap=True)
    table.add_column("更新")
    table.add_column("摘要")

    tasks = state["tasks"]
    if not tasks:
        table.add_row("-", "-", "-", "-", "-", "没有符合条件的任务")
    for task in tasks:
        route = task.get("route_update") or {}
        summary = route.get("bodyPreview") or task.get("note") or ""
        worker = task.get("worker") or route.get("worker") or "-"
        mode = task.get("dispatch_mode") or ("headless" if task.get("headless_run_dir") else "-")
        updated = age_text(task.get("updated_at"))
        task_label = task["task_id"]
        if task.get("run_id"):
            task_label = f"{task_label}\n[dim]{shorten(task.get('run_id'), 34)}[/]"
        table.add_row(
            task_label,
            style_state(task.get("state") or ""),
            worker,
            mode,
            updated,
            shorten(summary, 72),
        )
    title = f"任务锁 / TASK-LOCKS  更新={age_text(state.get('locks_updated_at'))}"
    return Panel(table, title=title, border_style="blue")


def make_runtime_panel(state: dict[str, Any]) -> Panel:
    table = Table(expand=True, box=None)
    table.add_column("Task", style="bold")
    table.add_column("Worker")
    table.add_column("Runtime")
    table.add_column("PID")
    table.add_column("更新")
    table.add_column("Note")

    rows = state["runtime_rows"]
    if not rows:
        table.add_row("-", "-", "-", "-", "-", "当前无活跃运行态")
    for row in rows[:12]:
        runtime_state = row.get("status") or row.get("lock_state") or "-"
        phase = row.get("phase") or row.get("dispatch_mode") or "-"
        pid = row.get("pid") or 0
        pid_text = "-"
        if pid:
            pid_text = f"{pid} {'alive' if row.get('pid_alive') else 'gone'}"
        note = row.get("note") or path_tail(row.get("run_dir"), 2)
        runtime_label = f"{style_state(runtime_state)} / {phase}"
        table.add_row(
            row.get("task_id") or "-",
            row.get("worker") or "-",
            runtime_label,
            pid_text,
            age_text(row.get("updated_at")),
            shorten(note, 62),
        )
    return Panel(table, title="Worker / Headless 运行态", border_style="magenta")


def make_delivery_panel(state: dict[str, Any]) -> Panel:
    table = Table(expand=True, box=None)
    table.add_column("时间")
    table.add_column("Task")
    table.add_column("Status")
    table.add_column("送达")
    table.add_column("消息")

    rows = state["deliveries"]
    if not rows:
        table.add_row("-", "-", "-", "-", "最近没有 route/notifier 事件")
    for row in rows:
        status = row.get("status") or row.get("action") or "-"
        sent = row.get("sent")
        delivery = "ok" if sent is True else "fail" if sent is False else "-"
        if row.get("error"):
            delivery = f"{delivery}:{shorten(row.get('error'), 18)}"
        table.add_row(
            age_text(row.get("at")),
            row.get("task") or "-",
            style_state(status),
            delivery,
            shorten(row.get("message") or "", 76),
        )
    return Panel(table, title="最近 Route / Team Lead 通知", border_style="green")


def make_attempts_panel(state: dict[str, Any]) -> Panel:
    table = Table(expand=True, box=None)
    table.add_column("开始")
    table.add_column("Task")
    table.add_column("Phase")
    table.add_column("Result")
    table.add_column("Reason")

    attempts = state["attempts"]
    if not attempts:
        table.add_row("-", "-", "-", "-", "最近没有 attempt")
    for item in attempts:
        table.add_row(
            age_text(item.get("started_at")),
            item.get("task_id") or "-",
            item.get("phase") or "-",
            style_state(item.get("result") or "-"),
            shorten(item.get("requeue_reason") or item.get("updated_by") or "", 40),
        )
    title = f"最近 Attempts  更新={age_text(state.get('attempts_updated_at'))}"
    return Panel(table, title=title, border_style="yellow")


def watcher_line(name: str, doc: dict[str, Any]) -> Text:
    text = Text()
    status = str(doc.get("status") or "unknown")
    lag = age_text(doc.get("last_loop_at"))
    pane = doc.get("monitor_pane_id") or doc.get("notifier_pane_id") or "-"
    pid = doc.get("pid") or "-"
    note = shorten(doc.get("note") or "", 70)
    text.append(f"{name}: ")
    text.append(status, style=state_style(status))
    text.append(f"  lag={lag}  pid={pid}  pane={pane}")
    if note:
        text.append(f"  note={note}", style="dim")
    return text


def make_summary_panel(state: dict[str, Any]) -> Panel:
    workers = state["workers"] or {}
    approval_state = state.get("approval_state") or {}
    local_pending = 0
    if isinstance(approval_state, dict):
        for value in approval_state.values():
            if isinstance(value, dict) and str(value.get("status") or "") == "pending":
                local_pending += 1

    blocked_tasks = [task for task in state["tasks"] if (task.get("state") or "") == "blocked"]
    lines: list[Any] = [
        watcher_line("route-monitor", state.get("route_monitor") or {}),
        watcher_line("route-notifier", state.get("route_notifier") or {}),
        Text(f"worker registry={len(workers)}  approval_requests={state.get('approval_count', 0)}  local_pending={local_pending}")
    ]

    if blocked_tasks:
        lines.append(Text("阻塞任务:", style="bold red"))
        for task in blocked_tasks[:5]:
            route = task.get("route_update") or {}
            lines.append(Text(f"- {task['task_id']} {shorten(route.get('bodyPreview') or task.get('note') or '', 88)}"))
    else:
        lines.append(Text("阻塞任务: 无", style="green"))

    return Panel(Group(*lines), title="监控器 / 告警摘要", border_style="red")


def render_dashboard(state: dict[str, Any], args: argparse.Namespace) -> Layout:
    layout = Layout(name="root")
    layout.split_column(
        Layout(name="header", size=3),
        Layout(name="body"),
        Layout(name="footer", size=12),
    )
    layout["body"].split_row(
        Layout(name="tasks", ratio=3),
        Layout(name="right", ratio=2),
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