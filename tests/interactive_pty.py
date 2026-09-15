"""Bounded Linux PTY acceptance; standard library only, also reusable by artifacts."""

import fcntl
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


if __name__ == "__main__":
    unittest.main()
