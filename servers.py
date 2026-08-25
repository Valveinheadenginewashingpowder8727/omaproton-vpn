#!/usr/bin/env python3
"""Extract one country's Proton VPN locations from the client's own cache.

The CLI has no server-list command (`protonvpn servers` just prints a URL), but
the GTK/CLI client caches the full logical server list — ~18k entries — at
~/.cache/Proton/VPN/serverlist.json, refreshed whenever it connects. Reading it
here is far cheaper than a 1s CLI round-trip and gives us load and tier per
server, which `protonvpn connect <NAME>` then accepts directly.

Results are collapsed to ONE ROW PER CITY, keeping that city's best server.
A flat score-sorted list is useless in practice: large countries carry
thousands of servers and whichever city is nearest monopolises the entire top
of the list, so you'd scroll past hundreds of near-identical entries before
seeing a second city. One row per city is the choice a person actually wants
to make.

Usage: servers.py <COUNTRY_CODE> [limit]
Prints a compact JSON array, best-first, or [] when the cache is missing.
"""
import json
import os
import sys

# Proton's feature bitmask, from proton.vpn.session.servers.enums.
SECURE_CORE = 1
TOR = 2
P2P = 4
STREAMING = 8

CACHE = os.path.expanduser("~/.cache/Proton/VPN/serverlist.json")


def labels(features):
    out = []
    if features & P2P:
        out.append("P2P")
    if features & TOR:
        out.append("Tor")
    if features & STREAMING:
        out.append("Streaming")
    return out


def main():
    if len(sys.argv) < 2:
        print("[]")
        return
    code = sys.argv[1].strip().upper()
    limit = int(sys.argv[2]) if len(sys.argv) > 2 else 80

    try:
        with open(CACHE, "r") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        print("[]")
        return

    # city -> best server seen so far, plus a count of that city's servers.
    cities = {}
    for s in data.get("LogicalServers") or []:
        # Status 0 means the server is under maintenance — not connectable.
        if s.get("Status") != 1:
            continue
        if (s.get("ExitCountry") or "").upper() != code:
            continue
        features = s.get("Features") or 0
        # Secure Core entries are reached via --securecore, not by name here;
        # listing them under their exit country would be misleading.
        if features & SECURE_CORE:
            continue

        # Some servers carry no city; group them together rather than dropping
        # them, so small countries don't come back empty.
        city = (s.get("City") or "").strip() or "Other"
        score = s.get("Score")
        score = score if score is not None else 9e9
        load = s.get("Load")
        load = load if load is not None else 999

        entry = cities.get(city)
        if entry is None:
            cities[city] = {
                "city": city,
                "name": s.get("Name") or "",
                "load": s.get("Load"),
                "tier": s.get("Tier"),
                "score": score,
                "tags": labels(features),
                "count": 1,
            }
            continue

        entry["count"] += 1
        # Score is Proton's own "fastest" metric (lower is better) and is what
        # the CLI sorts on; load breaks ties.
        if (score, load) < (entry["score"], entry["load"] if entry["load"] is not None else 999):
            entry.update({
                "name": s.get("Name") or "",
                "load": s.get("Load"),
                "tier": s.get("Tier"),
                "score": score,
                "tags": labels(features),
            })

    rows = sorted(cities.values(), key=lambda r: r["score"])
    print(json.dumps(rows[:limit], separators=(",", ":")))


if __name__ == "__main__":
    main()
