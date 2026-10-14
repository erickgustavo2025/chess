# Python / test_castling_animation.py / Python 3.10+ / late castling animation regression.
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'termux'))
import chess
from positions import PositionStore

class CastlingAnimationTests(unittest.TestCase):
    def test_rook_arriving_before_king_is_corrected_atomically(self):
        for turn, rook_move, castle in [('w','h1f1','e1g1'),('w','a1d1','e1c1'),
                                       ('b','h8f8','e8g8'),('b','a8d8','e8c8')]:
            with self.subTest(castle=castle):
                before=chess.Board(f'r3k2r/8/8/8/8/8/8/R3K2R {turn} KQkq - 0 1')
                store=PositionStore()
                data=store.create(before.board_fen(),turn,before.fen())
                transient=before.copy(); transient.push_uci(rook_move)
                first=store.sync(data['session'],transient.board_fen(),0)
                final=before.copy(); final.push_uci(castle)
                result=store.sync(data['session'],final.board_fen(),first['revision'])
                actual=store.get(data['session'])
                self.assertEqual(actual.fen(en_passant='fen'),final.fen(en_passant='fen'))
                self.assertEqual([m.uci() for m in actual.move_stack],[castle])
                self.assertEqual(result['last_move'],castle)

if __name__=='__main__': unittest.main()
