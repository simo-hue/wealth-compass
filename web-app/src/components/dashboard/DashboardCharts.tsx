import { useState, useMemo } from 'react';
import {
    BarChart,
    Bar,
    XAxis,
    YAxis,
    CartesianGrid,
    Tooltip,
    Legend,
    ResponsiveContainer,
    PieChart,
    Pie,
    Cell,
    Sector,
    ReferenceLine
} from 'recharts';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { useChartData } from '@/hooks/useChartData';
import { useSettings } from '@/contexts/SettingsContext';
import { useIsMobile } from '@/hooks/use-mobile';
import { cn } from '@/lib/utils';
import { TrendingUp, PieChart as PieChartIcon } from 'lucide-react';

// --- Cash Flow Trend (Bar) ---
export function CashFlowTrendChart() {
    const { getCashFlowTrend } = useChartData();
    const { formatCurrency, isPrivacyMode, currencySymbol } = useSettings();
    const isMobile = useIsMobile();
    const data = getCashFlowTrend(6); // Last 6 months
    const [activeIndex, setActiveIndex] = useState<number | null>(null);

    return (
        <Card className="glass-card border-none bg-black/40 backdrop-blur-xl ring-1 ring-white/5">
            <CardHeader>
                <CardTitle className="text-lg font-semibold flex items-center gap-2 text-white/90">
                    <TrendingUp className="h-5 w-5 text-emerald-400" />
                    Cash Flow Trend (6 Months)
                </CardTitle>
            </CardHeader>
            <CardContent className="h-[200px] md:h-[250px]">
                <ResponsiveContainer width="100%" height="100%">
                    <BarChart
                        data={data}
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
                            tickFormatter={(val) => `${currencySymbol}${val / 1000}k`}
                        />
                        <Tooltip
                            cursor={{ fill: 'rgba(255,255,255,0.03)', radius: 4 }}
                            content={({ active, payload, label }) => {
                                if (active && payload && payload.length) {
                                    return (
                                        <div className="bg-black/80 backdrop-blur-xl border border-white/10 p-3 rounded-xl shadow-xl">
                                            <div className="font-bold text-white mb-2">{label}</div>
                                            <div className="space-y-1">
                                                {payload.map((entry: any) => (
                                                    <div key={entry.name} className="flex justify-between gap-8 text-sm">
                                                        <div className="flex items-center gap-2">
                                                            <div className="w-2 h-2 rounded-full" style={{ backgroundColor: entry.color }} />
                                                            <span className="text-white/70">{entry.name}</span>
                                                        </div>
                                                        <span className="font-mono text-white/90">
                                                            {isPrivacyMode ? "****" : formatCurrency(entry.value)}
                                                        </span>
                                                    </div>
                                                ))}
                                            </div>
                                        </div>
                                    );
                                }
                                return null;
                            }}
                        />
                        <Legend
                            wrapperStyle={{ paddingTop: '20px' }}
                            formatter={(value) => <span style={{ color: '#9ca3af' }}>{value}</span>}
                        />
                        <Bar
                            dataKey="Income"
                            fill="#10B981"
                            radius={[4, 4, 0, 0]}
                            maxBarSize={50}
                            fillOpacity={0.8}
                        />
                        <Bar
                            dataKey="Expense"
                            fill="#EF4444"
                            radius={[4, 4, 0, 0]}
                            maxBarSize={50}
                            fillOpacity={0.8}
                        />
                    </BarChart>
                </ResponsiveContainer>
            </CardContent>
        </Card>
    );
}

// --- Top Expenses (Horizontal Bar) ---
export function ExpensesBreakdownChart() {
    const { getExpensesByCategory } = useChartData();
    const { formatCurrency, isPrivacyMode, currencySymbol } = useSettings();
    const isMobile = useIsMobile();
    const [activeIndex, setActiveIndex] = useState<number | null>(null);

    // Get last 30 days expenses
    const { data } = getExpensesByCategory('30d');
    const topExpenses = data.slice(0, 5); // Top 5

    return (
        <Card className="glass-card border-none bg-black/40 backdrop-blur-xl ring-1 ring-white/5">
            <CardHeader className="pb-2">
                <CardTitle className="text-lg font-semibold flex items-center gap-2 text-white/90">
                    <TrendingUp className="h-5 w-5 text-rose-400" />
                    Top Expenses (30d)
                </CardTitle>
            </CardHeader>
            <CardContent className="h-[250px]">
                {topExpenses.length === 0 ? (
                    <div className="h-full flex items-center justify-center text-muted-foreground text-sm">
                        No expenses found
                    </div>
                ) : (
                    <ResponsiveContainer width="100%" height="100%">
                        <BarChart
                            layout="vertical"
                            data={topExpenses}
                            margin={{ top: 5, right: 30, left: 10, bottom: 5 }}
                            barSize={20}
                            onMouseMove={(state) => {
                                if (state.isTooltipActive) {
                                    setActiveIndex(state.activeTooltipIndex ?? null);
                                } else {
                                    setActiveIndex(null);
                                }
                            }}
                            onMouseLeave={() => setActiveIndex(null)}
                        >
                            <CartesianGrid strokeDasharray="3 3" opacity={0.05} horizontal={false} stroke="#ffffff" />
                            <XAxis type="number" hide />
                            <YAxis
                                dataKey="name"
                                type="category"
                                width={100}
                                tick={{ fill: '#e5e7eb', fontSize: 12 }}
                                tickLine={false}
                                axisLine={false}
                            />
                            <Tooltip
                                cursor={{ fill: 'rgba(255,255,255,0.03)', radius: 4 }}
                                content={({ active, payload }) => {
                                    if (active && payload && payload.length) {
                                        const data = payload[0].payload;
                                        return (
                                            <div className="bg-black/80 backdrop-blur-xl border border-white/10 p-3 rounded-xl shadow-xl">
                                                <div className="flex items-center gap-2 mb-1">
                                                    <div className="w-2 h-2 rounded-full bg-rose-500" />
                                                    <span className="font-bold text-white">{data.name}</span>
                                                </div>
                                                <div className="text-white/90 font-mono">
                                                    {isPrivacyMode ? "****" : formatCurrency(data.value)}
                                                </div>
                                                <div className="text-white/50 text-xs">
                                                    {data.percentage.toFixed(1)}% of total
                                                </div>
                                            </div>
                                        );
                                    }
                                    return null;
                                }}
                            />
                            <Bar
                                dataKey="value"
                                radius={[0, 4, 4, 0]}
                                animationDuration={1000}
                            >
                                {topExpenses.map((entry, index) => (
                                    <Cell
                                        key={`cell-${index}`}
                                        fill={activeIndex === index ? '#f43f5e' : '#e11d48'} // Rose-500 / Rose-600
                                        className="transition-all duration-300"
                                        fillOpacity={activeIndex === index ? 1 : 0.8}
                                    />
                                ))}
                            </Bar>
                        </BarChart>
                    </ResponsiveContainer>
                )}
            </CardContent>
        </Card>
    );
}

// --- Asset Allocation (Donut) ---
export function AssetAllocationChart() {
    const { getAssetAllocation } = useChartData();
    const { formatCurrency, isPrivacyMode } = useSettings();
    const isMobile = useIsMobile();
    const data = getAssetAllocation();
    const [activeIndex, setActiveIndex] = useState(0);

    const totalValue = useMemo(() => {
        return data.reduce((sum, item) => sum + item.value, 0);
    }, [data]);

    // Custom Active Shape
    const renderActiveShape = (props: any) => {
        const { cx, cy, innerRadius, outerRadius, startAngle, endAngle, fill } = props;
        return (
            <g>
                <text x={cx} y={cy} dy={-10} textAnchor="middle" fill="#9ca3af" fontSize={12} className="font-medium">
                    Total Assets
                </text>
                <text x={cx} y={cy} dy={20} textAnchor="middle" fill="#FFFFFF" fontSize={isMobile ? 18 : 22} className="font-bold">
                    {isPrivacyMode ? "****" : formatCurrency(totalValue)}
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

    return (
        <Card className="glass-card border-none bg-black/40 backdrop-blur-xl ring-1 ring-white/5">
            <CardHeader>
                <CardTitle className="text-lg font-semibold flex items-center gap-2 text-white/90">
                    <PieChartIcon className="h-5 w-5 text-indigo-400" />
                    Asset Allocation
                </CardTitle>
            </CardHeader>
            <CardContent className="flex-1 flex flex-col justify-center">
                {data.length === 0 ? (
                    <div className="h-[300px] flex items-center justify-center text-muted-foreground text-sm">
                        No assets found
                    </div>
                ) : (
                    <div className="flex flex-col items-center gap-6">
                        {/* Donut Chart */}
                        <div className="relative w-full h-[260px] flex-shrink-0">
                            <ResponsiveContainer width="100%" height="100%">
                                <PieChart>
                                    <Pie
                                        activeIndex={activeIndex}
                                        activeShape={renderActiveShape}
                                        data={data}
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
                                        {data.map((entry, index) => (
                                            <Cell
                                                key={`cell-${index}`}
                                                fill={entry.color}
                                                className="transition-all duration-300 ease-in-out hover:opacity-100 opacity-90"
                                            />
                                        ))}
                                    </Pie>
                                </PieChart>
                            </ResponsiveContainer>
                        </div>

                        {/* Custom Legend - Below Chart */}
                        <div className="w-full flex flex-col gap-3 px-2">
                            {data.map((item, index) => (
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
                                            style={{ backgroundColor: item.color }}
                                        />
                                        <div className="flex flex-col">
                                            <span className="font-bold text-sm text-white/90 group-hover:text-white transition-colors">
                                                {item.name}
                                            </span>
                                            <span className="text-xs text-white/50 font-medium">
                                                {totalValue > 0 ? ((item.value / totalValue) * 100).toFixed(1) : 0}%
                                            </span>
                                        </div>
                                    </div>
                                    <div className="text-right">
                                        <div className="font-mono text-sm font-medium text-white/80">
                                            {isPrivacyMode ? "****" : formatCurrency(item.value)}
                                        </div>
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
