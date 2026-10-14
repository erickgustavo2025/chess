---
version: "2.0.0"
name: "ChessHint"
description: "Painel compacto de análise de xadrez dentro do Roblox"
colors:
  background: "#1C1F27"
  field: "#2D303A"
  action: "#414C82"
  text: "#FFFFFF"
  source: "#FFC800"
  destination: "#00FF64"
typography:
  sans:
    fontFamily: "Gotham"
rounded:
  DEFAULT: "8px"
spacing:
  field-height: "44px"
  page-inset: "8px"
components:
  button: {}
  input: {}
  panel: {}
  status: {}
---

# ChessHint Design System

## Overview

Ferramenta de análise no tabuleiro do Roblox. Preserva a identidade do projeto original: painel escuro, controles compactos e destaque amarelo/verde diretamente nas casas. Interface em português; uso por toque e mouse.

A fonte canônica dos valores em execução é `chess.lua`. Este documento registra esses valores; `tools/build_release.py` gera o alias `chess_termux.lua`. Nenhum CSS, navegador ou biblioteca web participa do painel.

## Colors

Fundo #1C1F27; campos #2D303A; ações #414C82; texto #FFFFFF. Destaques #FFC800 (origem) e #00FF64 (destino). O status descreve a jogada em texto, complementando as cores.

## Typography

Gotham nas entradas e GothamBold nos controles. Controles com texto 15–16px; entrada 14px; status 13px com quebra de linha.

## Layout

Painel entre 350 e 380px, limitado à largura disponível menos 16px; altura máxima 470px. Cabeçalho 64px. Conteúdo rola verticalmente, com barra visível. Entradas e ações têm altura 44px. O botão Configurar permanece acessível quando o painel fecha; status fixo acima dele.

## Elevation & Depth

Painel usa DisplayOrder 999999 para permanecer visível no jogo. HUD de status usa ZIndex 5 e botão de abertura ZIndex 6. Destaques das peças usam AlwaysOnTop. Sem sombras adicionais.

## Shapes

UICorner conserva raio padrão 8px. Entradas retangulares; marcadores respeitam o tamanho das casas.

## Components

Botões reutilizam `button`; campos reutilizam `input`; feedback reutiliza `status`. Labels preservam nomes de ações e campos. Iniciar/resincronizar valida valores antes de criar uma sessão. Falha repetida pausa consultas com mensagem de recuperação. A chave fica mascarada quando não está em edição, com ação Mostrar.

O cabeçalho permite arrastar; reabrir recoloca acesso ao painel. O layout limita posições à área disponível. Textos de status quebram linha e os campos permanecem na região rolável. Seleções de lado/vez/estilo usam texto explícito, não apenas cor.

Sem animação decorativa; consultas aguardam estabilidade observada de 0,6s. O status informa movimento, espera pelo adversário, análise, resultado ou falha.

## Do's and Don'ts

- Manter peça/destino e a mesma jogada descritos em texto.
- Preservar geometria do painel ao alterar feedback.
- Nunca mostrar chave em logs ou gravá-la no JSON do cliente.
- Não apresentar análise antiga após uma mudança de tabuleiro.
- Não declarar acessibilidade ou compatibilidade Roblox verificada com base apenas na compilação Luau. Verificação de toque, teclado e GUI no jogo permanece pendente.
