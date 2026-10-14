@echo off
rem Batch / start-local.bat / Windows Python 3.10+ / ChessHint 2.0.0.
cd /d "%~dp0"
py -3 -m venv .venv || exit /b 1
.venv\Scripts\python.exe -m pip install -r termux\requirements.txt || exit /b 1
.venv\Scripts\python.exe termux\install_engine.py || exit /b 1
.venv\Scripts\python.exe termux\server.py --engine termux\bin\stockfish.exe
