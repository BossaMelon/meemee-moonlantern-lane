"""Temporary-lock/Python-process fixtures; no global lock, renderer or game."""
import errno
import fcntl
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import unittest

import with_render_lock as render


TOOLS = str(Path(__file__).resolve().parent)
IMPORT = "import sys; sys.path.insert(0, %r); import with_render_lock as r; " % TOOLS


class RenderHandoffTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="render-lock-test-")
        self.addCleanup(self.temp.cleanup)
        self.path = str(Path(self.temp.name) / "render.lock")

    def wrapper(self, code):
        command = [sys.executable, "-B", "-c", IMPORT + code]
        bootstrap = IMPORT + "sys.argv = ['with_render_lock.py'] + %r; raise SystemExit(r.main(lock_path=%r))" % (command, self.path)
        return subprocess.Popen([sys.executable, "-B", "-c", bootstrap], stdin=subprocess.PIPE,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    def finish(self, process):
        def cleanup():
            if process.poll() is None:
                process.kill()
            process.communicate(timeout=5)
        self.addCleanup(cleanup)
        return process

    def exclusive_available(self):
        fd = os.open(self.path, os.O_CREAT | os.O_RDWR, 0o600)
        try:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except OSError as error:
                if error.errno in (errno.EACCES, errno.EAGAIN):
                    return False
                raise
            return True
        finally:
            os.close(fd)

    def test_real_wrapper_exec_pid_and_entire_supervisor_lifetime(self):
        probe = ("import os,fcntl,errno; fd=os.open(%r,os.O_RDONLY); "
                 "\ntry: fcntl.flock(fd,fcntl.LOCK_SH|fcntl.LOCK_NB)"
                 "\nexcept OSError as e: assert e.errno in (errno.EAGAIN,errno.EACCES)"
                 "\nelse: raise AssertionError('supervisor EX lost')"
                 "\nfinally: os.close(fd)\n" % self.path)
        child = probe + "import subprocess,sys; subprocess.run([sys.executable,'-B','-c',%r],check=True)" % probe
        code = ("import subprocess, os, json; "
                "proof=r.consume_render_lock_handoff([sys.executable,*sys.orig_argv[1:]], lock_path=%r); "
                "print(json.dumps(proof), flush=True); sys.stdin.readline(); "
                "subprocess.run([sys.executable, '-B', '-c', %r],check=True); "
                "r.verify_render_lock_handoff(proof, [sys.executable,*sys.orig_argv[1:]], lock_path=%r); "
                "print('children-exited-final-report', flush=True); sys.stdin.readline(); "
                "r.verify_render_lock_handoff(proof, [sys.executable,*sys.orig_argv[1:]], lock_path=%r); sys.exit(23)" %
                (self.path, child, self.path, self.path))
        p = self.finish(self.wrapper(code))
        proof = json.loads(p.stdout.readline())
        self.assertEqual(proof["pid"], p.pid)
        self.assertFalse(self.exclusive_available())
        p.stdin.write("children\n"); p.stdin.flush()
        self.assertEqual(p.stdout.readline().strip(), "children-exited-final-report")
        self.assertFalse(self.exclusive_available())
        stdout, stderr = p.communicate("exit\n", timeout=10)
        self.assertEqual((p.returncode, stdout, stderr), (23, "", ""))
        self.assertTrue(self.exclusive_available())

    def test_receipt_is_readonly_one_shot_not_env_proof(self):
        code = ("import os,fcntl,json; fd=int(os.environ[r.HANDOFF_ENV]); "
                "assert fcntl.fcntl(fd,fcntl.F_GETFL)&os.O_ACCMODE == os.O_RDONLY; "
                "duplicate=os.dup(fd); os.set_inheritable(duplicate,True); "
                "proof=r.consume_render_lock_handoff([sys.executable,*sys.orig_argv[1:]],lock_path=%r); "
                "os.environ[r.HANDOFF_ENV]=str(duplicate); "
                "\ntry: r.consume_render_lock_handoff([sys.executable,*sys.orig_argv[1:]],lock_path=%r)"
                "\nexcept ValueError: print('one-shot')"
                "\nelse: raise AssertionError('receipt reused')" % (self.path, self.path))
        p = self.finish(self.wrapper(code)); out, err = p.communicate(timeout=10)
        self.assertEqual((p.returncode, out, err), (0, "one-shot\n", ""))

    def test_invalid_receipts_reject_bounded_before_any_work(self):
        for kind in ["regular-file", "write-end", "open-writer", "oversized", "invalid-json",
                     "duplicate-key", "empty", "wrong-pipe-identity"]:
            with self.subTest(kind=kind):
                reader, writer = os.pipe()
                extra = None
                try:
                    fd = reader
                    if kind == "regular-file":
                        extra = os.open(self.path, os.O_CREAT | os.O_RDWR, 0o600); fd = extra
                    elif kind == "write-end": fd = writer
                    elif kind == "oversized": os.write(writer, b"x" * (render._MAX_HANDOFF_BYTES + 1))
                    elif kind == "invalid-json": os.write(writer, b"not-json")
                    elif kind == "duplicate-key": os.write(writer, b'{"receipt":0,"receipt":1}')
                    elif kind == "wrong-pipe-identity": os.write(writer, b'{"receipt":{"fd":999}}')
                    elif kind == "open-writer": os.write(writer, b"{}")
                    if kind not in ["open-writer", "write-end"]:
                        os.close(writer); writer = None
                    env = dict(os.environ, **{render.HANDOFF_ENV: str(fd)})
                    code = IMPORT + ("\ntry: r.consume_render_lock_handoff([sys.executable,*sys.orig_argv[1:]],lock_path=%r)"
                                     "\nexcept ValueError: print('rejected')"
                                     "\nelse: raise AssertionError('invalid handoff accepted')" % self.path)
                    p = self.finish(subprocess.Popen([sys.executable, "-B", "-c", code],
                        pass_fds=(fd,), env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True))
                    out, err = p.communicate(timeout=3)
                    self.assertEqual((p.returncode, out, err), (0, "rejected\n", ""))
                finally:
                    os.close(reader)
                    if writer is not None: os.close(writer)
                    if extra is not None: os.close(extra)

    def test_real_receipt_rejects_different_exec_pid(self):
        # Fork inherits the genuine receipt and exact argv but is not the exec PID.
        code = ("import os; pid=os.fork(); "
                "\nif pid == 0:"
                "\n try: r.consume_render_lock_handoff([sys.executable,*sys.orig_argv[1:]],lock_path=%r)"
                "\n except ValueError: os._exit(0)"
                "\n os._exit(1)"
                "\nassert os.waitpid(pid,0)[1] == 0; print('different-pid-rejected')" % self.path)
        p = self.finish(self.wrapper(code)); out, err = p.communicate(timeout=5)
        self.assertEqual((p.returncode, out, err), (0, "different-pid-rejected\n", ""))

    def test_wrong_pid_command_fd_or_path_identity_rejected(self):
        for mutation in ["proof['pid'] += 1", "proof['command_sha256'] = '0'*64",
                         "proof['lock']['fd'] = 999999", "proof['lock']['inode'] += 1",
                         "os.rename(%r,%r); open(%r,'w').close()" % (self.path,self.path+'.old',self.path)]:
            with self.subTest(mutation=mutation):
                # Each case uses a real fresh wrapper receipt, then tests rechecks.
                if os.path.exists(self.path): os.unlink(self.path)
                code = ("import os; proof=r.consume_render_lock_handoff([sys.executable,*sys.orig_argv[1:]],lock_path=%r); " % self.path
                        + mutation + ";\ntry: r.verify_render_lock_handoff(proof,[sys.executable,*sys.orig_argv[1:]],lock_path=%r)" % self.path
                        + "\nexcept (ValueError,OSError): print('rejected')\nelse: raise AssertionError('invalid proof accepted')")
                p=self.finish(self.wrapper(code));out,err=p.communicate(timeout=10)
                self.assertEqual((p.returncode,out,err),(0,"rejected\n",""))

    def test_shared_or_unlocked_wrapper_fd_rejected_without_ex_request(self):
        for operation in ["fcntl.LOCK_SH", "fcntl.LOCK_UN"]:
            with self.subTest(operation=operation):
                code = ("import os,fcntl; proof=r.consume_render_lock_handoff([sys.executable,*sys.orig_argv[1:]],lock_path=%r); " % self.path
                        + "fcntl.flock(proof['lock']['fd'],%s); original=fcntl.flock; " % operation
                        + "\ndef checked(fd,op):\n assert not op & fcntl.LOCK_EX, 'verifier acquired EX'\n return original(fd,op)"
                        + "\nfcntl.flock=checked\ntry: r.verify_render_lock_handoff(proof,[sys.executable,*sys.orig_argv[1:]],lock_path=%r)" % self.path
                        + "\nexcept ValueError: print('rejected')\nelse: raise AssertionError('nonexclusive accepted')")
                p=self.finish(self.wrapper(code));out,err=p.communicate(timeout=10)
                self.assertEqual((p.returncode,out,err),(0,"rejected\n",""))

    def test_unwrapped_foreign_release_race_rejected_without_acquiring(self):
        holder=os.open(self.path,os.O_CREAT|os.O_RDWR,0o600)
        inherited=os.open(self.path,os.O_RDWR)
        try:
            fcntl.flock(holder,fcntl.LOCK_EX)
            # Correct inode, really inherited but unlocked FD. The foreign holder
            # releases after exec, before validation. No wrapper receipt exists.
            code = IMPORT + ("import os,fcntl; sys.stdin.readline(); "
                "\ntry: r.consume_render_lock_handoff([sys.executable,*sys.orig_argv[1:]],lock_path=%r)"
                "\nexcept ValueError: print('rejected',flush=True); sys.stdin.readline()"
                "\nelse: raise AssertionError('unwrapped inherited FD accepted')" % self.path)
            env=dict(os.environ);env.pop(getattr(render,"HANDOFF_ENV","MOONLANTERN_RENDER_HANDOFF_FD"),None)
            p=self.finish(subprocess.Popen([sys.executable,"-B","-c",code],pass_fds=(inherited,),
                env=env,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True))
            fcntl.flock(holder,fcntl.LOCK_UN)
            p.stdin.write("foreign-released\n");p.stdin.flush()
            self.assertEqual(p.stdout.readline().strip(),"rejected")
            self.assertTrue(self.exclusive_available())  # verifier acquired nothing
            out,err=p.communicate("exit\n",timeout=10)
            self.assertEqual((p.returncode,out,err),(0,"",""))
        finally:
            os.close(inherited);os.close(holder)

    def test_waiting_contention_ctrl_c_and_stdio_exit_preserved(self):
        fd=os.open(self.path,os.O_CREAT|os.O_RDWR,0o600)
        try:
            fcntl.flock(fd,fcntl.LOCK_EX)
            p=self.finish(self.wrapper("print('started',flush=True)"))
            self.assertIn("等待",p.stderr.readline())
            self.assertIsNone(p.poll())
            fcntl.flock(fd,fcntl.LOCK_UN)
            out,err=p.communicate(timeout=10)
            self.assertEqual((p.returncode,out,err),(0,"started\n",""))
            fcntl.flock(fd,fcntl.LOCK_EX)
            p=self.finish(self.wrapper("raise AssertionError('must not exec')"))
            self.assertIn("等待",p.stderr.readline());p.send_signal(signal.SIGINT)
            out,err=p.communicate(timeout=10)
            self.assertEqual((p.returncode,out,err),(130,"",""))
        finally: os.close(fd)
        p = self.finish(self.wrapper("print('stdout'); print('stderr',file=sys.stderr); sys.exit(7)"))
        out, err = p.communicate(timeout=5)
        self.assertEqual((p.returncode, out, err), (7, "stdout\n", "stderr\n"))

    def test_cli_usage_and_missing_command_keep_status_and_release_lock(self):
        for arguments, expected in [([], 2), ([str(Path(self.temp.name) / "absent")], 127)]:
            with self.subTest(arguments=arguments):
                code = IMPORT + "sys.argv=['with_render_lock.py']+%r; sys.exit(r.main(lock_path=%r))" % (arguments, self.path)
                p=self.finish(subprocess.Popen([sys.executable,"-B","-c",code],
                    stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True))
                out,err=p.communicate(timeout=5)
                self.assertEqual(p.returncode,expected)
                self.assertEqual(out,"")
                self.assertNotIn("Traceback",err)
                self.assertNotIn(self.temp.name,err)
                self.assertTrue(self.exclusive_available())


if __name__ == "__main__":
    unittest.main()
