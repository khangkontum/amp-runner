#!/usr/bin/env python3
"""Exercise the real helper under launchd, using a fake Amp and disposable folders."""
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import time
import uuid


def wait_for(predicate, description, timeout=20):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.2)
    raise AssertionError(description)


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


repo = Path(__file__).resolve().parent.parent
subprocess.run(["swift", "build", "--package-path", str(repo)], check=True)
binary = Path(subprocess.check_output(
    ["swift", "build", "--package-path", str(repo), "--show-bin-path"], text=True).strip()) / "AmpRunnerService"
label = "com.local.AmpRunner.smoke." + uuid.uuid4().hex
domain = f"gui/{os.getuid()}"
target = f"{domain}/{label}"

with tempfile.TemporaryDirectory(prefix="amp-runner-smoke-") as directory:
    root = Path(directory)
    workspace = root / "Workspace"
    workspace.mkdir()
    project = root / "project with 'quotes' & spaces"
    project.mkdir()
    sentinel = project / "keep.txt"
    sentinel.write_text("never delete project files")
    fake = root / "fake-amp"
    fake.write_text('''#!/usr/bin/python3
import json, os, sys, time
from pathlib import Path
root = Path.cwd().parent
args = sys.argv[1:]
if args[0] == "--no-tui":
    (root / "runner.pid").write_text(str(os.getpid()))
    while True: time.sleep(1)
assert args[:2] == ["runner", "dirs"]
assert args[-2:] == ["--runner-id", "smoke-runner"]
state = root / "fake-state.json"
paths = json.loads(state.read_text()) if state.exists() else []
action = args[2]
if action == "add":
    if args[3] not in paths: paths.append(args[3])
elif action == "remove":
    if (root / "fail-remove").exists():
        print("injected removal failure", file=sys.stderr)
        sys.exit(1)
    paths = [p for p in paths if p != args[3]]
elif action == "list":
    print("\\n".join(paths))
state.write_text(json.dumps(paths))
''')
    fake.chmod(0o755)
    config = {"runnerID": "smoke-runner", "ampPath": str(fake),
              "directories": [str(project)], "startAtLogin": False}

    def save_config():
        staging = root / "configuration.tmp"
        staging.write_text(json.dumps(config))
        staging.replace(root / "configuration.json")

    def status():
        try:
            return json.loads((root / "status.json").read_text())
        except FileNotFoundError:
            return {}

    save_config()
    plist = root / "test.plist"
    plist.write_bytes(plistlib.dumps({
        "Label": label, "ProgramArguments": [str(binary), str(root)],
        "WorkingDirectory": str(workspace), "RunAtLoad": True,
        "KeepAlive": True, "ThrottleInterval": 1,
        "StandardOutPath": str(root / "test.log"),
        "StandardErrorPath": str(root / "test.log"),
    }))
    try:
        subprocess.run(["launchctl", "bootstrap", domain, str(plist)], check=True)
        wait_for(lambda: status().get("registered") == [str(project)], "initial registration")
        first_pid = int((root / "runner.pid").read_text())
        subprocess.run(["launchctl", "kickstart", "-k", target], check=True)
        wait_for(lambda: int((root / "runner.pid").read_text()) != first_pid, "helper restart")
        wait_for(lambda: not alive(first_pid), "old runner must not survive helper restart")
        wait_for(lambda: status().get("ready") is True, "runner ready after restart")
        (root / "fail-remove").touch()
        config["directories"] = []
        save_config()
        wait_for(lambda: str(project) in status().get("errors", {}), "failure reported")
        assert status()["registered"] == [str(project)], "failed removal must remain registered"
        (root / "fail-remove").unlink()
        wait_for(lambda: status().get("managed") == [], "removal retry")
        assert json.loads((root / "fake-state.json").read_text()) == []
        assert sentinel.read_text() == "never delete project files"
        last_pid = int((root / "runner.pid").read_text())
        subprocess.run(["launchctl", "bootout", target], check=True)
        wait_for(lambda: not alive(last_pid), "stop must terminate runner child")
        time.sleep(2)
        assert subprocess.run(["launchctl", "print", target], capture_output=True).returncode != 0
        print("PASS: registration, restart, process cleanup, failed removal/retry, file preservation, explicit stop")
    finally:
        subprocess.run(["launchctl", "bootout", target], capture_output=True)
