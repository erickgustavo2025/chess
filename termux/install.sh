#!/data/data/com.termux/files/usr/bin/bash
# Bash / install.sh / Termux Android / ChessHint 2.0.0.
set -euo pipefail
cd "$(dirname "$0")"
pkg install -y python curl cloudflared
python -m pip install -r requirements.txt
python install_engine.py
python -m unittest discover -s ../tests -p 'test_*.py'
python check_engine.py --engine bin/stockfish
printf '\nInstalado e testado. Inicie com: bash start.sh\n'
