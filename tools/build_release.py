# Python / build_release.py / Python 3.10+ / generate compatibility client and embedded Colab.
import json
from pathlib import Path
root=Path(__file__).resolve().parents[1]
(root/'chess_termux.lua').write_text((root/'chess.lua').read_text())
setup='''# Python / Colab installation / CPU runtime / ChessHint 2.0.0.
import os, sys, subprocess, pathlib, urllib.request, hashlib
BASE = pathlib.Path('/content/chesshint-v2')
BASE.mkdir(exist_ok=True)
subprocess.run([sys.executable, '-m', 'pip', '-q', 'install', 'chess==1.11.2'], check=True)
'''
for path in ['termux/server.py','termux/positions.py','termux/install_engine.py','termux/check_engine.py','termux/requirements.txt','tests/test_positions.py','tests/test_server.py','tests/test_castling_animation.py']:
 setup+=f"target = BASE / {path!r}\ntarget.parent.mkdir(parents=True, exist_ok=True)\ntarget.write_text({(root/path).read_text()!r}, encoding='utf-8')\n"
setup+='''SERVER = BASE / 'termux' / 'server.py'
subprocess.run([sys.executable, str(BASE / 'termux' / 'install_engine.py')], check=True)
ENGINE = BASE / 'termux' / 'bin' / 'stockfish'
subprocess.run([sys.executable, '-m', 'unittest', 'discover', '-s', str(BASE/'tests')], check=True)
subprocess.run([sys.executable, str(BASE/'termux'/'check_engine.py'), '--engine', str(ENGINE)], check=True)
TUNNEL = BASE / 'cloudflared'
EXPECTED = 'd33ff2d14475178d2012c2c56beba87389ac5ded27649519f198a7d3134a99db'
if not TUNNEL.exists() or hashlib.sha256(TUNNEL.read_bytes()).hexdigest() != EXPECTED:
    urllib.request.urlretrieve('https://github.com/cloudflare/cloudflared/releases/download/2026.10.0/cloudflared-linux-amd64', TUNNEL)
if hashlib.sha256(TUNNEL.read_bytes()).hexdigest() != EXPECTED:
    raise RuntimeError('SHA256 do Cloudflare Tunnel inválido')
TUNNEL.chmod(0o755)
print('Instalação e testes concluídos. Execute a célula de início.')
'''
start=json.loads((root/'Stockfish_Colab.ipynb').read_text())['cells'][2]['source']
start=''.join(start)
start=start.replace('THREADS = min(16, os.cpu_count() or 1)','THREADS = min(2, os.cpu_count() or 1)').replace('HASH_MB = 1024','HASH_MB = 128')
start=start.replace('key_file = BASE / ".api-key"','key_file = BASE / "termux" / ".api-key"')
start=start.replace('"--port", str(PORT), "--force-precise", "--adaptive-time", "--threads",','"--port", str(PORT), "--threads",')
intro='''# ChessHint 2.0.0 — Stockfish 19 no Colab
1. Escolha um ambiente **CPU** e execute a célula **Instalar**. Ela contém o servidor desta versão: não baixa código do repositório original.
2. Execute **Iniciar**, copie a **URL PARA O PAINEL** e a **CHAVE PARA O PAINEL**.
3. Abra uma partida no Roblox e execute o conteúdo de `chess.lua` do pacote ChessHint 2.0.0.
4. Escolha seu lado e quem joga agora, cole URL e chave, e clique **Iniciar / resincronizar**.

O notebook instala binários oficiais com SHA256 verificado e executa testes antes de iniciar. Os modos Preciso e Atacante funcionam aqui. URL/chave são específicas desta sessão; mantenha a célula Iniciar ativa. Interrompê-la encerra o servidor e o túnel. O Colab pode encerrar o runtime; se isso acontecer, execute as células novamente. Comece preferencialmente antes da primeira jogada para preservar todo o histórico. Para partida em andamento, a FEN completa opcional recupera roque e en passant conhecidos.
'''
cells=[]
for typ,text in [('markdown',intro),('code',setup),('code',start)]:
 c={'cell_type':typ,'metadata':{},'source':text.splitlines(keepends=True)}
 if typ=='code':c.update(execution_count=None,outputs=[])
 cells.append(c)
n={'nbformat':4,'nbformat_minor':5,'metadata':{'colab':{'name':'ChessHint_2_Colab.ipynb'},'kernelspec':{'display_name':'Python 3','language':'python','name':'python3'}},'cells':cells}
(root/'Stockfish_Colab.ipynb').write_text(json.dumps(n,ensure_ascii=False,indent=2)+'\n')
