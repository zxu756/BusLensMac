#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

APP_BIN="$ROOT/build/BusLensMac.app/Contents/MacOS/BusLensMac"
if [[ ! -x "$APP_BIN" ]]; then
    echo "==> Building build/BusLensMac.app for README command replay..."
    "$ROOT/Scripts/build-app.sh" >/dev/null
fi

echo "=== BusLens Mac README Command Replay & Honesty Gate ==="
echo "Date (UTC): $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "App Binary: $APP_BIN"
echo ""

python3 - "$ROOT" <<'PY'
import json
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

# 1. Verify required honesty & scope disclosures across EN, ZH, and SPEC
for required_en in [
    "[DEMO]",
    "BusLensMonitor.preview()",
    "Unverified on real hardware (synthetic fixtures only)",
    "Planned (M1)",
]:
    assert required_en in readme_en, f"README.md missing required disclosure: {required_en!r}"

for required_zh in [
    "[演示数据]",
    "BusLensMonitor.preview()",
    "尚未在真机上验证（仅合成样本测试）",
    "计划中（M1）",
]:
    assert required_zh in readme_zh, f"README.zh-CN.md missing required disclosure: {required_zh!r}"

assert "Unverified on real hardware (synthetic fixtures only)" in spec_md
assert "尚未在真机上验证（仅合成样本测试）" in spec_md
print("[PASS] Documentation honesty disclosures verified in README.md, README.zh-CN.md, and docs/SPEC.md")

# 2. Extract CLI command blocks from README.md and README.zh-CN.md
def extract_cli_commands(markdown_text: str, heading: str) -> list[str]:
    pattern = rf"^## {re.escape(heading)}\s*$.*?```bash\n(.*?)```"
    m = re.search(pattern, markdown_text, flags=re.M | re.S)
    assert m, f"Could not find bash block under '## {heading}'"
    cmds = []
    for raw_line in m.group(1).splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        cmds.append(line)
    return cmds

cmds_en = extract_cli_commands(readme_en, "CLI Usage")
cmds_zh = extract_cli_commands(readme_zh, "命令行用法")

assert len(cmds_en) >= 8, f"Expected >= 8 CLI commands in README.md, got {len(cmds_en)}"
assert len(cmds_en) == len(cmds_zh), f"EN/ZH CLI command count mismatch: EN={len(cmds_en)} vs ZH={len(cmds_zh)}"
print(f"[PASS] Extracted symmetric CLI command blocks (README.md={len(cmds_en)}, README.zh-CN.md={len(cmds_zh)})")

demo_dir = root / ".build/demo-shots"
if demo_dir.exists():
    shutil.rmtree(demo_dir)

for source_label, cmds in [("README.md", cmds_en), ("README.zh-CN.md", cmds_zh)]:
    for idx, cmd in enumerate(cmds, start=1):
        argv = shlex.split(cmd)
        proc = subprocess.run(argv, cwd=str(root), capture_output=True, text=True)
        assert proc.returncode == 0, (
            f"[{source_label} #{idx}] Command failed (rc={proc.returncode}): {cmd}\n"
            f"stdout: {proc.stdout}\nstderr: {proc.stderr}"
        )
        assert proc.stderr == "", f"[{source_label} #{idx}] Unexpected stderr for {cmd}: {proc.stderr!r}"
        assert len(proc.stdout.strip()) > 0, f"[{source_label} #{idx}] Empty stdout for {cmd}"
        if "--json" in argv:
            parsed = json.loads(proc.stdout)
            assert isinstance(parsed.get("devices"), list)
        first_line = proc.stdout.strip().splitlines()[0]
        print(f"[PASS] [{source_label} #{idx:02d}] `{cmd}` -> rc=0 ({first_line[:88]})")

for expected_png in (
    "screenshot-main.png",
    "screenshot-menubar.png",
    "screenshot-main-zh.png",
    "screenshot-menubar-zh.png",
):
    png_path = demo_dir / expected_png
    assert png_path.is_file() and png_path.stat().st_size > 10_000, f"Missing or tiny exported PNG: {png_path}"

shutil.rmtree(demo_dir)
print("\n=== ALL README COMMANDS PASSED ===")
PY
