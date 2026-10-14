# Alterações

## 2.0.0 — 2026-10-14

### Corrigido
- Sincronização atômica de roque e recuperação de animação da torre antes do rei.
- Validação legal de movimentos, captura, en passant e promoção.
- Leitura atual ao iniciar e atualização da dica após devolver uma peça à origem.
- Descarte de respostas antigas e suporte real ao estilo atacante no Colab.

### Adicionado
- Sessões com histórico, revisão e recuperação explícita.
- Reinício do motor, limites HTTP e retorno BUSY com espera curta.
- Instalador de Stockfish 19 oficial com checksum, sem compilação no Android.
- Notebook autossuficiente, comandos para computador e suíte de regressão.
- Campo FEN completa opcional, estado visível e chave mascarada.

### Migração
- Cliente e servidor devem ser atualizados juntos para v2.
- O cliente `chess.lua` agora usa a API autenticada do projeto, assim como o alias `chess_termux.lua`.
- Execute `python tools/build_release.py` após editar cliente/servidor para manter o notebook e o alias atualizados.
