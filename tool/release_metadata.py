"""Resolve the numeric app version and validate a release's source and tag."""

import argparse
import os
import re
import subprocess
from pathlib import Path


VERSION_PATTERN = re.compile(r"^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$", re.M)
PREVIOUS_BUILD_PATTERN = re.compile(
    r"^version:\s*[0-9A-Za-z.\-]+\+(\d+)\s*$", re.M
)


def git(*args):
    return subprocess.check_output(["git", *args], text=True).strip()


def resolve_metadata(release=False, expected_build_name=None, expected_build_number=None):
    match = VERSION_PATTERN.search(Path("pubspec.yaml").read_text(encoding="utf-8"))
    if not match:
        raise ValueError("pubspec.yaml must have a numeric version like x.y.z+N")
    build_name, build_number = match.group(1), int(match.group(2))
    if build_number < 1:
        raise ValueError("build number must be positive")
    if expected_build_name and expected_build_name != build_name:
        raise ValueError("build name does not match the prepared source")
    if expected_build_number and int(expected_build_number) != build_number:
        raise ValueError("build number does not match the prepared source")

    metadata = {
        "build_name": build_name,
        "build_number": str(build_number),
        "source_sha": git("rev-parse", "HEAD"),
    }
    if not release:
        return metadata

    event = os.environ.get("GITHUB_EVENT_NAME")
    if event == "push" and os.environ.get("GITHUB_REF_TYPE") == "tag":
        tag = os.environ.get("GITHUB_REF_NAME", "")
    elif event == "workflow_dispatch":
        tag = os.environ.get("DISPATCH_TAG_NAME", "").strip()
    else:
        raise ValueError("release requires a tag push or workflow_dispatch")
    if tag != f"v{build_name}":
        raise ValueError(f"release tag must be v{build_name}")

    skip_release = event == "workflow_dispatch" and os.environ.get("SKIP_RELEASE") == "true"
    if not skip_release:
        target_sha = git("rev-parse", "--verify", f"refs/tags/{tag}^{{commit}}")
        if target_sha != metadata["source_sha"]:
            raise ValueError("release tag must point to the checked-out source commit")

    previous_numbers = []
    for previous_tag in git("tag", "--list", "v*").splitlines():
        if previous_tag == tag:
            continue
        try:
            content = subprocess.check_output(
                ["git", "show", f"{previous_tag}:pubspec.yaml"],
                text=True,
                stderr=subprocess.DEVNULL,
            )
        except subprocess.CalledProcessError:
            continue
        previous_match = PREVIOUS_BUILD_PATTERN.search(content)
        if previous_match:
            previous_numbers.append(int(previous_match.group(1)))
    if previous_numbers and build_number <= max(previous_numbers):
        raise ValueError(
            f"build number {build_number} must exceed previous maximum {max(previous_numbers)}"
        )
    metadata["tag_name"] = tag
    return metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release", action="store_true")
    parser.add_argument("--expected-build-name")
    parser.add_argument("--expected-build-number")
    args = parser.parse_args()
    try:
        metadata = resolve_metadata(
            args.release, args.expected_build_name, args.expected_build_number
        )
    except (ValueError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error)) from error
    for key, value in metadata.items():
        print(f"{key}={value}")


if __name__ == "__main__":
    main()
