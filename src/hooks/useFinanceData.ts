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
} from '@/types/finance';
import { subMonths, subYears, parseISO, isAfter, format } from 'date-fns';

const STORAGE_KEY = 'finance_dashboard_data';

const getInitialData = (): FinancialData => ({
  income: [],
  expenses: [],
  investments: [],
  crypto: [],
  liabilities: [],
  liquidity: [],
  snapshots: [],
});

const generateId = () => crypto.randomUUID();

export function useFinanceData() {
  const [data, setData] = useState<FinancialData>(getInitialData);
  const [isLoaded, setIsLoaded] = useState(false);

  // Load data from localStorage on mount
  useEffect(() => {
    const stored = localStorage.getItem(STORAGE_KEY);
    if (stored) {
      try {
        setData(JSON.parse(stored));
      } catch (e) {
        console.error('Failed to parse stored finance data:', e);
      }
    }
    setIsLoaded(true);
  }, []);

  // Persist data to localStorage whenever it changes
  useEffect(() => {
    if (isLoaded) {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(data));
    }
  }, [data, isLoaded]);

  // Calculate totals
  const calculateTotals = useCallback(() => {
    const totalLiquidity = data.liquidity.reduce((sum, a) => sum + a.balance, 0);
    const totalInvestments = data.investments.reduce((sum, i) => sum + i.currentValue, 0);
    const totalCrypto = data.crypto.reduce((sum, c) => sum + c.quantity * c.currentPrice, 0);
    const totalAssets = totalLiquidity + totalInvestments + totalCrypto;
    const totalLiabilities = data.liabilities.reduce((sum, l) => sum + l.currentBalance, 0);
    const netWorth = totalAssets - totalLiabilities;

    return {
      totalLiquidity,
      totalInvestments,
      totalCrypto,
      totalAssets,
      totalLiabilities,
      netWorth,
    };
  }, [data]);

  // Take a snapshot of current state
  const takeSnapshot = useCallback(() => {
    const totals = calculateTotals();
    const snapshot: NetWorthSnapshot = {
      id: generateId(),
      date: new Date().toISOString(),
      totalAssets: totals.totalAssets,
      totalLiabilities: totals.totalLiabilities,
      netWorth: totals.netWorth,
      liquidity: totals.totalLiquidity,
      investments: totals.totalInvestments,
      crypto: totals.totalCrypto,
      createdAt: new Date().toISOString(),
    };
    setData((prev) => ({ ...prev, snapshots: [...prev.snapshots, snapshot] }));
  }, [calculateTotals]);

  // Filter snapshots by time range
  const getSnapshotsByRange = useCallback(
    (range: TimeRange): ChartDataPoint[] => {
      const now = new Date();
      let cutoff: Date;

      switch (range) {
        case '1M':
          cutoff = subMonths(now, 1);
          break;
        case '6M':
          cutoff = subMonths(now, 6);
          break;
        case '1Y':
          cutoff = subYears(now, 1);
          break;
        case 'ALL':
        default:
          cutoff = new Date(0);
      }

      return data.snapshots
        .filter((s) => isAfter(parseISO(s.date), cutoff))
        .map((s) => ({
          date: format(parseISO(s.date), 'MMM dd'),
          value: s.netWorth,
        }))
        .sort((a, b) => a.date.localeCompare(b.date));
    },
    [data.snapshots]
  );

  // CRUD for Income
  const addIncome = useCallback((entry: Omit<IncomeEntry, 'id' | 'createdAt'>) => {
    const newEntry: IncomeEntry = {
      ...entry,
      id: generateId(),
      createdAt: new Date().toISOString(),
    };
    setData((prev) => ({ ...prev, income: [...prev.income, newEntry] }));
  }, []);

  const deleteIncome = useCallback((id: string) => {
    setData((prev) => ({ ...prev, income: prev.income.filter((i) => i.id !== id) }));
  }, []);

  // CRUD for Expenses
  const addExpense = useCallback((entry: Omit<ExpenseEntry, 'id' | 'createdAt'>) => {
    const newEntry: ExpenseEntry = {
      ...entry,
      id: generateId(),
      createdAt: new Date().toISOString(),
    };
    setData((prev) => ({ ...prev, expenses: [...prev.expenses, newEntry] }));
  }, []);

  const deleteExpense = useCallback((id: string) => {
    setData((prev) => ({ ...prev, expenses: prev.expenses.filter((e) => e.id !== id) }));
  }, []);

  // CRUD for Investments
  const addInvestment = useCallback((investment: Omit<Investment, 'id' | 'createdAt' | 'updatedAt'>) => {
    const newInvestment: Investment = {
      ...investment,
      id: generateId(),
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };
    setData((prev) => ({ ...prev, investments: [...prev.investments, newInvestment] }));
  }, []);

  const updateInvestment = useCallback((id: string, updates: Partial<Investment>) => {
    setData((prev) => ({
      ...prev,
      investments: prev.investments.map((i) =>
        i.id === id ? { ...i, ...updates, updatedAt: new Date().toISOString() } : i
      ),
    }));
  }, []);

  const deleteInvestment = useCallback((id: string) => {
    setData((prev) => ({ ...prev, investments: prev.investments.filter((i) => i.id !== id) }));
  }, []);

  // CRUD for Crypto
  const addCrypto = useCallback((crypto: Omit<CryptoHolding, 'id' | 'createdAt' | 'updatedAt'>) => {
    const newCrypto: CryptoHolding = {
      ...crypto,
      id: generateId(),
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };
    setData((prev) => ({ ...prev, crypto: [...prev.crypto, newCrypto] }));
  }, []);

  const updateCrypto = useCallback((id: string, updates: Partial<CryptoHolding>) => {
    setData((prev) => ({
      ...prev,
      crypto: prev.crypto.map((c) =>
        c.id === id ? { ...c, ...updates, updatedAt: new Date().toISOString() } : c
      ),
    }));
  }, []);

  const deleteCrypto = useCallback((id: string) => {
    setData((prev) => ({ ...prev, crypto: prev.crypto.filter((c) => c.id !== id) }));
  }, []);

  // CRUD for Liabilities
  const addLiability = useCallback((liability: Omit<Liability, 'id' | 'createdAt' | 'updatedAt'>) => {
    const newLiability: Liability = {
      ...liability,
      id: generateId(),
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };
    setData((prev) => ({ ...prev, liabilities: [...prev.liabilities, newLiability] }));
  }, []);

  const updateLiability = useCallback((id: string, updates: Partial<Liability>) => {
    setData((prev) => ({
      ...prev,
      liabilities: prev.liabilities.map((l) =>
        l.id === id ? { ...l, ...updates, updatedAt: new Date().toISOString() } : l
      ),
    }));
  }, []);

  const deleteLiability = useCallback((id: string) => {
    setData((prev) => ({ ...prev, liabilities: prev.liabilities.filter((l) => l.id !== id) }));
  }, []);

  // CRUD for Liquidity
  const addLiquidity = useCallback((account: Omit<LiquidityAccount, 'id' | 'createdAt' | 'updatedAt'>) => {
    const newAccount: LiquidityAccount = {
      ...account,
      id: generateId(),
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };
    setData((prev) => ({ ...prev, liquidity: [...prev.liquidity, newAccount] }));
  }, []);

  const updateLiquidity = useCallback((id: string, updates: Partial<LiquidityAccount>) => {
    setData((prev) => ({
      ...prev,
      liquidity: prev.liquidity.map((l) =>
        l.id === id ? { ...l, ...updates, updatedAt: new Date().toISOString() } : l
      ),
    }));
  }, []);

  const deleteLiquidity = useCallback((id: string) => {
    setData((prev) => ({ ...prev, liquidity: prev.liquidity.filter((l) => l.id !== id) }));
  }, []);

  // Calculate monthly income/expenses for savings rate
  const getMonthlyCashFlow = useCallback((month: Date) => {
    const monthStr = format(month, 'yyyy-MM');
    const monthlyIncome = data.income
      .filter((i) => i.date.startsWith(monthStr))
      .reduce((sum, i) => sum + i.amount, 0);
    const monthlyExpenses = data.expenses
      .filter((e) => e.date.startsWith(monthStr))
      .reduce((sum, e) => sum + e.amount, 0);
    const savingsRate = monthlyIncome > 0 ? ((monthlyIncome - monthlyExpenses) / monthlyIncome) * 100 : 0;

    return { monthlyIncome, monthlyExpenses, savingsRate };
  }, [data.income, data.expenses]);

  return {
    data,
    isLoaded,
    calculateTotals,
    takeSnapshot,
    getSnapshotsByRange,
    getMonthlyCashFlow,
    // Income
    addIncome,
    deleteIncome,
    // Expenses
    addExpense,
    deleteExpense,
    // Investments
    addInvestment,
    updateInvestment,
    deleteInvestment,
    // Crypto
    addCrypto,
    updateCrypto,
    deleteCrypto,
    // Liabilities
    addLiability,
    updateLiability,
    deleteLiability,
    // Liquidity
    addLiquidity,
    updateLiquidity,
    deleteLiquidity,
  };
}
