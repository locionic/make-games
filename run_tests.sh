#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
godot --headless -s test.gd "$@"
