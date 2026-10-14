"""Optional geometry checks: set LUAU_BIN to the standalone Luau executable.
No Luau installation is required by the normal Python server suite.
"""
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(os.environ.get('LUAU_BIN'), 'Optional client geometry test: set LUAU_BIN')
class ClientGeometryTests(unittest.TestCase):
    def test_actual_production_geometry(self):
        source = (ROOT / 'chess_termux.lua').read_text()
        geometry = source[source.index('local function center(square)'):source.index('local function brightness(obj)')]
        harness = (ROOT / 'tests' / 'client_harness.luau').read_text()
        assembled = harness.replace('-- PRODUCTION_GEOMETRY', geometry)
        with tempfile.TemporaryDirectory() as directory:
            script = Path(directory) / 'client_geometry.luau'
            script.write_text(assembled)
            result = subprocess.run([os.environ['LUAU_BIN'], str(script)], capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('all 64 squares passed', result.stdout)


if __name__ == '__main__':
    unittest.main()
