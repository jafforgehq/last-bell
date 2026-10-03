#!/usr/bin/env python3
"""Compares two outputs of the balance harness (tools/balance.gd --out=...) and prints 'identical' or the games that differ.

    python3 tools/compare_harness.py before.json after.json

Only the `took` field (how many seconds a game took to play) and the `out` flag of the recorded arguments (where the file was
written) are ignored; everything else (every game, every day, the notes, the summary) must be equal. Exit status 0 when
identical, 1 when something differs, 2 when a file cannot be read.
"""
import json
import sys


def strip_took(value):
    """The same data without any `took` key, however deep."""
    if isinstance(value, dict):
        return {k: strip_took(v) for k, v in value.items() if k != "took"}
    if isinstance(value, list):
        return [strip_took(v) for v in value]
    return value


def comparable(data):
    """What is compared: no `took` anywhere, and not the path the file was written to."""
    data = strip_took(data)
    if isinstance(data, dict) and isinstance(data.get("args"), dict):
        data["args"] = {k: v for k, v in data["args"].items() if k != "out"}
    return data


def games_of(data):
    """The list of games of a harness file: it may be the list itself or a dictionary that holds it."""
    if isinstance(data, list):
        return data
    if isinstance(data, dict):
        for key in ("games", "results", "runs"):
            if isinstance(data.get(key), list):
                return data[key]
    return None


def label(game, index):
    if isinstance(game, dict) and "seed" in game:
        return "game %d (seed %g, difficulty %g)" % (index + 1, float(game.get("seed")), float(game.get("difficulty")))
    return "game %d" % (index + 1)


def first_difference(a, b, path=""):
    """Where two plain data trees first differ, as 'path: a != b' (None when equal)."""
    if isinstance(a, dict) and isinstance(b, dict):
        for key in sorted(set(a) | set(b)):
            if key not in a:
                return "%s.%s: missing before, now %r" % (path, key, b[key])
            if key not in b:
                return "%s.%s: %r before, missing now" % (path, key, a[key])
            found = first_difference(a[key], b[key], "%s.%s" % (path, key))
            if found:
                return found
        return None
    if isinstance(a, list) and isinstance(b, list):
        for i in range(max(len(a), len(b))):
            if i >= len(a):
                return "%s[%d]: missing before, now %r" % (path, i, b[i])
            if i >= len(b):
                return "%s[%d]: %r before, missing now" % (path, i, a[i])
            found = first_difference(a[i], b[i], "%s[%d]" % (path, i))
            if found:
                return found
        return None
    return None if a == b else "%s: %r != %r" % (path, a, b)


def main(argv):
    if len(argv) != 3:
        print(__doc__.strip())
        return 2
    loaded = []
    for path in argv[1:]:
        try:
            with open(path) as f:
                loaded.append(comparable(json.load(f)))
        except (OSError, ValueError) as err:
            print("cannot read %s: %s" % (path, err))
            return 2
    a, b = loaded
    if a == b:
        print("identical")
        return 0
    ga, gb = games_of(a), games_of(b)
    if ga is None or gb is None:
        print("differ: %s" % (first_difference(a, b) or "?"))
        return 1
    differing = 0
    if isinstance(a, dict) and isinstance(b, dict):
        for key in sorted((set(a) | set(b)) - {"games", "results", "runs"}):
            if a.get(key) != b.get(key):
                print("%s differs: %s" % (key, first_difference(a.get(key), b.get(key), "." + key)))
    for i in range(max(len(ga), len(gb))):
        if i >= len(ga) or i >= len(gb):
            print("%s: only in %s" % (label(gb[i] if i >= len(ga) else ga[i], i), "the second file" if i >= len(ga) else "the first file"))
            differing += 1
            continue
        if ga[i] != gb[i]:
            differing += 1
            print("%s differs: %s" % (label(ga[i], i), first_difference(ga[i], gb[i])))
    print("%d of %d games differ" % (differing, max(len(ga), len(gb))))
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
