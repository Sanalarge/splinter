#!/usr/bin/env python3
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(*args, cwd=ROOT):
    return subprocess.check_output(args, cwd=cwd, text=True).strip()


def version_for(root):
    base = (root / "VERSION").read_text().strip()
    if not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", base):
        raise ValueError("VERSION must contain a stable semantic version")
    anchor = run("git", "log", "--first-parent", "-1", "--format=%H", "HEAD", "--", "VERSION", cwd=root)
    if not anchor:
        raise ValueError("VERSION must be committed before preparing a release")
    committed = run("git", "show", "HEAD:VERSION", cwd=root)
    if committed != base:
        raise ValueError("Commit VERSION before preparing a release")
    distance = int(run("git", "rev-list", "--first-parent", "--count", f"{anchor}..HEAD", cwd=root))
    major, minor, patch = map(int, base.split("."))
    version = f"{major}.{minor}.{patch + distance}"
    build = run("git", "rev-list", "--first-parent", "--count", "HEAD", cwd=root)
    commit = run("git", "rev-parse", "HEAD", cwd=root)
    tag = f"v{version}"
    tags = run("git", "tag", "--list", "v*", cwd=root).splitlines()
    for existing in tags:
        if not re.fullmatch(r"v\d+\.\d+\.\d+", existing):
            continue
        target = run("git", "rev-list", "-1", existing, cwd=root)
        if existing == tag and target != commit:
            raise ValueError(f"{tag} already belongs to another commit")
        is_ancestor = subprocess.run(["git", "merge-base", "--is-ancestor", target, commit], cwd=root).returncode == 0
        if is_ancestor and target != commit and tuple(map(int, existing[1:].split("."))) >= (major, minor, patch + distance):
            raise ValueError("VERSION must advance beyond previous releases")
    return {"version": version, "tag": tag, "build": build, "commit": commit}


def prepare():
    values = version_for(ROOT)
    output = os.environ.get("GITHUB_OUTPUT")
    if output:
        with open(output, "a") as stream:
            stream.write("".join(f"{key}={value}\n" for key, value in values.items()))
    print(json.dumps(values))


def find_release(repository, tag):
    result = run("gh", "api", f"repos/{repository}/releases?per_page=100", "--paginate", "--jq",
                 f'.[] | select(.tag_name == "{tag}")')
    return json.loads(result) if result else None


def publish(directory):
    values = version_for(ROOT)
    repository = os.environ["GITHUB_REPOSITORY"]
    if os.environ.get("GITHUB_REF") != "refs/heads/main" or os.environ.get("GITHUB_EVENT_NAME") != "push":
        raise ValueError("Only main-branch pushes may publish releases")
    if values["commit"] != os.environ["GITHUB_SHA"]:
        raise ValueError("Release checkout does not match the triggering commit")
    tag = values["tag"]
    release = find_release(repository, tag)
    if release and release["target_commitish"] != values["commit"]:
        raise ValueError("Existing release targets a different commit")
    if release and not release["draft"]:
        print(f"{tag} is already published; leaving it unchanged")
        return
    assets = [directory / f"Splinter-{values['version']}-universal.zip", directory / "SHA256SUMS"]
    for asset in assets:
        if not asset.is_file():
            raise ValueError(f"Missing release asset: {asset.name}")
    previous = ""
    if int(values["build"]) > 1:
        result = subprocess.run(["git", "describe", "--tags", "--match", "v[0-9]*", "--abbrev=0", "HEAD^"],
                                cwd=ROOT, text=True, capture_output=True)
        if result.returncode == 0:
            previous = result.stdout.strip()
    history = f"{previous}..HEAD" if previous else "HEAD"
    changes = run("git", "log", "--first-parent", "--format=- %s (%h)", history)
    notes = (
        f"## Splinter {values['version']}\n\n"
        "Universal macOS app for Apple Silicon and Intel. Requires macOS 14 or later.\n\n"
        f"## Changes\n\n{changes}\n\n"
        "## Installation\n\n"
        "Download the universal ZIP, extract Splinter.app and move it to Applications. "
        "Enable Accessibility and Input Monitoring in System Settings.\n\n"
        "This package is ad-hoc signed and is not Apple-notarized. macOS may require "
        "Open Anyway in Privacy & Security; updates may require permission approval again. "
        "Verify the download with the accompanying SHA256SUMS file.\n"
    )
    if previous:
        notes += f"\n[Full changelog](https://github.com/{repository}/compare/{previous}...{tag})\n"
    with tempfile.TemporaryDirectory(prefix="splinter-release-") as temp:
        note_file = Path(temp) / "notes.md"
        note_file.write_text(notes)
        if not release:
            subprocess.run(["gh", "release", "create", tag, "--repo", repository, "--target", values["commit"],
                            "--draft", "--title", f"Splinter {values['version']}", "--notes-file", str(note_file)], check=True)
        subprocess.run(["gh", "release", "upload", tag, "--repo", repository, "--clobber", *map(str, assets)], check=True)
    release = find_release(repository, tag)
    if not release or not release["draft"]:
        raise RuntimeError("Cannot find the uploaded draft release")
    subprocess.run(["gh", "api", "--method", "PATCH", f"repos/{repository}/releases/{release['id']}",
                    "-F", "draft=false", "-f", "make_latest=legacy"], check=True, stdout=subprocess.DEVNULL)
    print(f"Published https://github.com/{repository}/releases/tag/{tag}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["prepare", "publish"])
    parser.add_argument("--assets", type=Path, default=ROOT / "dist")
    args = parser.parse_args()
    if args.command == "prepare":
        prepare()
    else:
        publish(args.assets.resolve())
