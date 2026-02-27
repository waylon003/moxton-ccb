import scripts.assign_task as assign_task


class DummyResult:
    def __init__(self, returncode: int, stdout: str = "", stderr: str = "") -> None:
        self.returncode = returncode
        self.stdout = stdout
        self.stderr = stderr


def test_ccb_ping_success_and_failure(monkeypatch):
    def fake_run(cmd, capture_output, text, timeout):  # noqa: ANN001
        if cmd == ["ping", "backend-dev"]:
            return DummyResult(0, "pong")
        return DummyResult(1, "offline")

    monkeypatch.setattr(assign_task.subprocess, "run", fake_run)

    assert assign_task.ccb_ping("backend-dev") is True
    assert assign_task.ccb_ping("nonexistent-worker") is False


def test_ccb_ask_success(monkeypatch):
    def fake_run(cmd, capture_output, text, timeout):  # noqa: ANN001
        assert cmd[0] == "ask"
        return DummyResult(0, "ok")

    monkeypatch.setattr(assign_task.subprocess, "run", fake_run)

    assert assign_task.ccb_ask("backend-dev", "hello") is True


def test_ccb_pend_returns_response(monkeypatch):
    def fake_run(cmd, capture_output, text, timeout):  # noqa: ANN001
        assert cmd == ["pend", "backend-dev"]
        assert timeout == 10
        return DummyResult(0, "done\n")

    monkeypatch.setattr(assign_task.subprocess, "run", fake_run)

    assert assign_task.ccb_pend("backend-dev", timeout=10) == "done"


def test_ccb_pend_returns_none_on_failure(monkeypatch):
    def fake_run(cmd, capture_output, text, timeout):  # noqa: ANN001
        return DummyResult(1, "")

    monkeypatch.setattr(assign_task.subprocess, "run", fake_run)

    assert assign_task.ccb_pend("backend-dev", timeout=10) is None
