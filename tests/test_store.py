from __future__ import annotations

import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "bin" / "journal-store.py"


def run_store(home: Path, op: str, stdin: bytes = b"", extra_env: dict[str, str] | None = None) -> subprocess.CompletedProcess[bytes]:
    env = {
        "HOME": str(home),
        "PATH": "/usr/bin",
        "LC_ALL": "C",
    }
    if extra_env:
        env.update(extra_env)
    return subprocess.run(
        ["/usr/bin/python3", "-I", "-S", str(HELPER), op],
        input=stdin,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        timeout=8,
        check=False,
    )


class JournalStoreTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)

    def store_dir(self) -> Path:
        return self.home / ".local" / "state" / "omarchy" / "myjournal"

    def test_write_then_read_roundtrip(self) -> None:
        payload = json.dumps(
            [{"id": "1", "timestamp": "2026-08-19T10:10:00.000Z", "content": "Hello", "kind": "note"}]
        ).encode()
        written = run_store(self.home, "write", payload)
        self.assertEqual(written.returncode, 0, written.stderr.decode())
        journal = self.store_dir() / "journal.json"
        notes = self.store_dir() / "notes.txt"
        st = journal.stat()
        self.assertTrue(stat.S_ISREG(st.st_mode))
        self.assertEqual(stat.S_IMODE(st.st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(self.store_dir().stat().st_mode), 0o700)
        self.assertIn(b"Hello", notes.read_bytes())
        read = run_store(self.home, "read")
        self.assertEqual(read.returncode, 0, read.stderr.decode())
        rows = json.loads(read.stdout.decode())
        self.assertEqual(rows[0]["content"], "Hello")

    def test_missing_file_is_empty_not_error(self) -> None:
        read = run_store(self.home, "read")
        self.assertEqual(read.returncode, 0, read.stderr.decode())
        self.assertEqual(read.stdout, b"")

    def test_write_replaces_symlink_instead_of_following(self) -> None:
        victim_dir = Path(self.tmp.name) / "victim-dir"
        victim_dir.mkdir()
        victim = victim_dir / "victim"
        victim.write_bytes(b"must survive\n")
        first = run_store(self.home, "write", b"[]")
        self.assertEqual(first.returncode, 0, first.stderr.decode())
        journal = self.store_dir() / "journal.json"
        journal.unlink()
        journal.symlink_to(victim)
        payload = json.dumps(
            [{"id": "1", "timestamp": "t", "content": "new", "kind": "note"}]
        ).encode()
        written = run_store(self.home, "write", payload)
        self.assertEqual(written.returncode, 0, written.stderr.decode())
        self.assertEqual(victim.read_bytes(), b"must survive\n")
        self.assertFalse(journal.is_symlink())
        self.assertIn(b"new", journal.read_bytes())

    def test_read_refuses_symlink(self) -> None:
        first = run_store(self.home, "write", b"[]")
        self.assertEqual(first.returncode, 0, first.stderr.decode())
        journal = self.store_dir() / "journal.json"
        journal.unlink()
        journal.symlink_to("/etc/passwd")
        read = run_store(self.home, "read")
        self.assertNotEqual(read.returncode, 0)
        self.assertGreater(len(read.stderr), 0)

    def test_rejects_oversize_payload(self) -> None:
        huge = b"[" + b'"x"' * 200000 + b"]"
        written = run_store(self.home, "write", huge)
        self.assertNotEqual(written.returncode, 0)

    def test_rejects_too_many_entries(self) -> None:
        rows = [{"id": str(i), "timestamp": "t", "content": "x", "kind": "note"} for i in range(401)]
        written = run_store(self.home, "write", json.dumps(rows).encode())
        self.assertNotEqual(written.returncode, 0)
        self.assertIn(b"too many", written.stderr)


if __name__ == "__main__":
    unittest.main()
