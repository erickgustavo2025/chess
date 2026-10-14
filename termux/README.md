# Stockfish 19 no Termux — ChessHint 2.0.0

```bash
bash install.sh
bash start.sh
```

Use o cliente `chess.lua` ou o alias gerado `chess_termux.lua` da mesma versão. Copie a URL HTTPS e a chave exibidas no terminal. No painel, escolha lado/vez e clique **Iniciar / resincronizar**.

A instalação baixa o binário oficial com SHA256 verificado e executa testes. A chave persiste em `.api-key`; a URL do túnel muda quando reinicia. Ajuste CPU e memória com `CHESS_THREADS=2 CHESS_HASH=128 bash start.sh`. Ctrl+C encerra servidor e túnel.

O [README principal](../README.md) contém instruções para ZIP baixado no Android, Colab, computador, recuperação, calibração e limites de verificação.
