#!/bin/zsh
set -eu
ROOT="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$ROOT/.build/ModuleCache"
/usr/bin/swiftc -module-cache-path "$ROOT/.build/ModuleCache" "$ROOT/Sources/Core.swift" "$ROOT/Sources/ServiceCore.swift" "$ROOT/Sources/Journal.swift" "$ROOT/Sources/IPC.swift" "$ROOT/Sources/System.swift" "$ROOT/Tests/main.swift" -o "$ROOT/.build/test-runner"
"$ROOT/.build/test-runner"
