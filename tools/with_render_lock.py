#!/usr/bin/env python3
"""Serialize one foreground rendering command across this user's worktrees."""
import errno
import fcntl
import hashlib
import json
import os
import stat
import sys


HANDOFF_ENV = "MOONLANTERN_RENDER_HANDOFF_FD"
_MAX_HANDOFF_BYTES = 2048


def _require(condition, message):
    if not condition:
        raise ValueError(message)


def _identity(fd):
    info = os.fstat(fd)
    return {"fd": fd, "device": info.st_dev, "inode": info.st_ino, "uid": info.st_uid}


def _command_hash(command):
    _require(isinstance(command, (list, tuple)) and command
             and all(isinstance(arg, str) for arg in command), "invalid exec command")
    return hashlib.sha256(json.dumps(list(command), ensure_ascii=True,
                                    separators=(",", ":")).encode("ascii")).hexdigest()


def _lock_path():
    return f"/tmp/moonlantern-render-{os.getuid()}.lock"


def _handoff(lock_fd, command):
    """Called only after EX succeeds. A fresh bounded pipe cannot block on write."""
    reader, writer = os.pipe()
    try:
        proof = {"version": 1, "pid": os.getpid(), "lock": _identity(lock_fd),
                 "receipt": _identity(reader), "command_sha256": _command_hash(command)}
        raw = json.dumps(proof, separators=(",", ":"), ensure_ascii=True).encode("ascii")
        _require(len(raw) <= min(_MAX_HANDOFF_BYTES, os.fpathconf(writer, "PC_PIPE_BUF")),
                 "render handoff exceeds atomic pipe bound")
        _require(os.write(writer, raw) == len(raw), "incomplete render handoff")
        os.set_inheritable(reader, True)
        return reader
    except BaseException:
        os.close(reader)
        raise
    finally:
        os.close(writer)  # EOF is part of the handoff, never inherit a writer.


def verify_render_lock_handoff(proof, command, *, lock_path=None):
    """Recheck retained proof; never acquire/convert the inherited lock.

    The separate SH probe only tests an existing EX conflict. If it succeeds,
    closing the probe releases SH and verification fails; it can never supply EX.
    This is a cooperative source contract, not hostile same-user authentication.
    """
    try:
        _require(isinstance(proof, dict) and set(proof) ==
                 {"version", "pid", "lock", "receipt", "command_sha256"}, "invalid render handoff schema")
        _require(type(proof["version"]) is int and proof["version"] == 1
                 and type(proof["pid"]) is int and proof["pid"] == os.getpid(), "render handoff PID/version differs")
        _require(proof["command_sha256"] == _command_hash(command), "render exec command differs")
        for row in (proof["lock"], proof["receipt"]):
            _require(isinstance(row, dict) and set(row) == {"fd", "device", "inode", "uid"}
                     and all(type(value) is int and value >= 0 for value in row.values())
                     and row["fd"] >= 3 and row["uid"] == os.getuid(), "invalid render descriptor binding")
        fd = proof["lock"]["fd"]
        _require(fd != proof["receipt"]["fd"] and _identity(fd) == proof["lock"]
                 and stat.S_ISREG(os.fstat(fd).st_mode) and os.get_inheritable(fd),
                 "inherited render lock identity differs")
        path = lock_path if lock_path is not None else _lock_path()
        info = os.lstat(path)
        _require(stat.S_ISREG(info.st_mode)
                 and (info.st_dev, info.st_ino, info.st_uid) ==
                 tuple(proof["lock"][key] for key in ("device", "inode", "uid")),
                 "render lock path differs")
        probe = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        try:
            _require(tuple(_identity(probe)[key] for key in ("device", "inode", "uid")) ==
                     tuple(proof["lock"][key] for key in ("device", "inode", "uid")), "render probe identity differs")
            try:
                fcntl.flock(probe, fcntl.LOCK_SH | fcntl.LOCK_NB)
            except OSError as error:
                if error.errno not in (errno.EACCES, errno.EAGAIN):
                    raise
            else:
                raise ValueError("render lock is not already exclusive")
        finally:
            os.close(probe)
    except (KeyError, TypeError, OSError) as error:
        raise ValueError("invalid inherited render handoff") from error
    return proof


def consume_render_lock_handoff(command, *, lock_path=None):
    """Consume once, before output/child creation. Keep proof + lock FD to exit.

    Python consumers pass [sys.executable, *sys.orig_argv[1:]] and the wrapper
    command must use that exact executable spelling (not a PATH alias). The environment is
    only a pipe locator. No regular file, write end, partial/open pipe or replay
    is accepted. The receipt closes on consumption; the lock FD stays untouched.
    """
    try:
        locator = os.environ.get(HANDOFF_ENV, "")
        _require(locator.isascii() and locator.isdecimal(), "missing render handoff")
        fd = int(locator)
        _require(fd >= 3, "invalid render handoff descriptor")
        info = os.fstat(fd)
        _require(stat.S_ISFIFO(info.st_mode) and info.st_nlink == 0 and os.get_inheritable(fd)
                 and fcntl.fcntl(fd, fcntl.F_GETFL) & os.O_ACCMODE == os.O_RDONLY,
                 "render handoff must be an inherited read-only pipe")
    except OSError as error:
        raise ValueError("render handoff descriptor missing or consumed") from error
    try:
        identity = _identity(fd)
        os.set_blocking(fd, False)
        raw = bytearray()
        while True:
            part = os.read(fd, _MAX_HANDOFF_BYTES + 1 - len(raw))
            if not part:
                break
            raw.extend(part)
            _require(len(raw) <= _MAX_HANDOFF_BYTES, "oversized render handoff")
        def pairs(rows):
            result = {}
            for key, value in rows:
                _require(key not in result, "duplicate render handoff key")
                result[key] = value
            return result
        proof = json.loads(raw, object_pairs_hook=pairs)
        _require(isinstance(proof, dict) and proof.get("receipt") == identity,
                 "render handoff pipe identity differs")
        return verify_render_lock_handoff(proof, command, lock_path=lock_path)
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ValueError("incomplete or invalid render handoff") from error
    finally:
        os.close(fd)


def main(*, lock_path=None) -> int:
    command = sys.argv[1:]
    if command[:1] == ["--"]:
        command = command[1:]
    if not command:
        print("用法：python3 tools/with_render_lock.py -- COMMAND [ARG...]", file=sys.stderr)
        return 2

    lock_fd = receipt_fd = None
    try:
        lock_fd = os.open(lock_path if lock_path is not None else _lock_path(), os.O_CREAT | os.O_RDWR, 0o600)
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as error:
            if error.errno not in (errno.EACCES, errno.EAGAIN):
                raise
            print("等待同用户的渲染验收结束；可按 Ctrl-C 取消。", file=sys.stderr)
            fcntl.flock(lock_fd, fcntl.LOCK_EX)
        # Replace this process, retaining the lock until the command exits.
        # stdout/stderr and the command's exit status are preserved by exec.
        os.set_inheritable(lock_fd, True)
        receipt_fd = _handoff(lock_fd, command)
        os.environ[HANDOFF_ENV] = str(receipt_fd)
        os.execvp(command[0], command)
    except KeyboardInterrupt:
        return 130
    except OSError as error:
        # Do not print argv or exception text that may contain private arguments.
        print(f"渲染命令未启动（系统错误 {error.errno}）。", file=sys.stderr)
        return 127 if error.errno == errno.ENOENT else 126
    except ValueError:
        print("渲染命令未启动（继承交接失败）。", file=sys.stderr)
        return 126
    finally:
        if receipt_fd is not None:
            os.close(receipt_fd)
        if lock_fd is not None:
            os.close(lock_fd)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
