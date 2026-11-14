#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

usage() {
    cat >&2 <<'EOF'
Usage:
  Scripts/test.sh scope <Module> [<Module2> ...]
  Scripts/test.sh milestone <N>
  Scripts/test.sh release
EOF
    exit 2
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
        if [[ $# -ne 1 ]]; then
            usage
        fi
        MS="$1"
        case "$MS" in
            0)
                echo "==> [M0] Running scoped unit tests (Diagnoser, Collector, CLI, BusLensMacCoreTests)..."
                swift test --no-parallel \
                    --filter Diagnoser \
                    --filter Collector \
                    --filter CLI \
                    --filter BusLensMacCoreTests
                echo "==> [M0] Running M0 acceptance checks..."
                "$ROOT/Scripts/acceptance/m0-acceptance.sh"
                if [[ -x "$ROOT/Scripts/acceptance/readme-commands.sh" ]]; then
                    echo "==> [M0] Verifying README commands..."
                    "$ROOT/Scripts/acceptance/readme-commands.sh"
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
        mkdir -p "$ROOT/reports"
        BUSLENS_BIN="$ROOT/build/BusLensMac.app/Contents/MacOS/BusLensMac" \
            "$ROOT/Scripts/acceptance/m0-acceptance.sh" | tee "$ROOT/reports/m0-acceptance.txt"
        echo "==> [Release] Replaying README commands..."
        BUSLENS_BIN="$ROOT/build/BusLensMac.app/Contents/MacOS/BusLensMac" \
            "$ROOT/Scripts/acceptance/readme-commands.sh" | tee "$ROOT/reports/readme-commands.txt"
        GUARD_PY="$HOME/.agents/skills/rea-build-guard/scripts/guard.py"
        if [[ -f "$GUARD_PY" ]]; then
            echo "==> [Release] Running rea-build-guard on build/BusLensMac.app..."
            python3 "$GUARD_PY" "$ROOT/build/BusLensMac.app" --out "$ROOT/.build/build-guard"
        else
            echo "==> [Release] SKIPPED rea-build-guard (guard.py not installed at $GUARD_PY)"
        fi
        ;;
    *)
        usage
        ;;
esac
