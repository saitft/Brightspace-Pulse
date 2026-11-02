#!/bin/zsh
set -euo pipefail

COURSE="${BRIGHTSPACE_COURSE_CODE:-COURSE}"
MODULE="${BRIGHTSPACE_MODULE_NAME:-General}"
FILE_PATH="${BRIGHTSPACE_FILE_PATH:-}"
SHA256="${BRIGHTSPACE_FILE_SHA256:-unknown}"
WORKSPACE_ID="${NOTEBOOK_WORKSPACE_ID:-default}"

if [[ -z "$FILE_PATH" || ! -f "$FILE_PATH" ]]; then
    exit 0
fi

NOTEBOOK_ROOT="$HOME/Downloads/BrightspacePulse/NotebookLM_Sources/${COURSE}_Notebook"
mkdir -p "$NOTEBOOK_ROOT"

FILENAME="$(basename "$FILE_PATH")"
cp -f "$FILE_PATH" "$NOTEBOOK_ROOT/$FILENAME"

INDEX_FILE="$NOTEBOOK_ROOT/00_${COURSE}_NotebookLM_Index.md"
if [[ ! -f "$INDEX_FILE" ]]; then
    cat > "$INDEX_FILE" << EOF
# ${COURSE} — NotebookLM Source Index
- **Workspace ID:** \`${WORKSPACE_ID}\`
- **Auto-Updated By:** Brightspace Pulse (macOS Menu Bar Utility)

| Timestamp | Module | File Name | SHA-256 |
|---|---|---|---|
EOF
fi

TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
if ! grep -q "$SHA256" "$INDEX_FILE" 2>/dev/null; then
    echo "| $TIMESTAMP | $MODULE | \`$FILENAME\` | \`${SHA256[1,12]}\` |" >> "$INDEX_FILE"
fi
