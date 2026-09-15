"""Source-only regressions for the pinned Expeditor repairs; standard library."""

from contextlib import contextmanager
import errno
import fcntl
import os
from pathlib import Path
import re
import select
import struct
import sys
import tempfile
import termios
import time
import unicodedata
import unittest

# Permit ordinary sibling imports when the source suite uses Python -I.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from interactive_pty import Terminal


class Screen:
    """Strict test model of the cursor/erase commands emitted by these cases."""

    def __init__(self, width):
        self.width = width
        self.x = self.y = 0
        self.wrap = True
        self.pending = False
        self.grid = [[" "] * width for _ in range(24)]

    def down(self):
        self.y += 1
        if self.y == 24:
            self.grid.pop(0)
            self.grid.append([" "] * self.width)
            self.y -= 1

    def feed(self, data):
        text = data.decode("utf-8")
        index = 0
        while index < len(text):
            char = text[index]
            index += 1
            if char == "\x1b":
                match = re.match(r"\[([0-9;?]*)([@-~])", text[index:])
                if not match:
                    raise AssertionError(f"unmodeled terminal escape: {text[index:]!r}")
                raw, command = match.groups()
                index += len(match[0])
                amount = int(raw or "1") if raw.isdecimal() or not raw else None
                self.pending = False
                if raw == "?7" and command in "hl":
                    self.wrap = command == "h"
                elif command == "A":
                    self.y = max(0, self.y - amount)
                elif command == "B":
                    self.y = min(23, self.y + amount)
                elif command == "C":
                    self.x = min(self.width - 1, self.x + amount)
                elif command == "D":
                    self.x = max(0, self.x - amount)
                elif command == "H":
                    parts = [int(value or "1") for value in raw.split(";")]
                    self.y = parts[0] - 1
                    self.x = (parts[1] if len(parts) > 1 else 1) - 1
                elif command == "K" and raw in ("", "0"):
                    self.grid[self.y][self.x:] = [" "] * (self.width - self.x)
                elif command == "J" and raw == "2":
                    self.grid = [[" "] * self.width for _ in range(24)]
                elif command == "J" and raw in ("", "0"):
                    self.grid[self.y][self.x:] = [" "] * (self.width - self.x)
                    for row in range(self.y + 1, 24):
                        self.grid[row] = [" "] * self.width
                elif command != "m":
                    raise AssertionError(f"unmodeled terminal command: {raw}{command}")
            elif char == "\r":
                self.x = 0
                self.pending = False
            elif char == "\n":
                self.pending = False
                self.down()
            elif char == "\b":
                self.x = max(0, self.x - 1)
                self.pending = False
            elif char != "\a":
                if ord(char) < 32 or 127 <= ord(char) <= 159:
                    raise AssertionError(f"raw source control reached display: {ord(char)}")
                width = 0 if unicodedata.combining(char) else (
                    2 if unicodedata.east_asian_width(char) in ("W", "F") else 1)
                if self.pending and self.wrap:
                    self.x = 0
                    self.down()
                self.pending = False
                if width:
                    self.grid[self.y][self.x] = char
                    if width == 2 and self.x + 1 < self.width:
                        self.grid[self.y][self.x + 1] = ""
                    if self.x + width >= self.width:
                        self.x = self.width - 1
                        self.pending = self.wrap
                    else:
                        self.x += width

    def state(self):
        return self.y, self.x, tuple(tuple(row) for row in self.grid)


def expected_screen(width, source, point):
    """Expected cells and logical point; independent of captured cursor commands."""
    prompt = "atta> " if width >= 6 else "atta> "[:width - 1]
    grid = [[" "] * width for _ in range(24)]
    positions = {}
    row = 0
    lines = source.split("\n")
    for logical, line in enumerate(lines):
        prefix = prompt if logical == 0 else " " * len(prompt)
        column = len(prefix)
        grid[row][:column] = prefix
        for index, char in enumerate(line):
            code = ord(char)
            if code < 32:
                cells = list("^" + chr(code + 64))
            elif code == 127:
                cells = list("^?")
            elif 128 <= code <= 159:
                cells = list(f"\\x{code:02X}")
            elif unicodedata.east_asian_width(char) in ("W", "F"):
                cells = [char, ""]
            else:
                cells = [char]
            if len(cells) > width:
                cells = ["?"]
            if column + len(cells) > width:
                row += 1
                column = 0
            positions[logical, index] = row, column
            grid[row][column:column + len(cells)] = cells
            column += len(cells)
        if column == width:
            row += 1
            column = 0
        positions[logical, len(line)] = row, column
        if logical != len(lines) - 1:
            row += 1
    return *positions[point], tuple(tuple(line) for line in grid)


class Editor:
    def __init__(self, terminal, checkpoints, width):
        self.terminal = terminal
        self.checkpoints = checkpoints
        self.width = width
        self.count = 0
        self.model_offset = None

    def drain(self):
        while select.select([self.terminal.master], [], [], 0)[0]:
            try:
                data = os.read(self.terminal.master, 65536)
            except OSError as failure:
                if failure.errno == errno.EIO:
                    break
                raise
            if not data:
                break
            self.terminal.output += data

    def checkpoint(self, keys=b""):
        self.terminal.send(keys + b"\x1b[24~")
        self.count += 1
        deadline = time.monotonic() + 5
        while not self.checkpoints.exists() or len(self.checkpoints.read_text().splitlines()) < self.count:
            if self.terminal.process.poll() is not None or time.monotonic() >= deadline:
                self.drain()
                raise AssertionError(f"editor checkpoint stalled: {self.terminal.output!r}")
            time.sleep(0.005)
        self.drain()

    def screen(self):
        screen = Screen(self.width)
        if self.model_offset is None:
            self.model_offset = self.terminal.output.index(b"start\r\n") + len(b"start\r\n")
        screen.feed(self.terminal.output[self.model_offset:])
        return screen.state()

    def assert_screen(self, source, point):
        actual = self.screen()
        expected = expected_screen(self.width, source, point)
        if actual != expected:
            raise AssertionError(f"cursor/grid mismatch\nactual={actual!r}\nexpected={expected!r}")

    def resize(self, width):
        self.width = width
        fcntl.ioctl(self.terminal.slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, width, 0, 0))
        self.checkpoint()

    def finish(self, expected):
        self.terminal.send(b"\x1b>\x1b\n")
        self.terminal.expect(b"REPORT ", timeout=5)
        self.terminal.expect(b"\r\n", timeout=5)
        self.terminal.finish()
        match = re.search(rb"REPORT \(([0-9 ]*)\) #f", self.terminal.output)
        if not match:
            raise AssertionError(f"missing unforced source report: {self.terminal.output!r}")
        actual = "".join(chr(int(value)) for value in match[1].split())
        if actual != expected:
            raise AssertionError(f"accepted source changed: {actual!r} != {expected!r}")
        if self.terminal.process.stdout.read() != b"stdout restored\n":
            raise AssertionError("stdout was not restored")


@contextmanager
def editor(source, width):
    with tempfile.TemporaryDirectory(prefix="attalambda-expeditor-") as home:
        checkpoint = Path(home, "checkpoints")
        fixture = Path(__file__).with_name("fixtures") / "interactive-expeditor-regression.rkt"
        command = [os.environ.get("ATTALAMBDA_TEST_RACKET", "racket"), str(fixture),
                   ",".join(str(ord(char)) for char in source), str(checkpoint)]
        terminal = Terminal(command, {"HOME": home, "PLTUSERHOME": home,
                                      "TMPDIR": "/tmp", "TERM": "xterm-256color"}, stdout_pipe=True)
        try:
            terminal.expect(b"READY", timeout=5)
            fcntl.ioctl(terminal.slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, width, 0, 0))
            terminal.send(b"start\n")
            deadline = time.monotonic() + 5
            while termios.tcgetattr(terminal.slave)[3] & termios.ICANON:
                if terminal.process.poll() is not None or time.monotonic() >= deadline:
                    raise AssertionError("editor never entered raw mode")
                time.sleep(0.005)
            yield Editor(terminal, checkpoint, width)
        finally:
            try:
                terminal.close()
            finally:
                if terminal.process.stdout is not None:
                    terminal.process.stdout.close()


@unittest.skipUnless(sys.platform.startswith("linux"), "Linux source editor regression")
class ExpeditorRegressionProbe(unittest.TestCase):
    def test_wrapped_control_insertion_and_deletion(self):
        for width in (3, 10):
            with self.subTest(width=width), editor("aa\x1bbb", width) as probe:
                probe.checkpoint(b"\t")
                probe.assert_screen("aa\x1bbb", (0, 5))
                probe.checkpoint(b"\x1b[D" * 3 + b"X")
                probe.assert_screen("aaX\x1bbb", (0, 3))
                probe.checkpoint(b"\x1b[3~")
                probe.assert_screen("aaXbb", (0, 3))
                probe.finish("aaXbb")

    def test_indentation_preserves_multicell_cursor_and_completes(self):
        for char in ("\x1b", "\x9b", "界"):
            with self.subTest(char=ord(char)), editor(" aa" + char + "bb", 10) as probe:
                probe.checkpoint(b"\t")
                probe.checkpoint(b"\x1b[13~")
                probe.assert_screen("aa" + char + "bb", (0, 0))
                probe.finish("aa" + char + "bb")

    def test_multiline_ascii_exact_row(self):
        for width in (10, 100):
            tail = "b" * (width - 6)
            with self.subTest(width=width), editor("aa" + tail, width) as probe:
                probe.checkpoint(b"\t")
                probe.checkpoint(b"\x1b[D" * len(tail) + b"\x1b\r")
                probe.assert_screen("aa\n" + tail, (1, 0))
                probe.finish("aa\n" + tail)

    def test_leading_multicell_newline_and_join(self):
        for width, char in ((3, "\x1b"), (7, "\x1b"), (8, "\x9b"), (10, "界")):
            source = "aa" + char + "bb"
            with self.subTest(width=width, char=ord(char)), editor(source, width) as probe:
                probe.checkpoint(b"\t")
                probe.checkpoint(b"\x1b[D" * 3 + b"\x1b\r")
                probe.assert_screen("aa\n" + char + "bb", (1, 0))
                probe.checkpoint(b"\x7f")
                probe.assert_screen(source, (0, 2))
                probe.finish(source)

    def test_resize_preserves_source_and_later_cursor_edit(self):
        for char, widths in (("\x9b", (100, 3, 8, 100)), ("界", (1, 100, 1, 100))):
            with self.subTest(char=ord(char)), editor("aa" + char + "bb", widths[0]) as probe:
                probe.checkpoint(b"\t")
                for width in widths[1:]:
                    probe.resize(width)
                # A test model cannot infer the emulator's window-reflow policy.
                # Model from a native full redisplay, retaining the full transcript.
                probe.checkpoint(b"\x0c\x0c")
                clear = b"\x1b[H\x1b[2J"
                probe.model_offset = probe.terminal.output.rindex(clear) + len(clear)
                probe.checkpoint(b"\x1b[D" * 3 + b"X")
                probe.assert_screen("aaX" + char + "bb", (0, 3))
                probe.finish("aaX" + char + "bb")

    def test_edit_beyond_one_screen_keeps_viewport_and_source(self):
        source = "a" * 160 + "\x1b" + "b" * 160
        with editor(source, 10) as probe:
            probe.checkpoint(b"\t")
            probe.checkpoint(b"\x1b[D" * 3 + b"X")
            previous = probe.screen()
            # The 33-row entry shows its last 24 physical rows. The point
            # follows X at absolute row 32, cell 6, hence visible row 23.
            rows = (["a" * 10] * 7 + ["aaaaaa^[bb"] +
                    ["b" * 10] * 15 + ["bbbbbXbbb "])
            self.assertEqual(previous, (23, 6, tuple(tuple(row) for row in rows)))
            probe.checkpoint(b"\x0c\x0c")
            self.assertEqual(probe.screen(), previous)
            probe.finish("a" * 160 + "\x1b" + "b" * 157 + "Xbbb")


if __name__ == "__main__":
    unittest.main(verbosity=2)
