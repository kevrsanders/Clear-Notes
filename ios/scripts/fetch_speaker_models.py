#!/usr/bin/env python3
"""Fetches the speaker-identification models that are built into Clear Notes.

The models are copied into the app when it's built (ios/SpeakerModels, a folder in project.yml),
so iPhones never download them: identifying speakers contacts no one. Run this once before
`xcodegen generate` and building; the build workflow runs it on the build machine.

The files come from one fixed commit of FluidInference/speaker-diarization-coreml on Hugging
Face, the commit the pinned FluidAudio version (project.yml) uses. Each file is checked against
the hash Hugging Face lists for it at that commit. Once fetched, later runs only check the files
against the hashes saved then, without going online.

Standard library only: python3 scripts/fetch_speaker_models.py
"""

import hashlib
import http.client
import json
import re
import shutil
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

REPO = "FluidInference/speaker-diarization-coreml"
# FluidAudio 0.18.3's pinned revision for this repo (ModelNames.swift, Repo.diarizer). Change it
# together with the FluidAudio version in project.yml.
REVISION = "df2625ac79a7ac6b65ad868fee6d80f320da4232"
# What FluidAudio's offline diarizer needs (ModelNames.OfflineDiarizer.requiredModels).
REQUIRED = [
    "Segmentation.mlmodelc",
    "FBank.mlmodelc",
    "Embedding.mlmodelc",
    "PldaRho.mlmodelc",
    "plda-parameters.json",
]

HUB = "https://huggingface.co"
IOS = Path(__file__).resolve().parent.parent
DESTINATION = IOS / "SpeakerModels"
# Kept beside the folder, not in it, so it isn't copied into the app.
MANIFEST = IOS / "SpeakerModels.manifest.json"
ATTEMPTS = 4


def with_retries(work, what):
    """Runs `work`, retrying network errors and server errors with a growing wait."""
    for attempt in range(1, ATTEMPTS + 1):
        try:
            return work()
        except (OSError, http.client.HTTPException) as error:
            status = getattr(error, "code", None)
            if status is not None and status < 500 and status != 429:
                raise
            if attempt == ATTEMPTS:
                raise
            wait = 15 * attempt
            print(f"  {what}: {error}; trying again in {wait}s", flush=True)
            time.sleep(wait)


def open_url(url):
    request = urllib.request.Request(url, headers={"User-Agent": "clear-notes-build"})
    return urllib.request.urlopen(request, timeout=120)


def list_directory(path):
    """The files and folders directly in `path` at the pinned commit, following the tree API's
    Link: <…>; rel="next" pages."""
    url = f"{HUB}/api/models/{REPO}/tree/{REVISION}"
    if path:
        url += "/" + urllib.parse.quote(path)
    items = []
    while url:
        def page(url=url):
            with open_url(url) as response:
                link = re.search(r'<([^>]+)>\s*;\s*rel="?next"?', response.headers.get("Link", ""))
                return json.load(response), link.group(1) if link else None

        found, url = with_retries(page, f"listing {path or 'the repository'}")
        items += found
    return items


def describe(item):
    """(path, size, hash kind, hash). Large files are in LFS, listed with their sha256; small
    ones with their git blob id."""
    if item.get("lfs"):
        return item["path"], item["size"], "sha256", item["lfs"]["oid"]
    return item["path"], item["size"], "git-sha1", item["oid"]


def files_under(path):
    files = []
    for item in list_directory(path):
        if item["type"] == "directory":
            files += files_under(item["path"])
        elif item["type"] == "file":
            files.append(describe(item))
    return files


def file_hash(path, kind):
    if kind == "sha256":
        digest = hashlib.sha256()
    else:
        digest = hashlib.sha1(f"blob {path.stat().st_size}\0".encode())
    with open(path, "rb") as file:
        for chunk in iter(lambda: file.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def already_fetched():
    """The folder holds every file from the pinned commit, unchanged since it was fetched."""
    try:
        manifest = json.loads(MANIFEST.read_text())
    except (OSError, ValueError):
        return False
    if manifest.get("revision") != REVISION or not manifest.get("files"):
        return False
    if not all((DESTINATION / name).exists() for name in REQUIRED):
        return False
    for entry in manifest["files"]:
        local = DESTINATION / entry["path"]
        if not local.is_file() or file_hash(local, entry["kind"]) != entry["hash"]:
            return False
    return True


def download(path, local):
    url = f"{HUB}/{REPO}/resolve/{REVISION}/{urllib.parse.quote(path)}"

    def transfer():
        with open_url(url) as response, open(local, "wb") as out:
            shutil.copyfileobj(response, out, 1 << 20)

    with_retries(transfer, f"downloading {path}")


def fetch():
    root = {item["path"]: item for item in list_directory("")}
    wanted = []
    for name in REQUIRED:
        item = root.get(name)
        if item is None:
            sys.exit(f"{name} isn't in {REPO} at {REVISION}")
        wanted += files_under(name) if item["type"] == "directory" else [describe(item)]

    staging = IOS / "SpeakerModels.partial"
    shutil.rmtree(staging, ignore_errors=True)
    total = sum(size for _, size, _, _ in wanted)
    print(f"Fetching {len(wanted)} files ({total / 1_000_000:.1f} MB) from {REPO} at {REVISION[:7]}", flush=True)
    manifest = []
    for path, size, kind, expected in wanted:
        local = staging / path
        local.parent.mkdir(parents=True, exist_ok=True)
        download(path, local)
        actual = file_hash(local, kind)
        if actual != expected:
            sys.exit(f"{path}: hash {actual} doesn't match {expected}, the one Hugging Face lists")
        manifest.append({"path": path, "size": size, "kind": kind, "hash": expected})

    shutil.rmtree(DESTINATION, ignore_errors=True)
    staging.rename(DESTINATION)
    MANIFEST.write_text(json.dumps({"repo": REPO, "revision": REVISION, "files": manifest}, indent=2) + "\n")
    print(f"Speaker models ready in {DESTINATION.relative_to(IOS)}")


if __name__ == "__main__":
    if already_fetched():
        print(f"Speaker models already in {DESTINATION.relative_to(IOS)} ({REVISION[:7]}), checked against their hashes")
    else:
        fetch()
