#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

APP_BIN="build/BusLensMac.app/Contents/MacOS/BusLensMac"
if [[ ! -x "$APP_BIN" ]]; then
    echo "==> Building build/BusLensMac.app for README command replay..."
    "$ROOT/Scripts/build-app.sh" >/dev/null
fi

echo "=== BusLens Mac README Command Replay & Honesty Gate ==="
echo "Date (UTC): $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "App Binary: <REPO_ROOT>/$APP_BIN"
echo ""

python3 - "$ROOT" <<'PY'
from __future__ import annotations
import json
import os
import pathlib
import re
import shlex
import shutil
import subprocess
import sys

root = pathlib.Path(sys.argv[1])
readme_en = (root / "README.md").read_text(encoding="utf-8")
readme_zh = (root / "README.zh-CN.md").read_text(encoding="utf-8")
spec_md = (root / "docs/SPEC.md").read_text(encoding="utf-8")

# 1. Verify W5 title hygiene & Unreleased labels + required honesty disclosures
assert re.search(r"^# BusLens Mac\s*$", readme_en, flags=re.M), "README.md title must be clean '# BusLens Mac' without branch/tag suffix"
assert re.search(r"^# BusLens Mac\s*$", readme_zh, flags=re.M), "README.zh-CN.md title must be clean '# BusLens Mac' without branch/tag suffix"
assert "(m0/honest)" not in readme_en and "(m0/honest)" not in readme_zh, "README must not contain '(m0/honest)'"

for required_en in [
    "[DEMO]",
    "BusLensMonitor.preview()",
    "Unreleased (after v0.2.0)",
    "Unverified on real hardware (synthetic fixtures only)",
    "Planned (M1)",
]:
    assert required_en in readme_en, f"README.md missing required disclosure: {required_en!r}"

for required_zh in [
    "[演示数据]",
    "BusLensMonitor.preview()",
    "未发布（v0.2.0 之后）",
    "尚未在真机上验证（仅合成样本测试）",
    "计划中（M1）",
]:
    assert required_zh in readme_zh, f"README.zh-CN.md missing required disclosure: {required_zh!r}"

assert "Unverified on real hardware (synthetic fixtures only)" in spec_md
assert "尚未在真机上验证（仅合成样本测试）" in spec_md
assert "Unreleased (after v0.2.0)" in spec_md
print("[PASS] Documentation honesty & Unreleased (after v0.2.0) disclosures verified in README.md, README.zh-CN.md, and docs/SPEC.md")

# 2. Extract ALL fenced bash/sh commands from README.md and README.zh-CN.md
def extract_all_bash_commands(markdown_text: str, doc_name: str) -> list[str]:
    blocks = re.findall(r"```(?:bash|sh)\n(.*?)```", markdown_text, flags=re.S)
    assert len(blocks) >= 3, f"Expected >= 3 fenced bash blocks in {doc_name}, got {len(blocks)}"
    cmds = []
    for block in blocks:
        for raw_line in block.splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            cmds.append(line)
    return cmds

cmds_en = extract_all_bash_commands(readme_en, "README.md")
cmds_zh = extract_all_bash_commands(readme_zh, "README.zh-CN.md")

assert len(cmds_en) >= 15, f"Expected >= 15 commands in README.md, got {len(cmds_en)}"
assert cmds_en == cmds_zh, (
    f"Command parity mismatch between README.md and README.zh-CN.md:\nEN={cmds_en}\nZH={cmds_zh}"
)
print(f"[PASS] Extracted all fenced bash commands with 100% EN/ZH parity (README.md={len(cmds_en)}, README.zh-CN.md={len(cmds_zh)})")

in_milestone_gate = os.environ.get("BUSLENS_IN_MILESTONE") == "1"

def explicit_skip_reason(cmd: str) -> str | None:
    if cmd.startswith("brew install"):
        return "external Homebrew cask install requires network/Homebrew tap; out of offline test scope"
    if cmd.startswith("git clone "):
        return "network clone from GitHub remote; local git clone independence is verified via /tmp clone test"
    if cmd == "cd BusLensMac":
        return "shell directory change builtin; replay already runs inside repository root"
    if cmd.startswith("open "):
        return "launches macOS GUI window; skipped to enforce zero-GUI headless test policy"
    if cmd == "./Scripts/test.sh milestone 0" and in_milestone_gate:
        return "already executing inside parent './Scripts/test.sh milestone 0' gate (prevents infinite recursion)"
    return None

def assert_command_output(cmd: str, stdout: str, stderr: str) -> str:
    combined = stdout + "\n" + stderr
    if cmd == "./Scripts/test.sh scope Diagnoser Collector CLI":
        assert "Test run started" in combined and "passed" in combined, f"Missing Swift Testing pass summary for {cmd}"
        return "Swift Testing scoped suites (Diagnoser, Collector, CLI) passed"
    if cmd == "./Scripts/test.sh milestone 0":
        assert "ALL 6 M0 ACCEPTANCE ROWS" in combined, f"Missing M0 gate pass banner for {cmd}"
        return "M0 acceptance gate passed"
    if cmd == "./Scripts/build-app.sh":
        assert "✓ Built build/BusLensMac.app" in stdout, f"Missing build completion banner for {cmd}"
        assert (root / "build/BusLensMac.app/Contents/MacOS/BusLensMac").is_file()
        return "Built and codesigned build/BusLensMac.app"
    if cmd.endswith("--cli topology --lang en"):
        assert stderr == "" and "Power:" in stdout and "Peak Negotiated Link:" in stdout
        return stdout.strip().splitlines()[0]
    if cmd.endswith("--cli topology --lang zh"):
        assert stderr == "" and "供电状态：" in stdout and "最高协商链路：" in stdout
        return stdout.strip().splitlines()[0]
    if cmd.endswith("--cli topology --json --lang en"):
        assert stderr == ""
        p = json.loads(stdout)
        assert p["language"] == "en" and p["isDemo"] is False and isinstance(p["devices"], list)
        return f"JSON valid (language=en, isDemo=false, devices={len(p['devices'])})"
    if cmd.endswith("--cli topology --json --lang zh"):
        assert stderr == ""
        p = json.loads(stdout)
        assert p["language"] == "zh-Hans" and p["isDemo"] is False and isinstance(p["devices"], list)
        return f"JSON valid (language=zh-Hans, isDemo=false, devices={len(p['devices'])})"
    if "--input Tests/BusLensMacTests/Fixtures/host_macmini_scrubbed.json --lang en" in cmd:
        assert stderr == ""
        for token in ("TBU405Pro", "Indeterminate", "[Low-speed peripheral]"):
            assert token in stdout, f"Missing {token!r} in {cmd} output:\n{stdout}"
        return "Verified TBU405Pro + Indeterminate + [Low-speed peripheral]"
    if "--input Tests/BusLensMacTests/Fixtures/host_macmini_scrubbed.json --lang zh" in cmd:
        assert stderr == ""
        for token in ("TBU405Pro", "无法判断是否被限速", "低速外设（USB 1.x）"):
            assert token in stdout, f"Missing {token!r} in {cmd} output:\n{stdout}"
        return "Verified TBU405Pro + 无法判断是否被限速 + 低速外设（USB 1.x）"
    if cmd.endswith("--cli topology --demo --lang en"):
        assert stderr == "" and stdout.startswith("[DEMO]") and "USB 1.1 Full-Speed Receiver" in stdout
        return stdout.strip().splitlines()[0]
    if cmd.endswith("--cli topology --demo --lang zh"):
        assert stderr == "" and stdout.startswith("[演示数据]") and "USB 1.1 Full-Speed Receiver" in stdout
        return stdout.strip().splitlines()[0]
    if cmd.endswith("--export-screenshots .build/demo-shots --lang en"):
        assert stderr == "" and "Exported 2x Retina [DEMO] screenshots (en) to .build/demo-shots" in stdout
        for fn in ("screenshot-main.png", "screenshot-menubar.png"):
            fp = root / ".build/demo-shots" / fn
            assert fp.is_file() and fp.stat().st_size > 10_000, f"Missing exported PNG {fn}"
        return stdout.strip()
    if cmd.endswith("--export-screenshots .build/demo-shots --lang zh"):
        assert stderr == "" and "已导出 2x Retina [演示数据] 截图（zh-Hans）至 .build/demo-shots" in stdout
        for fn in ("screenshot-main-zh.png", "screenshot-menubar-zh.png"):
            fp = root / ".build/demo-shots" / fn
            assert fp.is_file() and fp.stat().st_size > 10_000, f"Missing exported PNG {fn}"
        return stdout.strip()
    if cmd.endswith("--help --lang en"):
        assert stderr == "" and "Usage:" in stdout and "--cli topology" in stdout
        return stdout.strip().splitlines()[0]
    if cmd.endswith("--help --lang zh"):
        assert stderr == "" and "用法：" in stdout and "--cli topology" in stdout
        return stdout.strip().splitlines()[0]
    if cmd.endswith("--version"):
        assert stderr == "" and "BusLens Mac 0.2.0" in stdout
        return stdout.strip()
    raise AssertionError(f"Unhandled README command without explicit key-output assertion: {cmd}")

demo_dir = root / ".build/demo-shots"
if demo_dir.exists():
    shutil.rmtree(demo_dir)

executed_count = 0
skipped_count = 0

for source_label, cmds in [("README.md", cmds_en), ("README.zh-CN.md", cmds_zh)]:
    for idx, cmd in enumerate(cmds, start=1):
        skip_why = explicit_skip_reason(cmd)
        if skip_why is not None:
            skipped_count += 1
            print(f"[SKIP] [{source_label} #{idx:02d}] `{cmd}` -> reason: {skip_why}")
            continue

        # Avoid rebuilding the release .app twice in the ZH pass when identical command already ran in EN pass
        env = os.environ.copy()
        if cmd == "./Scripts/test.sh milestone 0":
            env["BUSLENS_SKIP_README_REPLAY"] = "1"

        argv = shlex.split(cmd)
        proc = subprocess.run(argv, cwd=str(root), env=env, capture_output=True, text=True)
        assert proc.returncode == 0, (
            f"[FAIL] [{source_label} #{idx:02d}] Command failed (rc={proc.returncode}): {cmd}\n"
            f"stdout: {proc.stdout}\nstderr: {proc.stderr}"
        )
        summary = assert_command_output(cmd, proc.stdout, proc.stderr)
        executed_count += 1
        print(f"[PASS] [{source_label} #{idx:02d}] `{cmd}` -> rc=0 ({summary[:96]})")

if demo_dir.exists():
    shutil.rmtree(demo_dir)

print(f"\n=== ALL README COMMANDS VERIFIED (executed={executed_count}, skipped={skipped_count}) ===")
PY
