// Core financial data types with timestamps for historical tracking

export interface IncomeEntry {
  id: string;
  type: 'salary' | 'dividends' | 'freelance' | 'other';
  amount: number;
  description: string;
  date: string; // ISO date
  createdAt: string;
}

export interface ExpenseEntry {
  id: string;
  category: string;
  amount: number;
  description: string;
  date: string;
  createdAt: string;
}

export interface Investment {
  id: string;
  type: 'stock' | 'etf' | 'bond' | 'real_estate' | 'commodity' | 'other';
  symbol: string;
  name: string;
  quantity: number;
  costBasis: number; // Total cost
  currentValue: number;
  currentPrice?: number; // Cached unit price
  lastPriceUpdate?: string; // Cache timestamp
  currency?: string; // Original currency, defaults to USD
  geography: string;
  sector: string;
  isin?: string;
  fees?: number;
  updatedAt: string;
  createdAt: string;
}

export interface CryptoHolding {
  id: string;
  symbol: string;
  name: string;
  quantity: number;
  avgBuyPrice: number;
  currentPrice: number;
  lastPriceUpdate?: string; // Cache timestamp
  currency?: string;
  fees?: number;
  coinId?: string;
  updatedAt: string;
  createdAt: string;
}

export interface Liability {
  id: string;
  type: 'mortgage' | 'loan' | 'credit_card' | 'other';
  name: string;
  principal: number;
  currentBalance: number;
  currency?: string;
  interestRate: number;
  monthlyPayment: number;
  createdAt: string;
  updatedAt: string;
}

export interface LiquidityAccount {
  id: string;
  type: 'checking' | 'savings' | 'cash' | 'money_market';
  name: string;
  balance: number;
  currency?: string;
  updatedAt: string;
  createdAt: string;
}

export interface NetWorthSnapshot {
  id: string;
  date: string;
  totalAssets: number;
  totalLiabilities: number;
  netWorth: number;
  liquidity: number;
  investments: number;
  crypto: number;
  createdAt: string;
}

export interface Transaction {
  id: string;
  type: 'income' | 'expense';
  category: string;
  amount: number;
  description: string;
  date: string;
  createdAt: string;
}

export interface FinancialData {
  income: IncomeEntry[]; // Legacy
  expenses: ExpenseEntry[]; // Legacy
  transactions: Transaction[]; // New
  investments: Investment[];
  crypto: CryptoHolding[];
  liabilities: Liability[];
  liquidity: LiquidityAccount[];
  snapshots: NetWorthSnapshot[];
}

export type TimeRange = '1M' | '6M' | '1Y' | 'ALL';

export interface ChartDataPoint {
  date: string;
  value: number;
}
