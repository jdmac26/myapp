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

‘’’
#!/usr/bin/env python3
"""
Extract a PDF's clickable table of contents into XML.

For every internal link on the TOC page(s), it captures:
  - the title text on the same line as the link
  - the printed page number (if the line ends in one)
  - the actual target page the link jumps to

Usage:
    pip install pymupdf
    python toc_to_xml.py input.pdf output.xml            # scans all pages for TOC links
    python toc_to_xml.py input.pdf output.xml --pages 2-3   # only scan TOC pages 2-3 (1-based)
"""
import argparse
import difflib
import re
import xml.etree.ElementTree as ET

import pymupdf as fitz  # PyMuPDF


def parse_pages(spec, page_count):
    if not spec:
        return range(page_count)
    out = []
    for part in spec.split(","):
        a, _, b = part.partition("-")
        out.extend(range(int(a) - 1, int(b or a)))
    return out


def line_text_for_link(page, rect):
    """Return the full text of the line(s) the link rectangle sits on.

    Link boxes often cover only the page number, so we take every word whose
    vertical centre falls within the link's height, across the whole page width.
    """
    words = page.get_text("words")  # (x0, y0, x1, y1, word, block, line, wordno)
    hits = [w for w in words if rect.y0 - 1 <= (w[1] + w[3]) / 2 <= rect.y1 + 1]
    hits.sort(key=lambda w: (round(w[1]), w[0]))
    return " ".join(w[4] for w in hits)


def split_title_and_number(text):
    """'1.2 Background ........ 14' -> ('1.2 Background', '14')"""
    m = re.match(r"^(.*?)[\s.·…_-]*?(\d+|[ivxlcdm]+)\s*$", text, re.IGNORECASE)
    if m and m.group(1).strip():
        return m.group(1).strip(" ._…·-"), m.group(2)
    return text.strip(), None


def _is_bold(span):
    return bool(span["flags"] & 16) or "bold" in span["font"].lower()


def page_lines(page):
    """Lines on a page with their position, size and boldness."""
    lines = []
    for block in page.get_text("dict")["blocks"]:
        for line in block.get("lines", []):
            spans = [s for s in line["spans"] if s["text"].strip()]
            if not spans:
                continue
            lines.append({
                "text": " ".join(s["text"].strip() for s in spans),
                "x0": line["bbox"][0],
                "y0": line["bbox"][1],
                "y1": line["bbox"][3],
                "size": max(s["size"] for s in spans),
                "bold": all(_is_bold(s) for s in spans),
                "font": spans[0]["font"],
            })
    lines.sort(key=lambda l: (round(l["y0"]), l["x0"]))
    return lines


def body_font_size(lines):
    """Most common font size on the page, weighted by characters."""
    counts = {}
    for l in lines:
        counts[round(l["size"], 1)] = counts.get(round(l["size"], 1), 0) + len(l["text"])
    return max(counts, key=counts.get) if counts else 0


def find_heading(doc, page_index, dest_y=None, window=250):
    """Find the heading at (or just below) where a link lands.

    A heading is the first line after the landing point that is bigger than
    the page's body text, or bold. Following lines in the same style are
    joined, so headings that wrap onto two lines come out whole.
    """
    page = doc[page_index]
    lines = page_lines(page)
    if not lines:
        return None
    body = body_font_size(lines)
    start = (dest_y or 0) - 2
    after = [l for l in lines if l["y0"] >= start and l["y0"] <= start + window]

    def looks_like_heading(l):
        return l["size"] >= body * 1.15 or (l["bold"] and l["size"] >= body)

    for i, l in enumerate(after):
        if not looks_like_heading(l):
            continue
        parts, last = [l["text"]], l
        for nxt in after[i + 1:]:
            same_style = abs(nxt["size"] - l["size"]) < 0.5 and nxt["font"] == l["font"]
            close = nxt["y0"] - last["y1"] < l["size"] * 0.8
            if same_style and close:
                parts.append(nxt["text"])
                last = nxt
            else:
                break
        return " ".join(" ".join(parts).split())

    # No styled heading found: fall back to the first line of normal-size text
    for l in after:
        if l["size"] >= body:
            return l["text"]
    return None


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


def extract(pdf_path, page_spec=None):
    doc = fitz.open(pdf_path)
    entries = []
    for pno in parse_pages(page_spec, doc.page_count):
        page = doc[pno]
        seen = set()
        for link in page.get_links():
            if link["kind"] != fitz.LINK_GOTO and link.get("page", -1) < 0:
                continue  # skip external/URL links
            target = link.get("page", -1)
            if target < 0:
                continue
            rect = fitz.Rect(link["from"])
            text = line_text_for_link(page, rect)
            if not text:
                continue
            key = (round(rect.y0), target)
            if key in seen:  # title and number are sometimes two separate links
                continue
            seen.add(key)
            title, printed = split_title_and_number(text)
            to = link.get("to")
            dest_y = to.y if to is not None else None
            heading = find_heading(doc, target, dest_y)
            entries.append({
                "title": title,
                "heading": heading,
                "match": compare(title, heading),
                "printed_page": printed,
                "target_page": target + 1,  # 1-based
                "toc_page": pno + 1,
                "y": rect.y0,
            })
    entries.sort(key=lambda e: (e["toc_page"], e["y"]))
    return doc, entries


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
    ap.add_argument("xml")
    ap.add_argument("--pages", help="TOC pages to scan, 1-based, e.g. '2' or '2-4'")
    args = ap.parse_args()

    doc, entries = extract(args.pdf, args.pages)
    if not entries:
        # Fallback: many PDFs also store the TOC as bookmarks (the outline)
        for level, title, page, dest in doc.get_toc(simple=False):
            to = dest.get("to")
            heading = find_heading(doc, page - 1, to.y if to is not None else None)
            entries.append({"title": title, "heading": heading,
                            "match": compare(title, heading), "printed_page": None,
                            "target_page": page, "toc_page": 0, "y": 0})
        print("No TOC links found; used the PDF's bookmarks instead.")
    to_xml(args.pdf, entries, args.xml)
    print(f"Wrote {len(entries)} entries to {args.xml}")


if __name__ == "__main__":
    main()
‘’’
