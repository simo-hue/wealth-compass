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
    Cell
} from 'recharts';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { useChartData } from '@/hooks/useChartData';
import { useSettings } from '@/contexts/SettingsContext';

// --- Cash Flow Trend (Bar) ---
export function CashFlowTrendChart() {
    const { getCashFlowTrend } = useChartData();
    const { formatCurrency } = useSettings();
    const data = getCashFlowTrend(6); // Last 6 months

    return (
        <Card className="glass-card">
            <CardHeader>
                <CardTitle>Cash Flow Trend (6 Months)</CardTitle>
            </CardHeader>
            <CardContent className="h-[300px]">
                <ResponsiveContainer width="100%" height="100%">
                    <BarChart data={data}>
                        <CartesianGrid strokeDasharray="3 3" opacity={0.1} vertical={false} />
                        <XAxis dataKey="name" fontSize={12} tickLine={false} axisLine={false} />
                        <YAxis
                            fontSize={12}
                            tickLine={false}
                            axisLine={false}
                            tickFormatter={(val) => `€${val / 1000}k`}
                        />
                        <Tooltip
                            cursor={{ fill: 'rgba(255,255,255,0.05)' }}
                            contentStyle={{ backgroundColor: '#18181b', border: '1px solid #27272a' }}
                            formatter={(value: number) => formatCurrency(value)}
                        />
                        <Legend />
                        <Bar dataKey="Income" fill="#10B981" radius={[4, 4, 0, 0]} maxBarSize={50} />
                        <Bar dataKey="Expense" fill="#EF4444" radius={[4, 4, 0, 0]} maxBarSize={50} />
                    </BarChart>
                </ResponsiveContainer>
            </CardContent>
        </Card>
    );
}

// --- Asset Allocation (Donut) ---
export function AssetAllocationChart() {
    const { getAssetAllocation } = useChartData();
    const { formatCurrency } = useSettings();
    const data = getAssetAllocation();

    return (
        <Card className="glass-card">
            <CardHeader>
                <CardTitle>Asset Allocation</CardTitle>
            </CardHeader>
            <CardContent className="h-[300px]">
                {data.length === 0 ? (
                    <div className="h-full flex items-center justify-center text-muted-foreground text-sm">
                        No assets found
                    </div>
                ) : (
                    <ResponsiveContainer width="100%" height="100%">
                        <PieChart>
                            <Pie
                                data={data}
                                cx="50%"
                                cy="50%"
                                innerRadius={60}
                                outerRadius={80}
                                paddingAngle={5}
                                dataKey="value"
                            >
                                {data.map((entry, index) => (
                                    <Cell key={`cell-${index}`} fill={entry.color} stroke="none" />
                                ))}
                            </Pie>
                            <Tooltip
                                contentStyle={{ backgroundColor: '#18181b', border: '1px solid #27272a' }}
                                formatter={(value: number) => formatCurrency(value)}
                            />
                            <Legend verticalAlign="bottom" height={36} />
                        </PieChart>
                    </ResponsiveContainer>
                )}
            </CardContent>
        </Card>
    );
}
