import { useState, useMemo } from 'react';
import {
    PieChart, Pie, Cell, Tooltip, Legend, ResponsiveContainer,
    AreaChart, Area, XAxis, YAxis, CartesianGrid, Sector
} from 'recharts';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useChartData, Period } from '@/hooks/useChartData';
import { useSettings } from '@/contexts/SettingsContext';
import { useIsMobile } from '@/hooks/use-mobile';
import { cn } from '@/lib/utils';
import { PieChart as PieChartIcon, TrendingUp } from 'lucide-react';

const COLORS = ['#10B981', '#3B82F6', '#F59E0B', '#EF4444', '#8B5CF6', '#EC4899', '#6366F1'];

export function CashFlowAnalytics() {
    const [period, setPeriod] = useState<Period>('30d');
    const { getExpensesByCategory, getSpendingTimeline } = useChartData();
    const { formatCurrency, isPrivacyMode, currencySymbol } = useSettings();
    const isMobile = useIsMobile();
    const [activeIndex, setActiveIndex] = useState(0);

    const expenseData = getExpensesByCategory(period);
    const timelineData = getSpendingTimeline(period);

    // Sort expense data
    const sortedExpenseData = useMemo(() => {
        return [...expenseData.data].sort((a, b) => b.value - a.value);
    }, [expenseData.data]);

    const totalExpenses = useMemo(() => {
        return sortedExpenseData.reduce((sum, item) => sum + item.value, 0);
    }, [sortedExpenseData]);

    // Custom Active Shape for Donut
    const renderActiveShape = (props: any) => {
        const { cx, cy, innerRadius, outerRadius, startAngle, endAngle, fill } = props;
        return (
            <g>
                <text x={cx} y={cy} dy={-10} textAnchor="middle" fill="#9ca3af" fontSize={12} className="font-medium">
                    Total
                </text>
                <text x={cx} y={cy} dy={20} textAnchor="middle" fill="#FFFFFF" fontSize={isMobile ? 18 : 22} className="font-bold">
                    {isPrivacyMode ? "****" : formatCurrency(totalExpenses)}
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
        <div className="space-y-6">
            <div className="flex items-center justify-between">
                <h2 className="text-2xl font-bold bg-clip-text text-transparent bg-gradient-to-r from-white to-white/60">
                    Analytics
                </h2>
                <div className="w-[180px]">
                    <Select value={period} onValueChange={(v: Period) => setPeriod(v)}>
                        <SelectTrigger className="glass-input border-white/10 bg-white/5 text-white">
                            <SelectValue />
                        </SelectTrigger>
                        <SelectContent className="glass-card border-white/10 text-white bg-black/90">
                            <SelectItem value="7d">Last 7 Days</SelectItem>
                            <SelectItem value="30d">Last 30 Days</SelectItem>
                            <SelectItem value="3m">Last 3 Months</SelectItem>
                            <SelectItem value="ytd">Year to Date</SelectItem>
                            <SelectItem value="all">All Time</SelectItem>
                        </SelectContent>
                    </Select>
                </div>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                {/* Expense Structure (Donut) */}
                <Card className="glass-card border-none bg-black/40 backdrop-blur-xl ring-1 ring-white/5 h-full">
                    <CardHeader>
                        <CardTitle className="text-lg font-semibold flex items-center gap-2 text-white/90">
                            <PieChartIcon className="h-5 w-5 text-indigo-400" />
                            Expense Structure
                        </CardTitle>
                    </CardHeader>
                    <CardContent className="h-auto md:h-[300px]">
                        {sortedExpenseData.length === 0 ? (
                            <div className="h-full flex items-center justify-center text-muted-foreground text-sm">No expenses for this period</div>
                        ) : (
                            <div className="flex flex-col md:flex-row items-center gap-4 h-full">
                                <div className="relative w-full md:w-1/2 h-[260px]">
                                    <ResponsiveContainer width="100%" height="100%">
                                        <PieChart>
                                            <Pie
                                                activeIndex={activeIndex}
                                                activeShape={renderActiveShape}
                                                data={sortedExpenseData}
                                                cx="50%"
                                                cy="50%"
                                                innerRadius={isMobile ? 60 : 70}
                                                outerRadius={isMobile ? 80 : 90}
                                                paddingAngle={4}
                                                dataKey="value"
                                                onMouseEnter={(_, index) => setActiveIndex(index)}
                                                stroke="none"
                                                cornerRadius={5}
                                            >
                                                {sortedExpenseData.map((entry, index) => (
                                                    <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} className="hover:opacity-100 opacity-90 transition-opacity" />
                                                ))}
                                            </Pie>
                                        </PieChart>
                                    </ResponsiveContainer>
                                </div>
                                <div className="w-full md:w-1/2 flex flex-col gap-2 overflow-y-auto max-h-[260px] pr-2 custom-scrollbar">
                                    {sortedExpenseData.map((item, index) => (
                                        <div
                                            key={item.name}
                                            onMouseEnter={() => setActiveIndex(index)}
                                            className={cn(
                                                "flex items-center justify-between p-2 rounded-lg border border-white/5 transition-all duration-200 cursor-pointer group",
                                                activeIndex === index ? "bg-white/10 border-white/10 translate-x-1" : "hover:bg-white/5 hover:border-white/10"
                                            )}
                                        >
                                            <div className="flex items-center gap-2">
                                                <div
                                                    className="w-2.5 h-2.5 rounded-full"
                                                    style={{ backgroundColor: COLORS[index % COLORS.length] }}
                                                />
                                                <span className="text-xs font-medium text-white/80">{item.name}</span>
                                            </div>
                                            <span className="text-xs font-mono text-white/60">
                                                {isPrivacyMode ? "****" : formatCurrency(item.value)}
                                            </span>
                                        </div>
                                    ))}
                                </div>
                            </div>
                        )}
                    </CardContent>
                </Card>

                {/* Spending Timeline (Area) */}
                <Card className="glass-card border-none bg-black/40 backdrop-blur-xl ring-1 ring-white/5 h-full">
                    <CardHeader>
                        <CardTitle className="text-lg font-semibold flex items-center gap-2 text-white/90">
                            <TrendingUp className="h-5 w-5 text-rose-400" />
                            Spending Timeline
                        </CardTitle>
                    </CardHeader>
                    <CardContent className="h-[300px]">
                        {timelineData.length === 0 ? (
                            <div className="h-full flex items-center justify-center text-muted-foreground text-sm">No activity for this period</div>
                        ) : (
                            <ResponsiveContainer width="100%" height="100%">
                                <AreaChart data={timelineData}>
                                    <defs>
                                        <linearGradient id="colorSplit" x1="0" y1="0" x2="0" y2="1">
                                            <stop offset="5%" stopColor="#EF4444" stopOpacity={0.3} />
                                            <stop offset="95%" stopColor="#EF4444" stopOpacity={0} />
                                        </linearGradient>
                                    </defs>
                                    <CartesianGrid strokeDasharray="3 3" opacity={0.05} vertical={false} stroke="#ffffff" />
                                    <XAxis
                                        dataKey="displayDate"
                                        fontSize={12}
                                        tickLine={false}
                                        axisLine={false}
                                        minTickGap={30}
                                        tick={{ fill: '#9ca3af' }}
                                        dy={10}
                                    />
                                    <YAxis
                                        hide={isPrivacyMode || isMobile}
                                        fontSize={12}
                                        tickLine={false}
                                        axisLine={false}
                                        tick={{ fill: '#9ca3af' }}
                                        tickFormatter={(val) => `${currencySymbol}${val}`}
                                    />
                                    <Tooltip
                                        cursor={{ stroke: '#EF4444', strokeWidth: 1, strokeDasharray: '3 3' }}
                                        content={({ active, payload, label }) => {
                                            if (active && payload && payload.length) {
                                                return (
                                                    <div className="bg-black/80 backdrop-blur-xl border border-white/10 p-3 rounded-xl shadow-xl">
                                                        <div className="text-white/50 text-xs mb-1">
                                                            {new Date(payload[0].payload.date).toLocaleDateString()}
                                                        </div>
                                                        <div className="flex items-center gap-2">
                                                            <div className="font-mono text-lg font-bold text-rose-400">
                                                                {isPrivacyMode ? "****" : formatCurrency(payload[0].value as number)}
                                                            </div>
                                                        </div>
                                                    </div>
                                                );
                                            }
                                            return null;
                                        }}
                                    />
                                    <Area
                                        type="monotone"
                                        dataKey="amount"
                                        stroke="#EF4444"
                                        strokeWidth={2}
                                        fillOpacity={1}
                                        fill="url(#colorSplit)"
                                        activeDot={{ r: 6, fill: "#EF4444", stroke: "#000", strokeWidth: 2 }}
                                    />
                                </AreaChart>
                            </ResponsiveContainer>
                        )}
                    </CardContent>
                </Card>
            </div>
        </div>
    );
}
