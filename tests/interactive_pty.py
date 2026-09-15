"""Bounded Linux PTY acceptance; standard library only, also reusable by artifacts."""

import fcntl
import json
import os
from pathlib import Path
import select
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time
import unittest


class Terminal:
    def __init__(self, command, environment=None, *, stdout_pipe=False):
        self.master, self.slave = os.openpty()
        self.process = None
        self.pidfd = None
        self.output = b""
        self.cursor = 0
        self.closed = False
        self.initial = termios.tcgetattr(self.slave)
        fcntl.ioctl(self.slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 100, 0, 0))

        def own_terminal():
            os.setsid()
            fcntl.ioctl(0, termios.TIOCSCTTY, 0)

        try:
            self.process = subprocess.Popen(
                command, stdin=self.slave,
                stdout=subprocess.PIPE if stdout_pipe else self.slave, stderr=self.slave,
                env={**os.environ, "TERM": "xterm-256color", **(environment or {})},
                preexec_fn=own_terminal,
            )
            self.pidfd = os.pidfd_open(self.process.pid)
        except BaseException:
            self.close()
            raise

    def send(self, data):
        offset = 0
        while offset < len(data):
            offset += os.write(self.master, data[offset:])

    def expect(self, expected, timeout=20):
        deadline = time.monotonic() + timeout
        while expected not in self.output[self.cursor:]:
            remaining = deadline - time.monotonic()
            ready = select.select([self.master, self.pidfd], [], [], max(0, remaining))[0]
            if remaining <= 0 or not ready:
                raise AssertionError(f"missing {expected!r}; observed {self.output!r}")
            if self.master not in ready:
                raise AssertionError(f"process exited before {expected!r}; observed {self.output!r}")
            try:
                chunk = os.read(self.master, 65536)
            except OSError as failure:
                raise AssertionError(f"PTY closed; observed {self.output!r}") from failure
            if not chunk:
                raise AssertionError(f"PTY EOF; observed {self.output!r}")
            self.output += chunk
        self.cursor = self.output.index(expected, self.cursor) + len(expected)

    def finish(self, expected_status=0):
        status = self.process.wait(timeout=10)
        if status != expected_status:
            raise AssertionError(f"exit {status}, expected {expected_status}; {self.output!r}")
        if termios.tcgetattr(self.slave) != self.initial:
            raise AssertionError("terminal state was not restored")

    def close(self):
        if self.closed:
            return
        try:
            if self.process is not None and self.process.poll() is None:
                os.killpg(self.process.pid, signal.SIGTERM)
                try:
                    self.process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    os.killpg(self.process.pid, signal.SIGKILL)
                    self.process.wait(timeout=5)
        finally:
            if self.process is not None and self.process.stdout is not None:
                self.process.stdout.close()
            if self.pidfd is not None:
                os.close(self.pidfd)
            os.close(self.master)
            os.close(self.slave)
            self.closed = True

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()


class EditorProbe(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.TemporaryDirectory(prefix="attalambda-editor-test-")
        self.addCleanup(self.home.cleanup)
        self.environment = {"HOME": self.home.name, "PLTUSERHOME": self.home.name}
        # Synthetic configuration only. No owner's initialization files are read.
        (Path(self.home.name) / ".expeditor.rkt").write_text(
            '#lang racket/base\n(error "UNSAFE-INITIALIZATION-EXECUTED")\n'
        )
        self.command = [os.environ.get("ATTALAMBDA_TEST_RACKET", "racket"),
                        str(Path(__file__).parent / "fixtures/interactive-editor-probe.rkt")]

    def test_accept_and_close(self):
        with Terminal(self.command, self.environment) as terminal:
            terminal.expect(b"atta> ")
            terminal.send(b"(add 1 2)\r")
            terminal.expect(b'accepted: "(add 1 2)"')
            terminal.expect(b'history: ("(add 1 2)")')
            terminal.finish()
            self.assertNotIn(b"UNSAFE-INITIALIZATION-EXECUTED", terminal.output)

    def test_controlled_open_failure(self):
        with Terminal(self.command + ["--fail-open"], self.environment) as terminal:
            terminal.expect(b"editor unavailable")
            terminal.finish()

    def test_redirected_stdout_is_restored(self):
        with Terminal(self.command, self.environment, stdout_pipe=True) as terminal:
            terminal.expect(b"atta> ")
            terminal.send(b"(add 1 2)\r")
            terminal.expect(b'history: ("(add 1 2)")')
            terminal.finish()
            self.assertEqual(terminal.process.stdout.read(), b"stdout restored\n")

    def test_program_input_then_editing(self):
        with Terminal(self.command + ["--input"], self.environment) as terminal:
            terminal.expect(b"atta> ")
            terminal.send(b"read\r")
            terminal.expect(b"program ready\r\n")
            self.assertEqual(termios.tcgetattr(terminal.slave), terminal.initial)
            terminal.send(b"unique-answer\n")
            terminal.expect(b'program: OK(SOME("unique-answer"))')
            terminal.expect(b"atta> ")
            terminal.send(b"next\r")
            terminal.expect(b'accepted: "next"')
            terminal.expect(b"atta> ")
            terminal.send(b"quit\r")
            terminal.expect(b'history: ("quit" "next" "read")')
            terminal.finish()

    def test_answer_and_following_source_typeahead(self):
        with Terminal(self.command + ["--input"], self.environment) as terminal:
            terminal.expect(b"atta> ")
            terminal.send(b"read\r")
            terminal.expect(b"program ready\r\n")
            terminal.send(b"typed-ahead-answer\nnext\n")
            terminal.expect(b'program: OK(SOME("typed-ahead-answer"))')
            terminal.expect(b'accepted: "next"')
            terminal.expect(b"atta> ")
            terminal.send(b"quit\r")
            terminal.expect(b'history: ("quit" "next" "read")')
            terminal.finish()

    def test_checked_session_read_and_return_to_editing(self):
        with Terminal(self.command + ["--session"], self.environment, stdout_pipe=True) as terminal:
            terminal.expect(b"atta> ")
            terminal.send(b"(read-line UNIT)\r")
            terminal.expect(b"entry ready\r\n")
            self.assertEqual(termios.tcgetattr(terminal.slave), terminal.initial)
            terminal.send(b"checked-answer\n(add 2 3)\n")
            terminal.expect(b'=> OK(SOME("checked-answer"))')
            terminal.expect(b"=> 5")
            terminal.expect(b"atta> ")
            terminal.send(b"quit\r")
            terminal.expect(b'history: ("quit" "(add 2 3)" "(read-line UNIT)")')
            terminal.finish()
            self.assertEqual(terminal.process.stdout.read(), b"stdout restored\n")

    def test_checked_session_cancellation_recovers_the_old_binding(self):
        with Terminal(self.command + ["--session"], self.environment) as terminal:
            terminal.expect(b"atta> ")
            terminal.send(b"(def old = 41) old\r")
            terminal.expect(b"=> 41")
            terminal.expect(b"atta> ")
            entries = [
                b"(read-line UNIT)",
                b"(read-line UNIT)",
                b'(rec spin n = (if (is-ok (stdout "running\\n")) (spin n) n)) (spin UNIT)',
                b'(rec raw n = (if (is-ok (stdout "rendering\\n")) (raw n) n)) raw',
            ]
            for source in entries:
                terminal.send(source + b"\r")
                terminal.expect(b"entry ready\r\n")
                if b"running" in source:
                    terminal.expect(b"running\r\n")
                elif b"rendering" in source:
                    terminal.expect(b"rendering\r\n")
                self.assertEqual(termios.tcgetattr(terminal.slave), terminal.initial)
                terminal.send(b"\x03")
                context = b"rendering" if b"rendering" in source else b"entry"
                terminal.expect(b"repl:probe: interrupted (" + context + b")")
                terminal.expect(b"atta> ")
                terminal.send(b"old\r")
                terminal.expect(b"=> 41")
                terminal.expect(b"atta> ")
            terminal.send(b"quit\r")
            terminal.expect(b"history:")
            terminal.finish()

    def test_session_reset_preserves_editor_history_echo_and_program_input(self):
        with Terminal(self.command + ["--session"], self.environment) as terminal:
            terminal.expect(b"atta> ")
            terminal.send(b"(def old = 41)\r")
            terminal.expect(b"entry ready\r\n")
            terminal.expect(b"atta> ")
            terminal.send(b":echo off\r")
            terminal.expect(b"echo: #f")
            terminal.expect(b"atta> ")
            terminal.send(b":reset\r")
            terminal.expect(b"session reset")
            terminal.expect(b"atta> ")
            start = terminal.cursor
            terminal.send(b'(stdout "after-reset\\n")\r')
            terminal.expect(b"after-reset\r\n")
            terminal.expect(b"atta> ")
            self.assertNotIn(b"=>", terminal.output[start:terminal.cursor])
            terminal.send(b":echo on\r")
            terminal.expect(b"echo: #t")
            terminal.expect(b"atta> ")
            terminal.send(b"(read-line UNIT)\r")
            terminal.expect(b"entry ready\r\n")
            terminal.send(b"reset-answer\n")
            terminal.expect(b'=> OK(SOME("reset-answer"))')
            terminal.expect(b"atta> ")
            terminal.send(b"quit\r")
            terminal.expect(b"history:")
            terminal.expect(b'(def old = 41)')
            terminal.finish()

    def test_session_exit_and_native_failure_restore_the_terminal(self):
        for status in [0, 1]:
            with self.subTest(status=status), Terminal(
                    self.command + ["--session"], self.environment, stdout_pipe=True) as terminal:
                terminal.expect(b"atta> ")
                terminal.send(b'(def kept = (tcp-listen "127.0.0.1" 0 1)) kept\r')
                terminal.expect(b"=> OK(")
                terminal.expect(b"atta> ")
                terminal.send(f"(exit {status})\r".encode())
                terminal.expect(b"session closed")
                terminal.expect(b"history:")
                terminal.finish(status)
                self.assertEqual(terminal.process.stdout.read(), b"stdout restored\n")
        with Terminal(self.command + ["--session-native-failure"], self.environment) as terminal:
            terminal.expect(b"atta> ")
            terminal.send(b'(tcp-listen "127.0.0.1" 0 1)\r')
            terminal.expect(b"session closed")
            terminal.expect(b"history:")
            terminal.expect(b"probe failure")
            terminal.finish(70)

    def test_session_fresh_eof_closes_cleanly(self):
        with Terminal(self.command + ["--session"], self.environment) as terminal:
            terminal.expect(b"atta> ")
            terminal.send(b"\x04")
            terminal.expect(b"session closed")
            terminal.expect(b"history:")
            terminal.finish()

    def test_multiline_paste_is_one_source_entry(self):
        with Terminal(self.command + ["--input"], self.environment) as terminal:
            terminal.expect(b"atta> ")
            terminal.send(b"(add 1\n2) (add 3 4)\r")
            terminal.expect(b'accepted: "(add 1\\n')
            terminal.expect(b') (add 3 4)"')
            terminal.expect(b"atta> ")
            terminal.send(b"quit\r")
            terminal.expect(b'history: ("quit" "(add 1\\n')
            terminal.finish()

    def test_cancel_source_and_blocked_program_input(self):
        with Terminal(self.command + ["--input"], self.environment, stdout_pipe=True) as terminal:
            terminal.expect(b"atta> ")
            terminal.send(b"(add ")
            terminal.expect(b"add ")
            terminal.send(b"\x03")
            # On a nonempty buffer Expeditor clears and redraws in place;
            # it raises a break only at an empty buffer or in program input.
            terminal.expect(b"atta> ")
            terminal.send(b"read\r")
            terminal.expect(b"program ready\r\n")
            terminal.send(b"\x03")
            terminal.expect(b"interrupted")
            terminal.expect(b"atta> ")
            terminal.send(b"read\r")
            terminal.expect(b"program ready\r\n")
            terminal.send(b"\x03")
            terminal.expect(b"interrupted")
            terminal.expect(b"atta> ")
            terminal.send(b"next\r")
            terminal.expect(b'accepted: "next"')
            terminal.expect(b"atta> ")
            terminal.send(b"quit\r")
            terminal.expect(b'history: ("quit" "next" "read")')
            terminal.finish()
            self.assertEqual(terminal.process.stdout.read(), b"stdout restored\n")

    def test_harness_failure_closes_waiting_reader_and_descriptors(self):
        terminal = Terminal(self.command + ["--input"], self.environment, stdout_pipe=True)
        with self.assertRaisesRegex(AssertionError, "intentional harness failure"):
            with terminal:
                terminal.expect(b"atta> ")
                terminal.send(b"read\r")
                terminal.expect(b"program ready\r\n")
                raise AssertionError("intentional harness failure")
        self.assertIsNotNone(terminal.process.poll())
        self.assertTrue(terminal.process.stdout.closed)
        for descriptor in [terminal.master, terminal.slave, terminal.pidfd]:
            with self.assertRaises(OSError):
                os.fstat(descriptor)

    def test_reader_directive_and_datum_comment_do_not_execute_extensions(self):
        sentinel = Path(self.home.name) / "reader-executed"
        reader = Path(self.home.name) / "reader.rkt"
        reader.write_text(
            '#lang racket/base\n(provide read read-syntax)\n'
            f'(call-with-output-file {json.dumps(str(sentinel))} '
            '(lambda (out) (display "executed" out)))\n'
        )
        directive = f'#reader (file {json.dumps(str(reader))}) 1'
        with Terminal(self.command + ["--input"], self.environment) as terminal:
            terminal.expect(b"atta> ")
            terminal.send(directive.encode() + b"\r")
            terminal.expect(b'accepted: "#reader')
            terminal.expect(b"atta> ")
            terminal.send(b"#;1\r")
            terminal.expect(b'accepted: "#;1"')
            terminal.expect(b"atta> ")
            terminal.send(b"quit\r")
            terminal.expect(b"history:")
            terminal.finish()
        self.assertFalse(sentinel.exists())


if __name__ == "__main__":
    unittest.main()
