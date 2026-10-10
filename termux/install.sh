#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
pkg install -y python clang make git curl cloudflared
python -m pip install 'chess==1.11.2'
mkdir -p bin
if [ ! -x bin/stockfish ]; then
    if [ ! -d stockfish-src ]; then
        git clone --depth 1 --branch sf_19 https://github.com/official-stockfish/Stockfish.git stockfish-src
    fi
    case "$(uname -m)" in
        aarch64) sf_arch=armv8 ;;
        x86_64) sf_arch=x86-64 ;;
        *) echo "Arquitetura não suportada: $(uname -m)"; exit 1 ;;
    esac
    make -C stockfish-src/src -j2 build ARCH="$sf_arch" COMP=clang
    cp stockfish-src/src/stockfish bin/stockfish
    chmod +x bin/stockfish
fi
printf '\nInstalado. Inicie com: bash start.sh\n'

