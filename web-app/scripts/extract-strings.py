#!/usr/bin/env python3
"""Regenerate web-app/src/sim/strings.ts from the Apple app's shipped strings.

The device simulations on the marketing site show a live language picker. The
strings behind it must be the app's real translations, not translations written
for the web — otherwise the demo is claiming something the app doesn't do.

Run from the repo root:

    python3 web-app/scripts/extract-strings.py

Add a key to KEYS when a simulated screen starts showing a new string. If the
key isn't in the catalogue the script fails loudly rather than emitting an
English-only entry that would silently look like a translation gap on the site.
"""

from __future__ import annotations

import io
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SHARED = ROOT / "apple/WealthCompass/Sources/Shared"
CATALOGUE = SHARED / "Resources/Localizable.xcstrings"
RESOLVER = SHARED / "Services/TabBarLabelResolver.swift"
OUT = ROOT / "web-app/src/sim/strings.ts"

# The demo subset: four scripts, one RTL. The catalogue itself covers 35 locales.
LANGS = ["en", "it", "de", "fr", "es", "ja", "zh-Hans", "ar"]

KEYS = [
    # Harvested from the Swift views and from every t() call in web-app/src/sim.
    "%@ / unit", "%@ units", "%@%% performance", "A clear view of what you own, owe, earn, and spend.",
    "ASSETS", "Across every asset", "Add", "Add Crypto Holding", "Add Investment", "Add Transaction",
    "Add stocks, ETFs, bonds, or other positions.", "All", "Allocation by Geography",
    "Allocation by Sector", "Allocation by Type", "Asset Allocation", "Automatic income and expenses",
    "Balances derived from your activity and holdings", "Biggest Loser", "Breakdown of recorded spending",
    "Capital invested", "Cash Flow", "Cash flow", "Cash-flow chart concealed", "Category", "Clear search",
    "CoinGecko API Key", "Completed", "Cost Basis", "Crypto", "Crypto Allocation", "Crypto Value",
    "Crypto assets", "Crypto holdings", "Crypto view", "Currency", "Current Price", "Current market value",
    "Custom Categories", "Custom...", "Dashboard", "Data", "Date", "Delete", "Delete Crypto Holding?",
    "Delete Investment", "Delete Investment?", "Delete Recurring Transaction?", "Delete Transaction",
    "Delete Transaction?",
    "Due schedules are recorded automatically while the app is active and caught up the next time it opens.",
    "Due schedules catch up on open", "ECB", "EXPENSES", "Edit", "Edit Investment", "Edit Transaction",
    "Edit schedule", "Entertainment", "Erase Everything", "Everything you own, owe, earn, and spend.",
    "Exchange Rates", "Expense", "Expense Categories", "Expenses", "Expenses grouped by category",
    "Export Sync Diagnostics", "Export...", "Financial horizon", "Finish", "Finish Recurring Transaction?",
    "Finish schedule", "Finnhub API Key", "Follow positions, allocation, and performance.", "Food",
    "Force Sync iCloud", "Holdings", "Housing", "How investable assets are distributed",
    "How the portfolio is distributed", "Import Data", "Income", "Income and expenses by month",
    "Income less expenses", "Investments", "Language", "Last Updated", "Liabilities", "Local Only",
    "Market Data", "Mode", "Monthly Expenses", "Monthly Income", "NET WORTH", "Net Savings",
    "New Investment", "Next: %@", "No Investments", "No activity yet", "No crypto holdings yet",
    "No end date", "No expenses for this period", "No investments yet", "No recent cash flow",
    "No recurring transactions", "No transactions found", "No transactions match these filters", "OK",
    "Of monthly income", "Offline fallback", "One-Time", "One-Time Transaction", "Overview", "Paused",
    "Performance", "Performance hidden", "Period", "Portfolio Value", "Position", "Positions", "Privacy",
    "Privacy Mode", "Privacy, sync, currency, and market data", "Profit / Loss", "Quantity",
    "Recent Activity", "Recorded Cash", "Recurring", "Recurring Transaction", "Recurring Transactions",
    "Region & Language", "Salary", "Savings Rate", "Schedule completed", "Search", "Security", "Settings",
    "Share Sync Diagnostics", "Showing %lld of %lld", "Snapshots", "Source", "Spending analytics",
    "Status • %@ Coins", "Stocks, ETFs, and more", "Storage", "Sync Data with iCloud", "System", "TOTAL",
    "Tap a holding to edit its details", "Tap a position to edit its details",
    "The stored credential will be deleted from Keychain.", "This month", "Top Expense Categories",
    "Top Holdings", "Top Performer", "Total Assets", "Total Cash",
    "Track holdings, allocation, and performance.", "Tracked assets", "Transaction", "Transactions",
    "Transport", "Type", "Understand what comes in and where it goes.", "Updated %@", "Utilities",
    "Where recorded spending is concentrated", "Yes", "Your financial horizon", "Your latest cash flow",
    "Your latest recorded cash movements", "Your preferences", "iCloud Sync",
]

HEADER = """/**
 * GENERATED — do not edit by hand.
 * Regenerate with `python3 web-app/scripts/extract-strings.py`.
 *
 * Sources:
 *   TABS    <- apple/WealthCompass/Sources/Shared/Services/TabBarLabelResolver.swift
 *              (the short, length-capped labels the tab bar really uses)
 *   STRINGS <- apple/WealthCompass/Sources/Shared/Resources/Localizable.xcstrings
 *
 * These are the shipped translations, reproduced as-is. Where a language is
 * absent below it is absent in the app too, and `t()` falls back to English
 * exactly as TabBarLabelResolver.title(for:appLanguage:) does.
 */

export type Lang = 'en' | 'it' | 'de' | 'fr' | 'es' | 'ja' | 'zh-Hans' | 'ar';

export const LANGUAGES: { code: Lang; label: string; rtl?: boolean }[] = [
  { code: 'en', label: 'English' },
  { code: 'it', label: 'Italiano' },
  { code: 'de', label: 'Deutsch' },
  { code: 'fr', label: 'Fran\\u00e7ais' },
  { code: 'es', label: 'Espa\\u00f1ol' },
  { code: 'ja', label: '\\u65e5\\u672c\\u8a9e' },
  { code: 'zh-Hans', label: '\\u7b80\\u4f53\\u4e2d\\u6587' },
  { code: 'ar', label: '\\u0627\\u0644\\u0639\\u0631\\u0628\\u064a\\u0629', rtl: true },
];

type Table = Partial<Record<Lang, string>> & { en: string };
"""

FOOTER = """
/** Mirrors TabBarLabelResolver.title(for:appLanguage:) — value, else en, else key. */
export const t = (key: string, lang: Lang): string => STRINGS[key]?.[lang] ?? STRINGS[key]?.en ?? key;
export const tab = (key: string, lang: Lang): string => TABS[key]?.[lang] ?? TABS[key]?.en ?? key;
export const isRTL = (lang: Lang) => LANGUAGES.find((l) => l.code === lang)?.rtl === true;
"""


def main() -> int:
    catalogue = json.loads(CATALOGUE.read_text())["strings"]

    absent = [k for k in KEYS if k not in catalogue]
    if absent:
        print("Not in Localizable.xcstrings:", ", ".join(map(repr, absent)), file=sys.stderr)
        return 1

    def table(key: str) -> dict[str, str]:
        localizations = catalogue[key].get("localizations", {})
        out = {"en": key}
        for lang in LANGS:
            value = localizations.get(lang, {}).get("stringUnit", {}).get("value")
            if value:
                out[lang] = value
        return out

    resolver = RESOLVER.read_text().split("private static let translations", 1)[1]
    tabs: dict[str, dict[str, str]] = {}
    for match in re.finditer(r"\.(\w+):\s*\[(.*?)\n\s*\],", resolver, re.S):
        pairs = dict(re.findall(r'"([\w-]+)":\s*"([^"]*)"', match.group(2)))
        tabs[match.group(1)] = {lang: pairs[lang] for lang in LANGS if lang in pairs}

    dump = lambda value: json.dumps(value, ensure_ascii=False)  # noqa: E731

    out = io.StringIO()
    out.write(HEADER)
    out.write("\nexport const TABS: Record<string, Table> = {\n")
    for name, values in tabs.items():
        out.write(f"  {name}: {dump(values)},\n")
    out.write("};\n\nexport const STRINGS: Record<string, Table> = {\n")
    for key in KEYS:
        out.write(f"  {dump(key)}: {dump(table(key))},\n")
    out.write("};\n")
    out.write(FOOTER)

    OUT.write_text(out.getvalue())

    untranslated = {
        key: [lang for lang in LANGS if lang != "en" and table(key).get(lang, key) == key]
        for key in KEYS
    }
    gaps = {k: v for k, v in untranslated.items() if v}
    print(f"wrote {OUT.relative_to(ROOT)}: {len(KEYS)} strings, {len(tabs)} tabs, {len(LANGS)} languages")
    if gaps:
        print("\nUntranslated in the app (shown in English on the site too):")
        for key, langs in gaps.items():
            print(f"  {key!r}: {', '.join(langs)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
