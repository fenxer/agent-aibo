#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

xcodebuild \
  -project aibo.xcodeproj \
  -scheme aibo \
  -configuration Debug \
  -derivedDataPath "$ROOT/.derivedData" \
  build

APP="$ROOT/.derivedData/Build/Products/Debug/aibo.app"
open "$APP"
