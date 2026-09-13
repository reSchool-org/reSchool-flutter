#!/usr/bin/env python3
"""публикуем проверенные файлы того же доверенного запуска actions, ключи apple не нужны"""

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

from apple_release import TARGETS, version_values

PUBLIC_ASSETS = {"ios-testflight": "reSchool-ios.ipa", "macos-direct": "reSchool-macos.dmg"}


def command(*args, missing_ok=False):
    result = subprocess.run(args, capture_output=True, check=False)
    if result.returncode:
        if missing_ok and b"HTTP 404" in result.stderr:
            return None
        raise RuntimeError(f"{args[0]} operation failed; no release assets were overwritten")
    return result.stdout


def verified_assets(root, targets, version, commit):
    if root.is_symlink() or not root.is_dir():
        raise ValueError("Artifact input must be a real directory")
    expected = set(targets)
    if not expected or len(expected) != len(targets) or not expected <= set(TARGETS):
        raise ValueError("Invalid expected release targets")
    records = {}
    # скачивание раскладывает каждый артефакт матрицы в свою подпапку
    for directory in root.iterdir():
        if directory.is_symlink() or not directory.is_dir():
            raise ValueError("Unexpected artifact input")
        metadata = directory / "release.json"
        if metadata.is_symlink() or not metadata.is_file() or metadata.stat().st_size > 16384:
            raise ValueError("Missing or invalid release metadata")
        data = json.loads(metadata.read_text())
        if not isinstance(data, dict):
            raise ValueError("Release metadata must be an object")
        target = data.get("target")
        if not isinstance(target, str) or target not in expected or target in records:
            raise ValueError("Duplicate or unexpected release target")
        if data.get("commit") != commit or data.get("version") != version:
            raise ValueError("Artifact commit/version does not match the requested release")
        filename = data.get("artifact", "")
        if (not isinstance(filename, str) or not filename or Path(filename).name != filename
                or "\\" in filename or not re.fullmatch(r"[A-Za-z0-9._-]+", filename)):
            raise ValueError("Invalid artifact filename")
        artifact = directory / filename
        suffix = {"ios-testflight": ".ipa", "macos-testflight": ".pkg", "macos-direct": ".dmg"}[target]
        if (artifact.suffix != suffix or artifact.is_symlink() or not artifact.is_file()
                or artifact.stat().st_size == 0):
            raise ValueError("Missing signed distribution artifact")
        with artifact.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        if (not isinstance(data.get("sha256"), str)
                or not re.fullmatch(r"[a-f0-9]{64}", data["sha256"]) or digest != data["sha256"]):
            raise ValueError("Distribution artifact checksum mismatch")
        if data.get("platform") != ("ios" if target == "ios-testflight" else "macos"):
            raise ValueError("Artifact platform mismatch")
        if target.startswith("macos") and data.get("native_macos") is not True:
            raise ValueError("macOS artifacts must be verified native desktop builds")
        if target == "macos-direct" and (data.get("notarized") is not True or data.get("app_notarized") is not True):
            raise ValueError("Both the macOS app and DMG must be notarized before publication")
        records[target] = (artifact, data)
    if set(records) != expected:
        raise ValueError("All requested distribution jobs must finish before publication")
    return {target: records[target] for target in PUBLIC_ASSETS if target in records}


def publish(root, repo, commit, version, targets):
    version_values(version, "1")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo) or not re.fullmatch(r"[a-f0-9]{40}", commit):
        raise ValueError("Invalid repository or commit")
    records = verified_assets(root, targets, version, commit)
    if not records:
        raise ValueError("Only IPA and DMG are published to GitHub Releases")
    tag = "v" + version
    marker = f"<!-- reschool-apple-release:{commit} -->"
    existing = command("gh", "api", f"repos/{repo}/releases/tags/{tag}", missing_ok=True)
    tag_ref = command("gh", "api", f"repos/{repo}/git/ref/tags/{tag}", missing_ok=True)
    tag_commit = command("gh", "api", f"repos/{repo}/commits/{tag}") if tag_ref is not None else None
    if tag_commit is not None and json.loads(tag_commit).get("sha") != commit:
        raise ValueError("Release tag already points to another commit; choose a new version")
    release = json.loads(existing) if existing is not None else None
    if release is not None and tag_commit is None and not (
            release.get("draft") and marker in (release.get("body") or "")
            and release.get("target_commitish") == commit):
        raise ValueError("Existing release has no verifiable tag")
    if release and release.get("draft") and marker not in (release.get("body") or ""):
        raise ValueError("Refusing to publish an unrelated draft release")

    with tempfile.TemporaryDirectory(prefix="reschool-release-") as temporary:
        staging = Path(temporary)
        files = []
        for target, (artifact, data) in records.items():
            name = PUBLIC_ASSETS[target]
            destination = staging / name
            shutil.copyfile(artifact, destination)
            checksum = staging / (name + ".sha256")
            checksum.write_text(f"{data['sha256']}  {name}\n")
            metadata = staging / (name + ".release.json")
            metadata.write_text(json.dumps({**data, "release_asset": name}, indent=2, sort_keys=True) + "\n")
            files.extend((destination, checksum, metadata))
        # уже выложенный бинарник не перетираем, повтор с тем же файлом просто ничего не делает
        existing_assets = {asset["name"]: asset for asset in (release or {}).get("assets", [])}
        pending = []
        for path in files:
            previous = existing_assets.get(path.name)
            if previous:
                digest = "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()
                if previous.get("digest") != digest:
                    raise ValueError("A different asset already exists; use a new release version")
            else:
                pending.append(str(path))
        if release is None:
            notes = "Signed Apple distributions.\n\n"
            if "macos-direct" in records:
                notes += "The DMG contains a native macOS app and is notarized.\n"
            if "ios-testflight" in records:
                notes += "The App Store-signed IPA is not an unrestricted sideload build; use TestFlight to install it.\n"
            notes += "\n" + marker
            command("gh", "release", "create", tag, "--repo", repo, "--target", commit,
                    "--title", "reSchool " + version, "--notes", notes, "--draft", *pending)
        elif pending:
            command("gh", "release", "upload", tag, *pending, "--repo", repo)
        if release is None or release.get("draft"):
            command("gh", "release", "edit", tag, "--repo", repo, "--draft=false")
    print(f"https://github.com/{repo}/releases/tag/{tag}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--artifacts", type=Path, required=True)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--targets", required=True, help="JSON array of all requested targets")
    args = parser.parse_args()
    publish(args.artifacts, args.repo, args.commit, args.version, json.loads(args.targets))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, RuntimeError) as error:
        print(f"::error::{error}", file=sys.stderr)
        sys.exit(1)
