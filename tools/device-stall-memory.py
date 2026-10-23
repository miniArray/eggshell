#!/usr/bin/env nix-shell
#! nix-shell -i python3 -p python3
"""Summarize a read-only process smaps capture by mapping (not system memory)."""

import argparse
import collections
import json
import pathlib
import re


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("smaps", type=pathlib.Path)
    options = parser.parse_args()
    mappings = collections.defaultdict(collections.Counter)
    name = ""
    for line in options.smaps.read_text().splitlines():
        if re.match(r"^[0-9a-f]+-[0-9a-f]+ ", line):
            fields = line.split(maxsplit=5)
            name = fields[5] if len(fields) == 6 else "[anonymous]"
        elif line.startswith(
            ("Rss:", "Pss:", "Private_Dirty:", "Private_Clean:", "Shared_Clean:")
        ):
            field, value, _unit = line.split()
            mappings[name][field.removesuffix(":")] += int(value)
    print(
        json.dumps(
            sorted(
                ({"mapping": name, **values} for name, values in mappings.items()),
                key=lambda row: row["Rss"],
                reverse=True,
            ),
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
