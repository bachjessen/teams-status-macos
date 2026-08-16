#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$HOME/Library/Application Support/TeamsMeetingStatus/.env"
mkdir -p "$(dirname "$CONFIG")"
cd "$ROOT"
swift build

RUNTIME_DIR="$ROOT/.build/development-runtime"
PID_FILE="$RUNTIME_DIR/TeamsMeetingStatus.pid"
LOG_FILE="$RUNTIME_DIR/TeamsMeetingStatus.log"
mkdir -p "$RUNTIME_DIR"

if [ -f "$PID_FILE" ]; then
    EXISTING_PID="$(cat "$PID_FILE")"
    if kill -0 "$EXISTING_PID" 2>/dev/null; then
        echo "TeamsMeetingStatus is already running with PID $EXISTING_PID"
        echo "Log: $LOG_FILE"
        exit 0
    fi
fi

nohup "$ROOT/.build/debug/TeamsMeetingStatus" >"$LOG_FILE" 2>&1 </dev/null &
PID=$!
echo "$PID" >"$PID_FILE"
sleep 1

if ! kill -0 "$PID" 2>/dev/null; then
    echo "TeamsMeetingStatus exited during startup. Check $LOG_FILE" >&2
    exit 1
fi

echo "Started TeamsMeetingStatus with PID $PID"
echo "Log: $LOG_FILE"
echo "Stop: kill $PID"
