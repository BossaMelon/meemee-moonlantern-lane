#!/usr/bin/env python3
"""Serialize one foreground rendering command across this user's worktrees."""
import errno
import fcntl
import os
import sys


def main() -> int:
    command = sys.argv[1:]
    if command[:1] == ["--"]:
        command = command[1:]
    if not command:
        print("用法：python3 tools/with_render_lock.py -- COMMAND [ARG...]", file=sys.stderr)
        return 2

    lock_fd = None
    try:
        lock_fd = os.open(f"/tmp/moonlantern-render-{os.getuid()}.lock", os.O_CREAT | os.O_RDWR, 0o600)
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
        os.execvp(command[0], command)
    except KeyboardInterrupt:
        return 130
    except OSError as error:
        # Do not print argv or exception text that may contain private arguments.
        print(f"渲染命令未启动（系统错误 {error.errno}）。", file=sys.stderr)
        return 127 if error.errno == errno.ENOENT else 126
    finally:
        if lock_fd is not None:
            os.close(lock_fd)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
