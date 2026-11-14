#!/usr/bin/env bash
# Generates the Xcode project from project.yml and opens it.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen is not installed. Install it with: brew install xcodegen" >&2
  exit 1
fi

xcodegen generate
open DribbleCoach.xcodeproj
