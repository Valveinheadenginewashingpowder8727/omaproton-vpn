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

Usage: servers.py <COUNTRY_CODE> [limit]   one country's cities, best-first
       servers.py --cities                  every city worldwide, with lat/long
       servers.py --locate <SERVER_NAME>    one server's city and coordinates
Prints compact JSON, or [] / {} when the cache is missing.
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


def read_cache():
    try:
        with open(CACHE, "r") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return None


def usable(s):
    """Connectable, and not Secure Core (those are reached via --securecore)."""
    return s.get("Status") == 1 and not ((s.get("Features") or 0) & SECURE_CORE)


def all_cities(data):
    """Every city worldwide: one entry per (country, city) with its coordinates
    and best server. Feeds the panel's mini-map; ~200 rows for ~18k servers."""
    out = {}
    for s in data.get("LogicalServers") or []:
        if not usable(s):
            continue
        loc = s.get("Location") or {}
        lat, lon = loc.get("Lat"), loc.get("Long")
        if lat is None or lon is None:
            continue
        code = (s.get("ExitCountry") or "").upper()
        city = (s.get("City") or "").strip()
        if code == "" or city == "":
            continue
        score = s.get("Score")
        score = score if score is not None else 9e9
        key = (code, city)
        entry = out.get(key)
        if entry is None or score < entry["score"]:
            out[key] = {
                "code": code,
                "city": city,
                "lat": round(float(lat), 3),
                "lon": round(float(lon), 3),
                "name": s.get("Name") or "",
                "load": s.get("Load"),
                "tier": s.get("Tier"),
                "score": score,
                "count": (entry["count"] + 1) if entry else 1,
            }
        else:
            entry["count"] += 1
    rows = sorted(out.values(), key=lambda r: (r["code"], r["city"]))
    for r in rows:
        del r["score"]
    return rows


def locate(data, name):
    """Where one server is. Used to light up the connected city on the map."""
    want = name.strip().upper()
    for s in data.get("LogicalServers") or []:
        if (s.get("Name") or "").upper() != want:
            continue
        loc = s.get("Location") or {}
        return {
            "name": s.get("Name") or "",
            "code": (s.get("ExitCountry") or "").upper(),
            "city": (s.get("City") or "").strip(),
            "lat": loc.get("Lat"),
            "lon": loc.get("Long"),
        }
    return {}


def main():
    if len(sys.argv) < 2:
        print("[]")
        return
    data = read_cache()
    if sys.argv[1] == "--cities":
        print(json.dumps(all_cities(data) if data else [], separators=(",", ":")))
        return
    if sys.argv[1] == "--locate":
        name = sys.argv[2] if len(sys.argv) > 2 else ""
        print(json.dumps(locate(data, name) if (data and name) else {}, separators=(",", ":")))
        return
    if data is None:
        print("[]")
        return
    code = sys.argv[1].strip().upper()
    limit = int(sys.argv[2]) if len(sys.argv) > 2 else 80

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
