/**
 * Outbound links, in one place so the App Store campaign tokens stay consistent.
 *
 * `ct` is the App Analytics campaign token and differs per placement, so App
 * Store Connect → App Analytics → Sources can tell you which part of the page
 * actually drove a download. `pt` is your Provider ID and has to come from App
 * Store Connect — until PROVIDER_TOKEN is filled in, the links still work and
 * still attribute at the Web Referrers level, they just can't break down by
 * placement. See TO_SIMO_DO.md.
 */

const APP_ID = '6777399748';

/** Fill in from App Store Connect → Payments and Financial Reports → Provider ID. */
const PROVIDER_TOKEN: string | null = null;

export type Placement = 'site-hero' | 'site-mac' | 'site-footer' | 'site-cta' | 'site-nav';

export function appStore(placement: Placement): string {
  const base = `https://apps.apple.com/app/wealth-compass-tracker/id${APP_ID}`;
  const params = new URLSearchParams({ ct: placement, mt: '8' });
  if (PROVIDER_TOKEN) params.set('pt', PROVIDER_TOKEN);
  return `${base}?${params.toString()}`;
}

export const REPO = 'https://github.com/simo-hue/wealth-compass';
export const ISSUES = `${REPO}/issues`;
export const LICENSE = `${REPO}/blob/main/LICENSE`;
export const SUPPORT_EMAIL = 'mattioli.simone.10@gmail.com';
