"""Bounded Linux PTY acceptance; standard library only, also reusable by artifacts."""

import fcntl
import errno
import json
import os
from pathlib import Path
import select
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import termios
import time
import unittest


def install_init_sentinels(home):
    # Verified Linux CS9.3 paths under PLTUSERHOME, plus the legacy HOME path.
    config = Path(home, ".config", "racket")
    config.mkdir(parents=True, exist_ok=True)
    for path in [config / "expeditor.rkt", config / "racketrc.rktl",
                 Path(home, ".expeditor.rkt")]:
        path.write_text('#lang racket/base\n(error "UNSAFE-INITIALIZATION-EXECUTED")\n')


def history_path(home):
    return Path(home, ".config", "racket", "attalambda", "history-v1")


def create_history_directory(home):
    directory = Path(home)
    for name in [".config", "racket", "attalambda"]:
        directory = directory / name
        directory.mkdir(mode=0o700, exist_ok=True)


def read_history(path):
    content = path.read_bytes()
    header = b"AttaLambda-history-v1\n"
    if not content.startswith(header) or len(content) > 1048576:
        raise AssertionError("unexpected history framing or byte bound")
    count = struct.unpack_from(">H", content, len(header))[0]
    if count > 1000:
        raise AssertionError("history exceeded1000 entries")
    offset = len(header) + 2
    entries = []
    for _ in range(count):
        size = struct.unpack_from(">I", content, offset)[0]
        offset += 4
        if offset + size > len(content):
            raise AssertionError("history frame exceeds the file")
        entries.append(content[offset:offset + size].decode("utf-8"))
        offset += size
    if offset != len(content):
        raise AssertionError("history has trailing bytes")
    return entries


def read_pipe_bytes(stream, count, timeout=20):
    result = b""
    deadline = time.monotonic() + timeout
    while len(result) < count:
        remaining = deadline - time.monotonic()
        if remaining <= 0 or not select.select([stream], [], [], remaining)[0]:
            raise AssertionError(f"pipe output stalled at {result!r}")
        chunk = os.read(stream.fileno(), count - len(result))
        if not chunk:
            raise AssertionError(f"pipe ended at {result!r}")
        result += chunk
    return result


def read_pipe_line(stream, timeout=20):
    result = b""
    deadline = time.monotonic() + timeout
    while not result.endswith(b"\n") and len(result) < 65536:
        remaining = deadline - time.monotonic()
        result += read_pipe_bytes(stream, 1, remaining)
    if not result.endswith(b"\n"):
        raise AssertionError("diagnostic exceeded the bounded line reader")
    return result


class Terminal:
    def __init__(self, command, environment=None, *, stdout_pipe=False, stderr_pipe=False,
                 canonical_input=True):
        self.master, self.slave = os.openpty()
        self.process = None
        self.pidfd = None
        self.output = b""
        self.cursor = 0
        self.closed = False
        self.stopped = False
        if not canonical_input:
            mode = termios.tcgetattr(self.slave)
            mode[3] = (mode[3] & ~termios.ICANON) | termios.ISIG
            mode[6][termios.VMIN] = 1
            mode[6][termios.VTIME] = 0
            termios.tcsetattr(self.slave, termios.TCSANOW, mode)
        self.initial = termios.tcgetattr(self.slave)
        fcntl.ioctl(self.slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 100, 0, 0))

        def own_terminal():
            os.setsid()
            fcntl.ioctl(0, termios.TIOCSCTTY, 0)

        try:
            self.process = subprocess.Popen(
                command, stdin=self.slave,
                stdout=subprocess.PIPE if stdout_pipe else self.slave,
                stderr=subprocess.PIPE if stderr_pipe else self.slave,
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

    def stop(self):
        self.process.send_signal(signal.SIGSTOP)
        self.stopped = True
        deadline = time.monotonic() + 5
        while True:
            pid, status = os.waitpid(self.process.pid, os.WUNTRACED | os.WNOHANG)
            if pid:
                if os.WIFSTOPPED(status):
                    return
                self.process.returncode = os.waitstatus_to_exitcode(status)
                raise AssertionError("child exited before stop acknowledgement")
            if time.monotonic() >= deadline:
                raise AssertionError("stop acknowledgement timed out")
            time.sleep(0.002)

    def resume(self):
        if self.stopped:
            try:
                self.process.send_signal(signal.SIGCONT)
            finally:
                self.stopped = False

    def queued_input(self):
        return struct.unpack("i", fcntl.ioctl(
            self.slave, termios.FIONREAD, struct.pack("i", 0)))[0]

    def wait_queued_input(self, expected):
        deadline = time.monotonic() + 5
        while self.queued_input() != expected:
            if self.process.poll() is not None or time.monotonic() >= deadline:
                raise AssertionError(f"input queue did not reach {expected} bytes")
            # The observed queue transition is evidence; polling only bounds it.
            time.sleep(0.002)

    def queue_prefix_while_stopped(self):
        self.stop()
        try:
            if self.queued_input() != 0:
                raise AssertionError("input remained before the program prefix")
            self.send(b"p")
            self.wait_queued_input(1)
        finally:
            self.resume()

    def close(self):
        if self.closed:
            return
        try:
            try:
                self.resume()
            finally:
                # Even an interrupted resume must reach bounded termination.
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
            if self.process is not None and self.process.stderr is not None:
                self.process.stderr.close()
            if self.pidfd is not None:
                os.close(self.pidfd)
            os.close(self.master)
            os.close(self.slave)
            self.closed = True

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()


class TerminalHarnessProbe(unittest.TestCase):
    def test_resume_failure_still_reaps_child_and_closes_descriptors(self):
        command = [sys.executable, "-I", "-B", "-c",
                   'import signal; signal.signal(signal.SIGHUP, signal.SIG_IGN); '
                   'print("ready", flush=True); signal.pause()']
        for failure_type in [KeyboardInterrupt, OSError]:
            with self.subTest(failure_type=failure_type.__name__):
                terminal = Terminal(command, canonical_input=False)
                original_send = terminal.process.send_signal
                failure = failure_type("controlled resume failure")

                def fail_resume(sig):
                    if sig == signal.SIGCONT:
                        raise failure
                    original_send(sig)

                try:
                    terminal.expect(b"ready\r\n")
                    terminal.stop()
                    terminal.process.send_signal = fail_resume
                    with self.assertRaises(failure_type) as raised:
                        terminal.close()
                    self.assertIs(raised.exception, failure)
                    self.assertIsNotNone(terminal.process.poll())
                    self.assertTrue(terminal.closed)
                    for descriptor in [terminal.master, terminal.slave, terminal.pidfd]:
                        with self.assertRaises(OSError) as closed:
                            os.fstat(descriptor)
                        self.assertEqual(closed.exception.errno, errno.EBADF)
                finally:
                    terminal.process.send_signal = original_send
                    # Independent cleanup also protects a failing regression.
                    if terminal.process.poll() is None:
                        os.killpg(terminal.process.pid, signal.SIGKILL)
                        terminal.process.wait(timeout=5)
                    terminal.close()


class DescriptorProbe(unittest.TestCase):
    def test_descriptor_restoration_after_action_flush_and_break_failures(self):
        command = [os.environ.get("ATTALAMBDA_TEST_RACKET", "racket"),
                   str(Path(__file__).parent / "fixtures/interactive-descriptor-probe.rkt")]
        for mode in ["pass", "before", "action", "after", "both", "break", "break-after"]:
            with self.subTest(mode=mode), subprocess.Popen(
                [*command, mode], stdin=subprocess.PIPE,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            ) as process:
                try:
                    report = b""
                    while b"REPORT " not in report:
                        report += read_pipe_line(process.stderr)
                    # Inspect while the child is alive, before exit can close leaked fds.
                    self.assertNotEqual(os.readlink(f"/proc/{process.pid}/fd/1"),
                                        os.readlink(f"/proc/{process.pid}/fd/2"))
                    out, err = process.communicate(b"finish\n", timeout=5)
                    self.assertEqual(process.returncode, 0, report + err)
                    self.assertEqual(out, b"before\nafter\n")
                    counts = report.rsplit(b" ", 2)
                    self.assertEqual(int(counts[-2]), int(counts[-1].rstrip(b")\n")))
                    if mode in ["action", "both"]:
                        self.assertIn(b"ACTION-FAILURE", report)
                    elif mode in ["before", "after"]:
                        self.assertIn(b"FLUSH-FAILURE", report)
                    elif mode in ["break", "break-after"]:
                        self.assertIn(b"user break", report)
                    else:
                        self.assertIn(b"returned", report)
                    if mode != "before":
                        self.assertIn(b"editor-text\n", report)
                finally:
                    if process.poll() is None:
                        process.kill()
                        process.wait(timeout=5)


class AdapterProbe(unittest.TestCase):
    def test_shared_source_reader_and_controlled_open_failure(self):
        command = [os.environ.get("ATTALAMBDA_TEST_RACKET", "racket"),
                   str(Path(__file__).parent / "fixtures/interactive-adapter-probe.rkt")]
        cases = [(b"(add 1 2) (mult 3 4)\r", b"(complete ((add 1 2) (mult 3 4)))"),
                 (b":echo off\r", b"(command echo #f)"),
                 (b'#reader "unsafe-adapter.rkt" 1\r', b"(error ())"),
                 (b"\x04", b"eof")]
        with tempfile.TemporaryDirectory(prefix="attalambda-adapter-") as home:
            environment = {"HOME": home, "PLTUSERHOME": home}
            install_init_sentinels(home)
            control = subprocess.run(
                [command[0], "-e", "(require expeditor) (expeditor-configure)"],
                env={**os.environ, **environment}, capture_output=True, timeout=15,
            )
            self.assertNotEqual(control.returncode, 0)
            self.assertIn(b"UNSAFE-INITIALIZATION-EXECUTED", control.stderr)
            for source, expected in cases:
                with self.subTest(source=source), Terminal(
                    [*command, "normal"], environment, stdout_pipe=True,
                ) as terminal:
                    terminal.expect(b"atta> ")
                    terminal.send(source)
                    terminal.expect(b"accepted: " + expected)
                    terminal.finish()
                    self.assertEqual(terminal.process.stdout.read(), b"stdout restored\n")
                    self.assertNotIn(b"UNSAFE-INITIALIZATION-EXECUTED", terminal.output)
            with Terminal([*command, "fail-open"], environment, stdout_pipe=True) as terminal:
                terminal.expect(b"accepted: unavailable")
                terminal.finish()
                self.assertEqual(terminal.process.stdout.read(), b"stdout restored\n")
                self.assertNotIn(b"atta> ", terminal.output)

    def test_native_sexpression_indentation_preserves_the_submitted_buffer(self):
        command = [os.environ.get("ATTALAMBDA_TEST_RACKET", "racket"),
                   str(Path(__file__).parent / "fixtures/interactive-adapter-probe.rkt"),
                   "normal"]
        with tempfile.TemporaryDirectory(prefix="attalambda-indent-") as home:
            with Terminal(command, {"HOME": home, "PLTUSERHOME": home}) as terminal:
                terminal.expect(b"atta> ")
                # Expeditor deliberately suppresses auto-indent on rapid paste.
                # Tab requests indentation explicitly, without a timing sleep.
                terminal.send(b"(let ((x 2))\r\t(add x 3))\r")
                terminal.expect(b'accepted: (complete ((let ((x 2)) (add x 3))))')
                terminal.expect(b'text: "(let ((x 2))\\n  (add x 3))"')
                terminal.finish()


class EditorProbe(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.TemporaryDirectory(prefix="attalambda-editor-test-")
        self.addCleanup(self.home.cleanup)
        self.environment = {"HOME": self.home.name, "PLTUSERHOME": self.home.name}
        # Synthetic configuration only. No owner's initialization files are read.
        install_init_sentinels(self.home.name)
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


class CLIEnvironment(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.TemporaryDirectory(prefix="attalambda-cli-test-")
        self.addCleanup(self.home.cleanup)
        self.environment = {"HOME": self.home.name, "PLTUSERHOME": self.home.name}
        executable = os.environ.get("ATTALAMBDA_TEST_EXECUTABLE")
        self.command = ([executable] if executable else
                        [os.environ.get("ATTALAMBDA_TEST_RACKET", "racket"),
                         str(Path(__file__).resolve().parent.parent / "runner/attalambda.rkt")])


class CLIProbe(CLIEnvironment):
    def test_distinct_stdout_and_ui_terminals_keep_result_boundaries(self):
        for terminal_name in ("xterm-256color", "attalambda-unrecognized"):
            with self.subTest(terminal=terminal_name):
                ui_master, ui_slave = os.openpty()
                out_master, out_slave = os.openpty()
                process = None
                initial_ui = termios.tcgetattr(ui_slave)
                initial_out = termios.tcgetattr(out_slave)
                try:
                    for slave in (ui_slave, out_slave):
                        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 100, 0, 0))
                    process = subprocess.Popen(
                        self.command + ["--repl", "--no-history"],
                        stdin=ui_slave, stdout=out_slave, stderr=ui_slave,
                        env={**os.environ, **self.environment, "TERM": terminal_name}, start_new_session=True)
                    os.write(ui_master, b':echo off\n(stdout "prefix")\n:echo on\n41\n:quit\n')
                    received = {ui_master: bytearray(), out_master: bytearray()}
                    deadline = time.monotonic() + 20
                    while process.poll() is None:
                        remaining = deadline - time.monotonic()
                        self.assertGreater(remaining, 0, repr(received))
                        for descriptor in select.select(list(received), [], [], min(0.1, remaining))[0]:
                            received[descriptor].extend(os.read(descriptor, 65536))
                    for descriptor in received:
                        while select.select([descriptor], [], [], 0)[0]:
                            received[descriptor].extend(os.read(descriptor, 65536))
                    self.assertEqual(process.returncode, 0, repr(received))
                    self.assertEqual(bytes(received[out_master]), b"prefix\r\n=> 41\r\n")
                    self.assertEqual(termios.tcgetattr(ui_slave), initial_ui)
                    self.assertEqual(termios.tcgetattr(out_slave), initial_out)
                finally:
                    if process is not None:
                        if process.poll() is None:
                            os.killpg(process.pid, signal.SIGKILL)
                        process.wait(timeout=5)
                    for descriptor in (ui_master, ui_slave, out_master, out_slave):
                        os.close(descriptor)

    def test_completion_tracks_public_committed_loaded_and_reset_names_without_demand(self):
        source = Path(self.home.name, "completion.attl")
        source.write_text('#lang attalambda\n(def zloaded = 43)\n'
                          '(def zlazy = (stdout "COMPLETION-DEMANDED-VALUE"))\n')
        with Terminal(self.command + ["--no-history"], self.environment) as terminal:
            terminal.expect(b"atta> ")
            terminal.send(b"(ad\t 2 3)\r")
            terminal.expect(b"=> 5\r\n")
            terminal.expect(b"atta> ")
            for value in (41, 42):
                terminal.send(f"(def zsession = {value})\r".encode())
                terminal.expect(b"atta> ")
                terminal.send(b"zses\t\r")
                terminal.expect(f"=> {value}\r\n".encode())
                terminal.expect(b"atta> ")
            terminal.send((":load " + json.dumps(str(source)) + "\r").encode())
            terminal.expect(b"atta> ")
            terminal.send(b"zloa\t\r")
            terminal.expect(b"=> 43\r\n")
            terminal.expect(b"atta> ")
            terminal.send(b"zlaz\t")
            terminal.expect(b"zlazy")
            terminal.send(b"\x03")
            # Source-edit cancellation clears the buffer and returns a prompt;
            # the evaluation-interruption diagnostic is not required here.
            terminal.expect(b"atta> ")
            terminal.send(b"(def zfailed = 47) missing-completion-value\r")
            terminal.expect(b"AttaLambda:")
            terminal.expect(b"atta> ")
            terminal.send(b"zfai\t\r")
            terminal.expect(b"AttaLambda:")
            terminal.expect(b"atta> ")
            terminal.send(b":reset\r")
            terminal.expect(b"atta> ")
            terminal.send(b"zses\t\r")
            terminal.expect(b"AttaLambda:")
            terminal.expect(b"atta> ")
            terminal.send(b"(ad\t 3 4)\r")
            terminal.expect(b"=> 7\r\n")
            terminal.expect(b"atta> ")
            terminal.send(b":quit\r")
            terminal.finish()
            self.assertNotIn(b"COMPLETION-DEMANDED-VALUE", terminal.output)

    def test_completion_preserves_control_and_unusual_identifier_source(self):
        codes = list(range(32)) + list(range(127, 160))
        definitions = [f"(def |zcontrol{code:03d}{chr(code)}name| = 41)" for code in codes]
        # These are fixed valid language spellings, not a second symbol printer.
        spellings = [r"zbar\|name", r"zback\\slash", r"ztwo\ words", r"\123", r"\:help", "||", "z日本語"]
        definitions += [f"(def {spelling} = 41)" for spelling in spellings]
        source = Path(self.home.name, "unusual-completion.attl")
        source.write_text("#lang attalambda\n" + "\n".join(definitions) + "\n")
        with Terminal(self.command + ["--no-history"], self.environment) as terminal:
            terminal.expect(b"atta> ")
            terminal.send((":load " + json.dumps(str(source)) + "\r").encode())
            terminal.expect(b"atta> ")
            prefixes = [f"zcontrol{code:03d}" for code in codes]
            prefixes += [r"zbar", r"zback", r"ztwo", r"\1", r"\:h", "||", "z日"]
            for prefix in prefixes:
                with self.subTest(prefix=prefix):
                    terminal.send(prefix.encode() + b"\t\r")
                    terminal.expect(b"=> 41\r\n")
                    terminal.expect(b"atta> ")
            terminal.send(b":quit\r")
            terminal.finish()

    def test_program_input_cancellation_after_consuming_an_incomplete_line(self):
        environment = {**self.environment, "TERM": "attalambda-unrecognized"}
        with Terminal(self.command + ["--no-history"], environment,
                      canonical_input=False) as terminal:
            terminal.expect(b"atta> ")
            terminal.send(b"(def old = 41) old\r")
            terminal.expect(b"=> 41\r\n")
            terminal.expect(b"atta> ")
            for entry, cancel in [(2, True), (4, True), (6, False)]:
                terminal.send(b'(stdout "reading\\n") (read-line UNIT)\r')
                terminal.expect(b"=> OK(UNIT)\r\n")
                # No newline is available. Only this accepted program can read
                # the byte enqueued after its output; output alone is too early.
                terminal.queue_prefix_while_stopped()
                terminal.wait_queued_input(0)
                terminal.send(b"\x03" if cancel else b"\n")
                terminal.expect(f"AttaLambda: repl:{entry}: entry interrupted".encode()
                                if cancel else b'=> OK(SOME("p"))\r\n')
                terminal.expect(b"atta> ")
                terminal.send(b"old\r")
                terminal.expect(b"=> 41\r\n")
                terminal.expect(b"atta> ")
            terminal.send(b":quit\r")
            terminal.finish()

    def test_input_readiness_ignores_computation_and_stopped_cleanup_reaps_child(self):
        environment = {**self.environment, "TERM": "attalambda-unrecognized"}
        with Terminal(self.command + ["--no-history"], environment,
                      canonical_input=False) as terminal:
            terminal.expect(b"atta> ")
            terminal.send(b'(rec spin n = (if (is-ok (stdout "tick\\n")) (spin n) n)) '
                          b'(spin UNIT)\r')
            terminal.expect(b"tick\r\n")
            terminal.stop()
            try:
                while select.select([terminal.master], [], [], 0)[0]:
                    terminal.output += os.read(terminal.master, 65536)
                terminal.cursor = len(terminal.output)
                terminal.send(b"p")
                terminal.wait_queued_input(1)
            finally:
                terminal.resume()
            for _ in range(10):
                terminal.expect(b"tick\r\n")
            terminal.stop()
            self.assertEqual(terminal.queued_input(), 1)
            # Leaving the child stopped exercises the failure cleanup path.
        self.assertIsNotNone(terminal.process.poll())
        self.assertTrue(terminal.closed)

    def test_actual_session_registry_and_listeners_are_replaced_on_reset(self):
        ports = []

        def check_port(port, occupied):
            with socket.socket() as probe:
                if occupied:
                    with self.assertRaises(OSError) as raised:
                        probe.bind(("127.0.0.1", port))
                    self.assertEqual(raised.exception.errno, errno.EADDRINUSE)
                else:
                    probe.bind(("127.0.0.1", port))

        with Terminal(self.command + ["--no-history"], self.environment,
                      stdout_pipe=True) as terminal:
            terminal.expect(b"atta> ")
            for _ in range(2):
                for handle in [1, 2]:
                    terminal.send(
                        b'(def kept = (tcp-listen "127.0.0.1" 0 1)) '
                        b'(head (unwrap-ok kept)) (head (tail (unwrap-ok kept)))\r')
                    self.assertEqual(read_pipe_line(terminal.process.stdout),
                                     f"=> {handle}\n".encode())
                    line = read_pipe_line(terminal.process.stdout)
                    self.assertTrue(line.startswith(b"=> "), line)
                    port = int(line[3:])
                    self.assertGreater(port, 0)
                    self.assertLessEqual(port, 65535)
                    ports.append(port)
                    terminal.expect(b"atta> ")
                    for active in ports:
                        check_port(active, True)
                terminal.send(b":reset\r")
                terminal.expect(b"Session reset.")
                terminal.expect(b"atta> ")
                for released in ports:
                    check_port(released, False)
                ports.clear()
                terminal.send(b":names\r")
                terminal.expect(b"No user definitions.")
                terminal.expect(b"atta> ")
            terminal.send(b":quit\r")
            terminal.finish()
            self.assertEqual(terminal.process.stdout.read(), b"")

    def test_history_persists_only_submitted_source_without_forcing_values(self):
        with Terminal(self.command, self.environment, stdout_pipe=True) as terminal:
            terminal.expect(b"atta> ")
            for source in [b'(def dormant = (stdout "must-stay-lazy"))', b":echo off"]:
                terminal.send(source + b"\r")
                terminal.expect(b"atta> ")
            program = b'(stdout "answer: ") (read-line UNIT)'
            terminal.send(program + b"\r")
            self.assertEqual(read_pipe_bytes(terminal.process.stdout, 8), b"answer: ")
            terminal.send(b"answer-must-not-enter-history\n")
            terminal.expect(b"atta> ")
            terminal.send(b"(add 1\n  2)\r")
            terminal.expect(b"atta> ")
            terminal.send(b":reset\r")
            terminal.expect(b"atta> ")
            terminal.send(b"9\r")
            terminal.expect(b"atta> ")
            terminal.send(b":quit\r")
            terminal.finish()
            self.assertEqual(terminal.process.stdout.read(), b"")
        entries = read_history(history_path(self.home.name))
        self.assertEqual(entries[:3], [":quit", "9", ":reset"])
        self.assertEqual(len(entries), 7)
        self.assertIn(program.decode(), entries)
        self.assertIn("(add 1\n  2)", entries)
        self.assertNotIn("answer-must-not-enter-history", "\n".join(entries))
        self.assertEqual(history_path(self.home.name).stat().st_mode & 0o777, 0o600)

    def test_no_history_keeps_navigation_and_reset_preferences_without_creating_files(self):
        with Terminal(self.command + ["--no-history"], self.environment) as terminal:
            terminal.expect(b"atta> ")
            terminal.send(b"(add 20 1)\r")
            terminal.expect(b"=> 21\r\n")
            terminal.expect(b"atta> ")
            terminal.send(b":reset\r")
            terminal.expect(b"atta> ")
            terminal.send(b"\x1b[A\x1b[A\r")
            terminal.expect(b"=> 21\r\n")
            terminal.expect(b"atta> ")
            terminal.send(b"\x04")
            terminal.finish()
        self.assertFalse(history_path(self.home.name).parent.exists())

    def test_persistent_history_recall_retains1000_entries_across_prompts(self):
        path = history_path(self.home.name)
        create_history_directory(self.home.name)
        entries = [str(index).encode() for index in range(1000)]
        path.write_bytes(b"AttaLambda-history-v1\n" + struct.pack(">H", 1000)
                         + b"".join(struct.pack(">I", len(entry)) + entry for entry in entries))
        path.chmod(0o600)
        with Terminal(self.command, self.environment) as terminal:
            terminal.expect(b"atta> ")
            terminal.send(b"\x1b[A" * 1000 + b"\r")
            terminal.expect(b"=> 999\r\n")
            terminal.expect(b"atta> ")
            terminal.send(b"\x1b[A" * 1000 + b"\r")
            terminal.expect(b"=> 998\r\n")
            terminal.expect(b"atta> ")
            terminal.send(b":quit\r")
            terminal.finish()
        retained = read_history(path)
        self.assertEqual(len(retained), 1000)
        self.assertEqual(retained[:3], [":quit", "998", "999"])
        self.assertEqual(retained[-1], "996")

    def test_unsafe_history_target_does_not_block_the_shell_or_get_replaced(self):
        path = history_path(self.home.name)
        create_history_directory(self.home.name)
        path.write_bytes(b"preserve-unsafe-history")
        path.chmod(0o644)
        with Terminal(self.command, self.environment) as terminal:
            terminal.expect(b"atta> ")
            terminal.send(b"(add 2 3)\r")
            terminal.expect(b"=> 5\r\n")
            terminal.expect(b"atta> ")
            terminal.send(b":quit\r")
            terminal.finish()
        self.assertEqual(path.read_bytes(), b"preserve-unsafe-history")
        self.assertEqual(path.stat().st_mode & 0o777, 0o644)

    def test_source_cancellation_and_exit_cleanup_preserve_only_submitted_history(self):
        for status in [None, 0, 1]:
            with self.subTest(status=status), tempfile.TemporaryDirectory(
                    prefix="attalambda-exit-", dir=self.home.name) as home:
                environment = {"HOME": home, "PLTUSERHOME": home}
                with Terminal(self.command, environment) as terminal:
                    terminal.expect(b"atta> ")
                    terminal.send(b":echo off\r")
                    terminal.expect(b"atta> ")
                    terminal.send(b"cancel-this-buffer")
                    terminal.expect(b"cancel-this-buffer")
                    terminal.send(b"\x03")
                    terminal.expect(b"atta> ")
                    terminal.send(b"\x04" if status is None else f"(exit {status})\r".encode())
                    terminal.finish(0 if status is None else status)
                expected = [":echo off"] if status is None else [f"(exit {status})", ":echo off"]
                self.assertEqual(read_history(history_path(home)), expected)

    def test_actual_terminal_loads_fresh_standalone_files_and_reset_removes_names(self):
        source = Path(self.home.name, "file with spaces.attl")
        source.write_text('#lang attalambda\n(stdout "loaded-file\\n")\n(def loaded = 41)\n')
        command = (":load " + json.dumps(str(source))).encode()
        with Terminal(self.command + ["--no-history"], self.environment) as terminal:
            terminal.expect(b"atta> ")
            for _ in range(2):
                terminal.send(command + b"\r")
                terminal.expect(b"loaded-file\r\n")
                terminal.expect(b"Loaded source file.")
                terminal.expect(b"atta> ")
            terminal.send(b"(add loaded 1)\r")
            terminal.expect(b"=> 42\r\n")
            terminal.expect(b"atta> ")
            terminal.send(b":reset\r")
            terminal.expect(b"Session reset.")
            terminal.expect(b"atta> ")
            terminal.send(b":names\r")
            terminal.expect(b"No user definitions.")
            terminal.expect(b"atta> ")
            terminal.send(b":quit\r")
            terminal.finish()

    def test_default_and_explicit_terminal_selection(self):
        for arguments in [[], ["--no-history"], ["--repl"],
                          ["--repl", "--no-history"], ["--no-history", "--repl"]]:
            with self.subTest(arguments=arguments), Terminal(
                    self.command + arguments, self.environment) as terminal:
                terminal.expect(b"AttaLambda ")
                terminal.expect(b"atta> ")
                terminal.send(b"(add 2 3)\r")
                terminal.expect(b"=> 5\r\n")
                terminal.expect(b"atta> ")
                terminal.send(b"\x04")
                terminal.finish()

    def test_redirected_stdout_contains_results_without_terminal_ui(self):
        with Terminal(self.command + ["--no-history"], self.environment,
                      stdout_pipe=True) as terminal:
            terminal.expect(b"AttaLambda ")
            terminal.expect(b"atta> ")
            terminal.send(b"(add 2 3)\r")
            terminal.expect(b"atta> ")
            terminal.send(b"\x04")
            terminal.finish()
            self.assertEqual(terminal.process.stdout.read(), b"=> 5\n")

    def test_terminal_input_with_redirected_ui_requires_explicit_transcript(self):
        with Terminal(self.command, self.environment,
                      stdout_pipe=True, stderr_pipe=True) as terminal:
            terminal.finish(64)
            self.assertEqual(terminal.process.stdout.read(), b"")
            self.assertIn(b"use attalambda --repl", terminal.process.stderr.read())
        with Terminal(self.command + ["--repl", "--no-history"], self.environment,
                      stdout_pipe=True, stderr_pipe=True) as terminal:
            terminal.send(b"(add 2 3)\r\x04")
            terminal.finish()
            self.assertEqual(terminal.process.stdout.read(), b"=> 5\n")
            self.assertEqual(terminal.process.stderr.read(), b"")

    def test_program_prompt_is_immediate_before_answer_with_echo_off(self):
        for redirected in [False, True]:
            with self.subTest(redirected=redirected), Terminal(
                    self.command + ["--no-history"], self.environment,
                    stdout_pipe=redirected) as terminal:
                terminal.expect(b"atta> ")
                terminal.send(b":echo off\r")
                terminal.expect(b"Automatic echo: off")
                terminal.expect(b"atta> ")
                terminal.send(b'(stdout "answer: ") (read-line UNIT)\r')
                if redirected:
                    self.assertEqual(read_pipe_bytes(terminal.process.stdout, 8), b"answer: ")
                else:
                    terminal.expect(b"\r\nanswer: ")
                self.assertEqual(termios.tcgetattr(terminal.slave), terminal.initial)
                terminal.send(b"program-answer\n")
                terminal.expect(b"atta> ")
                terminal.send(b":echo on\r")
                terminal.expect(b"atta> ")
                terminal.send(b"TRUE\r")
                terminal.expect(b"atta> ")
                terminal.send(b":quit\r")
                terminal.finish()
                if redirected:
                    self.assertEqual(terminal.process.stdout.read(), b"\n=> TRUE\n")
                else:
                    self.assertIn(b"=> TRUE\r\n", terminal.output)
                self.assertNotIn(b"=> OK", terminal.output)

    def test_non_newline_output_keeps_results_and_prompts_legible(self):
        with Terminal(self.command + ["--no-history"], self.environment) as terminal:
            terminal.expect(b"atta> ")
            terminal.send(b'(stdout "fragment")\r')
            terminal.expect(b"fragment\r\n=> OK(UNIT)\r\n")
            terminal.expect(b"atta> ")
            terminal.send(b":echo off\r")
            terminal.expect(b"atta> ")
            terminal.send(b'(stdout "unrendered")\r')
            terminal.expect(b"unrendered\r\n")
            terminal.expect(b"atta> ")
            terminal.send(b":quit\r")
            terminal.finish()

    def test_entry_cancellation_and_recovery_keep_the_actual_shell_usable(self):
        self.check_entry_cancellation(advanced=True)

    def test_plain_fallback_cancellation_and_recovery(self):
        self.check_entry_cancellation(advanced=False)

    def check_entry_cancellation(self, *, advanced):
        loaded = Path(self.home.name) / "blocked load.attl"
        loaded.write_text('#lang attalambda\n(stdout "loading\\n")\n(read-line UNIT)\n(def ghost = 2)\n')
        with Terminal(self.command + ["--no-history"],
                      {**self.environment, "TERM": "xterm-256color" if advanced
                       else "attalambda-unrecognized"}) as terminal:
            terminal.expect(b"atta> ")
            terminal.send(b"(def old = 41) old\r")
            terminal.expect(b"=> 41\r\n")
            terminal.expect(b"atta> ")
            entries = [
                (b"(add 1", b"add 1") if advanced else (b"(add 1\r", b"...> "),
                (b'(stdout "reading\\n") (read-line UNIT)\r', b"=> OK(UNIT)\r\n"),
                (b'(rec spin n = (if (is-ok (stdout "running\\n")) (spin n) n)) (spin UNIT)\r', b"running\r\n"),
                (b'(rec raw n = (if (is-ok (stdout "rendering\\n")) (raw n) n)) raw\r', b"rendering\r\n"),
                ((':load ' + json.dumps(str(loaded)) + '\r').encode(), b"loading\r\n"),
            ]
            for index, (source, reached) in enumerate(entries):
                terminal.send(source)
                terminal.expect(reached)
                terminal.send(b"\x03")
                if not advanced or index != 0:
                    terminal.expect(b"entry interrupted")
                terminal.expect(b"atta> ")
                terminal.send(b"old\r")
                terminal.expect(b"=> 41\r\n")
                terminal.expect(b"atta> ")
            terminal.send(b"unknown-name\r")
            terminal.expect(b"source expansion failed")
            terminal.expect(b"atta> ")
            terminal.send(b":quit\r")
            terminal.finish(0)

    def test_advanced_cursor_editing_and_source_program_typeahead(self):
        install_init_sentinels(self.home.name)
        with Terminal(self.command + ["--no-history"], self.environment,
                      stdout_pipe=True) as terminal:
            terminal.expect(b"atta> ")
            self.assertFalse(termios.tcgetattr(terminal.slave)[3] & termios.ICANON)
            terminal.send(b"(add 1 3)\x1b[D\x7f2\x1b[C\r")
            self.assertEqual(read_pipe_line(terminal.process.stdout), b"=> 3\n")
            terminal.expect(b"atta> ")
            # Bytes not accepted as source must cross the program-input handoff.
            terminal.send(b'(read-line UNIT)\rtyped-answer\n(add 4 5)\n')
            self.assertEqual(read_pipe_line(terminal.process.stdout),
                             b'=> OK(SOME("typed-answer"))\n')
            self.assertEqual(read_pipe_line(terminal.process.stdout), b"=> 9\n")
            terminal.expect(b"atta> ")
            terminal.expect(b"atta> ")
            terminal.send(b'(stdout "reading\\n") (read-line UNIT)\r')
            self.assertEqual(read_pipe_line(terminal.process.stdout), b"reading\n")
            self.assertEqual(read_pipe_line(terminal.process.stdout), b"=> OK(UNIT)\n")
            self.assertTrue(termios.tcgetattr(terminal.slave)[3] & termios.ICANON)
            terminal.send(b"another-answer\n")
            self.assertEqual(read_pipe_line(terminal.process.stdout),
                             b'=> OK(SOME("another-answer"))\n')
            terminal.expect(b"atta> ")
            terminal.send(b":quit\r")
            terminal.finish()
            self.assertEqual(terminal.process.stdout.read(), b"")
            self.assertNotIn(b"UNSAFE-INITIALIZATION-EXECUTED", terminal.output)

    def test_multiline_comments_strings_and_multiform_paste_in_both_modes(self):
        cases = [
            (b"(let ((x 2))\r#| ) ] \" |# (add x 3))\r", [b"=> 5\n"]),
            (b"(add 1 ; :quit stays a comment\r2)\r", [b"=> 3\n"]),
            (b'"line one: \\" (\rline two)"\r',
             [b'=> "line one: \\" (\\nline two)"\n']),
            (b"(add 1\r2) (mult 3 4)\r", [b"=> 3\n", b"=> 12\n"]),
        ]
        for kind in ["xterm-256color", "attalambda-unrecognized"]:
            with self.subTest(terminal=kind), Terminal(
                self.command + ["--no-history"], {**self.environment, "TERM": kind},
                stdout_pipe=True,
            ) as terminal:
                terminal.expect(b"atta> ")
                for source, expected in cases:
                    terminal.send(source)
                    for line in expected:
                        self.assertEqual(read_pipe_line(terminal.process.stdout), line)
                    terminal.expect(b"atta> ")
                terminal.send(b":quit\r")
                terminal.finish()
                self.assertEqual(terminal.process.stdout.read(), b"")

    def test_program_eof_returns_none_and_fresh_prompt_eof_exits(self):
        with Terminal(self.command + ["--no-history"], self.environment) as terminal:
            terminal.expect(b"atta> ")
            terminal.send(b'(stdout "reading\\n") (read-line UNIT)\r')
            terminal.expect(b"=> OK(UNIT)\r\n")
            terminal.send(b"\x04")
            terminal.expect(b"=> OK(NONE)\r\n")
            terminal.expect(b"atta> ")
            terminal.send(b"(add 2 3)\r")
            terminal.expect(b"=> 5\r\n")
            terminal.expect(b"atta> ")
            terminal.send(b"\x04")
            terminal.finish()


class TranscriptProbe(CLIEnvironment):
    def start_transcript(self):
        process = subprocess.Popen(
            self.command + ["--repl", "--no-history"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            env={**os.environ, **self.environment},
        )

        def close():
            if process.poll() is None:
                process.kill()
                process.wait(timeout=5)
            for stream in [process.stdin, process.stdout, process.stderr]:
                stream.close()

        self.addCleanup(close)
        return process

    def send(self, process, source):
        process.stdin.write(source)
        process.stdin.flush()

    def test_transcript_interrupt_exits130_during_source_and_program_input(self):
        for source, expected in [
            (b"1\n", b"=> 1\n"),
            (b'(stdout "ready\\n") (read-line UNIT)\n', b"ready\n=> OK(UNIT)\n"),
        ]:
            with self.subTest(source=source):
                process = self.start_transcript()
                self.send(process, source)
                self.assertEqual(read_pipe_bytes(process.stdout, len(expected)), expected)
                self.assertFalse(process.stdin.closed)
                process.send_signal(signal.SIGINT)
                self.assertEqual(process.wait(timeout=10), 130)
                self.assertEqual(process.stdout.read(), b"")
                self.assertEqual(process.stderr.read(), b"")

    def test_live_source_and_answers_keep_exact_boundaries_until_final_eof(self):
        process = self.start_transcript()
        self.send(process, b'(stdout "answer: ") (read-line UNIT)\n')
        expected = b"answer: \n=> OK(UNIT)\n"
        self.assertEqual(read_pipe_bytes(process.stdout, len(expected)), expected)
        self.assertFalse(process.stdin.closed)
        self.send(process, b":reset\n")
        expected = b'=> OK(SOME(":reset"))\n'
        self.assertEqual(read_pipe_bytes(process.stdout, len(expected)), expected)
        self.send(process, b"(read-line UNIT)\n\n(add 2 3) (mult 3 4)\n")
        expected = b'=> OK(SOME(""))\n=> 5\n=> 12\n'
        self.assertEqual(read_pipe_bytes(process.stdout, len(expected)), expected)
        self.send(process, b"unknown-name\n")
        diagnostic = read_pipe_line(process.stderr)
        self.assertIn(b"repl:4:1:0: source expansion failed", diagnostic)
        self.assertNotIn(b"/runner/", diagnostic)
        self.send(process, b"(add 20 22)\n")
        self.assertEqual(read_pipe_bytes(process.stdout, 6), b"=> 42\n")
        # The writer has stayed open across every earlier result. Close it only
        # now: the running read must return NONE, then fresh source EOF ends it.
        self.send(process, b"(read-line UNIT)\n")
        process.stdin.close()
        self.assertEqual(read_pipe_bytes(process.stdout, 12), b"=> OK(NONE)\n")
        self.assertEqual(process.wait(timeout=10), 1)
        self.assertEqual(process.stdout.read(), b"")
        self.assertEqual(process.stderr.read(), b"")

    def test_live_echo_off_never_adds_result_text_or_delays_program_prompt(self):
        process = self.start_transcript()
        self.send(process, b":echo off\n")
        self.assertEqual(read_pipe_line(process.stderr), b"Automatic echo: off\n")
        self.send(process, b'(stdout "answer: ") (read-line UNIT)\n')
        self.assertEqual(read_pipe_bytes(process.stdout, 8), b"answer: ")
        self.send(process, b"program-answer\n:echo on\n")
        self.assertEqual(read_pipe_line(process.stderr), b"Automatic echo: on\n")
        self.send(process, b"TRUE\n:quit\n")
        self.assertEqual(process.wait(timeout=10), 0)
        self.assertEqual(process.stdout.read(), b"\n=> TRUE\n")
        self.assertEqual(process.stderr.read(), b"")


if __name__ == "__main__":
    unittest.main()
