#!/usr/bin/env bash
# Bash / start-local.sh / Linux/macOS Python 3.10+ / ChessHint 2.0.0.
set -euo pipefail
cd "$(dirname "$0")"
python3 -m venv .venv
.venv/bin/python -m pip install -r termux/requirements.txt
.venv/bin/python termux/install_engine.py
exec .venv/bin/python termux/server.py --threads "${CHESS_THREADS:-2}" --hash "${CHESS_HASH:-128}"
