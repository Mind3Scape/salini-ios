"""Download only the three pinned trial assets; raw sources stay in ignored tmp/."""
import concurrent.futures
import hashlib
import json
from pathlib import Path
import urllib.request

ROOT = Path(__file__).resolve().parents[3]
DEST = ROOT / "tmp/simready-trial/source"
REPO = "nvidia/simready-assets"
REVISION = "524747d9b5e1f21b5b18b56041788c01d745f1a1"
ASSETS = ["vehicle_forklift_red_c01", "rack_bulk_storage_a03", "pallet_a01"]

def main():
    DEST.mkdir(parents=True, exist_ok=True)
    lock = DEST.parent / "download-manifest.json"
    revision = REVISION
    files = []
    for asset in ASSETS:
        url = f"https://huggingface.co/api/datasets/{REPO}/tree/{revision}/{asset}?recursive=true&limit=1000"
        while url:
            with urllib.request.urlopen(url, timeout=60) as response:
                files.extend(f for f in json.load(response) if f["type"] == "file")
                links = response.headers.get("Link", "")
            next_links = [part.split(">")[0].strip(" <") for part in links.split(",") if 'rel="next"' in part]
            url = next_links[0] if next_links else None
    lock.write_text(json.dumps({"repo": REPO, "revision": revision, "assets": ASSETS}, indent=2) + "\n")
    def download(entry):
        path = DEST / entry["path"]
        path.parent.mkdir(parents=True, exist_ok=True)
        if not path.exists() or path.stat().st_size != entry["size"]:
            url = f"https://huggingface.co/datasets/{REPO}/resolve/{revision}/{entry['path']}"
            with urllib.request.urlopen(url, timeout=120) as response:
                path.write_bytes(response.read())
        return {"path": entry["path"], "bytes": path.stat().st_size, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        downloaded = list(pool.map(download, files))
    lock.write_text(json.dumps({"repo": REPO, "revision": revision, "assets": ASSETS, "files": downloaded}, indent=2) + "\n")
    print(json.dumps({"revision": revision, "files": len(downloaded), "MB": round(sum(f["bytes"] for f in downloaded)/1e6, 1)}), flush=True)

if __name__ == "__main__":
    main()
