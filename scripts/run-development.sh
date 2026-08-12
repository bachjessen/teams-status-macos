#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$HOME/Library/Application Support/MSTeamsStatusSender/.env"
mkdir -p "$(dirname "$CONFIG")"
cd "$ROOT"
exec swift run MSTeamsStatusSender
