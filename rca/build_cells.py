#!/usr/bin/env python3
"""Assemble RCA notebook cells from one spec file, so the content is written once.

Spec format (plain text):
  ::meta name=RCA: <service> <symptom> (<YYYY-MM-DD>)
  ::meta site=app.datadoghq.com        # optional; your Datadog site host
  ::md
  <markdown; cite figures as {{key}}>
  ::fig <key> [size=xs|s|m|l|xl] [time=<ISO start>/<ISO end>]
  <widget definition JSON; "F<n> · " is prefixed to its title>

Usage:
  build_cells.py SPEC graphs                 # graph cells only, for create_datadog_notebook
  build_cells.py SPEC full NB_ID ID1,ID2,…   # all cells, figure refs linked to graph cell ids (figure order)
Writes the cells JSON to SPEC.<mode>.json and prints a summary. Exits 1 if a check fails.
"""
import json
import re
import sys

JIRA = re.compile(r"(?<!\[)(?<!browse/)\b[A-Z]{2,}-\d+\b")
BARE_PR = re.compile(r"(?<![\w/\[])#\d{2,}\b")
REF = re.compile(r"\{\{([a-z0-9_-]+)\}\}")


def parse(path):
    meta, blocks, cur = {}, [], None
    for line in open(path, encoding="utf-8").read().splitlines():
        if line.startswith("::meta "):
            k, _, v = line[7:].partition("=")
            meta[k.strip()] = v.strip()
        elif line.startswith("::md"):
            cur = {"kind": "md", "body": []}
            blocks.append(cur)
        elif line.startswith("::fig "):
            parts = line[6:].split()
            opts = dict(p.split("=", 1) for p in parts[1:])
            cur = {"kind": "fig", "key": parts[0], "opts": opts, "body": []}
            blocks.append(cur)
        elif cur is not None:
            cur["body"].append(line)
    return meta, blocks


def slug(name):
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def main():
    spec, mode = sys.argv[1], sys.argv[2]
    meta, blocks = parse(spec)
    figs = [b for b in blocks if b["kind"] == "fig"]
    num = {b["key"]: i + 1 for i, b in enumerate(figs)}
    errors = []

    if mode == "full":
        nb_id, ids = sys.argv[3], sys.argv[4].split(",")
        if len(ids) != len(figs):
            sys.exit(f"got {len(ids)} cell ids for {len(figs)} figures")
        cell_id = {b["key"]: ids[i] for i, b in enumerate(figs)}
        site = meta.get("site", "app.datadoghq.com")
        base = f"https://{site}/notebook/{nb_id}/{slug(meta['name'])}"

    cells, cited, md_text = [], set(), []
    for b in blocks:
        if b["kind"] == "fig":
            d = json.loads("\n".join(b["body"]))
            title = re.sub(r"^F\d+ · ", "", d.get("title", ""))
            d["title"] = f"F{num[b['key']]} · {title}"
            attrs = {"definition": d, "graph_size": b["opts"].get("size", "m")}
            if "time" in b["opts"]:
                start, end = b["opts"]["time"].split("/")
                attrs["time"] = {"start": start, "end": end, "live": False}
            cell = {"type": "notebook_cells", "attributes": attrs}
            if mode == "full":
                cell["id"] = cell_id[b["key"]]
            cells.append(cell)
        elif mode == "full":
            text = "\n".join(b["body"]).strip("\n")

            def link(m):
                key = m.group(1)
                if key not in num:
                    errors.append(f"unknown figure ref {{{{{key}}}}}")
                    return m.group(0)
                cited.add(key)
                return f"[F{num[key]}]({base}?cell_id={cell_id[key]})"

            text = REF.sub(link, text)
            md_text.append(text)
            cells.append({"type": "notebook_cells", "attributes": {"definition": {"type": "markdown", "text": text}}})

    if mode == "full":
        all_md = "\n".join(md_text)
        # Inline code holds market symbols like `NX.F.OPT.UFC-00001-…`, which look like Jira keys.
        no_code = re.sub(r"`[^`]*`", "", all_md)
        errors += [f"bare Jira key {k}" for k in sorted(set(JIRA.findall(no_code)))]
        errors += [f"bare PR ref {k}" for k in sorted(set(BARE_PR.findall(all_md)))]
        uncited = [k for k in num if k not in cited]
        if uncited:
            print("warning: figures never cited:", ", ".join(uncited))

    payload = json.dumps(cells, ensure_ascii=False)
    size = len(payload.encode())
    if size > 63000:
        errors.append(f"payload {size} bytes > 63KB; split with append_only")
    out = f"{spec}.{mode}.json"
    open(out, "w", encoding="utf-8").write(payload)
    for b in figs:
        print(f"F{num[b['key']]} = {b['key']}")
    print(f"{len(cells)} cells, {size} bytes -> {out}")
    if errors:
        print("FAIL:\n  " + "\n  ".join(errors))
        sys.exit(1)


if __name__ == "__main__":
    main()
