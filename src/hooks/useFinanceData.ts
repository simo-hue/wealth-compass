import { useState, useEffect, useCallback } from 'react';
import type {
  FinancialData,
  IncomeEntry,
  ExpenseEntry,
  Investment,
  CryptoHolding,
  Liability,
  LiquidityAccount,
  NetWorthSnapshot,
  TimeRange,
  ChartDataPoint,
  Transaction,
} from '@/types/finance';
import { subMonths, subYears, parseISO, isAfter, format } from 'date-fns';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from 'sonner';

const STORAGE_KEY = 'finance_dashboard_data';

const getInitialData = (): FinancialData => ({
  income: [],
  expenses: [],
  investments: [],
  crypto: [],
  liabilities: [],
  liquidity: [],
  transactions: [],
  snapshots: [],
});

const generateId = () => crypto.randomUUID();

export function useFinanceData() {
  const { user } = useAuth();
  const [data, setData] = useState<FinancialData>(getInitialData);
  const [isLoaded, setIsLoaded] = useState(false);

  // FETCH DATA
  const fetchData = useCallback(async () => {
    if (!user) {
      const stored = localStorage.getItem(STORAGE_KEY);
      if (stored) {
        try {
          setData(JSON.parse(stored));
        } catch (e) { console.error(e); }
      }
      setIsLoaded(true);
      return;
    }

    try {
      const [
        { data: assets },
        { data: liabilities },
        { data: liquidity }, // Keeping for now if user wants manual accounts visible, but logic changes
        { data: snapshots },
        { data: transactions }
      ] = await Promise.all([
        supabase.from('assets').select('*'),
        supabase.from('liabilities').select('*'),
        supabase.from('liquidity_accounts').select('*'),
        supabase.from('portfolio_snapshots').select('*'),
        supabase.from('transactions').select('*')
      ]);

      setData((prev) => ({
        ...prev,
        transactions: (transactions || []).map((t: any) => ({
          id: t.id,
          type: t.type,
          category: t.category,
          amount: t.amount,
          description: t.description,
          date: t.date,
          createdAt: t.created_at
        })).sort((a: any, b: any) => new Date(b.date).getTime() - new Date(a.date).getTime()),
        investments: (assets || []).filter((a: any) => a.category === 'investment').map((a: any) => ({
          id: a.id,
          type: a.type,
          symbol: a.symbol,
          name: a.name,
          quantity: a.quantity,
          costBasis: a.avg_buy_price * a.quantity,
          currentValue: 0,
          currency: a.trading_currency,
          sector: a.sector,
          geography: a.geography,
          createdAt: a.created_at,
          updatedAt: a.updated_at
        })),
        crypto: (assets || []).filter((a: any) => a.category === 'crypto').map((a: any) => ({
          id: a.id,
          symbol: a.symbol,
          name: a.name,
          quantity: a.quantity,
          avgBuyPrice: a.avg_buy_price,
          currentPrice: 0,
          currency: 'USD',
          createdAt: a.created_at,
          updatedAt: a.updated_at
        })),
        liabilities: (liabilities || []).map((l: any) => ({
          id: l.id,
          name: l.name,
          type: l.type,
          currentBalance: l.current_balance,
          principal: l.principal || l.current_balance, // Fallback
          interestRate: l.interest_rate,
          currency: l.currency,
          monthlyPayment: l.monthly_payment,
          createdAt: l.created_at,
          updatedAt: l.updated_at
        })),
        liquidity: (liquidity || []).map((l: any) => ({
          id: l.id,
          name: l.name,
          type: l.type,
          balance: l.balance,
          currency: l.currency,
          createdAt: l.created_at,
          updatedAt: l.updated_at
        })),
        snapshots: (snapshots || []).map((s: any) => ({
          id: s.id,
          date: s.date,
          netWorth: s.net_worth,
          totalAssets: s.total_assets,
          totalLiabilities: s.total_liabilities,
          liquidity: s.liquidity,
          investments: s.investments,
          crypto: s.crypto,
          createdAt: s.created_at
        })).sort((a: any, b: any) => a.date.localeCompare(b.date))
      }));
    } catch (e) {
      console.error('Supabase fetch error:', e);
      toast.error('Failed to load data from cloud');
    } finally {
      setIsLoaded(true);
    }
  }, [user]);

  useEffect(() => {
    fetchData();
  }, [fetchData]);


  // PERSISTENCE (Hybrid)
  useEffect(() => {
    if (isLoaded) {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(data));
    }
  }, [data, isLoaded]);

  // TRANSACTIONS
  const addTransaction = useCallback(async (entry: Omit<Transaction, 'id' | 'createdAt'>) => {
    if (!user) return;
    const { error } = await supabase.from('transactions').insert([{
      user_id: user.id,
      type: entry.type,
      category: entry.category,
      amount: entry.amount,
      description: entry.description,
      date: entry.date
    }]);

    if (error) toast.error('Failed to add transaction');
    else fetchData();
  }, [user, fetchData]);

  const deleteTransaction = useCallback(async (id: string) => {
    if (!user) return;
    const { error } = await supabase.from('transactions').delete().eq('id', id);
    if (error) toast.error('Failed to delete transaction');
    else fetchData();
  }, [user, fetchData]);

  // --- ACTIONS (Supabase Integration) ---

  const addInvestment = useCallback(async (entry: Omit<Investment, 'id' | 'createdAt' | 'updatedAt'>) => {
    if (!user) return;
    const avgPrice = entry.quantity > 0 ? (entry.costBasis || 0) / entry.quantity : 0;

    const dbPayload = {
      user_id: user.id,
      category: 'investment',
      type: entry.type,
      symbol: entry.symbol,
      name: entry.name,
      quantity: entry.quantity,
      avg_buy_price: avgPrice,
      trading_currency: entry.currency || 'USD',
      sector: entry.sector,
      geography: entry.geography,
      created_at: new Date().toISOString()
    };

    const { data: inserted, error } = await supabase.from('assets').insert([dbPayload]).select().single();
    if (error) { toast.error('Failed to save investment'); return; }
    fetchData();
  }, [user, fetchData]);

  const updateInvestment = useCallback(async (id: string, updates: Partial<Investment>) => {
    if (!user) return;
    const payload: any = { updated_at: new Date().toISOString() };
    if (updates.quantity !== undefined) payload.quantity = updates.quantity;

    setData((prev) => ({
      ...prev,
      investments: prev.investments.map((i) => i.id === id ? { ...i, ...updates } : i),
    }));
  }, [user]);

  const deleteInvestment = useCallback(async (id: string) => {
    if (!user) return;
    await supabase.from('assets').delete().eq('id', id);
    fetchData();
  }, [user, fetchData]);


  const addCrypto = useCallback(async (entry: Omit<CryptoHolding, 'id' | 'createdAt' | 'updatedAt'>) => {
    if (!user) return;
    const dbPayload = {
      user_id: user.id,
      category: 'crypto',
      type: 'crypto', // generic
      symbol: entry.symbol,
      name: entry.name,
      quantity: entry.quantity,
      avg_buy_price: entry.avgBuyPrice,
      trading_currency: 'USD',
      created_at: new Date().toISOString()
    };
    const { error } = await supabase.from('assets').insert([dbPayload]);
    if (error) toast.error('Failed to save crypto');
    else fetchData();
  }, [user, fetchData]);

  const updateCrypto = useCallback(async (id: string, updates: Partial<CryptoHolding>) => {
    setData((prev) => ({
      ...prev,
      crypto: prev.crypto.map((c) => c.id === id ? { ...c, ...updates } : c),
    }));
  }, []);

  const deleteCrypto = useCallback(async (id: string) => {
    if (!user) return;
    await supabase.from('assets').delete().eq('id', id);
    fetchData();
  }, [user, fetchData]);


  const addLiability = useCallback(async (entry: Omit<Liability, 'id' | 'createdAt' | 'updatedAt'>) => {
    if (!user) return;
    const { error } = await supabase.from('liabilities').insert([{
      user_id: user.id,
      name: entry.name,
      type: entry.type,
      current_balance: entry.currentBalance,
      interest_rate: entry.interestRate,
      currency: entry.currency,
      monthly_payment: entry.monthlyPayment
    }]);
    if (error) toast.error('Error adding liability');
    else fetchData();
  }, [user, fetchData]);

  const updateLiability = useCallback(async (id: string, updates: Partial<Liability>) => {
    if (!user) return;
    const payload: any = {};
    if (updates.currentBalance !== undefined) payload.current_balance = updates.currentBalance;

    if (Object.keys(payload).length > 0) {
      await supabase.from('liabilities').update(payload).eq('id', id);
      fetchData();
    } else {
      setData(prev => ({ ...prev, liabilities: prev.liabilities.map(l => l.id === id ? { ...l, ...updates } : l) }));
    }
  }, [user, fetchData]);

  const deleteLiability = useCallback(async (id: string) => {
    if (!user) return;
    await supabase.from('liabilities').delete().eq('id', id);
    fetchData();
  }, [user, fetchData]);


  const addLiquidity = useCallback(async (entry: Omit<LiquidityAccount, 'id' | 'createdAt' | 'updatedAt'>) => {
    if (!user) return;
    const { error } = await supabase.from('liquidity_accounts').insert([{
      user_id: user.id,
      name: entry.name,
      type: entry.type,
      balance: entry.balance,
      currency: entry.currency
    }]);
    if (error) toast.error('Error adding account');
    else fetchData();
  }, [user, fetchData]);

  const updateLiquidity = useCallback(async (id: string, updates: Partial<LiquidityAccount>) => {
    if (!user) return;
    const payload: any = {};
    if (updates.balance !== undefined) payload.balance = updates.balance;

    if (Object.keys(payload).length > 0) {
      await supabase.from('liquidity_accounts').update(payload).eq('id', id);
      fetchData();
    } else {
      setData(prev => ({ ...prev, liquidity: prev.liquidity.map(l => l.id === id ? { ...l, ...updates } : l) }));
    }
  }, [user, fetchData]);

  const deleteLiquidity = useCallback(async (id: string) => {
    if (!user) return;
    await supabase.from('liquidity_accounts').delete().eq('id', id);
    fetchData();
  }, [user, fetchData]);


  // Shared Calculations
  const calculateTotals = useCallback((convertFn?: (value: number, currency?: string) => number) => {
    const convert = (value: number, currency?: string) => convertFn ? convertFn(value, currency) : value;

    // Logic Change: Total Liquidity is now Sum(Income) - Sum(Expense) from 'transactions' table (plus optional manual accounts?)
    // User requested: "The 'Total Liquidity' or 'Cash' value... must be dynamically calculated as: SUM(Income) - SUM(Expenses)."
    const totalIncome = (data.transactions || []).filter(t => t.type === 'income').reduce((sum, t) => sum + convert(t.amount, 'EUR'), 0); // Assuming EUR/Base roughly, or converting? Transactions usually in base or specific. Assuming base for simplicity or convert. 
    // Wait, transactions table doesn't have currency column in schema. Assuming Base Currency.
    const totalExpenses = (data.transactions || []).filter(t => t.type === 'expense').reduce((sum, t) => sum + convert(t.amount, 'EUR'), 0);

    const cashBalance = totalIncome - totalExpenses;

    // We can also include the manual liquidity accounts if they are distinct (e.g. emergency fund separate from cash flow).
    // But user was specific. Let's merge them or just use cashBalance. 
    // "Connect the 'Liquidity' card... to this new transactions table. The 'Liquidity' should be the sum of all time (Income - Expenses)."
    // So distinct manual accounts might be legacy or "Investment Cash".
    // I will use ONLY cashBalance for "Total Liquidity" as requested for the Net Worth.
    const totalLiquidity = cashBalance;

    // Legacy manual liquidity accounts
    // const manualLiquidity = data.liquidity.reduce((sum, a) => sum + convert(a.balance, a.currency), 0);

    const totalInvestments = data.investments.reduce((sum, i) => sum + convert(i.currentValue, i.currency), 0);
    const totalCrypto = data.crypto.reduce((sum, c) => sum + convert(c.quantity * c.currentPrice, 'USD'), 0);

    const totalAssets = totalLiquidity + totalInvestments + totalCrypto; // + manualLiquidity? Omitted to follow strict instruction.
    const totalLiabilities = data.liabilities.reduce((sum, l) => sum + convert(l.currentBalance, l.currency), 0);
    const netWorth = totalAssets - totalLiabilities;

    return { totalLiquidity, totalInvestments, totalCrypto, totalAssets, totalLiabilities, netWorth };
  }, [data]);


  const takeSnapshot = useCallback(async (convertFn?: (value: number, currency?: string) => number) => {
    if (!user) return;
    const totals = calculateTotals(convertFn);

    // Persist Snapshot
    const { error } = await supabase.from('portfolio_snapshots').insert([{
      user_id: user.id,
      date: new Date().toISOString(),
      net_worth: totals.netWorth,
      total_assets: totals.totalAssets,
      total_liabilities: totals.totalLiabilities,
      liquidity: totals.totalLiquidity,
      investments: totals.totalInvestments,
      crypto: totals.totalCrypto
    }]);

    if (error) toast.error('Failed to save snapshot');
    else {
      toast.success('Snapshot saved to history');
      fetchData();
    }
  }, [user, calculateTotals, fetchData]);

  // Legacy/Local Income & Expenses (No Supabase yet) -> RETAINING FOR COMPAT, BUT UNUSED
  const addIncome = useCallback((entry: Omit<IncomeEntry, 'id' | 'createdAt'>) => { }, []);
  const deleteIncome = useCallback((id: string) => { }, []);
  const addExpense = useCallback((entry: Omit<ExpenseEntry, 'id' | 'createdAt'>) => { }, []);
  const deleteExpense = useCallback((id: string) => { }, []);

  const getMonthlyCashFlow = useCallback((month: Date) => {
    const monthStr = format(month, 'yyyy-MM');
    // Use NEW transactions
    const monthlyTransactions = (data.transactions || []).filter(t => t.date.startsWith(monthStr));
    const monthlyIncome = monthlyTransactions.filter(t => t.type === 'income').reduce((sum, t) => sum + t.amount, 0);
    const monthlyExpenses = monthlyTransactions.filter(t => t.type === 'expense').reduce((sum, t) => sum + t.amount, 0);
    const savingsRate = monthlyIncome > 0 ? ((monthlyIncome - monthlyExpenses) / monthlyIncome) * 100 : 0;

    return { monthlyIncome, monthlyExpenses, savingsRate };
  }, [data.transactions]);

  const getSnapshotsByRange = useCallback((range: TimeRange): ChartDataPoint[] => {
    const now = new Date();
    let cutoff: Date;
    switch (range) {
      case '1M': cutoff = subMonths(now, 1); break;
      case '6M': cutoff = subMonths(now, 6); break;
      case '1Y': cutoff = subYears(now, 1); break;
      case 'ALL': default: cutoff = new Date(0);
    }
    return data.snapshots
      .filter((s) => isAfter(parseISO(s.date), cutoff))
      .map((s) => ({ date: format(parseISO(s.date), 'MMM dd'), value: s.netWorth }))
      .sort((a, b) => a.date.localeCompare(b.date));
  }, [data.snapshots]);

  const clearData = useCallback(async () => {
    if (user) {
      // Delete from Supabase
      const { error: e1 } = await supabase.from('transactions').delete().eq('user_id', user.id);
      const { error: e2 } = await supabase.from('assets').delete().eq('user_id', user.id);
      const { error: e3 } = await supabase.from('liabilities').delete().eq('user_id', user.id);
      const { error: e4 } = await supabase.from('liquidity_accounts').delete().eq('user_id', user.id);
      const { error: e5 } = await supabase.from('portfolio_snapshots').delete().eq('user_id', user.id);

      if (e1 || e2 || e3 || e4 || e5) {
        console.error('Error clearing data', { e1, e2, e3, e4, e5 });
        toast.error('Failed to wipe some data from cloud');
      } else {
        toast.success('All cloud data wiped');
        fetchData();
      }
    } else {
      // Local only
      localStorage.removeItem(STORAGE_KEY);
      setData(getInitialData());
      toast.success('Local data wiped');
    }
  }, [user, fetchData]);


  return {
    data,
    isLoaded,
    calculateTotals,
    takeSnapshot,
    getSnapshotsByRange,
    getMonthlyCashFlow,
    addIncome, deleteIncome, // Legacy
    addExpense, deleteExpense, // Legacy
    addTransaction, deleteTransaction, // New
    addInvestment, updateInvestment, deleteInvestment,
    addCrypto, updateCrypto, deleteCrypto,
    addLiability, updateLiability, deleteLiability,
    addLiquidity, updateLiquidity, deleteLiquidity,
    clearData
  };
}
