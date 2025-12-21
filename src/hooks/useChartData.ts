import { useCallback } from 'react';
import { useFinance } from '@/contexts/FinanceContext';
import { format, subMonths, startOfMonth, endOfMonth, isWithinInterval, startOfYear, parseISO, subDays } from 'date-fns';

export type Period = '30d' | '3m' | 'ytd' | 'all';

export function useChartData() {
    const { data, calculateTotals } = useFinance();

    // 1. ASSET ALLOCATION (Donut)
    // Segments: Stocks, Crypto, Cash
    const getAssetAllocation = useCallback(() => {
        const totals = calculateTotals();

        // Filter out zero values to avoid ugly empty segments
        const chartData = [
            { name: 'Investments', value: totals.totalInvestments, color: '#3b82f6' }, // Blue-500
            { name: 'Crypto', value: totals.totalCrypto, color: '#f59e0b' }, // Amber-500
            { name: 'Cash', value: totals.totalLiquidity, color: '#10b981' }, // Emerald-500
        ].filter(item => item.value > 0);

        return chartData;
    }, [calculateTotals]);

    // 2. CASH FLOW TREND (Bar - Grouped)
    // Last 6 months income vs expense
    const getCashFlowTrend = useCallback((months = 6) => {
        const today = new Date();
        const result = [];

        for (let i = months - 1; i >= 0; i--) {
            const monthDate = subMonths(today, i);
            const monthKey = format(monthDate, 'yyyy-MM');
            const monthLabel = format(monthDate, 'MMM');

            // Filter transactions for this month
            const monthlyTrans = data.transactions.filter(t => t.date.startsWith(monthKey));

            const income = monthlyTrans
                .filter(t => t.type === 'income')
                .reduce((sum, t) => sum + t.amount, 0);

            const expense = monthlyTrans
                .filter(t => t.type === 'expense')
                .reduce((sum, t) => sum + t.amount, 0);

            result.push({
                name: monthLabel,
                Income: income,
                Expense: expense,
            });
        }
        return result;
    }, [data.transactions]);

    // Helper to filter transactions by period
    const filterByPeriod = useCallback((transactions: typeof data.transactions, period: Period) => {
        const now = new Date();
        let start: Date;

        switch (period) {
            case '30d': start = subDays(now, 30); break;
            case '3m': start = subMonths(now, 3); break;
            case 'ytd': start = startOfYear(now); break;
            case 'all': default: return transactions;
        }

        return transactions.filter(t => isWithinInterval(parseISO(t.date), { start, end: now }));
    }, []);

    // 3. EXPENSE STRUCTURE (Pie)
    const getExpensesByCategory = useCallback((period: Period) => {
        const relevant = filterByPeriod(data.transactions, period).filter(t => t.type === 'expense');

        // Group by category
        const grouped: Record<string, number> = {};
        let total = 0;

        relevant.forEach(t => {
            grouped[t.category] = (grouped[t.category] || 0) + t.amount;
            total += t.amount;
        });

        // Format for Recharts
        // Define a palette or let Recharts handle it. We'll pass specific colors for common cats?
        // Let's rely on component to assign colors for now or generate simple ones.
        const chartData = Object.entries(grouped)
            .map(([name, value]) => ({
                name,
                value,
                percentage: total > 0 ? (value / total) * 100 : 0
            }))
            .sort((a, b) => b.value - a.value); // Biggest first

        return { data: chartData, total };
    }, [data.transactions, filterByPeriod]);

    // 4. SPENDING TIMELINE (Area)
    const getSpendingTimeline = useCallback((period: Period) => {
        const relevant = filterByPeriod(data.transactions, period).filter(t => t.type === 'expense');

        // Group by Date
        const grouped: Record<string, number> = {};

        // Fill gaps? 
        // Ideally we want a continuous line. For '30d' or '3m' maybe fill days with 0?
        // For simplicity, let's just plot days with activity first. Area chart handles "linear" interpolation gap visually.
        // Better UX: Fill all days for 30d/3m to show the flatness.

        // Initialize map with 0 for all days in range if period is short enough (30d)
        // skipping full gap fill for 'all' to avoid performance hit on years of data.

        if (period === '30d') {
            const now = new Date();
            for (let i = 30; i >= 0; i--) {
                const d = format(subDays(now, i), 'yyyy-MM-dd');
                grouped[d] = 0;
            }
        }

        relevant.forEach(t => {
            grouped[t.date] = (grouped[t.date] || 0) + t.amount;
        });

        return Object.entries(grouped)
            .map(([date, value]) => ({
                date,
                displayDate: format(parseISO(date), 'MMM dd'),
                amount: value
            }))
            .sort((a, b) => a.date.localeCompare(b.date));
    }, [data.transactions, filterByPeriod]);

    return {
        getAssetAllocation,
        getCashFlowTrend,
        getExpensesByCategory,
        getSpendingTimeline
    };
}
