#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ARTIFACT_DIR="${ARTIFACT_DIR:-$ROOT_DIR/artifacts}"
ROJO_TIMEOUT_SECONDS="${ROJO_TIMEOUT_SECONDS:-120}"
TEMP_PROJECT_FILES=()

export PATH="$HOME/.cargo/bin:$HOME/.aftman/bin:$ROOT_DIR/.aftman/bin:$PATH"

mkdir -p "$ARTIFACT_DIR"

cleanup_temp_projects() {
    local project_file
    for project_file in "${TEMP_PROJECT_FILES[@]}"; do
        rm -f "$project_file" || true
    done
}
trap cleanup_temp_projects EXIT

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

    local command_status=0
    wait "$command_pid" || command_status=$?

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
    if [ ! -d "$place_dir" ]; then
        return
    fi

    local packages_dir="$place_dir/Packages"
    mkdir -p "$packages_dir"
    # Wally may delete Packages when no dependencies exist; keep path stable for Rojo.
    : >"$packages_dir/.gitkeep"
}

resolve_project_file() {
    local place_name="$1"
    local place_project="$ROOT_DIR/game/places/${place_name}/default.project.json"
    local root_project="$ROOT_DIR/${place_name}.project.json"
    local compat_project="$ROOT_DIR/.ci-${place_name}.compat.project.json"

    if [ -f "$place_project" ]; then
        echo "$place_project"
        return 0
    fi

    if [ -d "$ROOT_DIR/src/Packages" ]; then
        if [ "$place_name" = "lobby" ]; then
            cat >"$compat_project" <<'JSON'
{
  "name": "Brainrot Floor Lobby",
  "servePort": 34872,
  "tree": {
    "$className": "DataModel",
    "ReplicatedStorage": {
      "$className": "ReplicatedStorage",
      "$ignoreUnknownInstances": true,
      "Shared": {
        "$path": "src/Packages/Shared/ReplicatedStorage/Shared",
        "$ignoreUnknownInstances": true
      }
    },
    "ServerScriptService": {
      "$className": "ServerScriptService",
      "$ignoreUnknownInstances": true,
      "Shared": {
        "$path": "src/Packages/Shared/ServerScriptService/Shared",
        "$ignoreUnknownInstances": true
      },
      "Lobby": {
        "$path": "src/Packages/Lobby/ServerScriptService/Lobby",
        "$ignoreUnknownInstances": true
      }
    },
    "StarterPlayer": {
      "$className": "StarterPlayer",
      "$ignoreUnknownInstances": true,
      "StarterPlayerScripts": {
        "$className": "StarterPlayerScripts",
        "$ignoreUnknownInstances": true,
        "SharedClient": {
          "$path": "src/Packages/Shared/StarterPlayer/StarterPlayerScripts/SharedClient",
          "$ignoreUnknownInstances": true
        }
      }
    },
    "Workspace": {
      "$className": "Workspace",
      "$ignoreUnknownInstances": true,
      "DifficultyButtons": {
        "$path": "src/Packages/Lobby/Workspace/DifficultyButtons",
        "$ignoreUnknownInstances": true
      }
    }
  }
}
JSON
        elif [ "$place_name" = "match" ]; then
            cat >"$compat_project" <<'JSON'
{
  "name": "Brainrot Floor Match",
  "servePort": 34872,
  "tree": {
    "$className": "DataModel",
    "ReplicatedStorage": {
      "$className": "ReplicatedStorage",
      "$ignoreUnknownInstances": true,
      "Shared": {
        "$path": "src/Packages/Shared/ReplicatedStorage/Shared",
        "$ignoreUnknownInstances": true
      }
    },
    "ServerScriptService": {
      "$className": "ServerScriptService",
      "$ignoreUnknownInstances": true,
      "Shared": {
        "$path": "src/Packages/Shared/ServerScriptService/Shared",
        "$ignoreUnknownInstances": true
      },
      "Match": {
        "$path": "src/Packages/Match/ServerScriptService/Match",
        "$ignoreUnknownInstances": true
      }
    },
    "ServerStorage": {
      "$className": "ServerStorage",
      "$ignoreUnknownInstances": true,
      "EnemyTemplates": {
        "$path": "src/Packages/Match/ServerStorage/EnemyTemplates",
        "$ignoreUnknownInstances": true
      },
      "ShopItems": {
        "$path": "src/Packages/Match/ServerStorage/ShopItems",
        "$ignoreUnknownInstances": true
      }
    },
    "StarterPlayer": {
      "$className": "StarterPlayer",
      "$ignoreUnknownInstances": true,
      "StarterPlayerScripts": {
        "$className": "StarterPlayerScripts",
        "$ignoreUnknownInstances": true,
        "SharedClient": {
          "$path": "src/Packages/Shared/StarterPlayer/StarterPlayerScripts/SharedClient",
          "$ignoreUnknownInstances": true
        },
        "MatchClient": {
          "$path": "src/Packages/Match/StarterPlayer/StarterPlayerScripts/MatchClient",
          "$ignoreUnknownInstances": true
        }
      }
    },
    "Workspace": {
      "$className": "Workspace",
      "$ignoreUnknownInstances": true,
      "EnemyContainer": {
        "$path": "src/Packages/Match/Workspace/EnemyContainer",
        "$ignoreUnknownInstances": true
      },
      "SpawnPoints": {
        "$path": "src/Packages/Match/Workspace/SpawnPoints",
        "$ignoreUnknownInstances": true
      }
    }
  }
}
JSON
        fi

        if [ -f "$compat_project" ]; then
            echo "$compat_project"
            return 0
        fi
    fi

    if [ -f "$root_project" ]; then
        echo "$root_project"
        return 0
    fi

    echo "Could not find a project file for '${place_name}'." >&2
    echo "Checked:" >&2
    echo "  - $place_project" >&2
    echo "  - $root_project" >&2
    return 1
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

LOBBY_PROJECT_FILE="$(resolve_project_file "lobby")"
MATCH_PROJECT_FILE="$(resolve_project_file "match")"

if [[ "$LOBBY_PROJECT_FILE" == "$ROOT_DIR/.ci-"* ]]; then
    TEMP_PROJECT_FILES+=("$LOBBY_PROJECT_FILE")
fi

if [[ "$MATCH_PROJECT_FILE" == "$ROOT_DIR/.ci-"* ]]; then
    TEMP_PROJECT_FILES+=("$MATCH_PROJECT_FILE")
fi

echo "Lobby project: $LOBBY_PROJECT_FILE"
echo "Match project: $MATCH_PROJECT_FILE"

build_place_artifact() {
    local project_file="$1"
    local output_prefix="$2"
    local sourcemap_output="$ARTIFACT_DIR/${output_prefix}.sourcemap.json"
    local build_output="$ARTIFACT_DIR/${output_prefix}.rbxlx"
    local status

    echo "Validating ${project_file} via sourcemap..."
    status=0
    run_with_timeout "$ROJO_TIMEOUT_SECONDS" rojo sourcemap "$project_file" --output "$sourcemap_output" || status=$?

    if [ "$status" -ne 0 ]; then
        if [ "$status" -eq 124 ] && [ -s "$sourcemap_output" ]; then
            echo "Rojo sourcemap timed out after writing ${sourcemap_output}; continuing."
        else
            return "$status"
        fi
    fi

    echo "Building ${project_file}..."
    status=0
    run_with_timeout "$ROJO_TIMEOUT_SECONDS" rojo build "$project_file" --output "$build_output" || status=$?

    if [ "$status" -ne 0 ]; then
        if [ "$status" -eq 124 ] && [ -s "$build_output" ]; then
            echo "Rojo build timed out after writing ${build_output}; continuing."
        else
            return "$status"
        fi
    fi
}

build_place_artifact "$LOBBY_PROJECT_FILE" "lobby-place"
build_place_artifact "$MATCH_PROJECT_FILE" "match-place"

echo "Prepared artifacts:"
ls -lah "$ARTIFACT_DIR"
