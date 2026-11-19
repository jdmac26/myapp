# myapp

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://flutter.dev/docs/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://flutter.dev/docs/cookbook)

For help getting started with Flutter, view our
[online documentation](https://flutter.dev/docs), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

```
#!/usr/bin/env python3
"""
IPD part number -> ATA chapter/system extractor (S1000D Issue 3.0).

Walks a master PM and all child PMs, collects every IPD DM (incode 941)
referenced via <pmentry>/<refdm>, and pulls each <pnr> paired with the DM's
own <chapnum>, mapped to an ATA system name.

Usage:
    python ipd_parts.py <xml_folder> <master_pm.xml> <output.csv> [--workers N]

Assumes a flat folder with files named DMC-<code>[_<issno>-<inwork>][_<lang>-<country>].xml
(and PMC-... likewise).
"""
import argparse
import csv
import os
import re
import sys
import time
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

from lxml import etree

# --------------------------------------------------------------------------- config
IPD_INCODES = {"941"}

ATA = {
    "21": "Air Conditioning",
    "22": "Auto Flight",
    "23": "Communications",
    "24": "Electrical Power",
    "25": "Equipment/Furnishings",
    "26": "Fire Protection",
    "27": "Flight Controls",
    "28": "Fuel",
    "29": "Hydraulic Power",
    "30": "Ice and Rain Protection",
    "31": "Indicating/Recording Systems",
    "32": "Landing Gear",
    "33": "Lights",
    "34": "Navigation",
    "35": "Oxygen",
    "36": "Pneumatic",
    "38": "Water/Waste",
    "49": "Airborne Auxiliary Power",
    "52": "Doors",
    "53": "Fuselage",
    "57": "Wings",
    "71": "Power Plant",
    "72": "Engine",
    "73": "Engine Fuel and Control",
    "79": "Oil",
    "80": "Starting",
}  # extend/replace with your own mapping

# Below this many IPD DMs, a plain loop beats process-pool start-up cost.
PARALLEL_THRESHOLD = 50

# --------------------------------------------------------------------------- parsing
# Never load or fetch the DTD; it's the usual hidden cost with S1000D 3.0 files.
# Add recover=True if some files fail on undeclared entities.
PARSER = etree.XMLParser(load_dtd=False, no_network=True,
                         resolve_entities=False, huge_tree=True)

# Pre-compiled XPaths (S1000D 3.0 elements are not namespaced).
XP_PM_DM_AVEE = etree.XPath("//content//pmentry//refdm//avee")
XP_PM_PM_PMC = etree.XPath("//content//pmentry//refpm//pmc")
XP_DM_AVEE = etree.XPath("//dmaddres//avee")

FNAME = re.compile(r"^(DMC|PMC)-(.+?)(?:_(\d{3})-(\d{2}))?(?:_[A-Z]{2}-[A-Z]{2})?$",
                   re.IGNORECASE)
NON_ALNUM = re.compile(r"[^A-Z0-9]")


def norm(s: str) -> str:
    return NON_ALNUM.sub("", s.upper())


def ref_key(el) -> str:
    """Concatenate avee/pmc child values into the same form as a normalised filename."""
    return norm("".join((c.text or "") for c in el if isinstance(c.tag, str)))


def build_index(folder: str):
    """Filename-only index of a flat folder: normalised code -> (issue rank, path)."""
    dms, pms = {}, {}
    with os.scandir(folder) as it:
        for e in it:
            name = e.name
            if len(name) < 5 or name[-4:].lower() != ".xml":
                continue
            m = FNAME.match(name[:-4])
            if not m:
                continue
            kind, code, iss, inw = m.groups()
            key = norm(code)
            rank = (int(iss or 0), int(inw or 0))
            d = dms if kind.upper() == "DMC" else pms
            cur = d.get(key)
            if cur is None or rank > cur[0]:          # keep latest issue
                d[key] = (rank, e.path)
    return dms, pms


def collect_ipd_dms(master_pm: str, dms: dict, pms: dict):
    """Walk the PM tree; return paths of IPD DMs referenced anywhere in it."""
    ipd_paths, seen_pm, seen_dm, missing = set(), set(), set(), []
    stack = [master_pm]
    seen_pm.add(Path(master_pm).resolve())
    while stack:
        path = stack.pop()
        try:
            pm = etree.parse(path, PARSER)
        except (etree.XMLSyntaxError, OSError) as e:
            print(f"Skipping PM {path}: {e}", file=sys.stderr)
            continue

        for avee in XP_PM_DM_AVEE(pm):
            if (avee.findtext("incode") or "").strip() not in IPD_INCODES:
                continue                              # not IPD: never opened
            k = ref_key(avee)
            if k in seen_dm:
                continue
            seen_dm.add(k)
            hit = dms.get(k)
            if hit:
                ipd_paths.add(hit[1])
            else:
                missing.append(f"DM {k} (referenced in {os.path.basename(path)})")

        for pmc in XP_PM_PM_PMC(pm):
            k = ref_key(pmc)
            hit = pms.get(k)
            if not hit:
                missing.append(f"PM {k} (referenced in {os.path.basename(path)})")
                continue
            resolved = Path(hit[1]).resolve()
            if resolved in seen_pm:
                continue
            seen_pm.add(resolved)
            stack.append(hit[1])

    return ipd_paths, len(seen_pm), missing


def harvest(path: str):
    """Return [(pnr, system), ...] for one IPD DM."""
    try:
        doc = etree.parse(path, PARSER)
    except (etree.XMLSyntaxError, OSError) as e:
        print(f"Skipping DM {path}: {e}", file=sys.stderr)
        return []
    avee = XP_DM_AVEE(doc)
    if not avee or (avee[0].findtext("incode") or "").strip() not in IPD_INCODES:
        return []                                     # confirm it really is IPD
    chap = (avee[0].findtext("chapnum") or "").strip()
    system = ATA.get(chap, f"Unknown ({chap})")
    out = []
    for p in doc.iter("pnr"):                         # narrow to isn/pnr if needed
        t = p.text
        if t:
            t = t.strip()
            if t:
                out.append((t, system))
    return out


# --------------------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("folder")
    ap.add_argument("master_pm")
    ap.add_argument("output")
    ap.add_argument("--workers", type=int, default=None,
                    help="worker processes (default: CPU count; 1 = no parallelism)")
    args = ap.parse_args()

    t0 = t = time.perf_counter()

    def lap(label):
        nonlocal t
        now = time.perf_counter()
        print(f"{label:<8}{now - t:7.2f}s", file=sys.stderr)
        t = now

    dms, pms = build_index(args.folder)
    lap("index")
    print(f"        {len(dms)} DMs, {len(pms)} PMs on disk", file=sys.stderr)

    ipd_paths, n_pms, missing = collect_ipd_dms(args.master_pm, dms, pms)
    lap("PM walk")
    print(f"        {n_pms} PMs walked, {len(ipd_paths)} IPD DMs to parse", file=sys.stderr)
    for m in missing:
        print(f"Missing {m}", file=sys.stderr)

    rows = set()
    paths = sorted(ipd_paths)
    if args.workers == 1 or len(paths) < PARALLEL_THRESHOLD:
        for p in paths:
            rows.update(harvest(p))
    else:
        workers = args.workers or os.cpu_count() or 1
        chunk = max(1, len(paths) // (workers * 4))
        with ProcessPoolExecutor(max_workers=workers) as pool:
            for result in pool.map(harvest, paths, chunksize=chunk):
                rows.update(result)
    lap("harvest")

    with open(args.output, "w", newline="", encoding="utf-8-sig") as f:  # BOM for Excel
        w = csv.writer(f)
        w.writerow(["Part Number", "ATA Chap/System"])
        w.writerows(sorted(rows))
    lap("write")

    print(f"{len(rows)} rows written to {args.output} "
          f"({time.perf_counter() - t0:.2f}s total)", file=sys.stderr)


if __name__ == "__main__":   # required for multiprocessing on Windows
    main()
```
