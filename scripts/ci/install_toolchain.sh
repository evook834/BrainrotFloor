#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export PATH="$HOME/.cargo/bin:$HOME/.aftman/bin:$ROOT_DIR/.aftman/bin:$PATH"

if ! command -v aftman >/dev/null 2>&1; then
    if ! command -v cargo >/dev/null 2>&1; then
        echo "cargo is required to install aftman in CI."
        exit 1
    fi

    echo "Installing aftman via cargo..."
    cargo install --locked aftman --version 0.3.0
fi

echo "Using aftman at: $(command -v aftman)"
aftman --version

echo "Installing project tools from aftman.toml..."
(
    cd "$ROOT_DIR"
    aftman install --no-trust-check
)

export PATH="$HOME/.aftman/bin:$ROOT_DIR/.aftman/bin:$PATH"

if ! command -v rojo >/dev/null 2>&1; then
    echo "rojo was not found after aftman install."
    exit 1
fi

if ! command -v wally >/dev/null 2>&1; then
    echo "wally was not found after aftman install."
    exit 1
fi

echo "Rojo version:"
rojo --version

echo "Wally version:"
wally --version
