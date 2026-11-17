#!/usr/bin/env python3
"""fetch_weights.py — BUILD/DEV ONLY. The one place allowed to touch the network.

Downloads the pinned CED-tiny weights into the local model dir and verifies every
file against serve/weights_manifest.json (sha256). Run this at image-build / CI
time so the runtime image ships fixed, verified weights and NEVER downloads at
inference time (confidential-computing requirement).

    # direct Hub, or set a mirror if blocked:
    HF_ENDPOINT=https://hf-mirror.com python fetch_weights.py
    python fetch_weights.py --dest models/ced-tiny

Re-pin the manifest from a trusted local copy (only when deliberately updating the
model — e.g. a new revision):

    python fetch_weights.py --dest <trusted_dir> --write-manifest
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MANIFEST = os.path.join(HERE, "weights_manifest.json")


def sha256(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def main() -> int:
    man = json.load(open(MANIFEST))["ced_tiny"]
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dest", default=os.path.join(HERE, "models", "ced-tiny"),
                    help="local dir to populate (must match config ced_model_dir)")
    ap.add_argument("--revision", default=man["revision"])
    ap.add_argument("--write-manifest", action="store_true",
                    help="(re)compute weights_manifest.json from --dest; use only to deliberately re-pin")
    a = ap.parse_args()

    files = list(man["files"])
    if not a.write_manifest:
        from huggingface_hub import snapshot_download
        snapshot_download(man["repo"], revision=a.revision, local_dir=a.dest,
                          allow_patterns=files, endpoint=os.environ.get("HF_ENDPOINT"))

    if a.write_manifest:
        new = {f: sha256(os.path.join(a.dest, f)) for f in files}
        full = json.load(open(MANIFEST)); full["ced_tiny"]["files"] = new; full["ced_tiny"]["revision"] = a.revision
        json.dump(full, open(MANIFEST, "w"), indent=2)
        print("re-pinned weights_manifest.json:")
        for f, h in new.items():
            print(f"  {h}  {f}")
        return 0

    bad = []
    for f, want in man["files"].items():
        p = os.path.join(a.dest, f)
        if not os.path.isfile(p):
            bad.append(f"missing {f}")
        elif sha256(p) != want:
            bad.append(f"sha256 mismatch {f}")
    if bad:
        print("VERIFY FAILED:\n  " + "\n  ".join(bad), file=sys.stderr)
        return 1
    print(f"OK: {len(files)} files fetched + verified into {a.dest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
