#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
command -v termux-wake-lock >/dev/null && termux-wake-lock || true
server_pid=""
tunnel_pid=""
cleanup() {
    if [ -n "$tunnel_pid" ]; then kill "$tunnel_pid" 2>/dev/null || true; fi
    if [ -n "$server_pid" ]; then kill "$server_pid" 2>/dev/null || true; fi
    command -v termux-wake-unlock >/dev/null && termux-wake-unlock || true
}
trap cleanup EXIT
trap 'exit 130' INT TERM
python server.py --threads "${CHESS_THREADS:-2}" --hash "${CHESS_HASH:-128}" &
server_pid=$!
ready=false
for ((i=0;i<30;i++)); do
    kill -0 "$server_pid" 2>/dev/null || { echo "Servidor encerrou"; exit 1; }
    if [ -s .api-key ] && curl -fsS --max-time 1 \
        -H "Authorization: Bearer $(cat .api-key)" \
        http://127.0.0.1:8080/health >/dev/null 2>&1; then
        ready=true
        break
    fi
    sleep 1
done
if [ "$ready" != true ]; then echo "Servidor não iniciou em 30 segundos"; exit 1; fi
echo "Cole no painel a URL https://....trycloudflare.com exibida abaixo."
cloudflared tunnel --url http://127.0.0.1:8080 &
tunnel_pid=$!
wait -n "$server_pid" "$tunnel_pid"

