"""Regression tests for legal, atomic visual-board reconciliation."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'termux'))
import chess
from positions import PositionStore, PositionError


class PositionTests(unittest.TestCase):
    def setUp(self):
        self.store = PositionStore(max_sessions=32, ttl=7200)

    def create(self, fen):
        board = chess.Board(fen)
        return self.store.create(board.board_fen(), 'w' if board.turn else 'b', initial_fen=fen)

    def advance(self, state, uci):
        board = self.store.get(state['session'])
        board.push_uci(uci)
        result = self.store.sync(state['session'], board.board_fen(), revision=state['revision'])
        self.assertEqual(result['last_move'], uci)
        self.assertEqual(result['revision'], state['revision'] + 1)
        self.assertEqual(result['fen'], board.fen(en_passant='fen'))
        return result

    def error(self, code, action):
        with self.assertRaises(PositionError) as caught:
            action()
        self.assertEqual(caught.exception.code, code)

    def test_starting_position_has_rights_and_complete_history(self):
        result = self.store.create(chess.Board().board_fen(), 'w')
        self.assertEqual(result['fen'], chess.STARTING_FEN)
        self.assertTrue(result['history_complete'])

    def test_midgame_defaults_without_inferred_rights(self):
        board = chess.Board('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1')
        result = self.store.create(board.board_fen(), 'w')
        actual = self.store.get(result['session'])
        self.assertEqual(actual.castling_rights, 0)
        self.assertIsNone(actual.ep_square)
        self.assertFalse(result['history_complete'])

    def test_four_castlings_are_atomic(self):
        for turn, move in [('w', 'e1g1'), ('w', 'e1c1'), ('b', 'e8g8'), ('b', 'e8c8')]:
            with self.subTest(move=move):
                state = self.create(f'r3k2r/8/8/8/8/8/8/R3K2R {turn} KQkq - 0 1')
                self.advance(state, move)

    def test_rook_displacement_is_a_legal_rook_move(self):
        state = self.create('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1')
        self.advance(state, 'h1f1')

    def test_en_passant_from_sequence(self):
        state = self.store.create(chess.Board().board_fen(), 'w')
        for move in ['e2e4', 'a7a6', 'e4e5', 'd7d5', 'e5d6']:
            state = self.advance(state, move)
        self.assertIsNone(self.store.get(state['session']).piece_at(chess.D5))

    def test_all_promotion_choices(self):
        for piece in 'qrbn':
            with self.subTest(piece=piece):
                state = self.create('7k/P7/8/8/8/8/8/7K w - - 0 1')
                self.advance(state, 'a7a8' + piece)

    def test_capture(self):
        state = self.store.create(chess.Board().board_fen(), 'w')
        for move in ['e2e4', 'd7d5', 'e4d5']:
            state = self.advance(state, move)

    def test_idempotent_snapshot(self):
        state = self.store.create(chess.Board().board_fen(), 'w')
        result = self.store.sync(state['session'], chess.Board().board_fen(), revision=state['revision'])
        self.assertEqual(result['revision'], state['revision'])
        self.assertEqual(result['fen'], state['fen'])
        self.assertIsNone(result['last_move'])

    def test_illegal_displacement_does_not_mutate(self):
        state = self.store.create(chess.Board().board_fen(), 'w')
        invalid = chess.Board()
        invalid.set_piece_at(chess.E5, invalid.remove_piece_at(chess.E2))
        self.error('DESYNC', lambda: self.store.sync(state['session'], invalid.board_fen()))
        self.assertEqual(self.store.get(state['session']).fen(en_passant='fen'), state['fen'])
        valid = self.advance(state, 'e2e4')
        self.assertEqual(valid['revision'], state['revision'] + 1)

    def test_pinned_piece_cannot_expose_king(self):
        state = self.create('k3r3/8/8/8/8/8/4R3/4K3 w - - 0 1')
        invalid = self.store.get(state['session'])
        invalid.set_piece_at(chess.D2, invalid.remove_piece_at(chess.E2))
        self.error('DESYNC', lambda: self.store.sync(state['session'], invalid.board_fen()))
        self.assertEqual(self.store.get(state['session']).fen(en_passant='fen'), state['fen'])

    def test_history_retains_repetition(self):
        state = self.store.create(chess.Board().board_fen(), 'w')
        for move in ['g1f3', 'g8f6', 'f3g1', 'f6g8'] * 2:
            state = self.advance(state, move)
        board = self.store.get(state['session'])
        self.assertEqual(len(board.move_stack), 8)
        self.assertTrue(board.is_repetition(3))

    def test_stale_revision_and_unknown_session(self):
        state = self.store.create(chess.Board().board_fen(), 'w')
        state = self.advance(state, 'e2e4')
        self.error('STALE', lambda: self.store.sync(state['session'], self.store.get(state['session']).board_fen(), revision=state['revision'] - 1))
        self.error('SESSION_EXPIRED', lambda: self.store.get('unknown'))
        self.error('SESSION_EXPIRED', lambda: self.store.sync('unknown', chess.Board().board_fen()))

    def test_get_returns_isolated_copy_with_history(self):
        state = self.store.create(chess.Board().board_fen(), 'w')
        state = self.advance(state, 'e2e4')
        copy = self.store.get(state['session'])
        self.assertEqual(len(copy.move_stack), 1)
        copy.push_uci('e7e5')
        original = self.store.get(state['session'])
        self.assertEqual(original.fen(en_passant='fen'), state['fen'])
        self.assertEqual(len(original.move_stack), 1)

    def test_fools_mate_terminal_position(self):
        state = self.store.create(chess.Board().board_fen(), 'w')
        for move in ['f2f3', 'e7e5', 'g2g4', 'd8h4']:
            state = self.advance(state, move)
        self.assertTrue(self.store.get(state['session']).is_checkmate())

    def test_zero_ttl_expires_session(self):
        store = PositionStore(ttl=0)
        state = store.create(chess.Board().board_fen(), 'w')
        self.error('SESSION_EXPIRED', lambda: store.get(state['session']))

    def test_session_limit_is_enforced(self):
        store = PositionStore(max_sessions=1)
        state = store.create(chess.Board().board_fen(), 'w')
        self.error('SESSION_LIMIT', lambda: store.create(chess.Board().board_fen(), 'w'))
        self.assertEqual(store.get(state['session']).fen(), chess.STARTING_FEN)

    def test_initial_fen_turn_is_authoritative(self):
        fen = '7k/8/8/8/8/8/8/7K b - - 0 1'
        state = self.store.create(chess.Board(fen).board_fen(), 'w', initial_fen=fen)
        self.assertFalse(self.store.get(state['session']).turn)

    def test_initial_fen_must_match_and_be_valid(self):
        placement = chess.Board().board_fen()
        for fen in ['8/8/8/8/8/8/8/8 w - - 0 1', 'not a fen']:
            with self.subTest(fen=fen), self.assertRaises(PositionError):
                self.store.create(placement, 'w', initial_fen=fen)


if __name__ == '__main__':
    unittest.main()
