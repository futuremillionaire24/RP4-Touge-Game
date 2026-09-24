"""Anonymise ours-vs-reference image pairs for the blind judge.

  python tools/perfection/blind_pair.py make --piece 04 --round 2 --pairs <critic pairs dir>
      <pairs dir> holds ours_1.png/ref_1.(png|jpg), ours_2/ref_2, ... (critic's matched framings).
      Writes D:/RP4wt/_blind/<token>/pair_1/{A,B}.png ... (same size, no metadata, random side)
      and the answer key to D:/RP4wt/_keys/<token>.json. Prints the blind dir only.

  python tools/perfection/blind_pair.py unblind --token <token> --verdict <judge verdict.json>
      Judge verdict JSON: {"pairs": {"1": "A", "2": "B", ...}, ...}  (A/B labels are per pair)
      Prints {"ours_won": n, "pairs": k, "overall_ours": bool, "per_pair": {...}}.
"""
import argparse
import glob
import json
import os
import random
import re
import secrets

from PIL import Image

BLIND = r"D:\RP4wt\_blind"
KEYS = r"D:\RP4wt\_keys"
W, H = 1334, 750  # RP4 panel; references are cover-cropped to the same frame


def cover(img: Image.Image) -> Image.Image:
    img = img.convert("RGB")
    s = max(W / img.width, H / img.height)
    img = img.resize((max(W, round(img.width * s)), max(H, round(img.height * s))), Image.LANCZOS)
    x, y = (img.width - W) // 2, (img.height - H) // 2
    return img.crop((x, y, x + W, y + H))


def make(a) -> None:
    pairs = {}
    for ours in sorted(glob.glob(os.path.join(a.pairs, "ours_*.*"))):
        n = re.search(r"ours_(\w+)\.", os.path.basename(ours)).group(1)
        refs = glob.glob(os.path.join(a.pairs, f"ref_{n}.*"))
        if refs:
            pairs[n] = (ours, refs[0])
    if not pairs:
        raise SystemExit(f"no ours_N/ref_N pairs in {a.pairs}")
    token = secrets.token_hex(6)
    out = os.path.join(BLIND, token)
    key = {"piece": a.piece, "round": a.round, "pairs": {}}
    for i, (n, (ours, ref)) in enumerate(pairs.items(), 1):
        d = os.path.join(out, f"pair_{i}")
        os.makedirs(d, exist_ok=True)
        ours_side = random.choice("AB")
        ref_side = "B" if ours_side == "A" else "A"
        cover(Image.open(ours)).save(os.path.join(d, f"{ours_side}.png"))
        cover(Image.open(ref)).save(os.path.join(d, f"{ref_side}.png"))
        key["pairs"][str(i)] = {"ours": ours_side, "ours_src": ours, "ref_src": ref}
    os.makedirs(KEYS, exist_ok=True)
    with open(os.path.join(KEYS, f"{token}.json"), "w", encoding="utf-8") as f:
        json.dump(key, f, indent=1)
    print(json.dumps({"token": token, "blind_dir": out, "pairs": len(pairs)}))


def unblind(a) -> None:
    with open(os.path.join(KEYS, f"{a.token}.json"), encoding="utf-8") as f:
        key = json.load(f)
    with open(a.verdict, encoding="utf-8") as f:
        v = json.load(f)
    per = {}
    for i, k in key["pairs"].items():
        pick = str(v["pairs"].get(i, "")).strip().upper()
        per[i] = {"picked": pick, "ours": k["ours"], "ours_won": pick == k["ours"]}
    won = sum(p["ours_won"] for p in per.values())
    print(json.dumps({"ours_won": won, "pairs": len(per), "overall_ours": won * 2 > len(per), "per_pair": per}))


def main() -> None:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    m = sub.add_parser("make")
    m.add_argument("--piece", required=True)
    m.add_argument("--round", required=True, type=int)
    m.add_argument("--pairs", required=True)
    u = sub.add_parser("unblind")
    u.add_argument("--token", required=True)
    u.add_argument("--verdict", required=True)
    a = ap.parse_args()
    make(a) if a.cmd == "make" else unblind(a)


if __name__ == "__main__":
    main()
