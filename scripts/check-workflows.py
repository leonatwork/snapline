#!/usr/bin/env python3
"""Checks the supply-chain hardening of .github/workflows/{ci,release}.yml (issue #20):

  - every `uses:` is pinned to a full 40-character commit SHA with a version comment
  - every actions/checkout step sets `persist-credentials: false`
  - no workflow grants `contents: write` outside the release publish job
  - release.yml has a `concurrency` group, a `build` job with `contents: read`
    (signing, test, build, package, artifact upload) and a tag-only `publish` job
    with `contents: write` that takes the artifact via download-artifact, has no
    checkout, no signing secrets and calls `gh release create` with GH_REPO/--repo

Standard library only (the repo has no dependencies), so it runs on the macOS
runner and on Linux. The workflows are read line by line by indentation, which
is enough for the block-style YAML used in this repo.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
WORKFLOWS = ROOT / ".github" / "workflows"
FILES = ("ci.yml", "release.yml")

PINNED = re.compile(r"^[\w.-]+/[\w./-]+@[0-9a-f]{40} # v\d+(\.\d+)*$")
USES = re.compile(r"^\s*(?:-\s+)?uses:\s*(.*?)\s*$")

errors = []


def fail(path, message):
    errors.append(f"{path}: {message}")


def indent(line):
    return len(line) - len(line.lstrip(" "))


def content(lines):
    return [l for l in lines if l.strip() and not l.lstrip().startswith("#")]


def children(lines, key, level):
    """Maps every `key:` at indentation `level` to the lines of its block."""
    result, current = {}, None
    for line in lines:
        if not line.strip():
            continue
        if indent(line) == level and re.match(r"^\s*[\w-]+:", line):
            current = line.strip().split(":", 1)[0]
            result[current] = [line]
        elif indent(line) < level:
            current = None
        elif current is not None:
            result[current].append(line)
    return result if key is None else result.get(key, [])


def steps(job_lines):
    """Splits the `steps:` block of a job into one list of lines per step."""
    block = next((v for k, v in children(job_lines, None, 4).items() if k == "steps"), [])
    items, level = [], None
    for line in content(block[1:]):
        stripped = line.lstrip(" ")
        if stripped.startswith("- ") and (level is None or indent(line) == level):
            level = indent(line)
            items.append([line])
        elif items:
            items[-1].append(line)
    return items


def text(lines):
    return "\n".join(lines)


def permission(lines, level):
    """`contents:` value of the `permissions:` block at indentation `level`, or None."""
    block = children(lines, "permissions", level)
    for line in block:
        match = re.match(r"^\s*contents:\s*(\w+)", line)
        if match:
            return match.group(1)
    return None


def check_common(name, lines):
    for number, line in enumerate(lines, 1):
        match = USES.match(line)
        if match and not PINNED.match(match.group(1)):
            fail(name, f"line {number}: `uses: {match.group(1)}` is not pinned to a "
                       "40-character commit SHA with a `# vX.Y.Z` comment")
    jobs = children(content(lines), "jobs", 0)
    for job, job_lines in children(jobs, None, 2).items():
        for step in steps(job_lines):
            if any(re.search(r"uses:\s*actions/checkout@", l) for l in step):
                if not any(re.match(r"^\s*persist-credentials:\s*false\s*$", l) for l in step):
                    fail(name, f"job `{job}`: actions/checkout without `persist-credentials: false`")
    if permission(lines, 0) == "write":
        fail(name, "workflow-level `contents: write`")


def check_release(name, lines):
    top = children(content(lines), None, 0)
    concurrency = top.get("concurrency", [])
    if not any(re.match(r"^\s*group:\s*\S", l) for l in concurrency):
        fail(name, "missing workflow `concurrency` with a `group`")

    jobs = children(top.get("jobs", []), None, 2)
    if set(jobs) != {"build", "publish"}:
        fail(name, f"expected jobs `build` and `publish`, found {sorted(jobs)}")
    build, publish = jobs.get("build", []), jobs.get("publish", [])

    if permission(build, 4) != "read":
        fail(name, "job `build` must set `permissions: contents: read`")
    build_text = text(build)
    for needle, what in (
        ("secrets.MACOS_SIGNING_P12", "signing certificate import"),
        ("security create-keychain", "keychain setup"),
        ("swift test", "tests"),
        ("scripts/build-app.sh", "app build"),
        ("codesign --verify --strict", "signature verification"),
        ("CFBundleShortVersionString", "version check"),
        ("shasum -a 256", "checksum"),
        ("actions/upload-artifact@", "artifact upload"),
        ("name: Snapline-manual", "manual artifact Snapline-manual"),
        ("path: Snapline-manual.zip", "manual artifact path"),
        ("checksum.txt", "checksum.txt in the release artifact"),
    ):
        if needle not in build_text:
            fail(name, f"job `build` lacks the {what} (`{needle}`)")
    if "gh release" in build_text:
        fail(name, "job `build` must not publish a release")

    if permission(publish, 4) != "write":
        fail(name, "job `publish` must set `permissions: contents: write`")
    publish_text = text(publish)
    if not re.search(r"^\s*needs:\s*\[?\s*build\s*\]?\s*$", publish_text, re.M):
        fail(name, "job `publish` must have `needs: build`")
    if not re.search(r"^\s*if:.*github\.ref_type == 'tag'", publish_text, re.M):
        fail(name, "job `publish` must only run for tags")
    if "actions/checkout@" in publish_text:
        fail(name, "job `publish` must not check out the repository")
    if "actions/download-artifact@" not in publish_text:
        fail(name, "job `publish` must take the artifact via actions/download-artifact")
    if "gh release create" not in publish_text:
        fail(name, "job `publish` must call `gh release create`")
    if "GH_REPO:" not in publish_text and "--repo" not in publish_text:
        fail(name, "job `publish` must pass the repository via GH_REPO or --repo")
    if "**SHA-256**" not in publish_text or "cat checksum.txt" not in publish_text:
        fail(name, "job `publish` must put checksum.txt into the release notes")
    for needle in ("MACOS_SIGNING", "keychain", "codesign"):
        if needle in publish_text:
            fail(name, f"job `publish` must not handle signing (`{needle}`)")


def main():
    for name in FILES:
        path = WORKFLOWS / name
        if not path.is_file():
            fail(name, "missing")
            continue
        lines = path.read_text(encoding="utf-8").splitlines()
        check_common(name, lines)
        if name == "release.yml":
            check_release(name, lines)
    for error in errors:
        print(f"error: {error}", file=sys.stderr)
    if errors:
        return 1
    print(f"Workflows OK: {', '.join(FILES)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
