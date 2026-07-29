import { Suspense, lazy } from "react";
import { TooltipProvider } from "@/components/ui/tooltip";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Navigate, Route, Routes } from "react-router-dom";
import NotFound from "./pages/NotFound";
import { SiteLayout } from "./site/SiteLayout";

// Marketing pages. These are the prerendered routes, so they are imported
// eagerly — they ARE the static output.
import { Home } from "./pages/Home";
import { FAQ } from "./pages/FAQ";
import { Support } from "./pages/Support";
import { OpenSource } from "./pages/OpenSource";
import { PrivacyPolicy } from "./pages/PrivacyPolicy";
import { TermsOfService } from "./pages/TermsOfService";

/**
 * The original Supabase-backed web app, behind one lazy boundary.
 *
 * Everything it needs — AuthProvider, SettingsProvider, FinanceProvider, the
 * toast stack, Supabase, recharts — is inside SwRoutes, so none of it reaches
 * the marketing bundle. Previously those providers wrapped the public routes,
 * which meant every landing-page visit instantiated a Supabase client and fired
 * an exchange-rate request at api.frankfurter.app. The site footer claims the
 * page loads nothing from a third party; this is what makes that true.
 */
const SwRoutes = lazy(() => import("./sw/SwRoutes"));

export const BASENAME = "/wealth-compass";

/**
 * The route table, separated from the router so the prerender step can drive the
 * same tree through a StaticRouter while the browser uses a BrowserRouter.
 * BrowserRouter reads `document` during render and cannot be used server-side.
 */
export const AppRoutes = () => (
  <Routes>
    <Route element={<SiteLayout />}>
      <Route path="/" element={<Home />} />
      <Route path="/faq" element={<FAQ />} />
      <Route path="/support" element={<Support />} />
      <Route path="/open-source" element={<OpenSource />} />
      <Route path="/privacy" element={<PrivacyPolicy />} />
      <Route path="/terms" element={<TermsOfService />} />

      {/* The old marketing structure. These URLs are linked from elsewhere on
          the web and from earlier App Store metadata, so they redirect rather
          than 404. /features and /founder became sections of the home page. */}
      <Route path="/features" element={<Navigate to="/#areas" replace />} />
      <Route path="/founder" element={<Navigate to="/#who" replace />} />
      <Route path="/tutorial" element={<Navigate to="/open-source" replace />} />
    </Route>

    <Route path="sw/*" element={<Suspense fallback={null}><SwRoutes /></Suspense>} />

    <Route path="*" element={<NotFound />} />
  </Routes>
);

const queryClient = new QueryClient();

const App = () => (
  <QueryClientProvider client={queryClient}>
    <TooltipProvider>
      <BrowserRouter basename={BASENAME} future={{ v7_startTransition: true, v7_relativeSplatPath: true }}>
        <AppRoutes />
      </BrowserRouter>
    </TooltipProvider>
  </QueryClientProvider>
);

export default App;
