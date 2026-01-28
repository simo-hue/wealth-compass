import { useMemo, useState } from 'react';
import {
    PieChart,
    Pie,
    Cell,
    Tooltip,
    Legend,
    ResponsiveContainer,
    BarChart,
    Bar,
    XAxis,
    YAxis,
    CartesianGrid,
    ReferenceLine,
    Sector
} from 'recharts';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { useFinance } from '@/contexts/FinanceContext';
import { useSettings } from '@/contexts/SettingsContext';
import { useIsMobile } from '@/hooks/use-mobile';
import { cn } from '@/lib/utils';
import { PieChart as PieChartIcon, BarChart3 as BarChartIcon } from 'lucide-react';

const COLORS = ['#3b82f6', '#10b981', '#f59e0b', '#ef4444', '#8b5cf6', '#ec4899', '#06b6d4', '#84cc16'];

const COIN_COLORS: Record<string, string> = {
    BTC: '#F7931A', // Bitcoin Orange
    CRO: '#1060FF', // Cronos Blue (Brighter for dark mode visibility)
    ETH: '#627EEA', // Ethereum Blue
    SOL: '#14F195', // Solana Green
    USDT: '#26A17B', // Tether Green
    BNB: '#F3BA2F', // Binance Yellow
    ADA: '#0033AD', // Cardano Blue
    XRP: '#00AACE', // XRP Blue
    DOGE: '#C2A633', // Dogecoin Gold
    DOT: '#E6007A', // Polkadot Pink
    AVAX: '#E84142', // Avalanche Red
    MATIC: '#8247E5', // Polygon Purple
    LINK: '#2A5ADA', // Chainlink Blue
};

const getCoinColor = (symbol: string, index: number) => {
    return COIN_COLORS[symbol.toUpperCase()] || COLORS[index % COLORS.length];
};

export function CryptoAllocationChart() {
    const { data } = useFinance();
    const { formatCurrency, isPrivacyMode } = useSettings();
    const isMobile = useIsMobile();
    const [activeIndex, setActiveIndex] = useState(0);

    const chartData = useMemo(() => {
        const totalValue = data.crypto.reduce((sum, c) => sum + (c.quantity * c.currentPrice), 0);

        return data.crypto
            .map((c) => ({
                name: c.symbol,
                value: c.quantity * c.currentPrice,
                quantity: c.quantity,
                price: c.currentPrice,
                percentage: totalValue > 0 ? ((c.quantity * c.currentPrice) / totalValue) * 100 : 0
            }))
            .filter(item => item.value > 0)
            .sort((a, b) => b.value - a.value);
    }, [data.crypto]);

    const totalPortfolioValue = useMemo(() => {
        return data.crypto.reduce((sum, c) => sum + (c.quantity * c.currentPrice), 0);
    }, [data.crypto]);

    // Custom Active Shape for hover effect
    const renderActiveShape = (props: any) => {
        const { cx, cy, innerRadius, outerRadius, startAngle, endAngle, fill, payload, value } = props;

        return (
            <g>
                <text x={cx} y={cy} dy={-10} textAnchor="middle" fill="#9ca3af" fontSize={12} className="font-medium">
                    Total Balance
                </text>
                <text x={cx} y={cy} dy={20} textAnchor="middle" fill="#FFFFFF" fontSize={isMobile ? 18 : 22} className="font-bold">
                    {isPrivacyMode ? "****" : formatCurrency(totalPortfolioValue, 'USD')}
                </text>
                <Sector
                    cx={cx}
                    cy={cy}
                    innerRadius={innerRadius}
                    outerRadius={outerRadius + 6}
                    startAngle={startAngle}
                    endAngle={endAngle}
                    fill={fill}
                    cornerRadius={6}
                />
            </g>
        );
    };

    const ActiveItem = chartData[activeIndex];

    return (
        <Card className="glass-card border-none bg-black/40 backdrop-blur-xl ring-1 ring-white/5 h-full">
            <CardHeader>
                <CardTitle className="text-lg font-semibold flex items-center gap-2 text-white/90">
                    <PieChartIcon className="h-5 w-5 text-indigo-400" />
                    Portfolio Allocation
                </CardTitle>
            </CardHeader>
            <CardContent>
                {chartData.length === 0 ? (
                    <div className="h-[300px] flex items-center justify-center text-muted-foreground text-sm">
                        No assets found
                    </div>
                ) : (
                    <div className="flex flex-col items-center gap-6 h-full">
                        {/* Donut Chart */}
                        <div className="relative w-full h-[260px] flex-shrink-0">
                            <ResponsiveContainer width="100%" height="100%">
                                <PieChart>
                                    <Pie
                                        activeIndex={activeIndex}
                                        activeShape={renderActiveShape}
                                        data={chartData}
                                        cx="50%"
                                        cy="50%"
                                        innerRadius={isMobile ? 65 : 80}
                                        outerRadius={isMobile ? 85 : 100}
                                        paddingAngle={4}
                                        dataKey="value"
                                        onMouseEnter={(_, index) => setActiveIndex(index)}
                                        stroke="none"
                                        cornerRadius={5}
                                    >
                                        {chartData.map((entry, index) => (
                                            <Cell
                                                key={`cell-${index}`}
                                                fill={getCoinColor(entry.name, index)}
                                                className="transition-all duration-300 ease-in-out hover:opacity-100 opacity-90"
                                            />
                                        ))}
                                    </Pie>
                                </PieChart>
                            </ResponsiveContainer>
                            {/* Center Text Wrapper for initial view or non-hover/default */}
                            <div className="absolute inset-0 flex flex-col items-center justify-center pointer-events-none">
                                {/* This is visually handled by renderActiveShape now, but can serve as fallback */}
                            </div>
                        </div>

                        {/* Custom Legend - Below Chart */}
                        <div className="w-full flex flex-col gap-3 px-2">
                            {chartData.map((item, index) => (
                                <div
                                    key={item.name}
                                    onMouseEnter={() => setActiveIndex(index)}
                                    className={cn(
                                        "flex items-center justify-between p-3 rounded-lg border border-white/5 transition-all duration-200 cursor-pointer group",
                                        activeIndex === index ? "bg-white/10 border-white/10 translate-x-1" : "hover:bg-white/5 hover:border-white/10"
                                    )}
                                >
                                    <div className="flex items-center gap-3">
                                        <div
                                            className="w-3 h-3 rounded-full shadow-[0_0_8px_rgba(0,0,0,0.5)]"
                                            style={{ backgroundColor: getCoinColor(item.name, index) }}
                                        />
                                        <div className="flex flex-col">
                                            <span className="font-bold text-sm text-white/90 group-hover:text-white transition-colors">
                                                {item.name}
                                            </span>
                                            <span className="text-xs text-white/50 font-medium">
                                                {item.percentage.toFixed(1)}%
                                            </span>
                                        </div>
                                    </div>
                                    <div className="text-right">
                                        <div className="font-mono text-sm font-medium text-white/80">
                                            {isPrivacyMode ? "****" : formatCurrency(item.value, 'USD')}
                                        </div>
                                        {item.quantity > 0 && (
                                            <div className="text-[10px] text-white/40">
                                                {isPrivacyMode ? "***" : item.quantity.toLocaleString(undefined, { maximumFractionDigits: 4 })} {item.name}
                                            </div>
                                        )}
                                    </div>
                                </div>
                            ))}
                        </div>
                    </div>
                )}
            </CardContent>
        </Card>
    );
}

export function CryptoPerformanceChart() {
    const { data } = useFinance();
    const { formatCurrency, isPrivacyMode, currencySymbol, convertCurrency } = useSettings();
    const isMobile = useIsMobile();
    const [activeIndex, setActiveIndex] = useState<number | null>(null);

    const chartData = useMemo(() => {
        return data.crypto
            .map((c) => {
                const investedUSD = c.quantity * c.avgBuyPrice;
                const currentUSD = c.quantity * c.currentPrice;

                // Convert to Base Currency
                const invested = convertCurrency(investedUSD, 'USD');
                const current = convertCurrency(currentUSD, 'USD');
                const netProfit = current - invested;

                return {
                    name: c.symbol,
                    invested,
                    current,
                    netProfit,
                };
            })
            .filter(item => item.current > 0 || item.invested > 0)
            .sort((a, b) => b.netProfit - a.netProfit); // Sort by highest profit
    }, [data.crypto, convertCurrency]);

    return (
        <Card className="glass-card border-none bg-black/40 backdrop-blur-xl ring-1 ring-white/5 h-full">
            <CardHeader>
                <CardTitle className="text-lg font-semibold flex items-center gap-2 text-white/90">
                    <BarChartIcon className="h-5 w-5 text-emerald-400" />
                    Net Profit / Loss
                </CardTitle>
            </CardHeader>
            <CardContent>
                {chartData.length === 0 ? (
                    <div className="h-[300px] flex items-center justify-center text-muted-foreground text-sm">
                        No assets found
                    </div>
                ) : (
                    <div className="h-[300px] w-full">
                        <ResponsiveContainer width="100%" height="100%">
                            <BarChart
                                data={chartData}
                                barGap={0}
                                onMouseMove={(state) => {
                                    if (state.isTooltipActive) {
                                        setActiveIndex(state.activeTooltipIndex ?? null);
                                    } else {
                                        setActiveIndex(null);
                                    }
                                }}
                                onMouseLeave={() => setActiveIndex(null)}
                            >
                                <CartesianGrid strokeDasharray="3 3" opacity={0.05} vertical={false} stroke="#ffffff" />
                                <ReferenceLine y={0} stroke="#4b5563" strokeOpacity={0.5} />
                                <XAxis
                                    dataKey="name"
                                    fontSize={12}
                                    tickLine={false}
                                    axisLine={false}
                                    tick={{ fill: '#9ca3af' }}
                                    dy={10}
                                />
                                <YAxis
                                    hide={isPrivacyMode || isMobile}
                                    fontSize={12}
                                    tickLine={false}
                                    axisLine={false}
                                    tick={{ fill: '#9ca3af' }}
                                    tickFormatter={(val) => `${currencySymbol}${Math.abs(val) >= 1000 ? (val / 1000).toFixed(0) + 'k' : val}`}
                                />
                                <Tooltip
                                    cursor={{ fill: 'rgba(255,255,255,0.03)', radius: 4 }}
                                    content={({ active, payload }) => {
                                        if (active && payload && payload.length) {
                                            const data = payload[0].payload;
                                            return (
                                                <div className="bg-black/80 backdrop-blur-xl border border-white/10 p-3 rounded-xl shadow-xl">
                                                    <div className="flex items-center gap-2 mb-2">
                                                        <div className="font-bold text-white">{data.name}</div>
                                                        <span className={cn(
                                                            "text-xs px-1.5 py-0.5 rounded font-medium",
                                                            data.netProfit >= 0 ? "bg-emerald-500/20 text-emerald-400" : "bg-rose-500/20 text-rose-400"
                                                        )}>
                                                            {data.netProfit >= 0 ? 'PROFIT' : 'LOSS'}
                                                        </span>
                                                    </div>
                                                    <div className="space-y-1">
                                                        <div className="flex justify-between gap-8 text-sm">
                                                            <span className="text-white/50">Invested</span>
                                                            <span className="text-white/90 font-mono">
                                                                {isPrivacyMode ? "****" : formatCurrency(data.invested)}
                                                            </span>
                                                        </div>
                                                        <div className="flex justify-between gap-8 text-sm">
                                                            <span className="text-white/50">Current</span>
                                                            <span className="text-white/90 font-mono">
                                                                {isPrivacyMode ? "****" : formatCurrency(data.current)}
                                                            </span>
                                                        </div>
                                                        <div className="pt-2 mt-2 border-t border-white/10 flex justify-between gap-8 text-sm font-medium">
                                                            <span className={data.netProfit >= 0 ? "text-emerald-400" : "text-rose-400"}>
                                                                Net P/L
                                                            </span>
                                                            <span className={cn("font-mono", data.netProfit >= 0 ? "text-emerald-400" : "text-rose-400")}>
                                                                {isPrivacyMode ? "****" : (
                                                                    <>
                                                                        {data.netProfit >= 0 ? '+' : ''}{formatCurrency(data.netProfit)}
                                                                    </>
                                                                )}
                                                            </span>
                                                        </div>
                                                    </div>
                                                </div>
                                            );
                                        }
                                        return null;
                                    }}
                                />
                                <Bar
                                    dataKey="netProfit"
                                    radius={[6, 6, 6, 6]}
                                    maxBarSize={50}
                                    animationDuration={1000}
                                >
                                    {chartData.map((entry, index) => (
                                        <Cell
                                            key={`cell-${index}`}
                                            fill={entry.netProfit >= 0 ? '#10b981' : '#f43f5e'}
                                            fillOpacity={activeIndex === index ? 1 : 0.8}
                                            stroke={activeIndex === index ? (entry.netProfit >= 0 ? '#34d399' : '#fb7185') : 'none'}
                                            strokeWidth={2}
                                            className="transition-all duration-300"
                                        />
                                    ))}
                                </Bar>
                            </BarChart>
                        </ResponsiveContainer>
                    </div>
                )}
            </CardContent>
        </Card>
    );
}
