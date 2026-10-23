#!/usr/bin/env python3
"""Syntax-only fallback for Apple's plutil -lint on OpenStep .strings tables."""
import re
import sys
from pathlib import Path


def lint(text):
    # Accept comments and quoted strings, including escaped quotes/backslashes and
    # OpenStep octal/Unicode escapes. Reject stray text and unterminated constructs.
    token = re.compile(r'\s+|/\*.*?\*/|//[^\n]*|"(?:[^"\\\n]|\\(?:["\\abfnrtv]|[0-7]{1,3}|U[0-9a-fA-F]{4}|\n))*"|[=;]', re.DOTALL)
    position = 0
    expected = 0
    while position < len(text):
        match = token.match(text, position)
        if not match:
            raise ValueError(f"invalid syntax at line {text.count(chr(10), 0, position) + 1}")
        value = match.group()
        position = match.end()
        if value.isspace() or value.startswith(("/*", "//")):
            continue
        if (expected in (0, 2) and not value.startswith('"')) or (expected == 1 and value != "=") or (expected == 3 and value != ";"):
            raise ValueError("expected a quoted key, '=', a quoted value, then ';'")
        expected = (expected + 1) % 4
    if expected:
        raise ValueError("incomplete string-table entry")


if __name__ == "__main__":
    try:
        lint(Path(sys.argv[1]).read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeError, ValueError) as error:
        sys.exit(f"{sys.argv[1]}: {error}")
