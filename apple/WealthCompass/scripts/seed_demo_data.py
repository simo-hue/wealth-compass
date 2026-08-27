#!/usr/bin/env python3
"""Fill a booted simulator with demo data for App Store screenshots.

    python3 scripts/seed_demo_data.py <simulator-udid>
    python3 scripts/seed_demo_data.py <simulator-udid> --json-only out.json

Writes six months of transactions, four investments, two crypto holdings, one liability and
eight months of net-worth snapshots straight into the app's JSON store, then you relaunch the
app. Simulator only -- it never touches the Mac app's container.

Three things here are load-bearing and easy to get wrong again:

* Months are stepped by calendar month, not by 31 days. Subtracting 62 days from 1 August
  lands on 31 May, which silently drops June and double-books May in the six-month bar chart.
* The tickers below are REAL (VWCE, ASML, NESN, AGGH), so the app resolves them against Yahoo
  on the first foreground and overwrites the seeded `currentValue`. Investments jumped
  13.484,79 -> 17.706,11 EUR the first time this was run. That is the app behaving correctly, but
  it means the figures are NOT reproducible run to run: capture every screenshot in one pass so
  all the pages agree with each other, and re-check that the dashboard's net worth still equals
  Total Cash + Investments + Crypto - Liabilities before you ship the set.

* The snapshot ramp has to END on the value the app itself computes on launch
  (all-time income - expenses, plus investments and crypto, minus liabilities). Otherwise the
  app appends its own snapshot far below the seeded curve and the hero chart opens on a
  cliff -- it read -24,7% for 1W before this was pinned.
"""
import json, uuid, datetime as dt, sys, subprocess, os

args = [a for a in sys.argv[1:] if not a.startswith("--")]
if not args:
    sys.exit("usage: seed_demo_data.py <simulator-udid> [--json-only <path>]")
UDID = args[0]
JSON_ONLY = "--json-only" in sys.argv
OUT = args[1] if JSON_ONLY and len(args) > 1 else None

TODAY = dt.datetime(2026, 8, 27, 10, 0, 0)
def iso(d): return d.strftime("%Y-%m-%dT%H:%M:%S.000Z")
def uid(): return str(uuid.uuid4()).upper()

tx = []
def add(kind, amount, category, desc, when):
    tx.append({"id": uid(), "type": kind, "amount": round(amount, 2), "category": category,
               "description": desc, "currency": "EUR", "date": iso(when),
               "createdAt": iso(when), "updatedAt": iso(when)})

# Six months of activity, so the 6M bars, the Sankey and Recent Activity all have something to say.
plan = [
    ("Housing",       1150.00, "Rent"),
    ("Food",           420.00, "Groceries"),
    ("Transport",      118.50, "Season ticket"),
    ("Utilities",      142.30, "Electricity and water"),
    ("Fuel",            96.40, "Fuel"),
    ("Entertainment",  135.90, "Cinema and streaming"),
    ("Shopping",       210.75, "Clothing"),
    ("Health",          88.00, "Pharmacy"),
]
def month_start(back):
    y, mo = TODAY.year, TODAY.month - back
    while mo < 1:
        mo += 12; y -= 1
    return dt.datetime(y, mo, 1, 10, 0, 0)

for m in range(6, 0, -1):
    # Step whole months, not 31-day jumps: subtracting 62 days from 1 Aug lands on 31 May, which
    # silently dropped June and double-booked May in the six-month bar chart.
    base = month_start(m - 1)
    add("income", 4200.00, "Salary", "Monthly salary", base.replace(day=27 if m > 1 else 25))
    if m % 2 == 0:
        add("income", 640.00, "Freelance", "Design retainer", base.replace(day=14))
    for i, (cat, amt, desc) in enumerate(plan):
        drift = 1 + ((m * 7 + i * 13) % 11 - 5) / 100.0   # ±5%, deterministic
        add("expense", amt * drift, cat, desc, base.replace(day=min(2 + i * 3, 28)))

investments = [
    ("etf",   "VWCE", "Vanguard FTSE All-World",  42.0, 108.40, 118.62, "Global", "Diversified", "IE00BK5BQT80"),
    ("stock", "ASML", "ASML Holding",              6.0, 615.20, 682.90, "Europe", "Technology", "NL0010273215"),
    ("stock", "NESN", "Nestle",                   18.0,  92.10,  88.45, "Europe", "Consumer Staples", "CH0038863350"),
    ("etf",   "AGGH", "iShares Global Aggregate", 55.0,  49.80,  51.15, "Global", "Fixed Income", "IE00BDBRDM35"),
]
inv = []
for t, sym, name, qty, cost, price, geo, sector, isin in investments:
    inv.append({"id": uid(), "type": t, "symbol": sym, "name": name, "quantity": qty,
                "costBasis": round(cost * qty, 2), "currentValue": round(price * qty, 2),
                "currentPrice": price, "currency": "EUR", "geography": geo, "sector": sector,
                "isin": isin, "fees": 1.5,
                "createdAt": iso(TODAY - dt.timedelta(days=300)), "updatedAt": iso(TODAY)})

crypto = []
for sym, name, qty, avg, price, coin in [("BTC", "Bitcoin", 0.062, 51200.0, 58940.0, "bitcoin"),
                                          ("ETH", "Ethereum", 1.35, 2380.0, 2712.0, "ethereum")]:
    crypto.append({"id": uid(), "symbol": sym, "name": name, "quantity": qty, "avgBuyPrice": avg,
                   "currentPrice": price, "currency": "EUR", "fees": 2.0, "coinId": coin,
                   "createdAt": iso(TODAY - dt.timedelta(days=260)), "updatedAt": iso(TODAY)})

liabilities = [{"id": uid(), "name": "Car loan", "currentBalance": 8450.00, "currency": "EUR",
                "createdAt": iso(TODAY - dt.timedelta(days=400)), "updatedAt": iso(TODAY)}]

inv_total    = sum(i["currentValue"] for i in inv)
crypto_total = sum(c["quantity"] * c["currentPrice"] for c in crypto)
liab_total   = sum(l["currentBalance"] for l in liabilities)

# Net-worth history: a rising line with a realistic dip, ending on today's real figures.
snaps = []
# Must equal what the app itself computes on launch, or its own fresh snapshot lands far below
# the seeded curve and the hero chart opens on a cliff (it read -24,7% for 1W before this).
# FinanceStore derives liquidity as all-time income minus all-time expenses.
liq_end = round(sum(t["amount"] for t in tx if t["type"] == "income")
                - sum(t["amount"] for t in tx if t["type"] == "expense"), 2)
STEPS = 80          # every 3 days for ~8 months, so 1W and 1M draw a line too, not one dot
for k in range(STEPS, -1, -1):
    when  = TODAY - dt.timedelta(days=k * 3)
    ramp  = (STEPS - k) / float(STEPS)
    wobble = [0, .004, -.006, .002, -.003, .007, -.002, .005, -.004, .003, .001, -.005][k % 12]
    liq   = round(liq_end * (0.34 + 0.66 * ramp), 2)
    iv    = round(inv_total    * (0.72 + 0.28 * ramp) * (1 + wobble), 2)
    cv    = round(crypto_total * (0.61 + 0.39 * ramp) * (1 + wobble * 2), 2)
    lb    = round(liab_total + k * 27, 2)
    assets = round(liq + iv + cv, 2)
    snaps.append({"id": uid(), "date": iso(when), "totalAssets": assets, "totalLiabilities": lb,
                  "netWorth": round(assets - lb, 2), "liquidity": liq, "investments": iv,
                  "crypto": cv, "currency": "EUR", "createdAt": iso(when), "updatedAt": iso(when)})

data = {"transactions": sorted(tx, key=lambda t: t["date"]), "investments": inv, "crypto": crypto,
        "liabilities": liabilities, "recurringTransactions": [], "snapshots": snaps}
print(f"transactions {len(tx)} | investments {inv_total:,.2f} EUR | crypto {crypto_total:,.2f} EUR")
print(f"liabilities {liab_total:,.2f} | net worth {snaps[-1]['netWorth']:,.2f} EUR")

if JSON_ONLY:
    json.dump(data, open(OUT, "w"), indent=2)
    print("wrote", OUT)
else:
    container = subprocess.check_output(
        ["xcrun", "simctl", "get_app_container", UDID, "com.wealthcompass.mobile", "data"]
    ).decode().strip()
    target = os.path.join(container, "Library", "Application Support",
                          "Wealth Compass Tracker", "wealth-compass-local-data.json")
    os.makedirs(os.path.dirname(target), exist_ok=True)
    subprocess.run(["xcrun", "simctl", "terminate", UDID, "com.wealthcompass.mobile"],
                   stderr=subprocess.DEVNULL)
    json.dump(data, open(target, "w"), indent=2)
    print("seeded", target)
    print("now: xcrun simctl launch", UDID, "com.wealthcompass.mobile")
