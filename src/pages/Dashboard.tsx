import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Wallet, TrendingUp, Bitcoin, Camera, RefreshCw, Loader2, Settings } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { useFinance } from '@/contexts/FinanceContext';
import { StatCard } from '@/components/dashboard/StatCard';
import { NetWorthChart } from '@/components/dashboard/NetWorthChart';
import { InvestmentTable } from '@/components/dashboard/InvestmentTable';
import { CryptoTable } from '@/components/dashboard/CryptoTable';
import { LiabilitiesTable } from '@/components/dashboard/LiabilitiesTable';
import { LiquidityCards } from '@/components/dashboard/LiquidityCards';
import { IncomeExpenseModule } from '@/components/dashboard/IncomeExpenseModule';
import { RecentActivity } from '@/components/dashboard/RecentActivity';
import { CashFlowTrendChart, AssetAllocationChart } from '@/components/dashboard/DashboardCharts';
import { toast } from 'sonner';
import type { TimeRange } from '@/types/finance';
import { useSettings } from '@/contexts/SettingsContext';

const Dashboard = () => {
  const navigate = useNavigate();
  const [timeRange, setTimeRange] = useState<TimeRange>('1Y');
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [lastUpdated, setLastUpdated] = useState<Date | null>(null);

  const { convertCurrency } = useSettings();
  const finance = useFinance();
  const totals = finance.calculateTotals();
  const chartData = finance.getSnapshotsByRange(timeRange);
  const cashFlow = finance.getMonthlyCashFlow(new Date());

  if (!finance.isLoaded) {
    return <div className="min-h-screen flex items-center justify-center">Loading...</div>;
  }

  const handleGlobalRefresh = async () => {
    setIsRefreshing(true);
    let updatedCount = 0;

    try {
      // 1. Prepare Batches
      const cryptoItems = finance.data.crypto.map(h => ({
        symbol: h.symbol,
        coinId: h.coinId || (h.name ? h.name.toLowerCase() : undefined)
      }));

      const stockItems = finance.data.investments.filter(inv => inv.type === 'stock' || inv.type === 'etf');

      // 2. Execute Fetches Parallelly
      const [cryptoPrices, stockResults] = await Promise.all([
        getBatchCryptoPrices(cryptoItems),
        Promise.all(stockItems.map(async (inv) => {
          const price = await getStockPrice(inv.symbol);
          return { id: inv.id, price };
        }))
      ]);

      // 3. Process Updates (Atomic-like)

      // Update Crypto
      finance.data.crypto.forEach(h => {
        const lookup = h.coinId || h.name.toLowerCase();
        // Check if we have a price (getBatchCryptoPrices returns keyed by lookup ID)
        if (lookup && cryptoPrices[lookup] !== undefined) {
          finance.updateCrypto(h.id, {
            currentPrice: cryptoPrices[lookup],
            updatedAt: new Date().toISOString()
          });
          updatedCount++;
        }
      });

      // Update Stocks
      stockResults.forEach(({ id, price }) => {
        if (price !== null) {
          const inv = stockItems.find(i => i.id === id);
          if (inv) {
            finance.updateInvestment(id, {
              currentValue: price * inv.quantity,
              updatedAt: new Date().toISOString()
            });
            updatedCount++;
          }
        }
      });

      setLastUpdated(new Date());
      if (updatedCount > 0) {
        toast.success(`Refreshed prices for ${updatedCount} assets`);
      } else {
        toast.info('No prices needed updating or all failed');
      }
    } catch (error) {
      console.error(error);
      toast.error('Global refresh partially failed');
    } finally {
      setIsRefreshing(false);
    }
  };

  return (
    <div className="min-h-screen bg-background dark">
      <div className="max-w-7xl mx-auto p-6 space-y-8">
        {/* Header */}
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-3xl font-bold text-gradient">Dashboard</h1>
            <div className="flex items-center gap-2">
              <p className="text-muted-foreground">Financial Command Center</p>
              {lastUpdated && <span className="text-xs text-muted-foreground bg-muted/30 px-2 py-1 rounded-md">Updated {lastUpdated.toLocaleTimeString()}</span>}
            </div>
          </div>
          <div className="flex items-center gap-2">
            <Button
              variant="outline"
              onClick={handleGlobalRefresh}
              disabled={isRefreshing}
            >
              {isRefreshing ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <RefreshCw className="h-4 w-4 mr-2" />}
              Refresh
            </Button>
            <Button onClick={() => finance.takeSnapshot(convertCurrency)} className="gradient-primary">
              <Camera className="h-4 w-4 mr-2" /> Snapshot
            </Button>
          </div>
        </div>

        {/* Summary Cards */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          <StatCard
            title="Net Worth"
            value={totals.netWorth}
            icon={TrendingUp}
            helpText="Total Assets - Total Liabilities"
          />
          <StatCard
            title="Cash Balance"
            value={totals.totalLiquidity}
            icon={Wallet}
            helpText="Liquid Cash (Income - Expenses)"
          />
          <StatCard
            title="Investments"
            value={totals.totalInvestments}
            icon={TrendingUp}
            helpText="Stocks & ETF Holdings"
          />
          <StatCard
            title="Crypto"
            value={totals.totalCrypto}
            icon={Bitcoin}
            helpText="Cryptocurrency Holdings"
          />
        </div>

        {/* Charts & Activity Grid */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* Main Column */}
          <div className="lg:col-span-2 space-y-6">
            {/* 1. Net Worth History */}
            <NetWorthChart data={chartData} currentRange={timeRange} onRangeChange={setTimeRange} />

            {/* 2. Cash Flow Trend (New) */}
            <CashFlowTrendChart />
          </div>

          {/* Side Column */}
          <div className="space-y-6">
            {/* 3. Asset Allocation (Updated) */}
            <AssetAllocationChart />

            {/* 4. Recent Activity */}
            <RecentActivity />
          </div>
        </div>
      </div>
    </div>
  );
};

export default Dashboard;
