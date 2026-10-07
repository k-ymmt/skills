#!/usr/bin/env python3
"""Summarize the newest iOS Simulator crash report (.ips) of an app.

usage: crash_report.py <AppName> [newer-than-epoch-seconds]

Looks in ~/Library/Logs/DiagnosticReports for <AppName>-*.ips, prints the exception, the
termination reason, and the crashed thread's frames that belong to the app's own binary first.
An .ips file is a one-line JSON header followed by a JSON body.
"""
import glob, json, os, sys

def main():
    if len(sys.argv) < 2:
        print(__doc__); sys.exit(2)
    app = sys.argv[1]
    since = float(sys.argv[2]) if len(sys.argv) > 2 else 0
    files = [f for f in glob.glob(os.path.expanduser(f"~/Library/Logs/DiagnosticReports/{app}-*.ips")) if os.path.getmtime(f) > since]
    if not files:
        print(f"no crash report for {app}" + (" since the given time" if since else "")); sys.exit(1)
    path = max(files, key=os.path.getmtime)
    text = open(path, encoding="utf-8").read()
    header, _, body = text.partition("\n")
    h, b = json.loads(header), json.loads(body)
    print(f"report: {path}")
    print(f"app: {h.get('app_name')} {h.get('bundleID')}  time: {h.get('timestamp')}")
    exc = b.get("exception", {})
    print(f"exception: {exc.get('type')} {exc.get('signal', '')} {exc.get('subtype', '')}".rstrip())
    term = b.get("termination", {})
    if term.get("indicator"): print(f"termination: {term.get('indicator')}")
    images = b.get("usedImages", [])
    # Debug builds put the app's code in <App>.debug.dylib next to the executable.
    app_name = h.get("app_name") or app
    own_images = {i for i, img in enumerate(images) if img.get("name") in (app_name, f"{app_name}.debug.dylib")}
    thread = next((t for t in b.get("threads", []) if t.get("triggered")), None)
    if not thread:
        print("no crashed thread in the report"); return
    print(f"crashed thread: {thread.get('name') or thread.get('queue') or ''}")
    shown = 0
    for n, f in enumerate(thread.get("frames", [])):
        own = f.get("imageIndex") in own_images
        sym = f.get("symbol", "?")
        loc = f" ({os.path.basename(f['sourceFile'])}:{f.get('sourceLine')})" if f.get("sourceFile") else ""
        image = images[f["imageIndex"]].get("name", "?") if f.get("imageIndex") is not None and f["imageIndex"] < len(images) else "?"
        if own or n < 3:
            print(f"  {n:>2} {'*' if own else ' '} {image}: {sym}{loc}")
            shown += 1
        if shown >= 12: break
    print("(* = the app's own code)")

main()
