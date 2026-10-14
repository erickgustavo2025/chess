# Python / positions.py / Python 3.10+ / legal chess snapshot reconciliation.
import secrets
import threading
import time
from dataclasses import dataclass

import chess


class PositionError(ValueError):
    def __init__(self, code, text):
        super().__init__(text)
        self.code = code


@dataclass
class Session:
    board: chess.Board
    history_complete: bool
    touched: float
    revision: int = 0
    last_move: str | None = None


class PositionStore:
    def __init__(self, max_sessions=32, ttl=7200):
        self.sessions = {}
        self.lock = threading.RLock()
        self.max_sessions = max_sessions
        self.ttl = ttl

    @staticmethod
    def placement(value):
        if not isinstance(value, str) or len(value) > 100 or ' ' in value:
            raise PositionError('INVALID_POSITION', 'Envie somente as oito fileiras da posição')
        try:
            board = chess.Board(value + ' w - - 0 1')
        except ValueError as exc:
            raise PositionError('INVALID_POSITION', str(exc)) from exc
        if board.board_fen() != value:
            raise PositionError('INVALID_POSITION', 'Posição deve usar FEN canônica')
        return value

    def _purge(self):
        now = time.monotonic()
        for key in list(self.sessions):
            if now - self.sessions[key].touched > self.ttl:
                del self.sessions[key]

    def _session(self, key):
        self._purge()
        if not isinstance(key, str) or key not in self.sessions:
            raise PositionError('SESSION_EXPIRED', 'Sessão encerrada; clique em Resincronizar')
        session = self.sessions[key]
        session.touched = time.monotonic()
        return session

    @staticmethod
    def _result(key, session):
        return {'session': key, 'fen': session.board.fen(en_passant='fen'),
                'revision': session.revision, 'last_move': session.last_move,
                'history_complete': session.history_complete}

    def create(self, placement, turn, initial_fen=None):
        placement = self.placement(placement)
        if turn not in ('w', 'b'):
            raise PositionError('INVALID_POSITION', 'Vez deve ser w ou b')
        complete = False
        if initial_fen:
            if not isinstance(initial_fen, str) or len(initial_fen) > 256 or len(initial_fen.split()) != 6:
                raise PositionError('INVALID_POSITION', 'FEN inicial deve ter seis campos')
            try:
                board = chess.Board(initial_fen)
            except ValueError as exc:
                raise PositionError('INVALID_POSITION', str(exc)) from exc
            if board.board_fen() != placement:
                raise PositionError('DESYNC', 'A FEN informada não corresponde às peças observadas')
            complete = board.fen() == chess.STARTING_FEN
        elif placement == chess.Board().board_fen():
            board = chess.Board()
            complete = True
        else:
            board = chess.Board(placement + ' ' + turn + ' - - 0 1')
        if not board.is_valid():
            raise PositionError('INVALID_POSITION', f'Posição inválida: status={int(board.status())}')
        with self.lock:
            self._purge()
            if len(self.sessions) >= self.max_sessions:
                raise PositionError('SESSION_LIMIT', 'Limite de sessões; reinicie o servidor ou aguarde expiração')
            key = secrets.token_urlsafe(24)
            session = Session(board, complete, time.monotonic())
            self.sessions[key] = session
            return self._result(key, session)

    def sync(self, key, placement, revision=None):
        placement = self.placement(placement)
        with self.lock:
            session = self._session(key)
            if revision is not None and (type(revision) is not int or revision != session.revision):
                raise PositionError('STALE', 'Revisão mudou; confira o tabuleiro e resincronize')
            if session.board.board_fen() == placement:
                return self._result(key, session)
            if len(session.board.move_stack) >= 2048:
                raise PositionError('HISTORY_LIMIT', 'Histórico excedeu o limite; resincronize')
            matches = []
            for move in session.board.legal_moves:
                after = session.board.copy(stack=False)
                after.push(move)
                if after.board_fen() == placement:
                    matches.append(move)
            # A slow castle may expose a stable rook-only snapshot first.
            # Correct only the immediately preceding corner-rook displacement,
            # and only when the full new snapshot is a legal castle from before it.
            if not matches and session.board.move_stack:
                before = session.board.copy(stack=True)
                previous = before.pop()
                piece = before.piece_at(previous.from_square)
                rank = 0 if before.turn == chess.WHITE else 7
                rook_pairs = {(chess.square(7, rank), chess.square(5, rank)),
                              (chess.square(0, rank), chess.square(3, rank))}
                if piece and piece.piece_type == chess.ROOK and (previous.from_square, previous.to_square) in rook_pairs:
                    for castle in list(before.legal_moves):
                        if not before.is_castling(castle):
                            continue
                        after = before.copy(stack=False)
                        after.push(castle)
                        if after.board_fen() == placement:
                            before.push(castle)
                            session.board = before
                            session.last_move = castle.uci()
                            session.revision += 1
                            return self._result(key, session)
            if len(matches) != 1:
                raise PositionError('DESYNC', 'Tabuleiro não corresponde a uma jogada legal; espere a animação ou resincronize')
            session.board.push(matches[0])
            session.last_move = matches[0].uci()
            session.revision += 1
            return self._result(key, session)

    def get(self, key):
        with self.lock:
            return self._session(key).board.copy(stack=True)

    def delete(self, key):
        with self.lock:
            if isinstance(key, str):
                self.sessions.pop(key, None)
