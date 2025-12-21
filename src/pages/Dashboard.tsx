import { useState } from 'react';
import { Wallet, TrendingUp, Bitcoin, CreditCard, Camera } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { useFinanceData } from '@/hooks/useFinanceData';
import { StatCard } from '@/components/dashboard/StatCard';
import { NetWorthChart } from '@/components/dashboard/NetWorthChart';
import { AllocationChart } from '@/components/dashboard/AllocationChart';
import { InvestmentTable } from '@/components/dashboard/InvestmentTable';
import { CryptoTable } from '@/components/dashboard/CryptoTable';
import { LiabilitiesTable } from '@/components/dashboard/LiabilitiesTable';
import { LiquidityCards } from '@/components/dashboard/LiquidityCards';
import { IncomeExpenseModule } from '@/components/dashboard/IncomeExpenseModule';
import type { TimeRange } from '@/types/finance';

const Dashboard = () => {
  const [timeRange, setTimeRange] = useState<TimeRange>('1Y');
  const finance = useFinanceData();
  const totals = finance.calculateTotals();
  const chartData = finance.getSnapshotsByRange(timeRange);
  const cashFlow = finance.getMonthlyCashFlow(new Date());

  if (!finance.isLoaded) {
    return <div className="min-h-screen flex items-center justify-center">Loading...</div>;
  }

  return (
    <div className="min-h-screen bg-background dark">
      <div className="max-w-7xl mx-auto p-6 space-y-8">
        {/* Header */}
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-3xl font-bold text-gradient">Personal Finance</h1>
            <p className="text-muted-foreground">Track your wealth journey</p>
          </div>
          <Button onClick={finance.takeSnapshot} className="gradient-primary">
            <Camera className="h-4 w-4 mr-2" /> Take Snapshot
          </Button>
        </div>

        {/* Summary Cards */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          <StatCard title="Net Worth" value={totals.netWorth} icon={TrendingUp} />
          <StatCard title="Liquidity" value={totals.totalLiquidity} icon={Wallet} />
          <StatCard title="Investments" value={totals.totalInvestments} icon={TrendingUp} />
          <StatCard title="Crypto" value={totals.totalCrypto} icon={Bitcoin} />
        </div>

        {/* Net Worth Chart */}
        <NetWorthChart data={chartData} currentRange={timeRange} onRangeChange={setTimeRange} />

        {/* Income & Expenses */}
        <IncomeExpenseModule
          income={finance.data.income}
          expenses={finance.data.expenses}
          monthlyIncome={cashFlow.monthlyIncome}
          monthlyExpenses={cashFlow.monthlyExpenses}
          savingsRate={cashFlow.savingsRate}
          onAddIncome={finance.addIncome}
          onDeleteIncome={finance.deleteIncome}
          onAddExpense={finance.addExpense}
          onDeleteExpense={finance.deleteExpense}
        />

        {/* Liquidity */}
        <LiquidityCards
          accounts={finance.data.liquidity}
          onAdd={finance.addLiquidity}
          onUpdate={finance.updateLiquidity}
          onDelete={finance.deleteLiquidity}
        />

        {/* Investment Portfolio */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <div className="lg:col-span-2">
            <InvestmentTable
              investments={finance.data.investments}
              onAdd={finance.addInvestment}
              onUpdate={finance.updateInvestment}
              onDelete={finance.deleteInvestment}
            />
          </div>
          <AllocationChart investments={finance.data.investments} groupBy="sector" />
        </div>

        {/* Crypto Holdings */}
        <CryptoTable
          holdings={finance.data.crypto}
          onAdd={finance.addCrypto}
          onUpdate={finance.updateCrypto}
          onDelete={finance.deleteCrypto}
        />

        {/* Liabilities */}
        <LiabilitiesTable
          liabilities={finance.data.liabilities}
          onAdd={finance.addLiability}
          onUpdate={finance.updateLiability}
          onDelete={finance.deleteLiability}
        />
      </div>
    </div>
  );
};

export default Dashboard;
