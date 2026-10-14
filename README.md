# ChessHint 2.0.0

Dicas de xadrez no Roblox com Stockfish 19, confirmação de jogadas legais e destaque da peça/destino. Cliente atualizado a partir do projeto de erickgustavo2025, commit `f8c78320813644b19cabad42f6590318d22af66d`.

## Caminho mais simples: Colab

1. Abra `Stockfish_Colab.ipynb` no Google Colab, usando ambiente **CPU**.
2. Execute **Instalar** e depois **Iniciar**. A instalação executa testes e verifica os downloads oficiais.
3. Copie **URL PARA O PAINEL** e **CHAVE PARA O PAINEL**.
4. Dentro de uma partida, execute o conteúdo de `chess.lua` no executor já usado com a versão original.
5. Escolha **Teu lado** e **Quem joga agora?**, cole URL e chave e clique **Iniciar / resincronizar**. Comece antes da primeira jogada quando possível.

O notebook contém o servidor desta versão; funciona sem publicar ou fazer merge de alterações no GitHub. Mantenha a célula de início executando. Se o Colab encerrar o runtime, execute as células novamente e atualize URL/chave no painel. Stockfish usa CPU; GPU não acelera o motor. Esta entrega não inclui um executor Roblox.

## Android: Termux

Na pasta do projeto:

```bash
cd termux
bash install.sh
bash start.sh
```

O instalador baixa Stockfish 19 oficial com SHA256 verificado, sem compilar no celular. Instala Python e Cloudflare Tunnel e executa os testes. Copie a URL HTTPS exibida e a chave para o painel do cliente.

Se baixou `chesshint-2.0.0.zip` deste chat para Downloads, execute no Termux:

```bash
termux-setup-storage
pkg install -y python
python -m zipfile -e ~/storage/downloads/chesshint-2.0.0.zip ~/
cd ~/chesshint-2.0.0/termux
bash install.sh
bash start.sh
```

Autorize acesso ao armazenamento quando o Android solicitar. Copie o conteúdo de `chess.lua` do ZIP e execute durante a partida. Nas próximas vezes basta `cd ~/chesshint-2.0.0/termux && bash start.sh`.

Para ajustar consumo de CPU/memória:

```bash
CHESS_THREADS=2 CHESS_HASH=128 bash start.sh
```

Ctrl+C encerra os processos. A URL temporária muda ao reiniciar o túnel; a chave persiste em `termux/.api-key`.

## Computador

Com Python 3.10 ou superior:

- Linux/macOS: `bash start-local.sh`.
- Windows: execute `start-local.bat` (Python Launcher `py` necessário).

Se servidor e Roblox estiverem no mesmo dispositivo, use `http://127.0.0.1:8080` no painel. O executor precisa conseguir fazer a requisição HTTP local. Para outro dispositivo, use Colab ou um túnel HTTPS que encaminhe para o servidor. Em Debian/Ubuntu, instale `python3-venv` se o comando de criação do ambiente virtual informar sua ausência.

## O que mudou

- A sincronização compara o tabuleiro inteiro com jogadas legais. Roque, captura, en passant e promoção são tratados pelo python-chess.
- Roque com animação da torre anterior à do rei é reconciliado sem duplicar a jogada no histórico.
- A posição usada ao iniciar é a observada naquele momento, sem reutilizar a leitura antiga da configuração.
- Respostas antigas são descartadas; uma peça movida e devolvida à origem agenda nova dica.
- Histórico preservado desde o início permite informar empate reivindicável e detectar posições encerradas.
- Falha do processo Stockfish provoca uma tentativa de reinício automático.
- BUSY tem retorno e nova tentativa curta; falhas repetidas pausam consultas e mantêm mensagem de recuperação.
- Modos **Preciso** e **Atacante** funcionam no Termux e Colab. O atacante escolhe entre até quatro linhas dentro de um orçamento máximo de 50 centipeões de perda estimada; não garante uma vantagem objetiva.
- A chave aparece mascarada e fica somente na sessão do cliente. URL/tempo/estilo podem ser gravados pelo executor; a chave não é gravada no JSON.
- Calibração usa casas nomeadas a1/b1/a2 quando disponíveis e mantém as coordenadas do jogo original como fallback.
- Cliente e alias Termux são gerados a partir de um único arquivo canônico.

## Partida em andamento e recuperação

Sem uma FEN completa, o início no meio da partida não conhece direitos anteriores de roque/en passant, contador de cinquenta lances ou repetição anterior. É possível preencher o campo opcional **FEN completa** para informar esses direitos e contadores. A FEN deve corresponder exatamente às peças observadas. FEN não recupera histórico anterior de repetição.

**Iniciar / resincronizar** cria uma nova sessão a partir das peças atuais e da vez selecionada. Essa ação descarta o histórico da sessão anterior. Se a partida reiniciar, peças/modelos mudarem ou uma jogada inteira ocorrer durante uma interrupção de rede, use esse botão. A versão atual confirma uma jogada por transição; não tenta inventar sequências de movimentos perdidos.

Amarelo indica a peça; verde indica o destino. Avaliação positiva favorece as brancas, negativa favorece as pretas. Uma dica não executa a jogada automaticamente.

## Calibração de outro tabuleiro

O suporte automático espera pastas `workspace.Pieces`, `workspace.Board` e nomes de peças contendo king/queen/rook/bishop/knight/pawn. Os lados são separados pela luminosidade dos modelos. Temas com cores invertidas ou sem contraste exigem adaptação do leitor.

Para um tabuleiro horizontal sem casas nomeadas, configure antes de executar o cliente:

```lua
getgenv().ChessBoardCalibration = {
    a1 = Vector3.new(1032, 0, 4),
    b1 = Vector3.new(1028, 0, 4),
    a2 = Vector3.new(1032, 0, 8),
}
```

Os valores acima são os do jogo original. Para outro jogo, use os centros reais das três casas; a transformação suporta rotação e escala no plano XZ.

## Desenvolvimento e testes

```bash
python -m pip install -r termux/requirements.txt
python -m unittest discover -s tests -v
python termux/check_engine.py --engine termux/bin/stockfish
python tools/build_release.py
```

O teste geométrico Luau é opcional; para executá-lo, defina `LUAU_BIN` com o caminho da CLI Luau oficial. Compile o cliente com `luau-compile chess.lua`. O gerador atualiza `chess_termux.lua` e incorpora o servidor atual no notebook; rode-o após alterar o servidor ou o cliente.

Validação desta entrega: 29 testes com Luau ativado, cinco verificações com Stockfish 19 real, compilação Luau e sintaxe Python/Bash/notebook. GUI/executor Roblox, Android, Windows/macOS e túnel Colab precisam de verificação nos ambientes reais; os testes locais não simulam o Roblox completo.

## API v2

Todas as rotas exigem `Authorization: Bearer <chave>`.

- `GET /health`: versão, motor e capacidades.
- `POST /session`: `{placement, turn, initial_fen?}` → sessão, FEN e revisão.
- `POST /sync`: `{session, placement, revision}` → transição legal confirmada ou erro de sincronização.
- `POST /analyse`: `{session, revision, time, style, aggression}` → movimento UCI, avaliação e métricas. Também aceita `fen` completa para análise independente.
- `POST /close`: `{session}` → encerra a sessão.

Use cliente e servidor v2 juntos. A integração anterior com chess-api.com foi substituída por este servidor para manter as mesmas regras e o histórico nos dois modos.

Fontes: [projeto original](https://github.com/erickgustavo2025/chess), [Stockfish 19](https://github.com/official-stockfish/Stockfish/releases/tag/sf_19), [python-chess](https://python-chess.readthedocs.io/en/latest/), [Cloudflare Quick Tunnels](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/trycloudflare/).
