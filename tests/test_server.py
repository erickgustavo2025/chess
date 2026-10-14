"""HTTP contracts with fake UCI engine; no real engine operations."""
import http.client
import json
import sys
import threading
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'termux'))
import chess
import chess.engine
import server


class FakeEngine:
    id = {'name': 'ContractEngine'}

    def __init__(self, failed=False):
        self.failed = failed
        self.closed = False
        self.calls = []

    def configure(self, options):
        self.options = options

    def analyse(self, board, limit, multipv=1):
        if self.failed:
            raise chess.engine.EngineTerminatedError('terminated')
        self.calls.append((board.copy(), limit, multipv))
        return [{'score': chess.engine.PovScore(chess.engine.Cp(30 - i), board.turn),
                 'pv': [move], 'depth': 5, 'nodes': 100, 'time': 0.01}
                for i, move in enumerate(list(board.legal_moves)[:multipv])]

    def close(self):
        self.closed = True


class HTTPTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.engine = FakeEngine()
        cls.httpd = server.BoundedServer(('127.0.0.1', 0), server.Handler)
        cls.httpd.service = server.Service(cls.engine, 'test-secret')
        cls.thread = threading.Thread(target=cls.httpd.serve_forever, kwargs={'poll_interval': 0.01}, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()
        cls.httpd.server_close()
        cls.thread.join(timeout=2)

    def request(self, path, payload=None, auth=True, raw=None, method='POST'):
        conn = http.client.HTTPConnection(*self.httpd.server_address, timeout=3)
        headers = {'Content-Type': 'application/json'}
        if auth:
            headers['Authorization'] = 'Bearer test-secret'
        body = raw if raw is not None else json.dumps(payload).encode() if payload is not None else None
        conn.request(method, path, body=body, headers=headers)
        response = conn.getresponse()
        status, out_headers, data = response.status, dict(response.getheaders()), json.loads(response.read())
        conn.close()
        return status, out_headers, data

    def new_session(self):
        status, _, state = self.request('/session', {'placement': chess.Board().board_fen(), 'turn': 'w'})
        self.assertEqual(status, 200)
        return state

    def test_auth_and_health_v2(self):
        self.assertEqual(self.request('/health', auth=False, method='GET')[0], 401)
        status, headers, result = self.request('/health', method='GET')
        self.assertEqual(status, 200)
        self.assertEqual(result['version'], '2.0.0')
        self.assertTrue(result['sessions'])
        self.assertEqual(headers['Cache-Control'], 'no-store')

    def test_session_sync_and_analysis_schema(self):
        state = self.new_session()
        board = chess.Board()
        board.push_uci('e2e4')
        status, _, state = self.request('/sync', {'session': state['session'], 'revision': state['revision'], 'placement': board.board_fen()})
        self.assertEqual(status, 200)
        self.assertEqual(state['revision'], 1)
        status, _, result = self.request('/analyse', {'session': state['session'], 'revision': 1})
        self.assertEqual(status, 200)
        self.assertEqual(result['revision'], 1)
        self.assertIn(chess.Move.from_uci(result['move']), board.legal_moves)
        for key in ['pv', 'eval', 'mate', 'multipv', 'style', 'version', 'requested_time', 'search_budget']:
            self.assertIn(key, result)
        self.assertEqual(result['eval'], -0.3)

    def test_invalid_requests(self):
        cases = [{'fen': 'invalid'}, {'fen': chess.STARTING_FEN, 'style': 'invalid'},
                 {'fen': chess.STARTING_FEN, 'time': float('nan')},
                 {'fen': chess.STARTING_FEN, 'time': True},
                 {'fen': chess.STARTING_FEN, 'aggression': True},
                 {'fen': chess.STARTING_FEN, 'aggression': float('nan')}, []]
        for case in cases:
            with self.subTest(case=case):
                self.assertEqual(self.request('/analyse', case)[0], 400)
        self.assertEqual(self.request('/analyse', raw=b'{')[0], 400)
        self.assertEqual(self.request('/analyse', raw=b'x' * 4097)[0], 413)
        self.assertEqual(self.request('/analyse', raw=b'')[0], 413)

    def test_busy_retry_header(self):
        self.httpd.service.lock.acquire()
        try:
            status, headers, result = self.request('/analyse', {'fen': chess.STARTING_FEN})
        finally:
            self.httpd.service.lock.release()
        self.assertEqual(status, 429)
        self.assertEqual(headers['Retry-After'], '1')
        self.assertEqual(result['error'], 'BUSY')

    def test_close_unknown_and_stale(self):
        self.assertEqual(self.request('/close', {'session': 'unknown'})[0], 200)
        state = self.new_session()
        status, _, result = self.request('/analyse', {'session': state['session'], 'revision': 99})
        self.assertEqual(status, 409)
        self.assertEqual(result['error'], 'STALE')
        self.request('/close', {'session': state['session']})
        status, _, result = self.request('/analyse', {'session': state['session'], 'revision': 0})
        self.assertEqual(status, 409)
        self.assertEqual(result['error'], 'SESSION_EXPIRED')

    def test_terminal_fools_mate(self):
        state = self.new_session()
        board = chess.Board()
        for move in ['f2f3', 'e7e5', 'g2g4', 'd8h4']:
            board.push_uci(move)
            status, _, state = self.request('/sync', {'session': state['session'], 'revision': state['revision'], 'placement': board.board_fen()})
            self.assertEqual(status, 200)
        status, _, result = self.request('/analyse', {'session': state['session'], 'revision': state['revision']})
        self.assertEqual(status, 200)
        self.assertTrue(result['game_over'])
        self.assertEqual(result['result'], '0-1')
        self.assertEqual(result['reason'], 'CHECKMATE')

    def test_style_and_force_precise(self):
        service = server.Service(FakeEngine(), 'key')
        result = service.analyse({'fen': chess.STARTING_FEN, 'style': 'attacking', 'aggression': 50})
        self.assertEqual(result['multipv'], 4)
        self.assertEqual(result['style'], 'attacking')
        self.assertLessEqual(result['evaluation_loss_cp'], 25)
        precise = server.Service(FakeEngine(), 'key', force_precise=True)
        result = precise.analyse({'fen': chess.STARTING_FEN, 'style': 'attacking', 'aggression': 50})
        self.assertEqual(result['multipv'], 1)
        self.assertEqual(result['style'], 'precise')
        self.assertEqual(result['aggression'], 0)
        self.assertFalse(result['personality_supported'])


class EngineRecoveryTests(unittest.TestCase):
    def test_terminated_process_is_replaced_once(self):
        broken, healthy = FakeEngine(failed=True), FakeEngine()
        with patch('server.chess.engine.SimpleEngine.popen_uci', side_effect=[broken, healthy]) as spawn:
            manager = server.EngineManager('stockfish', 2, 128)
            result = manager.analyse(chess.Board(), chess.engine.Limit(time=0.1), multipv=1)
            self.assertTrue(result[0]['pv'])
            self.assertTrue(broken.closed)
            self.assertEqual(spawn.call_count, 2)
            manager.close()
            self.assertTrue(healthy.closed)

    def test_second_failure_propagates(self):
        first, second = FakeEngine(failed=True), FakeEngine(failed=True)
        with patch('server.chess.engine.SimpleEngine.popen_uci', side_effect=[first, second]) as spawn:
            manager = server.EngineManager('stockfish', 2, 128)
            with self.assertRaises(chess.engine.EngineTerminatedError):
                manager.analyse(chess.Board(), chess.engine.Limit(time=0.1))
            self.assertEqual(spawn.call_count, 2)
            self.assertTrue(first.closed)
            manager.close()


if __name__ == '__main__':
    unittest.main()
