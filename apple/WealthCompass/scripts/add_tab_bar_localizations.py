#!/usr/bin/env python3
"""Add compact tab-bar localization keys to Localizable.xcstrings."""

import json
from pathlib import Path

XCSTRINGS = Path(__file__).resolve().parents[1] / "Sources/Shared/Resources/Localizable.xcstrings"
MAX_TAB_LENGTH = 10

TAB_KEYS = {
    "Dashboard, Tab Bar": "Dashboard",
    "Cash Flow, Tab Bar": "Cash Flow",
    "Investments, Tab Bar": "Investments",
    "Crypto, Tab Bar": "Crypto",
    "Settings, Tab Bar": "Settings",
}

SHORT_OVERRIDES = {
    "Dashboard, Tab Bar": {
        "ar": "لوحة",
        "ca": "Tauler",
        "de": "Dashboard",
        "fr": "Tableau",
        "he": "לוח",
        "hr": "Ploča",
        "it": "Dashboard",
        "ms": "Pemuka",
        "ru": "Панель",
        "sv": "Dashboard",
        "tr": "Panel",
        "uk": "Панель",
        "vi": "Tổng quan",
    },
    "Cash Flow, Tab Bar": {
        "ar": "التدفق",
        "ca": "Flux",
        "el": "Ταμείο",
        "es": "Caja",
        "es-419": "Flujo",
        "fi": "Kassa",
        "fr": "Flux",
        "he": "תזרים",
        "hi": "नकद",
        "hr": "Novac",
        "hu": "Forgalom",
        "it": "Cassa",
        "ms": "Tunai",
        "nb": "Strøm",
        "nl": "Cash",
        "pl": "Przepływ",
        "pt-BR": "Caixa",
        "pt-PT": "Caixa",
        "ro": "Numerar",
        "ru": "Поток",
        "sv": "Kassa",
        "th": "เงินสด",
        "tr": "Nakit",
        "uk": "Потік",
    },
    "Investments, Tab Bar": {
        "de": "Anlagen",
        "fr": "Placements",
        "it": "Invest.",
    },
    "Crypto, Tab Bar": {
        "ar": "كريبتو",
        "fr": "Crypto",
        "pt-BR": "Cripto",
        "pt-PT": "Cripto",
        "th": "คริปโต",
        "vi": "Crypto",
    },
    "Settings, Tab Bar": {
        "de": "Optionen",
        "fr": "Réglages",
        "it": "Opzioni",
    },
}


def make_entry(value: str) -> dict:
    return {"stringUnit": {"state": "translated", "value": value}}


def resolve_short(full_key: str, tab_key: str, locale: str, full_value: str) -> str:
    overrides = SHORT_OVERRIDES.get(tab_key, {})
    if locale in overrides:
        return overrides[locale]
    if len(full_value) <= MAX_TAB_LENGTH:
        return full_value
    return full_value


def main() -> None:
    with XCSTRINGS.open(encoding="utf-8") as handle:
        catalog = json.load(handle)

    strings = catalog.setdefault("strings", {})

    for tab_key, full_key in TAB_KEYS.items():
        full_entry = strings.get(full_key, {})
        full_locs = full_entry.get("localizations", {})
        tab_locs = {}

        for locale, loc in full_locs.items():
            full_value = loc.get("stringUnit", {}).get("value", full_key)
            tab_locs[locale] = make_entry(resolve_short(full_key, tab_key, locale, full_value))

        strings[tab_key] = {
            "comment": "Compact label for the iOS tab bar (max ~10 characters).",
            "localizations": tab_locs,
        }

    with XCSTRINGS.open("w", encoding="utf-8") as handle:
        json.dump(catalog, handle, ensure_ascii=False, indent=2)
        handle.write("\n")

    print("Added tab bar keys:")
    for tab_key in TAB_KEYS:
        locs = strings[tab_key]["localizations"]
        long_entries = [
            (locale, loc["stringUnit"]["value"])
            for locale, loc in locs.items()
            if len(loc["stringUnit"]["value"]) > MAX_TAB_LENGTH
        ]
        print(f"  {tab_key}: {len(locs)} locales, {len(long_entries)} still > {MAX_TAB_LENGTH}")
        for locale, value in sorted(long_entries, key=lambda item: -len(item[1])):
            print(f"    {locale}: {len(value)} chars — {value}")


if __name__ == "__main__":
    main()
