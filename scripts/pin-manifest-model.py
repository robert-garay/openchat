#!/usr/bin/env python3
"""Download mlx-community model files and emit a manifest JSON entry with sha256 sums."""
import hashlib
import json
import sys
import urllib.request

HF = "https://huggingface.co"


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def main(repo: str, meta: dict) -> None:
    tree_url = f"https://huggingface.co/api/models/{repo}/tree/main"
    with urllib.request.urlopen(tree_url, timeout=120) as resp:
        tree = json.load(resp)
    skip = {".gitattributes", "README.md", "merges.txt", "vocab.json", "added_tokens.json"}
    files = []
    total = 0
    import os
    import tempfile

    tmp = tempfile.mkdtemp()
    for item in tree:
        if item.get("type") != "file":
            continue
        path = item["path"]
        if path in skip:
            continue
        url = f"{HF}/{repo}/resolve/main/{path}"
        dest = os.path.join(tmp, path.replace("/", "_"))
        print(f"Downloading {path}...", file=sys.stderr)
        urllib.request.urlretrieve(url, dest)
        digest = sha256_file(dest)
        size = os.path.getsize(dest)
        total += size
        files.append({"path": path, "url": url, "sha256": digest, "bytes": size})

    bundle_paths = sorted(f["path"] for f in files)
    bundle_hasher = hashlib.sha256()
    for path in bundle_paths:
        file_hash = next(x["sha256"] for x in files if x["path"] == path)
        bundle_hasher.update(path.encode())
        bundle_hasher.update(file_hash.encode())
    bundle_sha = bundle_hasher.hexdigest()

    entry = {
        **meta,
        "id": repo,
        "mlxModelID": repo,
        "bytes": total,
        "sha256": bundle_sha,
        "backend": "mlx",
        "files": files,
    }
    print(json.dumps(entry, indent=2))


if __name__ == "__main__":
    repo = sys.argv[1]
    meta = json.loads(sys.argv[2])
    main(repo, meta)
