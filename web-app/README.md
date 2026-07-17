# Wealth Compass (Web)

Wealth Compass is a comprehensive, privacy-focused personal finance dashboard designed to give you a
complete 360-degree view of your financial health. This directory contains the **web implementation**:
a React single-page app backed by Supabase, deployed to GitHub Pages.

It is structurally independent of the [native Apple apps](../apple/README.md) — the two share the
product and the JSON backup format, but no code. The key difference is storage: the Apple apps are
local-first, while the web app persists everything to a centralized Supabase backend.

## Tech Stack

- **Core**: React 18, TypeScript, Vite 7
- **UI**: Tailwind CSS, shadcn/ui (Radix primitives), Lucide icons, Framer Motion
- **Backend & Auth**: Supabase, with Row Level Security. Email + password sign-in only — no Magic Link / OTP.
- **Data**: TanStack React Query
- **Forms**: React Hook Form + Zod
- **Charts**: Recharts
- **Market data**: Finnhub (stocks/ETFs), CoinGecko (crypto)

## Project Layout

```text
web-app/
├── src/
│   ├── components/
│   │   ├── ui/            shadcn/ui primitives
│   │   ├── dashboard/     net worth, allocation, cash flow, tables
│   │   ├── calculations/  FIRE, compound interest, inflation, Monte Carlo
│   │   ├── layout/        app shell and marketing shell
│   │   └── previews/      landing-page demo components
│   ├── contexts/          AuthContext, FinanceContext, SettingsContext
│   ├── hooks/             useFinanceData, useChartData, use-mobile, use-toast
│   ├── lib/               supabase client, market-data api, export utils
│   ├── pages/             app + marketing pages
│   ├── routes/            ProtectedRoute
│   └── App.tsx            router, providers, basename
├── public/                static assets, PWA manifest, icons
└── index.html             Vite entry
```

The app serves two distinct surfaces from one bundle. The **marketing site** (`Home`, `Features`,
`Founder`, `FAQ`, `Tutorial`, `Support`, `PrivacyPolicy`, `TermsOfService`) is public. The
**application** (`Dashboard`, `Investments`, `Crypto`, `CashFlow`, `Calculations`, `Settings`) sits
behind `ProtectedRoute` and requires a Supabase session.

State is split across three contexts: `AuthContext` owns the Supabase session, `FinanceContext` owns
the financial data, and `SettingsContext` owns preferences including the base currency and its derived
symbol.

## Running Locally

```bash
cd web-app
npm install
npm run dev      # http://localhost:8080
```

Requires a `.env` in this directory — see [`env_example.txt`](./env_example.txt) for the variables.
Full setup, including the Supabase schema, is in **[INSTALLATION.md](./INSTALLATION.md)**
([Italiano](./INSTALLATION_IT.md)).

| Script | Does |
|---|---|
| `npm run dev` | Vite dev server on port 8080 |
| `npm run build` | Production build into `dist/` |
| `npm run lint` | ESLint over the project |
| `npm run preview` | Serve the built `dist/` locally |
| `npm run deploy` | Build, then publish `dist/` to the `gh-pages` branch |

## Deployment

Manual, via `npm run deploy` from this directory. There is no CI workflow. The site is served from
the `/wealth-compass/` **sub-path**, which is encoded in three places that must agree —
`vite.config.ts`, `src/App.tsx`, and `package.json`. See **[DEPLOYMENT.md](./DEPLOYMENT.md)** before
changing hosts.

## Notes

- `dist/` is generated and gitignored. It is rebuilt on every deploy.
- The `@` import alias resolves to `web-app/src`.
- A running history of changes is in [IMPLEMENTATION_LOG.md](./IMPLEMENTATION_LOG.md); repo-wide
  history is in the [root DOCUMENTATION.md](../DOCUMENTATION.md).
