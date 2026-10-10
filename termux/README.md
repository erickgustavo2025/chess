# Stockfish no Termux + Cloudflare

Esta versão usa chess_termux.lua. O chess.lua original continua separado.

## Instalar no Termux


```bash
pkg install -y git
git clone https://github.com/erickgustavo2025/chess.git
cd chess/termux
bash install.sh
bash start.sh
```

O instalador compila a versão oficial Stockfish 19 (tag sf_19) para Android.
A primeira instalação baixa também as redes NNUE e pode levar vários minutos.
Não exige root. Precisa de espaço para compilador, fontes e redes.

O terminal exibe a chave e uma URL HTTPS trycloudflare.com.
No Roblox, execute durante uma partida:

```lua
local url = "https://raw.githubusercontent.com/erickgustavo2025/chess/main/chess_termux.lua"
local execute, err = loadstring(game:HttpGet(url .. "?t=" .. tostring(os.time())))
assert(execute, err)
execute()
```

Escolha teu lado e quem joga agora, cole a URL (sem /analyse) e a chave,
e aperte Iniciar / salvar. O tempo padrão é 1 segundo por análise.

## Uso posterior

```bash
cd ~/chess/termux
bash start.sh
```

Para atualizar os arquivos: git pull na pasta do projeto.
Para mudar CPU e memória: CHESS_THREADS=2 CHESS_HASH=128 bash start.sh.
Tempo de busca: campo no painel, de 0.1 a 10 segundos.
O motor para pela duração escolhida; a profundidade atingida varia por posição.

Ctrl+C encerra servidor e túnel. Mantenha o Termux em segundo plano e permita
execução sem restrição de bateria. O wake lock não impede todo encerramento do Android.
A URL temporária muda quando o túnel reinicia: cole a nova URL no painel.
A chave permanece no arquivo .api-key no celular; nunca publique esse arquivo.
Os campos da GUI persistem apenas enquanto o executor mantiver getgenv().

Avaliação positiva favorece brancas; negativa favorece pretas. Mate é exibido separadamente.
O servidor valida a FEN e serializa acesso ao motor; requisições simultâneas recebem BUSY.
En passant é mantido na análise, sem a tentativa de remover esse direito da Chess API.

## Limites e verificação

O cálculo disputa CPU e bateria com o Roblox. Cloudflare só transporta as requisições.
Esta versão mantém a leitura de peças e movimentos da versão 1.3.0.
Ao iniciar no meio de uma partida, direitos anteriores de roque/en passant são
desconhecidos. O histórico não basta para detectar repetição tripla.

A sintaxe do servidor e dos scripts de shell e o contrato HTTP foram verificados
fora do Android. Compilação no Termux, túnel real, GUI e executor precisam ser
validados no dispositivo.

Fontes: https://github.com/official-stockfish/Stockfish/releases/tag/sf_19
e https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/
