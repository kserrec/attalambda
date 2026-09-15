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
    def __init__(self, command, environment=None, *, stdout_pipe=False, stderr_pipe=False):
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
            terminal.expect(b"fragment\r\n=> OK(UNIT)\r\natta> ")
            terminal.send(b":echo off\r")
            terminal.expect(b"atta> ")
            terminal.send(b'(stdout "unrendered")\r')
            terminal.expect(b"unrendered\r\natta> ")
            terminal.send(b":quit\r")
            terminal.finish()

    def test_entry_cancellation_and_recovery_keep_the_actual_shell_usable(self):
        loaded = Path(self.home.name) / "blocked load.attl"
        loaded.write_text('#lang attalambda\n(stdout "loading\\n")\n(read-line UNIT)\n(def ghost = 2)\n')
        with Terminal(self.command + ["--no-history"], self.environment) as terminal:
            terminal.expect(b"atta> ")
            terminal.send(b"(def old = 41) old\r")
            terminal.expect(b"=> 41\r\natta> ")
            entries = [
                (b"(add 1\r", b"...> "),
                (b'(stdout "reading\\n") (read-line UNIT)\r', b"=> OK(UNIT)\r\n"),
                (b'(rec spin n = (if (is-ok (stdout "running\\n")) (spin n) n)) (spin UNIT)\r', b"running\r\n"),
                (b'(rec raw n = (if (is-ok (stdout "rendering\\n")) (raw n) n)) raw\r', b"rendering\r\n"),
                ((':load ' + json.dumps(str(loaded)) + '\r').encode(), b"loading\r\n"),
            ]
            for source, reached in entries:
                terminal.send(source)
                terminal.expect(reached)
                terminal.send(b"\x03")
                terminal.expect(b"entry interrupted")
                terminal.expect(b"atta> ")
                terminal.send(b"old\r")
                terminal.expect(b"=> 41\r\natta> ")
            terminal.send(b"unknown-name\r")
            terminal.expect(b"source expansion failed")
            terminal.expect(b"atta> ")
            terminal.send(b":quit\r")
            terminal.finish(0)

    def test_program_eof_returns_none_and_fresh_prompt_eof_exits(self):
        with Terminal(self.command + ["--no-history"], self.environment) as terminal:
            terminal.expect(b"atta> ")
            terminal.send(b'(stdout "reading\\n") (read-line UNIT)\r')
            terminal.expect(b"=> OK(UNIT)\r\n")
            terminal.send(b"\x04")
            terminal.expect(b"=> OK(NONE)\r\natta> ")
            terminal.send(b"(add 2 3)\r")
            terminal.expect(b"=> 5\r\natta> ")
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
