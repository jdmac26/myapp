#!/usr/bin/env python3
"""
Extract a PDF's clickable table of contents into XML, and note the heading
each entry actually lands on.

For every internal link on the TOC page(s) it records:
  - tocTitle     the text of the TOC line
  - printedPage  the page number printed in the TOC (if any)
  - targetPage   the page the link really jumps to
  - pageHeading  the heading found where the link lands
  - match        how tocTitle compares to pageHeading

A heading is matched by its style. Defaults: Verdana, 12pt, bold, with a
drawn border around it. Change these with the options below.

Usage:
    pip install pymupdf
    python toc_to_xml.py input.pdf output.xml --pages 2-3
    python toc_to_xml.py input.pdf output.xml --heading-font Verdana --heading-size 12
    python toc_to_xml.py input.pdf output.xml --no-border       # headings without a box
    python toc_to_xml.py input.pdf --inspect 7                   # show the fonts/borders on page 7
"""
import argparse
import difflib
import re
import xml.etree.ElementTree as ET

import pymupdf as fitz  # PyMuPDF


# ---------------------------------------------------------------- TOC links

def parse_pages(spec, page_count):
    if not spec:
        return range(page_count)
    out = []
    for part in spec.split(","):
        a, _, b = part.partition("-")
        out.extend(range(int(a) - 1, int(b or a)))
    return out


def line_text_for_link(page, rect):
    """Full text of the line a link box sits on (the box often covers only the number)."""
    words = page.get_text("words")
    hits = [w for w in words if rect.y0 - 1 <= (w[1] + w[3]) / 2 <= rect.y1 + 1]
    hits.sort(key=lambda w: (round(w[1]), w[0]))
    return " ".join(w[4] for w in hits)


def split_title_and_number(text):
    """'1.2 Background ........ 14' -> ('1.2 Background', '14')"""
    m = re.match(r"^(.*?)[\s.·…_-]*?(\d+|[ivxlcdm]+)\s*$", text, re.IGNORECASE)
    if m and m.group(1).strip():
        return m.group(1).strip(" ._…·-"), m.group(2)
    return text.strip(), None


# ---------------------------------------------------------------- page analysis

def _is_bold(span):
    return bool(span["flags"] & 16) or "bold" in span["font"].lower()


def _font_key(name):
    """'ABCDEF+Verdana,Bold' -> 'verdanabold' (drops subset prefix and punctuation)."""
    name = name.split("+", 1)[-1]
    return re.sub(r"[^a-z0-9]", "", name.lower())


def page_lines(page):
    lines = []
    for block in page.get_text("dict")["blocks"]:
        for line in block.get("lines", []):
            spans = [s for s in line["spans"] if s["text"].strip()]
            if not spans:
                continue
            lines.append({
                "text": " ".join(" ".join(s["text"] for s in spans).split()),
                "bbox": fitz.Rect(line["bbox"]),
                "size": max(s["size"] for s in spans),
                "bold": all(_is_bold(s) for s in spans),
                "fonts": sorted({s["font"] for s in spans}),
            })
    lines.sort(key=lambda l: (round(l["bbox"].y0), l["bbox"].x0))
    return lines


def page_shapes(page):
    """Rectangles and horizontal/vertical rules drawn on the page."""
    boxes, hrules = [], []
    for d in page.get_drawings():
        for item in d["items"]:
            kind = item[0]
            if kind == "re":
                r = fitz.Rect(item[1])
                if r.height < 2.5:          # a thin filled bar is really a rule
                    hrules.append((r.x0, r.x1, (r.y0 + r.y1) / 2))
                else:
                    boxes.append(r)
            elif kind == "qu":
                boxes.append(item[1].rect)
            elif kind == "l":
                p1, p2 = item[1], item[2]
                if abs(p1.y - p2.y) < 1:
                    hrules.append((min(p1.x, p2.x), max(p1.x, p2.x), p1.y))
        # a closed path drawn from 4 separate lines: use its overall rectangle
        if d.get("closePath") or len(d["items"]) >= 4:
            r = d["rect"]
            if r.height >= 2.5 and r.width >= 2.5:
                boxes.append(r)
    return boxes, hrules


def bordered_box(bbox, boxes, hrules, tol=4):
    """The border around a text line, if there is one; else None."""
    best = None
    for r in boxes:
        if (r.x0 - tol <= bbox.x0 and r.y0 - tol <= bbox.y0 and
                r.x1 + tol >= bbox.x1 and r.y1 + tol >= bbox.y1 and
                r.height <= bbox.height * 8):          # not a whole-page frame
            if best is None or r.get_area() < best.get_area():
                best = r
    if best is not None:
        return best
    # top and bottom rules close to the text, overlapping it horizontally
    def overlaps(x0, x1):
        return x0 <= bbox.x0 + 2 and x1 >= bbox.x1 - 2
    reach = max(15, bbox.height * 3)   # room for a heading that wraps to 2-3 lines
    above = [y for x0, x1, y in hrules if overlaps(x0, x1) and bbox.y0 - reach <= y <= bbox.y0 + 1]
    below = [y for x0, x1, y in hrules if overlaps(x0, x1) and bbox.y1 - 1 <= y <= bbox.y1 + reach]
    if above and below:
        return fitz.Rect(bbox.x0, max(above), bbox.x1, min(below))
    return None


class HeadingStyle:
    def __init__(self, font="Verdana", size=12.0, bold=True, border=True, size_tol=0.6):
        self.font = _font_key(font) if font else ""
        self.size, self.bold, self.border, self.size_tol = size, bold, border, size_tol

    def matches(self, line, boxes, hrules):
        if self.font and not any(self.font in _font_key(f) for f in line["fonts"]):
            return False
        if self.size and abs(line["size"] - self.size) > self.size_tol:
            return False
        if self.bold and not line["bold"]:
            return False
        if self.border and bordered_box(line["bbox"], boxes, hrules) is None:
            return False
        return True


def find_heading(doc, page_index, dest_y, style):
    """First heading-styled line at or below where the link lands.

    Lines in the same style straight after it (e.g. a heading that wraps
    inside its box) are joined on.
    """
    page = doc[page_index]
    lines = page_lines(page)
    boxes, hrules = page_shapes(page)
    start = (dest_y or 0) - 4
    after = [l for l in lines if l["bbox"].y1 >= start]

    for i, l in enumerate(after):
        if not style.matches(l, boxes, hrules):
            continue
        parts, last = [l["text"]], l
        box = bordered_box(l["bbox"], boxes, hrules) if style.border else None
        for nxt in after[i + 1:]:
            if not style.matches(nxt, boxes, hrules):
                break
            same_box = box is not None and box.contains(nxt["bbox"].irect) or (
                box is not None and nxt["bbox"].y1 <= box.y1 + 4)
            close = nxt["bbox"].y0 - last["bbox"].y1 < l["size"] * 0.8
            if (box is not None and same_box) or (box is None and close):
                parts.append(nxt["text"])
                last = nxt
            else:
                break
        return " ".join(parts)
    return None


def inspect_page(doc, page_number, style):
    page = doc[page_number - 1]
    boxes, hrules = page_shapes(page)
    print(f"Page {page_number}: {len(boxes)} boxes, {len(hrules)} horizontal rules drawn\n")
    print(f"{'HEADING?':9} {'SIZE':>5} {'BOLD':5} {'BORDER':6}  FONT / TEXT")
    for l in page_lines(page):
        border = bordered_box(l["bbox"], boxes, hrules) is not None
        flag = "  YES" if style.matches(l, boxes, hrules) else ""
        print(f"{flag:9} {l['size']:5.1f} {str(l['bold']):5} {str(border):6}  "
              f"{', '.join(l['fonts'])} | {l['text'][:60]}")


# ---------------------------------------------------------------- compare + output

def _norm(s):
    return re.sub(r"[\W_]+", " ", s or "").strip().lower()


def compare(toc_title, heading):
    if not heading:
        return "not-found"
    a, b = _norm(toc_title), _norm(heading)
    if a == b:
        return "exact"
    if a in b or b in a or difflib.SequenceMatcher(None, a, b).ratio() >= 0.8:
        return "close"
    return "different"


def extract(doc, page_spec, style):
    entries = []
    for pno in parse_pages(page_spec, doc.page_count):
        page = doc[pno]
        seen = set()
        for link in page.get_links():
            target = link.get("page", -1)
            if link["kind"] != fitz.LINK_GOTO or target < 0:
                continue
            rect = fitz.Rect(link["from"])
            text = line_text_for_link(page, rect)
            if not text:
                continue
            key = (round(rect.y0), target)
            if key in seen:
                continue
            seen.add(key)
            title, printed = split_title_and_number(text)
            to = link.get("to")
            heading = find_heading(doc, target, to.y if to is not None else None, style)
            entries.append({
                "title": title, "heading": heading, "match": compare(title, heading),
                "printed_page": printed, "target_page": target + 1,
                "toc_page": pno + 1, "y": rect.y0,
            })
    entries.sort(key=lambda e: (e["toc_page"], e["y"]))

    if not entries:  # fall back to the PDF's bookmarks
        for level, title, page, dest in doc.get_toc(simple=False):
            to = dest.get("to")
            heading = find_heading(doc, page - 1, to.y if to is not None else None, style)
            entries.append({"title": title, "heading": heading, "match": compare(title, heading),
                            "printed_page": None, "target_page": page})
        print("No TOC links found; used the PDF's bookmarks instead.")
    return entries


def to_xml(pdf_path, entries, out_path):
    root = ET.Element("toc", source=pdf_path)
    for e in entries:
        el = ET.SubElement(root, "entry", targetPage=str(e["target_page"]))
        if e["printed_page"]:
            el.set("printedPage", e["printed_page"])
        el.set("match", e["match"])
        ET.SubElement(el, "tocTitle").text = e["title"]
        ET.SubElement(el, "pageHeading").text = e["heading"] or ""
    tree = ET.ElementTree(root)
    ET.indent(tree, space="  ")
    tree.write(out_path, encoding="utf-8", xml_declaration=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("pdf")
    ap.add_argument("xml", nargs="?")
    ap.add_argument("--pages", help="TOC pages to scan, 1-based, e.g. '2' or '2-4'")
    ap.add_argument("--heading-font", default="Verdana", help="font name to match (default Verdana)")
    ap.add_argument("--heading-size", type=float, default=12.0, help="point size (default 12)")
    ap.add_argument("--not-bold", action="store_true", help="headings are not bold")
    ap.add_argument("--no-border", action="store_true", help="headings have no border")
    ap.add_argument("--inspect", type=int, metavar="PAGE",
                    help="list every line on PAGE with its font, size, bold and border, then exit")
    args = ap.parse_args()

    style = HeadingStyle(args.heading_font, args.heading_size,
                         bold=not args.not_bold, border=not args.no_border)
    doc = fitz.open(args.pdf)

    if args.inspect:
        inspect_page(doc, args.inspect, style)
        return
    if not args.xml:
        ap.error("an output XML path is required (unless using --inspect)")

    entries = extract(doc, args.pages, style)
    to_xml(args.pdf, entries, args.xml)
    missing = sum(e["match"] == "not-found" for e in entries)
    print(f"Wrote {len(entries)} entries to {args.xml}"
          + (f" ({missing} with no heading found; try --inspect on those pages)" if missing else ""))


if __name__ == "__main__":
    main()
