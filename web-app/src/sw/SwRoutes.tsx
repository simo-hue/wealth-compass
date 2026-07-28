import { Navigate, Outlet, Route, Routes } from 'react-router-dom';
import { Toaster } from '@/components/ui/toaster';
import { Toaster as Sonner } from '@/components/ui/sonner';
import { AuthProvider } from '../contexts/AuthContext';
import { SettingsProvider } from '../contexts/SettingsContext';
import { FinanceProvider } from '../contexts/FinanceContext';
import { ProtectedRoute } from '../routes/ProtectedRoute';
import MainLayout from '../components/layout/MainLayout';
import LoginPage from '../pages/Login';
import Dashboard from '../pages/Dashboard';
import CashFlowPage from '../pages/CashFlow';
import InvestmentsPage from '../pages/Investments';
import CryptoPage from '../pages/Crypto';
import CalculationsPage from '../pages/Calculations';
import SettingsPage from '../pages/Settings';

/**
 * The original web app, everything under /sw.
 *
 * It lives behind a single React.lazy boundary in App.tsx so that Supabase, the
 * toast stack, recharts and the whole authenticated dashboard stay out of the
 * marketing bundle. Two reasons that matters:
 *
 *  - The landing page states in its footer that it loads nothing from a third
 *    party. SettingsContext fetches ECB rates from api.frankfurter.app on mount,
 *    so while these providers wrapped the public routes that claim was false.
 *  - lib/supabase.ts calls createClient() at module scope, which ran on every
 *    marketing page load for a client nothing there uses.
 *
 * The provider nesting is forced by their dependencies and must not be
 * reordered: FinanceProvider reads useSettings and useAuth, SettingsProvider
 * reads useAuth.
 */
const AppShell = () => (
  <AuthProvider>
    <SettingsProvider>
      <FinanceProvider>
        <Toaster />
        <Sonner />
        <Outlet />
      </FinanceProvider>
    </SettingsProvider>
  </AuthProvider>
);

export default function SwRoutes() {
  return (
    <Routes>
      <Route element={<AppShell />}>
        <Route path="login" element={<LoginPage />} />
        <Route
          element={
            <ProtectedRoute>
              <MainLayout />
            </ProtectedRoute>
          }
        >
          <Route index element={<Navigate to="dashboard" replace />} />
          <Route path="dashboard" element={<Dashboard />} />
          <Route path="cash-flow" element={<CashFlowPage />} />
          <Route path="investments" element={<InvestmentsPage />} />
          <Route path="crypto" element={<CryptoPage />} />
          <Route path="calculations" element={<CalculationsPage />} />
          <Route path="settings" element={<SettingsPage />} />
        </Route>
      </Route>
    </Routes>
  );
}
