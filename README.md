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
import csv, sys
from pathlib import Path
from lxml import etree

ATA = {"21": "Air Conditioning", "22": "Auto Flight", "24": "Electrical Power",
       "28": "Fuel", "29": "Hydraulic Power", "32": "Landing Gear"}  # extend as needed

IPD_ONLY = True          # only harvest DMs with an IPD info code
IPD_INCODES = {"941"}    # adjust to your project's IPD info codes

def L(name):             # namespace-agnostic step
    return f'*[local-name()="{name}"]'

def first(node, xp):
    r = node.xpath(xp)
    return r[0] if r else None

def code(el):
    return "-".join((c.text or "").strip() for c in el if isinstance(c.tag, str))

def issue_key(doc, addr):
    iss = first(doc, f'//{L(addr)}//{L("issno")}')
    if iss is None:
        return (0, 0)
    return (int(iss.get("issno", "0") or 0), int(iss.get("inwork", "0") or 0))

def build_index(folder):
    dms, pms = {}, {}
    for f in Path(folder).rglob("*.xml"):
        try:
            doc = etree.parse(str(f))
        except etree.XMLSyntaxError as e:
            print(f"Skipping {f}: {e}", file=sys.stderr)
            continue
        if (a := first(doc, f'//{L("dmaddres")}//{L("avee")}')) is not None:
            target, k, iss = dms, code(a), issue_key(doc, "dmaddres")
        elif (p := first(doc, f'//{L("pmaddres")}//{L("pmc")}')) is not None:
            target, k, iss = pms, code(p), issue_key(doc, "pmaddres")
        else:
            continue
        if k not in target or iss > target[k][0]:   # keep the latest issue
            target[k] = (iss, doc, f)
    return dms, pms

def harvest_dm(doc, rows):
    avee = first(doc, f'//{L("dmaddres")}//{L("avee")}')
    if IPD_ONLY:
        incode = first(avee, f'{L("incode")}')
        if incode is None or (incode.text or "").strip() not in IPD_INCODES:
            return
    chap_el = first(avee, f'{L("chapnum")}')
    chap = (chap_el.text or "").strip() if chap_el is not None else ""
    system = ATA.get(chap, f"Unknown ({chap})")
    for p in doc.xpath(f'//{L("pnr")}'):     # narrow to //isn/pnr if needed
        if p.text and p.text.strip():
            rows.add((p.text.strip(), system))

def walk(master_pm, dms, pms):
    rows, seen_pm, seen_dm = set(), set(), set()
    stack = [master_pm]
    while stack:
        pm = stack.pop()
        content = first(pm, f'//{L("content")}')
        if content is None:
            continue
        # DMs listed in this PM
        for a in content.xpath(f'.//{L("pmentry")}//{L("refdm")}//{L("avee")}'):
            k = code(a)
            if k in seen_dm:
                continue
            seen_dm.add(k)
            if k in dms:
                harvest_dm(dms[k][1], rows)
            else:
                print(f"Missing DM: {k}", file=sys.stderr)
        # Child PMs listed in this PM
        for p in content.xpath(f'.//{L("pmentry")}//{L("refpm")}//{L("pmc")}'):
            k = code(p)
            if k in seen_pm:
                continue
            seen_pm.add(k)
            if k in pms:
                stack.append(pms[k][1])
            else:
                print(f"Missing PM: {k}", file=sys.stderr)
    return sorted(rows)

if __name__ == "__main__":
    folder, master_file, out = sys.argv[1:4]
    dms, pms = build_index(folder)
    rows = walk(etree.parse(master_file), dms, pms)
    with open(out, "w", newline="", encoding="utf-8-sig") as f:   # BOM so Excel reads UTF-8
        w = csv.writer(f)
        w.writerow(["Part Number", "ATA Chap/System"])
        w.writerows(rows)
    print(f"{len(rows)} rows written to {out}")
```

