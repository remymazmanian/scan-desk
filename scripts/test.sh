#!/bin/bash
# Runs the ScanKit test suite. The tests generate their own images; no real scans needed.
# The Command Line Tools' copy of Swift Testing fails to load its macros for this package,
# so when Xcode is installed its toolchain is used (same Swift version; nothing is changed system-wide).
set -euo pipefail
cd "$(dirname "$0")/../App"
XCODE="/Applications/Xcode.app/Contents/Developer"
if [[ -d "$XCODE" ]]; then
  DEVELOPER_DIR="$XCODE" swift test --scratch-path .build-xcode "$@"
else
  swift test "$@"
fi
