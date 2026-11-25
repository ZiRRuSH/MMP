#!/bin/sh
# Double-click (macOS: UpdateLibrary.command) or run (Linux: ./UpdateLibrary.sh)
# to rebuild Library.lua from the mp3 folder.
cd "$(dirname "$0")" || exit 1
if command -v python3 >/dev/null 2>&1; then
    python3 GenerateLibrary.py
    status=$?
else
    echo "Python 3 is needed. Install it from python.org (macOS) or your package manager (Linux)."
    status=1
fi
if [ "$status" -ne 0 ]; then
    echo "FAILED: See the error above. The previous library may still be in place."
fi
printf "Press Enter to close..."
read -r _
