# Deploy to GitHub Pages

The web app is published to the `gh-pages` branch of `simo-hue/wealth-compass`, which GitHub
Pages serves at <https://simo-hue.github.io/wealth-compass/>.

Deployment is **manual** — there is no CI workflow. Every deploy is a command you run.

## The sub-path is load-bearing

The site is served from `/wealth-compass/`, not from a domain root. Three settings encode that,
and they must agree or the app will 404 on its own assets:

| Setting | File | Value |
|---|---|---|
| Vite `base` | `vite.config.ts` | `/wealth-compass/` |
| Router `basename` | `src/App.tsx` | `/wealth-compass` |
| `homepage` | `package.json` | `https://simo-hue.github.io/wealth-compass/` |

Any other host (Vercel, Netlify, …) must serve the app from the same sub-path, or you must
update all three to match that host's root first.

## How to deploy

`gh-pages` is already a devDependency — no install step beyond `npm install`. Run from this
directory, not the repo root:

```bash
cd web-app
npm install       # first time only
npm run deploy    # predeploy builds, then gh-pages publishes dist/
```

`npm run deploy` builds into `dist/` and pushes that folder to the `gh-pages` branch. It targets
whatever the `origin` remote points at, not the `homepage` field.

## Verify on GitHub

1. Repository → **Settings** → **Pages**.
2. **Source** = `Deploy from a branch`.
3. **Branch** = `gh-pages` / `(root)`.
4. Visit <https://simo-hue.github.io/wealth-compass/>.

> It can take a few minutes for GitHub to serve the new build.

## Note on `gh-pages-webapp`

An older GitHub Actions workflow used to publish to a `gh-pages-webapp` branch. That workflow was
deleted in commit `ba8c852` (2026-06-22) and Pages does not serve that branch. It is stale.
