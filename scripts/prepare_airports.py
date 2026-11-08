#!/usr/bin/env python3
"""Turns the raw OpenFlights data into the compact format bundled with the app.

  mkdir raw && cd raw
  curl -O https://raw.githubusercontent.com/jpatokal/openflights/master/data/airports.dat
  curl -O https://raw.githubusercontent.com/jpatokal/openflights/master/data/routes.dat
  cd .. && python3 -I scripts/prepare_airports.py raw Resources

Keeps only airports with scheduled service and non-stop (Stops == 0) routes.
Data source and license: see THIRD_PARTY_NOTICES.md (ODbL).
"""
import csv, sys, collections
raw, out = sys.argv[1], sys.argv[2]
air = {}
with open(f"{raw}/airports.dat", encoding="utf-8") as f:
    for r in csv.reader(f):
        if len(r) < 13: continue
        iata, typ = r[4], r[12]
        if iata in ("", "\\N") or len(iata) != 3 or typ != "airport": continue
        try: lat, lon = float(r[6]), float(r[7])
        except ValueError: continue
        air[iata] = (r[1].replace("\t"," "), r[2].replace("\t"," "), r[3].replace("\t"," "), lat, lon)
routes = collections.defaultdict(set)
with open(f"{raw}/routes.dat", encoding="utf-8") as f:
    for r in csv.reader(f):
        if len(r) < 8 or r[7] != "0": continue
        s, d = r[2], r[4]
        if s in air and d in air and s != d: routes[s].add(d)
used = set(routes) | {d for v in routes.values() for d in v}
with open(f"{out}/airports.tsv", "w", encoding="utf-8") as f:
    for iata in sorted(used):
        n, c, k, la, lo = air[iata]
        f.write(f"{iata}\t{n}\t{c}\t{k}\t{la:.5f}\t{lo:.5f}\n")
with open(f"{out}/routes.txt", "w", encoding="utf-8") as f:
    for s in sorted(routes): f.write(f"{s}:{','.join(sorted(routes[s]))}\n")
print("airports", len(used), "origin airports with routes", len(routes), "pairs", sum(len(v) for v in routes.values()))
