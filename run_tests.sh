#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
cd "$SCRIPT_DIR"

echo "Building and running Brightspace Pulse test suite..."
xcrun swift build --target BrightspaceSyncTests
xcrun swift run BrightspaceSyncTests "$@"
