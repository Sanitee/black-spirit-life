"""Dated, source-labelled catalog additions, never fishing-zone assignments.

These public reference facts are separate from FishyStuff's map tables. The
official English PC Asia patch notes confirm regional habitat, not cast points
or polygons. The module performs no I/O and never reads personal journal data.
"""

from __future__ import annotations

from copy import deepcopy
from typing import Any


REVIEWED_ON = "2026-08-31"
INNER_PATCH = "https://blackdesert.pearlabyss.com/Asia/en-US/News/Notice/Detail?_boardNo=19693"
OUTER_PATCH = "https://blackdesert.pearlabyss.com/Asia/en-us/News/Notice/Detail?_boardNo=8017"
LAKE_PATCH = "https://blackdesert.pearlabyss.com/Asia/News/Notice/Detail?_boardNo=13108"
GUIDE_URL = "https://bdocodex.com/us/encyclopedia/"
SUMMARY_URL = "https://fishystuff.fish/api/v1/zone_loot_summary?lang=en&locale=en-US"
SOURCE_DISAGREEMENTS = (
    (821017, "Mantis Shrimp", "155,206,230", "Peyon Sea - Depth 3", "https://fishystuff.fish/dex/mantis-shrimp/"),
    (821008, "Salp", "0,194,96", "Valencia Sea - Depth 2", "https://fishystuff.fish/dex/salp/"),
    (821008, "Salp", "0,230,113", "Valencia Sea - Depth 3", "https://fishystuff.fish/dex/salp/"),
)


def _source(item_id: int, *, patch: str | None = None,
            published_on: str | None = None) -> dict[str, Any]:
    return {
        "kind": "reviewed-catalog-supplement",
        "itemUrl": f"https://bdocodex.com/us/item/{item_id}/",
        "officialUrl": patch,
        "publishedOn": published_on,
        "reviewedOn": REVIEWED_ON,
        "officialService": "PC Asia (TH/SEA), English" if patch else None,
        "scope": "Item identity, grade and capture method; regional habitat only where officially stated.",
        "exactBoundaryVerified": False,
    }


CATALOG_ADDITIONS = (
    {
        "item_id": 8431, "name": "Balenos Mullet", "grade": "General",
        "vendor_price": 29_000, "catch_methods": ["rod"],
        "is_prize": False, "is_dried": False,
        "icon_item_id": 8236, "icon_file": "00008236.webp",
        "icon_image": "/images/items/00008236.webp",
        "location_note": "Balenos waterfall freshwater/sea confluence (BDO Codex item description). This normal-fishing item is outside the Fish Guide roster. Its exact current fishing-water boundary and table assignment are not verified; no coordinate or map table is inferred.",
        "water_type": "freshwater-saltwater-confluence",
        "source": {**_source(8431), "itemUrl": "https://bdocodex.com/us/item/8431/?sl=1",
                   "additionalItemUrls": ["https://bdocodex.com/sp/item/8431/?sl=1"],
                   "catalogScope": "Non-Fish-Guide normal-fishing item; current item description, not current exact-map verification"},
    },
    {
        "item_id": 821373, "name": "Edania Gar", "grade": "Prize",
        "vendor_price": 216_770_000, "catch_methods": ["rod"],
        "is_prize": True, "is_dried": False,
        "icon_item_id": 821373, "icon_file": "00821373.webp",
        "icon_image": "/images/items/00821373.webp",
        "location_note": "Inner Edania freshwater (official PC patch, 13 Aug 2026). Exact fishing-water boundaries and cast points are not verified; this regional fact does not assign a map table.",
        "water_type": "freshwater",
        "source": _source(821373, patch=INNER_PATCH, published_on="2026-08-13"),
    },
    {
        "item_id": 821374, "name": "Cano Toadfish", "grade": "Prize",
        "vendor_price": 170_300_000, "catch_methods": ["rod"],
        "is_prize": True, "is_dried": False,
        "icon_item_id": 821374, "icon_file": "00821374.webp",
        "icon_image": "/images/items/00821374.webp",
        "location_note": "Inner Edania saltwater (official PC patch, 13 Aug 2026). Exact fishing-water boundaries and cast points are not verified; this regional fact does not assign a map table.",
        "water_type": "saltwater",
        "source": _source(821374, patch=INNER_PATCH, published_on="2026-08-13"),
    },
)

EXISTING_NOTES = {
    8307: {
        "location_note": "Mako Shark is a Rare fish whose current BDO Codex item description lists normal and harpoon fishing. Its exact current fishing-water locations are not verified here. It is distinct from Prize-grade Blue Shark (8477), despite shared artwork.",
        "methods": ["rod", "harpoon"],
        "source": {**_source(8307), "itemUrl": "https://bdocodex.com/us/item/8307/?sl=1",
                   "additionalOfficialUrls": ["https://www.sa.playblackdesert.com/es-MX/News/Notice/Detail?groupContentNo=5410"],
                   "officialContext": "PC SA, 7 Nov 2024: harpoon availability in certain unspecified areas; current normal/harpoon labels from Codex item description."},
    },
    821027: {
        "location_note": "Black Halibut is a Prize Catch obtained by normal fishing (BDO Codex). Its exact current fishing-water location is not independently verified; conflicting community location comments are not treated as a map assignment.",
        "source": _source(821027),
    },
    821294: {
        "location_note": "Edania freshwater (official PC patch, 21 Aug 2025); certain Edania lakes received a catch-rate adjustment on 16 Apr 2026. Exact fishing-water boundaries and cast points are not verified; no map table is inferred.",
        "source": {**_source(821294, patch=OUTER_PATCH, published_on="2025-08-21"),
                   "additionalOfficialUrls": [LAKE_PATCH]},
    },
    821295: {
        "location_note": "Edania saltwater (official PC patch, 21 Aug 2025). Exact fishing-water boundaries and cast points are not verified; this regional fact does not assign a map table.",
        "source": _source(821295, patch=OUTER_PATCH, published_on="2025-08-21"),
    },
}


def apply_catalog_supplement(
    fish_by_id: dict[int, dict[str, Any]],
    fish: list[dict[str, Any]],
    zones: list[dict[str, Any]],
) -> dict[str, Any]:
    """Add missing identities and report coverage without inventing memberships.

Existing source values win over this dated supplement. Conflicts are returned
for review rather than silently rewriting newer source prices/grades/methods.
Repeated calls are idempotent. ``zones`` receives warning metadata only; no
membership, rate, geometry or recommendation-eligibility field is changed.
    """
    normalized = {row["itemId"]: row for row in fish}
    conflicts: list[dict[str, Any]] = []
    added_ids: list[int] = []
    for addition in CATALOG_ADDITIONS:
        item_id = addition["item_id"]
        if item_id not in fish_by_id:
            fish_by_id[item_id] = deepcopy(addition)
            added_ids.append(item_id)
        else:
            raw = fish_by_id[item_id]
            for field in ("name", "grade", "vendor_price", "catch_methods"):
                if raw.get(field) not in (None, [], "") and raw[field] != addition[field]:
                    conflicts.append({"itemId": item_id, "field": field,
                                      "sourceValue": deepcopy(raw[field]),
                                      "supplementValue": deepcopy(addition[field]),
                                      "supplementSource": deepcopy(addition["source"])})
            for field, value in addition.items():
                if raw.get(field) in (None, [], ""):
                    raw[field] = deepcopy(value)
        raw = fish_by_id[item_id]
        if item_id not in normalized:
            row = {
                "itemId": item_id, "iconItemId": raw.get("icon_item_id", item_id),
                "name": raw["name"], "grade": raw["grade"],
                "price": raw["vendor_price"], "methods": list(raw["catch_methods"]),
                "iconUrl": f"/icon/{item_id}.webp", "assignmentMethods": [],
            }
            fish.append(row)
            normalized[item_id] = row
        normalized[item_id]["locationNote"] = addition["location_note"]
        normalized[item_id]["source"] = deepcopy(addition["source"])
        normalized[item_id]["waterType"] = addition["water_type"]
        if not normalized[item_id].get("methods"):
            normalized[item_id]["methods"] = list(raw["catch_methods"])

    named_locations: dict[int, list[str]] = {}
    for zone in zones:
        if zone.get("active") is False or zone.get("zoneRole", "named-table") != "named-table":
            continue
        for member in zone.get("items", []):
            if isinstance(member, dict) and isinstance(member.get("itemId"), int):
                named_locations.setdefault(member["itemId"], []).append(str(zone.get("name") or zone.get("rgbKey")))

    for item_id, note in EXISTING_NOTES.items():
        raw = fish_by_id.get(item_id)
        row = normalized.get(item_id)
        if raw is None or row is None:
            continue
        # Codex item descriptions independently confirm these methods. Keep
        # nonempty upstream method declarations intact, even if they conflict.
        if not raw.get("catch_methods"):
            raw["catch_methods"] = list(note.get("methods", ["rod"]))
        if not row.get("methods"):
            row["methods"] = list(raw["catch_methods"])
        locations = sorted(set(named_locations.get(item_id, [])))
        location_note = note["location_note"]
        if locations:
            location_note = "Current FishyStuff source-table membership: " + ", ".join(locations) + ". " + location_note
        raw["location_note"] = location_note
        raw["supplement_source"] = deepcopy(note["source"])
        row["locationNote"] = location_note
        row["source"] = deepcopy(note["source"])

    # A dated cross-source disagreement is not an extra loot-table member.
    # Re-evaluate it on every rebuild so a later upstream correction clears it.
    for row in fish:
        row.pop("sourceConflictNotes", None)
        if row.get("locationNoteKind") == "source-conflict":
            row.pop("locationNote", None)
            row.pop("locationNoteKind", None)
    for zone in zones:
        remaining = [note for note in zone.get("accuracyNotes", [])
                     if not isinstance(note, dict) or note.get("kind") != "dex-summary-disagreement"]
        if remaining:
            zone["accuracyNotes"] = remaining
        else:
            zone.pop("accuracyNotes", None)
    source_conflicts = []
    for item_id, name, rgb, zone_name, dex_url in SOURCE_DISAGREEMENTS:
        zone = next((zone for zone in zones if zone.get("rgbKey") == rgb and zone.get("active") is not False), None)
        if zone is None or any(member.get("itemId") == item_id and member.get("method", "rod") == "rod"
                               for member in zone.get("items", []) if isinstance(member, dict)):
            continue
        conflict = {
            "kind": "dex-summary-disagreement", "itemId": item_id, "name": name,
            "rgbKey": rgb, "zoneName": zone_name, "reviewedOn": REVIEWED_ON,
            "dexUrl": dex_url, "summaryUrl": SUMMARY_URL,
            "note": f"The FishyStuff Dex lists {name} in {zone_name}, but the currently loaded source table does not. The sources disagree; exact membership is not resolved and no row or rate has been invented.",
        }
        source_conflicts.append(conflict)
        zone.setdefault("accuracyNotes", []).append(deepcopy(conflict))
        if item_id in normalized:
            normalized[item_id].setdefault("sourceConflictNotes", []).append(deepcopy(conflict))
            if not normalized[item_id].get("locationNote"):
                normalized[item_id]["locationNote"] = f"Location sources disagree for {name}. Some Dex locations are absent from the current source table; no missing membership or rate has been inferred."
                normalized[item_id]["locationNoteKind"] = "source-conflict"
    named_assignments = set(named_locations)
    unmapped = []
    for row in fish:
        if row["itemId"] in named_assignments:
            continue
        mapping_status = "no-named-table-assignment"
        if row.get("methods") == ["hotspot"]:
            mapping_status = "hotspot-spawn-layer-not-implemented"
            row["locationNote"] = "The source catalog classifies this species as hotspot fishing, not an ordinary fixed fishing-table assignment. The hotspot spawn layer is not implemented here; no permanent location, boundary or spawn time is inferred."
            row["source"] = {
                "kind": "source-catalog-hotspot-classification",
                "catalogUrl": "https://fishystuff.fish/api/v1/fish?lang=en",
                "explanationUrl": "https://fishystuff.fish/glossary/",
                "reviewedOn": REVIEWED_ON,
                "scope": "Hotspot acquisition classification only; no spawn boundaries imported.",
            }
        unmapped.append({
            "itemId": row["itemId"], "name": row["name"], "grade": row.get("grade"),
            "methods": list(row.get("methods", [])),
            "mappingStatus": mapping_status,
            "locationNote": row.get("locationNote") or "No current named fishing-table assignment is available. This does not mean the fish cannot be caught; an exact location is not verified here.",
            "source": deepcopy(row.get("source")),
        })
    fish.sort(key=lambda row: (row["name"].casefold(), row["itemId"]))
    unmapped.sort(key=lambda row: (row["grade"] != "Prize", row["name"].casefold(), row["itemId"]))
    return {
        "catalogReviewedOn": REVIEWED_ON,
        "scope": "Compared with the 302-entry BDO Codex US Fish Guide retrieved 31 Aug 2026 (104 green, 46 blue, 86 yellow, 66 red), plus separately documented non-guide normal-fishing Balenos Mullet (303 catalog species after supplements). This checks catalog identities, grades and base values, not current availability of all event/special items, exact water boundaries, or catch probabilities. Regional additions use official English PC Asia patch notes, not direct NAEU patch confirmation.",
        "catalogSourceUrl": GUIDE_URL,
        "reviewedGuideCount": 302,
        "supplementAddedItemIds": added_ids,
        "supplementConflicts": conflicts,
        "sourceConflicts": source_conflicts,
        "unmappedFish": unmapped,
    }
