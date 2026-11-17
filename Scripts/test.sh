#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

usage() {
    cat >&2 <<'EOF'
Usage:
  Scripts/test.sh scope <Module> [<Module2> ...]
  Scripts/test.sh milestone <N> [--record]
  Scripts/test.sh release
EOF
    exit 2
}

scrub_and_write() {
    local target_file="$1"
    python3 -c '
import pathlib, re, sys
root = sys.argv[1]
dest = pathlib.Path(sys.argv[2])
raw = sys.stdin.read()
sys.stdout.write(raw)
scrubbed = raw.replace(root, "<REPO_ROOT>")
users_prefix = "/" + "Users/"
scrubbed = re.sub(users_prefix + r"[A-Za-z0-9._-]+", "<USER_HOME>", scrubbed)
dest.parent.mkdir(parents=True, exist_ok=True)
dest.write_text(scrubbed, encoding="utf-8")
' "$ROOT" "$target_file"
}

if [[ $# -lt 1 ]]; then
    usage
fi

MODE="$1"
shift

case "$MODE" in
    scope)
        if [[ $# -lt 1 ]]; then
            usage
        fi
        ARGS=(swift test --no-parallel)
        for mod in "$@"; do
            ARGS+=(--filter "$mod")
        done
        echo "==> Running scoped tests: $*"
        "${ARGS[@]}"
        ;;
    milestone)
        if [[ $# -lt 1 || $# -gt 2 ]]; then
            usage
        fi
        MS="$1"
        RECORD=0
        if [[ $# -eq 2 ]]; then
            if [[ "$2" == "--record" ]]; then
                RECORD=1
            else
                usage
            fi
        fi
        case "$MS" in
            0)
                echo "==> [M0] Running scoped unit tests (Diagnoser, Collector, CLI, BusLensMacCoreTests)..."
                swift test --no-parallel \
                    --filter Diagnoser \
                    --filter Collector \
                    --filter CLI \
                    --filter BusLensMacCoreTests
                echo "==> [M0] Running M0 acceptance checks..."
                if [[ "$RECORD" -eq 1 ]]; then
                    "$ROOT/Scripts/acceptance/m0-acceptance.sh" | scrub_and_write "$ROOT/reports/m0-acceptance.txt"
                else
                    "$ROOT/Scripts/acceptance/m0-acceptance.sh"
                fi
                if [[ "${BUSLENS_SKIP_README_REPLAY:-0}" != "1" && -x "$ROOT/Scripts/acceptance/readme-commands.sh" ]]; then
                    echo "==> [M0] Verifying README commands..."
                    if [[ "$RECORD" -eq 1 ]]; then
                        BUSLENS_IN_MILESTONE=1 "$ROOT/Scripts/acceptance/readme-commands.sh" \
                            | scrub_and_write "$ROOT/reports/readme-commands.txt"
                    else
                        BUSLENS_IN_MILESTONE=1 "$ROOT/Scripts/acceptance/readme-commands.sh"
                    fi
                fi
                ;;
            1)
                echo "==> [M1] Running scoped unit tests (Diagnoser, Collector, CLI, BusLensMacCoreTests)..."
                swift test --no-parallel \
                    --filter Diagnoser \
                    --filter Collector \
                    --filter CLI \
                    --filter BusLensMacCoreTests
                echo "==> [M1] Running M1 differential & capability acceptance checks..."
                if [[ "$RECORD" -eq 1 ]]; then
                    "$ROOT/Scripts/acceptance/m1-differential.sh" | scrub_and_write "$ROOT/reports/m1-acceptance.txt"
                else
                    "$ROOT/Scripts/acceptance/m1-differential.sh"
                fi
                if [[ "${BUSLENS_SKIP_README_REPLAY:-0}" != "1" && -x "$ROOT/Scripts/acceptance/readme-commands.sh" ]]; then
                    echo "==> [M1] Verifying README commands..."
                    if [[ "$RECORD" -eq 1 ]]; then
                        BUSLENS_IN_MILESTONE=1 "$ROOT/Scripts/acceptance/readme-commands.sh" \
                            | scrub_and_write "$ROOT/reports/readme-commands.txt"
                    else
                        BUSLENS_IN_MILESTONE=1 "$ROOT/Scripts/acceptance/readme-commands.sh"
                    fi
                fi
                ;;
            *)
                SCRIPT="$ROOT/Scripts/acceptance/m${MS}-acceptance.sh"
                if [[ ! -x "$SCRIPT" ]]; then
                    echo "Error: acceptance script not found or not executable: $SCRIPT" >&2
                    exit 1
                fi
                swift test --no-parallel
                "$SCRIPT"
                ;;
        esac
        ;;
    release)
        echo "==> [Release] Running all unit tests..."
        swift test --no-parallel
        echo "==> [Release] Building release app bundle..."
        "$ROOT/Scripts/build-app.sh"
        echo "==> [Release] Running M0 acceptance gate (50x CLI runs + bilingual checks)..."
        BUSLENS_BIN="$ROOT/build/BusLensMac.app/Contents/MacOS/BusLensMac" \
            "$ROOT/Scripts/acceptance/m0-acceptance.sh" | scrub_and_write "$ROOT/reports/m0-acceptance.txt"
        echo "==> [Release] Running M1 differential & capability acceptance gate..."
        BUSLENS_BIN="$ROOT/build/BusLensMac.app/Contents/MacOS/BusLensMac" \
            "$ROOT/Scripts/acceptance/m1-differential.sh" | scrub_and_write "$ROOT/reports/m1-acceptance.txt"
        echo "==> [Release] Replaying README commands..."
        BUSLENS_BIN="$ROOT/build/BusLensMac.app/Contents/MacOS/BusLensMac" \
            BUSLENS_IN_MILESTONE=1 "$ROOT/Scripts/acceptance/readme-commands.sh" \
            | scrub_and_write "$ROOT/reports/readme-commands.txt"
        GUARD_PY="$HOME/.agents/skills/rea-build-guard/scripts/guard.py"
        if [[ -f "$GUARD_PY" ]]; then
            echo "==> [Release] Running rea-build-guard on build/BusLensMac.app..."
            python3 "$GUARD_PY" "$ROOT/build/BusLensMac.app" --out "$ROOT/.build/build-guard"
        else
            echo "==> [Release] SKIPPED rea-build-guard (guard.py not installed)"
        fi
        ;;
    *)
        usage
        ;;
esac
