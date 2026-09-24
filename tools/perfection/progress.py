"""Live progress feed for the perfection loop dashboard (dist/progress/).

Each piece has its own status file so parallel agents never write the same file;
the activity feed is an append-only JSONL. The orchestrator alone owns state.json.

  python tools/perfection/progress.py piece 04 --status BUILDING --note "Rewriting spring-damper follow"
  python tools/perfection/progress.py piece 04 --status LOST --round 2 --score 38 --blind "lost 0/3" \
        --gap "..." --verdict "..." --ours shots/04/r2/ours_1.png --ref refs/04/fh5_chase_1.jpg --history
  python tools/perfection/progress.py feed "Wave 1 started"
  python tools/perfection/progress.py state --phase "Wave 1: builders running" --wave 1 --device "idle"
"""
import argparse
import json
import os
import sys
import time
from datetime import datetime, timezone

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
# Worktrees live outside the main checkout, but the dashboard is served from the main one.
MAIN = os.environ.get("NT_MAIN_ROOT", r"D:\Android_RP4_Game")
PROGRESS = os.path.join(MAIN, "dist", "progress")


def now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def read(path: str, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def write(path: str, data) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = f"{path}.{os.getpid()}.tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    for _ in range(20):  # the web server may hold the file open for a moment on Windows
        try:
            os.replace(tmp, path)
            return
        except PermissionError:
            time.sleep(0.1)
    os.replace(tmp, path)


def feed(msg: str) -> None:
    os.makedirs(PROGRESS, exist_ok=True)
    with open(os.path.join(PROGRESS, "feed.jsonl"), "a", encoding="utf-8") as f:
        f.write(json.dumps({"t": now(), "msg": msg}, ensure_ascii=False) + "\n")


def rel(p: str | None) -> str | None:
    """Dashboard image paths are relative to dist/; accept absolute paths too."""
    if not p:
        return p
    dist = os.path.join(MAIN, "dist")
    ap = os.path.abspath(p) if os.path.isabs(p) else None
    if ap and ap.lower().startswith(dist.lower()):
        return os.path.relpath(ap, dist).replace("\\", "/")
    return p.replace("\\", "/")


def main() -> None:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("piece")
    p.add_argument("id")
    p.add_argument("--status", choices=["QUEUED", "BUILDING", "BUILT", "INTEGRATING", "CRITIQUING", "JUDGING", "LOST", "PASSED"])
    p.add_argument("--note")
    p.add_argument("--round", type=int)
    p.add_argument("--score", type=int)
    p.add_argument("--blind")
    p.add_argument("--wowed", choices=["true", "false"])
    p.add_argument("--gap")
    p.add_argument("--verdict")
    p.add_argument("--ours")
    p.add_argument("--ref")
    p.add_argument("--history", action="store_true", help="append this round's result to the history strip")
    p.add_argument("--quiet", action="store_true", help="don't echo to the activity feed")

    f = sub.add_parser("feed")
    f.add_argument("msg")

    s = sub.add_parser("state")
    s.add_argument("--phase")
    s.add_argument("--wave", type=int)
    s.add_argument("--device")
    s.add_argument("--apk")

    a = ap.parse_args()

    if a.cmd == "feed":
        feed(a.msg)
    elif a.cmd == "state":
        path = os.path.join(PROGRESS, "state.json")
        st = read(path, {})
        if a.phase is not None:
            st["phase"] = a.phase
        if a.wave is not None:
            st["wave"] = a.wave
        if a.device is not None or a.apk is not None:
            dev = st.setdefault("device", {})
            if a.device is not None:
                dev["status"] = a.device
            if a.apk is not None:
                dev["apk"] = a.apk
        st["updated"] = now()
        write(path, st)
        if a.phase:
            feed(a.phase)
    else:
        pid = a.id.zfill(2)
        path = os.path.join(PROGRESS, "pieces", f"{pid}.json")
        cur = read(path, {})
        fields = {
            "status": a.status, "note": a.note, "round": a.round, "score": a.score, "blind": a.blind,
            "gap": a.gap, "verdict": a.verdict, "ours": rel(a.ours), "ref": rel(a.ref),
            "wowed": None if a.wowed is None else a.wowed == "true",
        }
        for k, v in fields.items():
            if v is not None:
                cur[k] = v
        if a.history:
            h = cur.setdefault("history", [])
            h[:] = [x for x in h if x.get("round") != cur.get("round")]
            h.append({"round": cur.get("round"), "score": cur.get("score"), "blind": cur.get("blind"),
                      "gap": cur.get("gap"), "won": cur.get("status") == "PASSED"})
        cur["updated"] = now()
        write(path, cur)
        if not a.quiet and (a.status or a.note):
            feed(f"[{pid}] {a.status or ''} {a.note or ''}".strip())


if __name__ == "__main__":
    sys.exit(main())
