#!/usr/bin/env python3
"""Assert that the documentation still describes the repository.

Documentation drifts silently: a link survives a file rename as a dead reference,
and a stated test count survives the addition of a test as an understatement. Both
were present in this repository before this check existed, which is the argument for
it running on every push rather than being audited occasionally.

Only claims that can be verified mechanically are checked. Prose is left to review.

Usage: scripts/docs-check.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parent.parent

# Counts are written as words in the prose, so the mapping is explicit rather than
# parsed; a module gaining a tenth test should force the sentence to be reread.
NUMBER_WORDS = {
    "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
    "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13,
    "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18,
    "nineteen": 19, "twenty": 20,
}

MARKDOWN_LINK = re.compile(r"\[[^\]]*\]\(([^)]+)\)")
RUN_COUNT = re.compile(r"`terraform test` — ([a-z]+) runs")

_failures: list[str] = []
_checks = 0


def check(description: str, condition: bool, detail: str = "") -> None:
    """Record one assertion and report it."""
    global _checks
    _checks += 1
    if condition:
        print(f"  PASS  {description}")
        return
    suffix = f" ({detail})" if detail else ""
    print(f"  FAIL  {description}{suffix}")
    _failures.append(description)


def markdown_files() -> list[Path]:
    return sorted(
        path
        for path in REPOSITORY_ROOT.rglob("*.md")
        if ".git" not in path.parts and ".terraform" not in str(path)
    )


def check_links() -> None:
    """Every relative link must resolve to something that exists."""
    broken: list[str] = []
    total = 0
    for document in markdown_files():
        for target in MARKDOWN_LINK.findall(document.read_text()):
            if target.startswith(("http://", "https://", "mailto:", "#")):
                continue
            total += 1
            path = (document.parent / target.split("#", 1)[0]).resolve()
            if not path.exists():
                broken.append(f"{document.relative_to(REPOSITORY_ROOT)} -> {target}")

    check(
        f"every relative link resolves ({total} checked)",
        not broken,
        "; ".join(broken),
    )


def check_module_test_counts() -> None:
    """A module README stating a run count must state the correct one."""
    for readme in sorted((REPOSITORY_ROOT / "terraform" / "modules").glob("*/README.md")):
        module = readme.parent
        stated = RUN_COUNT.search(readme.read_text())
        if stated is None:
            check(f"{module.name} README states its test count", False, "no count found")
            continue

        claimed = NUMBER_WORDS.get(stated.group(1))
        actual = sum(
            len(re.findall(r"^run \"", test.read_text(), re.MULTILINE))
            for test in (module / "tests").glob("*.tftest.hcl")
        )
        check(
            f"{module.name} README states {actual} test runs",
            claimed == actual,
            f"README says {stated.group(1)} ({claimed})",
        )


def check_declared_readme_exists() -> None:
    """The package manifest must not name a long description that is absent."""
    manifest = (REPOSITORY_ROOT / "app" / "pyproject.toml").read_text()
    declared = re.search(r'^readme = "([^"]+)"', manifest, re.MULTILINE)
    check(
        "the package manifest's declared readme exists",
        declared is not None and (REPOSITORY_ROOT / "app" / declared.group(1)).exists(),
    )


def check_documented_directories() -> None:
    """Each part of the repository a reader lands in must introduce itself."""
    for directory in ("app", "k8s", "scripts", "terraform", "terraform/envs", "docs/adr"):
        check(
            f"{directory}/ carries a README",
            (REPOSITORY_ROOT / directory / "README.md").is_file(),
        )


def check_make_targets_are_documented() -> None:
    """Every target reachable from the command line must appear in `make help`."""
    makefile = (REPOSITORY_ROOT / "Makefile").read_text()
    declared = set(re.findall(r"^\.PHONY: ([\w-]+)", makefile, re.MULTILINE))
    documented = set(re.findall(r"^([\w-]+):.*## ", makefile, re.MULTILINE))
    missing = sorted(declared - documented)
    check("every make target is described by `make help`", not missing, ", ".join(missing))


def check_adr_index_is_complete() -> None:
    """The decision index must list every record, and no record that is absent."""
    index = REPOSITORY_ROOT / "docs" / "adr" / "README.md"
    listed = set(re.findall(r"\((\d{4}-[\w-]+\.md)\)", index.read_text()))
    present = {path.name for path in index.parent.glob("[0-9]*.md")}
    check(
        "the decision index lists exactly the records that exist",
        listed == present,
        f"indexed but absent: {sorted(listed - present)}; present but unindexed: {sorted(present - listed)}",
    )


def main() -> int:
    print("[docs-check] verifying the documentation against the repository")
    check_links()
    check_module_test_counts()
    check_declared_readme_exists()
    check_documented_directories()
    check_make_targets_are_documented()
    check_adr_index_is_complete()

    print(f"[docs-check] {_checks} checks, {len(_failures)} failed")
    return 1 if _failures else 0


if __name__ == "__main__":
    sys.exit(main())
