#!/usr/bin/env python3
"""Print the useful lines of a DeviceInteractionSynthesize hierarchy file.

usage: hierarchy.py <hierarchyPath | Synthesize JSON result | file with it | - (stdin)> [regex ...]

- Accepts the hierarchy file path, the whole JSON text the tool returned (paths in it are
  JSON-escaped, e.g. "\\/var\\/folders\\/..."), or a file holding that JSON.
- Always prints the foreground app lines, then element lines without the layout-only noise:
  bare `Other` containers and everything inside the keyboard (keys, suggestion bar); the
  `Keyboard` line itself stays, so you can see that the keyboard is up and how high it reaches.
- With regexes, prints only element lines matching any of them (case-insensitive), with line numbers.
"""
import json, re, sys

def main():
    if len(sys.argv) < 2:
        print(__doc__); sys.exit(2)
    arg = sys.argv[1]
    if arg == "-":
        arg = sys.stdin.read()
    path = arg
    # A file that holds the saved Synthesize JSON counts as that JSON.
    if not arg.lstrip().startswith("{"):
        try:
            head = open(arg, encoding="utf-8").read(1).strip() or ""
            if head == "{": arg = open(arg, encoding="utf-8").read()
        except OSError:
            pass
    if arg.lstrip().startswith("{"):
        d = json.loads(arg)
        if "hierarchyPath" not in d:
            print(f"no hierarchyPath in the result: {arg[:300]}"); sys.exit(1)
        print(f"applicationState: {d.get('applicationState')}  screenshot: {d.get('screenshotPath')}")
        path = d["hierarchyPath"]
    lines = open(path, encoding="utf-8").read().splitlines()
    patterns = [re.compile(p, re.I) for p in sys.argv[2:]]
    front = next((l.split(":", 1)[1].strip() for l in lines if l.startswith("Application bundle identifier")), "")
    if front == "com.apple.springboard" and not patterns:
        print("SpringBoard (the home screen) is in front: the app is not. If applicationState is Crashed, it crashed;")
        print("otherwise it was sent to the background. Pass a regex to search the home screen anyway.")
        return
    keyboard_indent = None  # inside the keyboard's subtree (keys, suggestion bar): skip it
    for i, line in enumerate(lines, 1):
        s = line.strip()
        indent = len(line) - len(line.lstrip())
        if keyboard_indent is not None:
            if indent > keyboard_indent: continue
            keyboard_indent = None
        if s.startswith("Keyboard, ") or "identifier: 'SystemInputAssistantView'" in s:
            keyboard_indent = indent
            if s.startswith("Keyboard, "): print(line if not patterns else f"{i}: {line}")
            continue
        if s.startswith(("Application bundle identifier", "Application, pid", "Device orientation")):
            print(line); continue
        if re.match(r"^Other, \{\{[^}]*\}, \{[^}]*\}\}, hitPoint", s) or s.startswith(("Key, ", "Keyboard, ")) or s.startswith("-----"):
            continue
        if "identifier: 'UIKeyboardLayoutStar" in s:
            continue
        if patterns and not any(p.search(s) for p in patterns):
            continue
        print(f"{i}: {line}" if patterns else line)

main()
