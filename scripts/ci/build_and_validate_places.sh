#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ARTIFACT_DIR="${ARTIFACT_DIR:-$ROOT_DIR/artifacts}"
ROJO_TIMEOUT_SECONDS="${ROJO_TIMEOUT_SECONDS:-120}"

export PATH="$HOME/.cargo/bin:$HOME/.aftman/bin:$ROOT_DIR/.aftman/bin:$PATH"

mkdir -p "$ARTIFACT_DIR"

if ! command -v rojo >/dev/null 2>&1; then
    echo "rojo is required but not found in PATH."
    exit 1
fi

if ! command -v wally >/dev/null 2>&1; then
    echo "wally is required but not found in PATH."
    exit 1
fi

has_network() {
    curl --silent --head --fail --max-time 5 https://github.com >/dev/null 2>&1
}

run_with_timeout() {
    local timeout_seconds="$1"
    shift

    local timeout_flag
    timeout_flag="$(mktemp)"
    rm -f "$timeout_flag"

    "$@" &
    local command_pid=$!

    (
        sleep "$timeout_seconds"
        if kill -0 "$command_pid" >/dev/null 2>&1; then
            echo 1 >"$timeout_flag"
            kill "$command_pid" >/dev/null 2>&1 || true
            sleep 2
            kill -9 "$command_pid" >/dev/null 2>&1 || true
        fi
    ) &
    local watchdog_pid=$!

    set +e
    wait "$command_pid"
    local command_status=$?
    set -e

    kill "$watchdog_pid" >/dev/null 2>&1 || true
    wait "$watchdog_pid" 2>/dev/null || true

    if [ -f "$timeout_flag" ]; then
        rm -f "$timeout_flag"
        echo "Timed out after ${timeout_seconds}s: $*"
        return 124
    fi

    rm -f "$timeout_flag"
    return "$command_status"
}

install_place_dependencies() {
    local place_dir="$1"
    if [ ! -f "$place_dir/wally.toml" ]; then
        return
    fi

    echo "Running wally install in ${place_dir}..."
    (
        cd "$place_dir"
        wally install
    )
}

ensure_packages_dir() {
    local place_dir="$1"
    local packages_dir="$place_dir/Packages"
    mkdir -p "$packages_dir"
    # Wally may delete Packages when no dependencies exist; keep path stable for Rojo.
    : >"$packages_dir/.gitkeep"
}

if [ "${SKIP_WALLY_INSTALL:-0}" = "1" ]; then
    echo "Skipping wally install because SKIP_WALLY_INSTALL=1."
elif has_network; then
    install_place_dependencies "$ROOT_DIR/game/places/lobby"
    install_place_dependencies "$ROOT_DIR/game/places/match"
else
    echo "Network unavailable; skipping per-place wally install."
fi

ensure_packages_dir "$ROOT_DIR/game/places/lobby"
ensure_packages_dir "$ROOT_DIR/game/places/match"

build_place_artifact() {
    local project_file="$1"
    local output_prefix="$2"
    local sourcemap_output="$ARTIFACT_DIR/${output_prefix}.sourcemap.json"
    local build_output="$ARTIFACT_DIR/${output_prefix}.rbxlx"

    echo "Validating ${project_file} via sourcemap..."
    run_with_timeout "$ROJO_TIMEOUT_SECONDS" rojo sourcemap "$project_file" --output "$sourcemap_output"

    echo "Building ${project_file}..."
    run_with_timeout "$ROJO_TIMEOUT_SECONDS" rojo build "$project_file" --output "$build_output"
}

build_place_artifact "$ROOT_DIR/game/places/lobby/default.project.json" "lobby-place"
build_place_artifact "$ROOT_DIR/game/places/match/default.project.json" "match-place"

echo "Prepared artifacts:"
ls -lah "$ARTIFACT_DIR"
