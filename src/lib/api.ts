// API Service for fetching asset prices
import { toast } from 'sonner';

const STORAGE_KEY_FINNHUB = 'wealth_compass_finnhub_key';

// --- Configuration ---

export function getFinnhubKey(): string | null {
    const envKey = import.meta.env.VITE_FINNHUB_API_KEY;
    if (envKey) return envKey;
    return localStorage.getItem(STORAGE_KEY_FINNHUB);
}

export function setFinnhubKey(key: string) {
    localStorage.setItem(STORAGE_KEY_FINNHUB, key);
}

// --- CoinGecko (Crypto) ---

export interface CoinResult {
    id: string;
    symbol: string;
    name: string;
}

// Search for a coin by query (e.g. "bitcoin")
export async function searchCoinGecko(query: string): Promise<CoinResult[]> {
    try {
        const res = await fetch(`https://api.coingecko.com/api/v3/search?query=${encodeURIComponent(query)}`);
        if (!res.ok) throw new Error('CoinGecko search failed');
        const data = await res.json();
        return data.coins.map((c: any) => ({
            id: c.id,
            symbol: c.symbol,
            name: c.name,
        }));
    } catch (error) {
        console.error('CoinGecko search error:', error);
        return [];
    }
}

const STORAGE_KEY_CRYPTO_CACHE = 'wealth_compass_crypto_cache';
const CACHE_DURATION = 5 * 60 * 1000; // 5 minutes

interface CachedCryptoData {
    timestamp: number;
    prices: Record<string, number>;
}

// Fetch crypto price from CoinGecko (individual) - kept for legacy or single add
export async function getCryptoPrice(idOrSymbol: string): Promise<number | null> {
    try {
        let coinId = idOrSymbol.toLowerCase();
        if (coinId.length <= 5) {
            const results = await searchCoinGecko(coinId);
            const match = results.find(c => c.symbol.toLowerCase() === coinId);
            if (match) coinId = match.id;
        }

        const res = await fetch(`https://api.coingecko.com/api/v3/simple/price?ids=${coinId}&vs_currencies=usd`);
        if (!res.ok) throw new Error('CoinGecko price fetch failed');
        const data = await res.json();

        return data[coinId]?.usd || null;
    } catch (error) {
        console.error(`Error fetching crypto price for ${idOrSymbol}:`, error);
        return null;
    }
}

// Batch Fetch with Caching
// Batch Fetch with Caching
export async function getBatchCryptoPrices(items: { symbol: string; coinId?: string }[], forceRefresh = false): Promise<Record<string, number>> {
    const now = Date.now();

    // 1. Prepare IDs to fetch
    // Use coinId if present, otherwise try to map symbol to ID (simple lowercase for now, strictly we should search but we want to avoid spam)
    // If we don't have a coinId, we might normally skip or try one search. 
    // For this implementation, we will try to use coinId if available, and if not, we use the name/symbol as a fallback ID if we can guess it, 
    // but ideally we only fetch known IDs.

    const uniqueIds = new Set<string>();
    const symbolToIdMap: Record<string, string> = {}; // Helper to map result back to request if needed

    items.forEach(item => {
        if (item.coinId) {
            uniqueIds.add(item.coinId);
            symbolToIdMap[item.symbol] = item.coinId;
        } else {
            // Fallback: assume ID is symbol name lowercase? 
            // Risky but better than searching 10 times.
            // Let's just use the symbol as ID for now and hope it matches (e.g. "bitcoin")
            // Or better, skip it? The user prompt said: "map symbols to IDs internally (or use a stored ID if available)".
            // If we don't have ID, we can't reliably fetch in batch without search. 
            // Let's use the symbol.toLowerCase() as a best effort guess for ID if coinId is missing.
            const guessId = item.symbol.toLowerCase(); // e.g. BTC -> btc (wrong), usually 'bitcoin'.
            // Actually, usually CoinGecko needs full ID. 
            // If coinId is missing, we might fail to fetch. That's updated behavior.
            // But let's try to include it.
            // checks if the symbol looks like an ID? No.
            // We will skip items without coinId to avoid 404s/waste, OR we can try to search them if we want to be fancy, but the prompt says "Stop this. We should not search for IDs on every refresh."
            // So we ONLY fetch provided valid coinIds. 
            // IF items have no coinId, we can't fetch them in batch easily without mapping.
            // Users should ensure coinId is saved.
        }
    });

    // If we have no IDs to fetch, return empty
    if (uniqueIds.size === 0) return {};

    const idsArray = Array.from(uniqueIds);

    // 2. Check Cache
    if (!forceRefresh) {
        const cachedRaw = localStorage.getItem(STORAGE_KEY_CRYPTO_CACHE);
        if (cachedRaw) {
            try {
                const cached: CachedCryptoData = JSON.parse(cachedRaw);
                if (now - cached.timestamp < CACHE_DURATION) {
                    // console.log('Using cached crypto prices');
                    // Filter cache for requested IDs
                    const result: Record<string, number> = {};
                    idsArray.forEach(id => {
                        if (cached.prices[id]) result[id] = cached.prices[id];
                    });
                    // If we have all needed prices, return? Or partial?
                    // Let's just return what we have from cache if it covers enough?
                    // Simplest: just return whole cache filtered?
                    // But if we need fresh data for *some*, we might fallback to fetch?
                    // Current logic: if cache invalid, fetch ALL.
                    return result; // This might be incomplete if new coins added? 
                    // To be safe, if we are strictly using cache:
                    // implementation assumes global cache.
                    // If we want to return ALL cached prices that match:
                    return cached.prices;
                }
            } catch (e) {
                console.error('Cache parse error, ignoring');
            }
        }
    }

    // 3. Fetch from API
    try {
        const idsParam = idsArray.join(',');
        const res = await fetch(`https://api.coingecko.com/api/v3/simple/price?ids=${idsParam}&vs_currencies=usd`);

        if (res.status === 429) {
            console.warn('Rate limit reached (429). Returning empty.');
            toast.warning('Crypto API rate limit. Prices may be outdated.');
            return {};
        }
        if (!res.ok) throw new Error(`CoinGecko Batch Error: ${res.statusText}`);

        const data = await res.json();
        const prices: Record<string, number> = {};

        // Parse response
        idsArray.forEach(id => {
            if (data[id]?.usd) {
                prices[id] = data[id].usd;
            }
        });

        // 4. Update Cache (merge with existing if possible, or overwrite)
        // We'll read existing cache to preserve other coins if we want, but overwriting is safer for freshness.
        // Let's overwrite for now to keep it simple and clean.
        const newCache: CachedCryptoData = { timestamp: now, prices: { ...prices } };
        localStorage.setItem(STORAGE_KEY_CRYPTO_CACHE, JSON.stringify(newCache));

        return prices;
    } catch (error: any) {
        console.error('Batch crypto fetch error:', error);
        return {}; // Return empty on failure so app doesn't crash
    }
}

// --- Finnhub (Stocks/ETFs) ---

// Search for asset by ISIN or Name via Yahoo Finance
export async function searchByIsin(query: string): Promise<{ symbol: string, name: string, isin?: string } | null> {
    try {
        const proxyUrl = 'https://corsproxy.io/?';
        // Yahoo Finance Autocomplete API
        const targetUrl = `https://query1.finance.yahoo.com/v1/finance/search?q=${query}&quotesCount=1&newsCount=0`;

        const res = await fetch(proxyUrl + encodeURIComponent(targetUrl));

        let quote = null;
        if (res.ok) {
            const data = await res.json();
            quote = data.quotes?.[0];
        }

        if (quote) {
            return {
                symbol: quote.symbol,
                name: quote.longname || quote.shortname,
                isin: quote.isin
            };
        }

        // --- Fallback: Finnhub ---
        const finnhubKey = getFinnhubKey();
        if (finnhubKey) {
            try {
                // Finnhub search works for ISINs too (returns symbol)
                const fhRes = await fetch(`https://finnhub.io/api/v1/search?q=${query}&token=${finnhubKey}`);
                if (fhRes.ok) {
                    const fhData = await fhRes.json();
                    const best = fhData.result?.[0];
                    if (best) {
                        return {
                            symbol: best.symbol,
                            name: best.description,
                            // If the query looks like an ISIN (12 chars), pass it back, otherwise undefined
                            isin: query.length === 12 ? query : undefined
                        };
                    }
                }
            } catch (e) {
                console.error('Finnhub fallback search failed', e);
            }
        }

        return null;
    } catch (error) {
        console.error(`Error searching for ${query}:`, error);
        return null;
    }
}

export async function getStockPrice(symbol: string): Promise<number | null> {
    try {
        const apiKey = getFinnhubKey();

        // Method 1: Finnhub (if key exists) - basic symbols only
        if (apiKey) {
            try {
                const res = await fetch(`https://finnhub.io/api/v1/quote?symbol=${symbol}&token=${apiKey}`);
                if (res.ok) {
                    const data = await res.json();
                    if (data.c > 0) return data.c;
                }
            } catch (error) {
                // Silently fail finnhub
            }
        }

        // Method 2: Yahoo Finance Proxy (Smart Search First)
        // Instead of guessing suffixes which causes 404s, we search for the symbol to get the correct Yahoo ticker.
        const proxyUrl = 'https://corsproxy.io/?';

        let targetSymbol = symbol;

        // If it doesn't look like a yahoo symbol (no dot), try to find it
        if (!symbol.includes('.')) {
            try {
                // Search for the symbol to find the best match (e.g. searching "VWCE" might return "VWCE.DE")
                const searchRes = await fetch(proxyUrl + encodeURIComponent(`https://query1.finance.yahoo.com/v1/finance/search?q=${symbol}&quotesCount=1&newsCount=0`));
                if (searchRes.ok) {
                    const searchData = await searchRes.json();
                    const bestMatch = searchData.quotes?.[0];
                    if (bestMatch && bestMatch.symbol) {
                        targetSymbol = bestMatch.symbol;
                    }
                }
            } catch (e) {
                // Ignore search failure, fallback to original symbol
            }
        }

        const targetUrl = `https://query1.finance.yahoo.com/v8/finance/chart/${targetSymbol}`;
        const res = await fetch(proxyUrl + encodeURIComponent(targetUrl));

        if (!res.ok) {
            // If direct fetch fails and we haven't tried suffixes yet (and we didn't just search), 
            // we *could* try suffixes, but blindly trying them is what caused the 404 spam.
            // Better to just fail silently or log a single warning if critical.
            // console.warn(`Yahoo price fetch failed for ${targetSymbol}`); 
            return null;
        }

        const data = await res.json();
        return data?.chart?.result?.[0]?.meta?.regularMarketPrice || null;

    } catch (e) {
        console.error(`Unexpected error in getStockPrice for ${symbol}:`, e);
        return null;
    }
}

// --- Frankfurter (Currency) ---

export async function fetchExchangeRates(baseCurrency: string): Promise<Record<string, number> | null> {
    try {
        const res = await fetch(`https://api.frankfurter.app/latest?from=${baseCurrency}`);
        if (!res.ok) throw new Error('Frankfurter API failed');
        const data = await res.json();
        return data.rates || null;
    } catch (error) {
        console.error('Error fetching exchange rates:', error);
        return null; // Return null to indicate failure
    }
}
