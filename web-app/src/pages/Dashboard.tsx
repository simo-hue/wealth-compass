import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { motion } from 'framer-motion';
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
import { CashFlowTrendChart, AssetAllocationChart, ExpensesBreakdownChart } from '@/components/dashboard/DashboardCharts';
import { toast } from 'sonner';
import type { TimeRange } from '@/types/finance';
import { useSettings } from '@/contexts/SettingsContext';
import { getBatchCryptoPrices, getStockPrice } from '@/lib/api';

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

  const fadeUp = {
    hidden: { opacity: 0, y: 20 },
    visible: { opacity: 1, y: 0, transition: { duration: 0.5, ease: "easeOut" } }
  };

  const staggerContainer = {
    hidden: { opacity: 0 },
    visible: {
      opacity: 1,
      transition: { staggerChildren: 0.1 }
    }
  };

  return (
    <div className="min-h-screen bg-background dark relative overflow-hidden">
      <div className="ambient-bg" />
      <div className="max-w-7xl mx-auto p-4 md:p-6 space-y-8 relative z-10">
        {/* Header */}
        <motion.div 
          initial="hidden"
          animate="visible"
          variants={fadeUp}
          className="flex flex-col md:flex-row md:items-center justify-between gap-4"
        >
          <div>
            <h1 className="text-3xl font-bold text-gradient">Dashboard</h1>
            <div className="flex items-center gap-2">
              <p className="text-muted-foreground">Financial Command Center</p>
              {lastUpdated && <span className="text-xs text-muted-foreground bg-muted/30 px-2 py-1 rounded-md">Updated {lastUpdated.toLocaleTimeString()}</span>}
            </div>
          </div>
          <div className="flex items-center gap-2 w-full md:w-auto">
            <Button
              variant="outline"
              onClick={handleGlobalRefresh}
              disabled={isRefreshing}
              className="flex-1 md:flex-none"
            >
              {isRefreshing ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : <RefreshCw className="h-4 w-4 mr-2" />}
              Refresh
            </Button>
            <Button onClick={() => finance.takeSnapshot(convertCurrency)} className="gradient-primary flex-1 md:flex-none">
              <Camera className="h-4 w-4 mr-2" /> Snapshot
            </Button>
          </div>
        </motion.div>

        {/* Summary Cards */}
        <motion.div 
          initial="hidden"
          whileInView="visible"
          viewport={{ once: true, margin: "-50px" }}
          variants={staggerContainer}
          className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4"
        >
          <motion.div variants={fadeUp}>
            <StatCard
              title="Net Worth"
              value={totals.netWorth}
              icon={TrendingUp}
              helpText="Total Assets - Total Liabilities"
            />
          </motion.div>
          <motion.div variants={fadeUp}>
            <StatCard
              title="Cash Balance"
              value={totals.totalLiquidity}
              icon={Wallet}
              helpText="Liquid Cash (Income - Expenses)"
            />
          </motion.div>
          <motion.div variants={fadeUp}>
            <StatCard
              title="Investments"
              value={totals.totalInvestments}
              icon={TrendingUp}
              helpText="Stocks & ETF Holdings"
            />
          </motion.div>
          <motion.div variants={fadeUp}>
            <StatCard
              title="Crypto"
              value={totals.totalCrypto}
              icon={Bitcoin}
              helpText="Cryptocurrency Holdings"
            />
          </motion.div>
        </motion.div>

        {/* Charts & Activity Grid */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* Main Column */}
          <motion.div 
            initial="hidden"
            whileInView="visible"
            viewport={{ once: true, margin: "-50px" }}
            variants={staggerContainer}
            className="lg:col-span-2 space-y-6"
          >
            <motion.div variants={fadeUp}>
              <NetWorthChart data={chartData} currentRange={timeRange} onRangeChange={setTimeRange} />
            </motion.div>

            <motion.div variants={fadeUp}>
              <CashFlowTrendChart />
            </motion.div>

            <motion.div variants={fadeUp}>
              <ExpensesBreakdownChart />
            </motion.div>
          </motion.div>

          {/* Side Column */}
          <motion.div 
            initial="hidden"
            whileInView="visible"
            viewport={{ once: true, margin: "-50px" }}
            variants={staggerContainer}
            className="flex flex-col gap-6 h-full"
          >
            <motion.div variants={fadeUp}>
              <RecentActivity />
            </motion.div>

            <motion.div variants={fadeUp}>
              <AssetAllocationChart />
            </motion.div>
          </motion.div>
        </div>
      </div>
    </div>
  );
};

export default Dashboard;
