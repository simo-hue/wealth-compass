import { renderToString } from 'react-dom/server';
import { StaticRouter } from 'react-router-dom/server';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { TooltipProvider } from '@/components/ui/tooltip';
import { AppRoutes, BASENAME } from './App';

/**
 * The build-time half of the app.
 *
 * GitHub Pages serves static files only: a cold request for /wealth-compass/privacy
 * looks for a file at that path, finds none, and returns GitHub's 404 page — the SPA
 * never gets a chance to route. scripts/prerender.mjs fixes that by calling `render`
 * here once per marketing route and writing the result to disk as a real HTML file.
 *
 * This module deliberately mirrors the provider stack in App.tsx rather than importing
 * <App /> itself: App owns a BrowserRouter, which reads `document` while rendering and
 * cannot run in Node. Everything *around* the router is reproduced exactly, because the
 * browser hydrates over this markup and React compares the two trees — a provider
 * present on one side and missing on the other is a mismatch waiting to happen.
 */
export function render(route: string): string {
  // A router with a basename matches against the full path and strips the prefix
  // itself, so it has to be given the deployed URL, not the route.
  //
  // With the trailing slash, because that is the URL the browser will be sitting on when
  // it hydrates: GitHub Pages 301s /wealth-compass/faq to /wealth-compass/faq/, so the
  // client router sees the slashed form. React Router matches a `/faq` route either way,
  // but rendering the server tree at the exact client location keeps anything that reads
  // the location from disagreeing across the hydration boundary.
  const location = `${BASENAME}${route === '/' ? '/' : `${route}/`}`;

  // Per render, not per module: a QueryClient is a cache, and prerendering six routes
  // in one process should not let one page's cache leak into the next.
  const queryClient = new QueryClient();

  return renderToString(
    <QueryClientProvider client={queryClient}>
      <TooltipProvider>
        <StaticRouter basename={BASENAME} location={location} future={{ v7_relativeSplatPath: true }}>
          <AppRoutes />
        </StaticRouter>
      </TooltipProvider>
    </QueryClientProvider>,
  );
}
