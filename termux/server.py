#!/usr/bin/env python3
"""Authenticated Stockfish UCI HTTP server."""
import argparse
import hmac
import json
import math
import secrets
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import chess
import chess.engine

ROOT = Path(__file__).resolve().parent

def attack_value(board, move):
    side = board.turn
    value = 0.0
    captured = board.piece_at(move.to_square)
    moving = board.piece_at(move.from_square)
    if captured:
        value += 1.0
    if moving:
        rank = chess.square_rank(move.to_square)
        value += (rank if side == chess.WHITE else 7 - rank) * 0.08
    after = board.copy()
    after.push(move)
    if after.is_check():
        value += 1.5
    king = after.king(not side)
    if king is not None:
        ring = set(after.attacks(king)) | {king}
        value += sum(len(after.attackers(side, sq)) for sq in ring) * 0.2
    # Material offered is only a preference inside the evaluation-loss budget.
    if moving and after.is_attacked_by(not side, move.to_square):
        value += {chess.PAWN:0.1,chess.KNIGHT:0.3,chess.BISHOP:0.3,
                  chess.ROOK:0.5,chess.QUEEN:0.8}.get(moving.piece_type, 0)
    return value

def select_line(board, lines, style, aggression):
    ranked = sorted(lines, key=lambda line: line["score"].pov(board.turn).score(mate_score=100000), reverse=True)
    best = ranked[0]
    best_score = best["score"].pov(board.turn)
    # Preserve forced mate decisions instead of treating mate as centipawns.
    if style == "precise" or aggression == 0 or best_score.is_mate():
        return best, 0
    top = best_score.score()
    budget = round(aggression * 0.5)  # 100 => at most 50 centipawns.
    eligible = [line for line in ranked
                if not line["score"].pov(board.turn).is_mate()
                and top - line["score"].pov(board.turn).score() <= budget]
    chosen = max(eligible, key=lambda line:
                 attack_value(board, line["pv"][0]) * (aggression / 100)
                 - (top - line["score"].pov(board.turn).score()) / 100)
    return chosen, top - chosen["score"].pov(board.turn).score()


class Service:
    def __init__(self, engine, key):
        self.engine, self.key = engine, key
        self.lock = threading.Lock()

    def analyse(self, payload):
        if not isinstance(payload, dict):
            raise ValueError("JSON deve ser um objeto")
        fen = payload.get("fen")
        if not isinstance(fen, str) or len(fen) > 256 or len(fen.split()) != 6:
            raise ValueError("Envie FEN completa com seis campos")
        board = chess.Board(fen)
        if not board.is_valid():
            raise ValueError(f"Posição inválida; status={int(board.status())}")
        seconds = float(payload.get("time", 1))
        if not math.isfinite(seconds) or not 0.1 <= seconds <= 10:
            raise ValueError("Tempo deve estar entre 0.1 e 10 segundos")
        style = payload.get("style", "precise")
        if style not in ("precise", "attacking"):
            raise ValueError("Estilo deve ser precise ou attacking")
        aggression = float(payload.get("aggression", 0))
        if not math.isfinite(aggression) or not 0 <= aggression <= 100:
            raise ValueError("Agressividade deve estar entre 0 e 100")
        outcome = board.outcome()
        if outcome:
            return {"game_over": True, "result": outcome.result(),
                    "reason": outcome.termination.name}
        if not self.lock.acquire(blocking=False):
            return None
        try:
            count = min(4, board.legal_moves.count()) if style == "attacking" and aggression > 0 else 1
            lines = self.engine.analyse(board, chess.engine.Limit(time=seconds), multipv=count)
            info, loss = select_line(board, lines, style, aggression)
            pv = info.get("pv", [])
            if not pv or pv[0] not in board.legal_moves:
                raise RuntimeError("Motor não retornou jogada legal")
            score = info.get("score")
            white = score.white() if score is not None else None
            cp = white.score() if white is not None else None
            return {"move": pv[0].uci(), "depth": info.get("depth"),
                    "eval": cp / 100 if cp is not None else None,
                    "mate": white.mate() if white is not None else None,
                    "pv": [m.uci() for m in pv], "nodes": info.get("nodes"),
                    "time": info.get("time"), "engine": self.engine.id.get("name"),
                    "fen": fen, "game_over": False, "style": style,
                    "aggression": aggression, "evaluation_loss_cp": loss,
                    "personality_supported": True, "multipv": count}
        finally:
            self.lock.release()

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def reply(self, status, data):
        body = json.dumps(data, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "close")
        self.end_headers()
        self.close_connection = True
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def authorized(self):
        expected = ("Bearer " + self.server.service.key).encode()
        actual = self.headers.get("Authorization", "").encode()
        if not hmac.compare_digest(actual, expected):
            self.reply(401, {"error": "UNAUTHORIZED", "text": "Chave incorreta"})
            return False
        return True

    def do_GET(self):
        if not self.authorized():
            return
        if self.path != "/health":
            self.reply(404, {"error": "NOT_FOUND"})
            return
        self.reply(200, {"ok": True, "engine": self.server.service.engine.id})

    def do_POST(self):
        if not self.authorized():
            return
        if self.path != "/analyse":
            self.reply(404, {"error": "NOT_FOUND"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= 4096:
                self.reply(413, {"error": "INVALID_SIZE"})
                return
            self.connection.settimeout(15)
            payload = json.loads(self.rfile.read(length))
            result = self.server.service.analyse(payload)
            self.reply(429, {"error": "BUSY"}) if result is None else self.reply(200, result)
        except (ValueError, TypeError, UnicodeError) as exc:
            self.reply(400, {"error": "INVALID_REQUEST", "text": str(exc)})
        except TimeoutError:
            self.reply(408, {"error": "TIMEOUT"})
        except Exception as exc:
            print(f"Erro no motor: {type(exc).__name__}: {exc}", flush=True)
            self.reply(503, {"error": "ENGINE_ERROR", "text": "Reinicie o servidor"})

    def log_message(self, fmt, *args):
        print(fmt % args, flush=True)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--engine", default=str(ROOT / "bin" / "stockfish"))
    parser.add_argument("--threads", type=int, default=2)
    parser.add_argument("--hash", type=int, default=128)
    parser.add_argument("--port", type=int, default=8080)
    args = parser.parse_args()
    if not 1 <= args.threads <= 16 or not 16 <= args.hash <= 1024:
        parser.error("threads: 1–16; hash: 16–1024 MB")
    key_path = ROOT / ".api-key"
    if not key_path.exists():
        key_path.write_text(secrets.token_urlsafe(32) + "\n")
    key_path.chmod(0o600)
    key = key_path.read_text().strip()
    if not key:
        raise SystemExit("Arquivo .api-key vazio")
    with chess.engine.SimpleEngine.popen_uci(args.engine, timeout=20) as engine:
        engine.configure({"Threads": args.threads, "Hash": args.hash})
        server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
        server.service = Service(engine, key)
        print("Motor:", engine.id.get("name"), flush=True)
        print("Chave para colar no painel:", key, flush=True)
        print(f"Servidor: http://127.0.0.1:{args.port}", flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass
        finally:
            server.server_close()

if __name__ == "__main__":
    main()

