# Python / check_engine.py / Python 3.10+ / real Stockfish smoke tests.
import argparse
import chess
from server import EngineManager, Service


def check(path):
    engine = EngineManager(path, 1, 32)
    service = Service(engine, 'test')
    count = 0
    try:
        for fen, style in [(chess.STARTING_FEN, 'precise'),
                           (chess.STARTING_FEN, 'attacking'),
                           ('7k/5Q2/6K1/8/8/8/8/8 w - - 0 1', 'precise')]:
            result = service.analyse({'fen': fen, 'time': 0.1, 'style': style, 'aggression': 100})
            board = chess.Board(fen)
            move = chess.Move.from_uci(result['move'])
            assert move in board.legal_moves, result
            assert 0 <= result['evaluation_loss_cp'] <= 50, result
            if fen.startswith('7k/'):
                board.push(move)
                assert board.is_checkmate(), result
            print('OK:', style, result['move'], 'profundidade', result['depth'])
            count += 1
        session = service.positions.create(chess.Board().board_fen(), 'w')
        board = chess.Board(); board.push_uci('e2e4')
        session = service.positions.sync(session['session'], board.board_fen(), 0)
        result = service.analyse({**session, 'time': 0.1})
        assert chess.Move.from_uci(result['move']) in board.legal_moves
        assert result['revision'] == 1
        count += 1
        engine.engine.close()
        result = service.analyse({'fen': chess.STARTING_FEN, 'time': 0.1})
        assert chess.Move.from_uci(result['move']) in chess.Board().legal_moves
        count += 1
        print(f'{count} verificações com {engine.id.get("name")} passaram.')
    finally:
        engine.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--engine', required=True)
    check(parser.parse_args().engine)
