"""Print the Policy review groups of AGENTS.md and CODING_STANDARDS.md as JSON for policy-review.

Each `###` subsection of a file's "## Policy" section is one group, and every `**<PREFIX>-<n>.**`
rule under it belongs to that group. The workflow cannot read files, so this script is where the
coverage check happens: it refuses a missing file, a rule outside a subsection, an empty subsection,
a duplicate ID, or a gap in the numbering of a prefix. A refused file stops the review instead of
leaving a rule unchecked.

Usage, from the project root: python3 <skill dir>/groups.py [FILE ...]
(default: AGENTS.md CODING_STANDARDS.md)
"""

import json
import re
import sys
from collections import defaultdict
from pathlib import Path

GROUP = re.compile(r"^### \d+\. (?P<title>.+?) \(`.*`\)$")
RULE = re.compile(r"^\*\*(?P<prefix>[A-Z]+)-(?P<number>\d+)\.\*\*")


def parse(name: str, text: str) -> list[dict]:
    """Return each Policy subsection of `text` with its rule IDs. Exit on a defect."""
    lines = text.splitlines()
    if "## Policy" not in lines:
        sys.exit(f"{name} has no '## Policy' section")
    start = lines.index("## Policy")
    end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("## ")), len(lines))

    groups: list[dict] = []
    for line in lines[start + 1 : end]:
        if line.startswith("### "):
            match = GROUP.match(line)
            if not match:
                sys.exit(f"{name}: Policy heading is not '### <n>. <title> (`PREFIX`)': {line}")
            groups.append({"title": match["title"], "file": name, "rules": []})
        elif match := RULE.match(line):
            if not groups:
                sys.exit(f"{name}: rule outside a Policy subsection: {line}")
            groups[-1]["rules"].append(f"{match['prefix']}-{match['number']}")

    for group in groups:
        if not group["rules"]:
            sys.exit(f"{name}: Policy subsection with no rules: {group['title']}")
    return groups


def check(groups: list[dict]) -> None:
    """Exit on a duplicate ID or a numbering gap, across all files."""
    ids = [rule for group in groups for rule in group["rules"]]
    duplicates = sorted({rule for rule in ids if ids.count(rule) > 1})
    if duplicates:
        sys.exit(f"Duplicate rule IDs: {', '.join(duplicates)}")

    numbers: dict[str, list[int]] = defaultdict(list)
    for rule in ids:
        prefix, number = rule.split("-")
        numbers[prefix].append(int(number))
    for prefix, found in numbers.items():
        if sorted(found) != list(range(1, len(found) + 1)):
            sys.exit(f"{prefix} rules are not numbered 1 to {len(found)}: {sorted(found)}")


if __name__ == "__main__":
    names = sys.argv[1:] or ["AGENTS.md", "CODING_STANDARDS.md"]
    for name in names:
        if not Path(name).is_file():
            sys.exit(f"{name} not found; run from the project root")
    groups = [group for name in names for group in parse(name, Path(name).read_text())]
    check(groups)
    print(json.dumps(groups))
