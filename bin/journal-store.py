#!/usr/bin/python3 -I
"""Descriptor-bound read/write for ~/.local/state/omarchy/myjournal/."""

from __future__ import annotations

import json
import os
import re
import select
import stat
import sys
import time

MAX_BYTES = 262144
MAX_ENTRIES = 400
MAX_CONTENT = 16384
MAX_ID = 16
MAX_TIMESTAMP = 40
MAX_STDERR = 200
READ_DEADLINE_S = 8.0
PLUGIN_PARTS = (".local", "state", "omarchy", "myjournal")
JSON_NAME = "journal.json"
TXT_NAME = "notes.txt"
ID_RE = re.compile(r"^[0-9]{1,16}$")
COMPONENT_RE = re.compile(r"^[A-Za-z0-9._-]+$")


class StoreError(RuntimeError):
    def __init__(self, message: str, code: int = 1) -> None:
        super().__init__(message)
        self.code = code


def die(message: str, code: int = 1) -> None:
    sys.stderr.write(message[:MAX_STDERR] + "\n")
    raise SystemExit(code)


def open_dir_chain(parts: tuple[str, ...]) -> int:
    home = os.path.expanduser("~")
    if not home or not os.path.isabs(home):
        raise StoreError("HOME is not an absolute path")
    fd = os.open(home, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC)
    try:
        last = len(parts) - 1
        for i, name in enumerate(parts):
            if not COMPONENT_RE.fullmatch(name) or name in (".", ".."):
                raise StoreError("bad path component")
            try:
                nfd = os.open(
                    name,
                    os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC,
                    dir_fd=fd,
                )
            except FileNotFoundError:
                os.mkdir(name, 0o700, dir_fd=fd)
                nfd = os.open(
                    name,
                    os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC,
                    dir_fd=fd,
                )
            os.close(fd)
            fd = nfd
            st = os.fstat(fd)
            if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.geteuid():
                raise StoreError("untrusted directory")
            if i == last and (st.st_mode & 0o077):
                os.fchmod(fd, 0o700)
        return fd
    except BaseException:
        os.close(fd)
        raise


def read_bounded(dirfd: int, name: str) -> bytes | None:
    try:
        fd = os.open(
            name,
            os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC,
            dir_fd=dirfd,
        )
    except FileNotFoundError:
        return None
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_uid != os.geteuid() or st.st_nlink != 1:
            raise StoreError("refusing state file")
        if st.st_size > MAX_BYTES:
            raise StoreError("state file exceeds size limit")
        if st.st_mode & 0o077:
            os.fchmod(fd, 0o600)
        os.set_blocking(fd, True)
        data = b""
        while len(data) <= MAX_BYTES:
            chunk = os.read(fd, min(65536, MAX_BYTES + 1 - len(data)))
            if not chunk:
                break
            data += chunk
        if len(data) > MAX_BYTES:
            raise StoreError("state file grew past the limit")
        return data
    finally:
        os.close(fd)


def write_atomic(dirfd: int, name: str, data: bytes) -> None:
    if len(data) > MAX_BYTES:
        raise StoreError("payload too large", 3)
    tmp = f".{name}.{os.urandom(8).hex()}.tmp"
    fd = os.open(
        tmp,
        os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
        0o600,
        dir_fd=dirfd,
    )
    try:
        os.fchmod(fd, 0o600)
        view = memoryview(data)
        while view:
            n = os.write(fd, view)
            if n <= 0:
                raise StoreError("short write")
            view = view[n:]
        os.fsync(fd)
        os.rename(tmp, name, src_dir_fd=dirfd, dst_dir_fd=dirfd)
        tmp = ""
        os.fsync(dirfd)
    except BaseException:
        if tmp:
            try:
                os.unlink(tmp, dir_fd=dirfd)
            except OSError:
                pass
        raise
    finally:
        os.close(fd)


def copy_entry(item: object) -> dict[str, object]:
    if not isinstance(item, dict):
        raise StoreError("journal entry is not an object")
    raw_id = item.get("id")
    ident = str(raw_id) if raw_id is not None else ""
    if not ID_RE.fullmatch(ident):
        raise StoreError("journal id is invalid")
    ts = str(item.get("timestamp") or "")
    if len(ts) > MAX_TIMESTAMP:
        raise StoreError("journal timestamp is too long")
    content = str(item.get("content") or "")
    if len(content) > MAX_CONTENT:
        raise StoreError("journal entry exceeds content limit")
    kind = "todo" if item.get("kind") == "todo" else "note"
    out: dict[str, object] = {"id": ident, "timestamp": ts, "content": content, "kind": kind}
    if kind == "todo":
        out["done"] = bool(item.get("done"))
    return out


def parse_journal(raw: bytes) -> list[dict[str, object]]:
    if not raw:
        return []
    try:
        value = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise StoreError("could not parse journal") from exc
    if isinstance(value, dict) and isinstance(value.get("entries"), list):
        rows = value["entries"]
    elif isinstance(value, list):
        rows = value
    else:
        raise StoreError("journal is not a list")
    if len(rows) > MAX_ENTRIES:
        raise StoreError("too many journal entries")
    return [copy_entry(item) for item in rows]


def serialize_journal(entries: list[dict[str, object]]) -> bytes:
    return (json.dumps(entries, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def notes_txt(entries: list[dict[str, object]]) -> bytes:
    if not entries:
        return b""
    parts: list[str] = []
    for entry in entries:
        mark = ""
        if entry.get("kind") == "todo":
            mark = " · todo [x]" if entry.get("done") else " · todo"
        content = str(entry.get("content") or "").rstrip()
        parts.append(
            f"======= {entry['id']} · {entry['timestamp']}{mark} =======\n{content}\n"
        )
    return ("\n".join(parts)).encode("utf-8")


def read_stdin_json() -> bytes:
    fd = sys.stdin.fileno()
    data = b""
    deadline = time.monotonic() + READ_DEADLINE_S
    while len(data) <= MAX_BYTES:
        remain = deadline - time.monotonic()
        if remain <= 0:
            break
        ready, _, _ = select.select([fd], [], [], min(0.25, remain))
        if not ready:
            if data:
                break
            continue
        chunk = os.read(fd, min(65536, MAX_BYTES + 1 - len(data)))
        if not chunk:
            break
        data += chunk
        try:
            json.loads(data.decode("utf-8"))
            break
        except (UnicodeDecodeError, json.JSONDecodeError):
            continue
    if len(data) > MAX_BYTES:
        raise StoreError("payload too large", 3)
    return data


def cmd_read(dirfd: int) -> None:
    raw = read_bounded(dirfd, JSON_NAME)
    if raw is None:
        return
    entries = parse_journal(raw)
    sys.stdout.buffer.write(serialize_journal(entries))


def cmd_write(dirfd: int) -> None:
    entries = parse_journal(read_stdin_json())
    write_atomic(dirfd, JSON_NAME, serialize_journal(entries))
    write_atomic(dirfd, TXT_NAME, notes_txt(entries))


def main(argv: list[str]) -> int:
    if len(argv) != 2 or argv[1] not in ("read", "write"):
        die("usage: journal-store.py read|write", 2)
    try:
        os.setsid()
    except OSError:
        pass
    try:
        dirfd = open_dir_chain(PLUGIN_PARTS)
    except StoreError as exc:
        die(str(exc), exc.code)
    except OSError as exc:
        die(str(exc) or "directory error")
    try:
        if argv[1] == "read":
            cmd_read(dirfd)
        else:
            cmd_write(dirfd)
    except StoreError as exc:
        die(str(exc), exc.code)
    except OSError as exc:
        die(str(exc) or "I/O error")
    finally:
        os.close(dirfd)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
