#!/usr/bin/env python3
"""Encrypt or decrypt a file with age --passphrase via a PTY.

Passphrase is the first line of stdin (never argv). Remaining stdin is ignored.
"""

from __future__ import annotations

import os
import pty
import select
import subprocess
import sys
import time


def read_passphrase() -> str:
    line = sys.stdin.readline()
    if not line:
        sys.stderr.write("missing passphrase on stdin\n")
        sys.exit(2)
    return line.rstrip("\n")


def drive(args: list[str], passphrase: str, confirm: bool) -> int:
    master, slave = pty.openpty()
    proc = subprocess.Popen(
        args,
        stdin=slave,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
    )
    os.close(slave)
    sent_first = False
    sent_second = False
    buf = b""
    deadline = time.time() + 20
    while proc.poll() is None and time.time() < deadline:
        ready, _, _ = select.select([master], [], [], 0.1)
        if master not in ready:
            continue
        try:
            chunk = os.read(master, 4096)
        except OSError:
            break
        if not chunk:
            break
        buf += chunk
        text = buf.decode("utf-8", "replace").lower()
        if not sent_first and "passphrase" in text:
            os.write(master, (passphrase + "\n").encode())
            sent_first = True
        elif sent_first and confirm and not sent_second and "confirm" in text:
            os.write(master, (passphrase + "\n").encode())
            sent_second = True
    stdout, stderr = proc.communicate(timeout=15)
    try:
        os.close(master)
    except OSError:
        pass
    if stdout:
        sys.stdout.buffer.write(stdout)
    if stderr:
        sys.stderr.buffer.write(stderr)
    return proc.returncode or 0


def main() -> int:
    if len(sys.argv) < 3:
        sys.stderr.write("usage: age-crypt.py encrypt <plain> <dest.age>\n")
        sys.stderr.write("       age-crypt.py decrypt <src.age>\n")
        return 2
    action = sys.argv[1]
    passphrase = read_passphrase()
    if passphrase == "":
        sys.stderr.write("empty passphrase refused (age would autogenerate a key)\n")
        return 2
    if action == "encrypt":
        if len(sys.argv) != 4:
            sys.stderr.write("usage: age-crypt.py encrypt <plain> <dest.age>\n")
            return 2
        plain, dest = sys.argv[2], sys.argv[3]
        return drive(["age", "-e", "-p", "-o", dest, plain], passphrase, True)
    if action == "decrypt":
        src = sys.argv[2]
        return drive(["age", "-d", src], passphrase, False)
    sys.stderr.write("unknown action: " + action + "\n")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
