"""GBIF client owned exclusively by the internet-facing Fetcher service."""

import hashlib
import os
import re
from difflib import get_close_matches

import requests
from fastapi import HTTPException

from fetcher_service.animals import ANIMAL_NAMES


GBIF_URL = os.getenv("GBIF_BASE_URL", "https://api.gbif.org/v1")
GBIF_USER_AGENT = os.getenv(
    "GBIF_USER_AGENT",
    "UkraineWildlifeTrainingApp/5.0",
)
GBIF_HEADERS = {"User-Agent": GBIF_USER_AGENT}


def normalize_name(name: str) -> str:
    """Normalize spaces, letter case and common apostrophe variants."""

    return " ".join(
        name.lower().replace("’", "'").replace("`", "'").split()
    )


def suggest_animal_names(name: str) -> list[str]:
    """Return up to five Ukrainian names similar to a mistyped query."""

    return get_close_matches(
        normalize_name(name),
        ANIMAL_NAMES.keys(),
        n=5,
        cutoff=0.55,
    )


def resolve_gbif_name(user_name: str) -> str:
    """Translate a known Ukrainian name or validate an unknown one."""

    cleaned_name = normalize_name(user_name)
    scientific_name = ANIMAL_NAMES.get(cleaned_name)

    if scientific_name:
        return scientific_name

    if re.search(r"[а-яіїєґ]", cleaned_name):
        raise HTTPException(
            status_code=422,
            detail={
                "message": f"Невідома назва «{user_name}».",
                "suggestions": suggest_animal_names(cleaned_name),
            },
        )

    return user_name.strip()


def _request_json(path: str, params: dict, timeout: int) -> dict:
    """Call one documented GBIF JSON endpoint."""

    try:
        response = requests.get(
            f"{GBIF_URL}{path}",
            params=params,
            headers=GBIF_HEADERS,
            timeout=timeout,
        )
        response.raise_for_status()
        return response.json()
    except (requests.RequestException, ValueError) as error:
        raise HTTPException(
            status_code=502,
            detail="GBIF зараз не відповідає. Спробуйте пізніше.",
        ) from error


def _image_details(item: dict) -> dict | None:
    """Build one display-ready image reference from a GBIF occurrence."""

    occurrence_key = item.get("key")
    for media in item.get("media", []):
        identifier = str(media.get("identifier") or "").strip()
        if not identifier.startswith(("http://", "https://")):
            continue

        if occurrence_key is not None:
            digest = hashlib.md5(
                identifier.encode("utf-8"),
                usedforsecurity=False,
            ).hexdigest()
            image_url = (
                f"{GBIF_URL}/image/cache/600x/occurrence/"
                f"{occurrence_key}/media/{digest}"
            )
        else:
            image_url = identifier

        return {
            "image_url": image_url,
            "image_source_url": (
                f"https://www.gbif.org/occurrence/{occurrence_key}"
                if occurrence_key is not None
                else identifier
            ),
            "image_creator": (
                media.get("creator")
                or item.get("recordedBy")
                or item.get("institutionCode")
            ),
            "image_license": media.get("license") or item.get("license"),
        }

    return None


def _species_image(taxon_key: int) -> dict:
    """Find a species photo in Ukraine first, then in global GBIF records."""

    searches = [
        {"taxon_key": taxon_key, "country": "UA"},
        {"taxon_key": taxon_key},
    ]
    for search_params in searches:
        try:
            result = _request_json(
                "/occurrence/search",
                {
                    **search_params,
                    "media_type": "StillImage",
                    "limit": 10,
                },
                timeout=20,
            )
        except HTTPException:
            continue

        for item in result.get("results", []):
            details = _image_details(item)
            if details:
                return details

    return {
        "image_url": None,
        "image_source_url": None,
        "image_creator": None,
        "image_license": None,
    }


def _occurrence_data(
    user_name: str,
    scientific_name: str,
    taxon_key: int,
    include_samples: bool,
    include_image: bool = False,
) -> dict:
    """Get Ukraine occurrence count and optional example records."""

    occurrence = _request_json(
        "/occurrence/search",
        {
            "taxon_key": taxon_key,
            "country": "UA",
            "limit": 5 if include_samples else 0,
        },
        timeout=20,
    )

    samples = []
    if include_samples:
        for item in occurrence.get("results", []):
            samples.append(
                {
                    "year": item.get("year"),
                    "locality": (
                        item.get("locality")
                        or item.get("stateProvince")
                    ),
                    "recorded_by": item.get("recordedBy"),
                }
            )

    result = {
        "query": user_name,
        "scientific_name": scientific_name,
        "taxon_key": taxon_key,
        "observation_count": int(occurrence.get("count", 0)),
        "sample_records": samples,
        "source_url": (
            "https://www.gbif.org/occurrence/search"
            f"?taxon_key={taxon_key}&country=UA"
        ),
    }
    if include_image:
        result.update(_species_image(taxon_key))

    return result


def get_gbif_data(
    user_name: str,
    include_samples: bool = True,
) -> dict:
    """Match one species and get its Ukraine occurrence data."""

    gbif_name = resolve_gbif_name(user_name)
    match = _request_json(
        "/species/match",
        {"name": gbif_name, "kingdom": "Animalia"},
        timeout=15,
    )

    usage = match.get("usage") if isinstance(match.get("usage"), dict) else {}
    taxon_key = match.get("usageKey") or usage.get("key")
    taxon_rank = str(
        match.get("rank") or usage.get("rank") or ""
    ).upper()

    if taxon_key is None or taxon_rank not in {"SPECIES", "SUBSPECIES"}:
        raise HTTPException(
            status_code=404,
            detail=(
                "GBIF не знайшов точний вид. Перевірте назву "
                "або введіть наукову латинську назву."
            ),
        )

    scientific_name = (
        match.get("scientificName")
        or usage.get("scientificName")
        or match.get("canonicalName")
        or gbif_name
    )
    return _occurrence_data(
        user_name,
        scientific_name,
        int(taxon_key),
        include_samples,
        include_image=not include_samples,
    )


def refresh_gbif_data(scientific_name: str, taxon_key: int) -> dict:
    """Refresh a previously matched species without matching its name again."""

    return _occurrence_data(
        scientific_name,
        scientific_name,
        taxon_key,
        include_samples=False,
        include_image=False,
    )
