import { useState } from 'react';
import {
    PieChart, Pie, Cell, Tooltip, Legend, ResponsiveContainer,
    AreaChart, Area, XAxis, YAxis, CartesianGrid
} from 'recharts';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { useChartData, Period } from '@/hooks/useChartData';
import { useSettings } from '@/contexts/SettingsContext';
import { cn } from '@/lib/utils';

const COLORS = ['#10B981', '#3B82F6', '#F59E0B', '#EF4444', '#8B5CF6', '#EC4899', '#6366F1'];

export function CashFlowAnalytics() {
    const [period, setPeriod] = useState<Period>('30d');
    const { getExpensesByCategory, getSpendingTimeline } = useChartData();
    const { formatCurrency, isPrivacyMode } = useSettings();

    const expenseData = getExpensesByCategory(period);
    const timelineData = getSpendingTimeline(period);

    return (
        <div className="space-y-6">
            <div className="flex items-center justify-between">
                <h2 className="text-2xl font-bold text-gradient">Analytics</h2>
                <div className="w-[180px]">
                    <Select value={period} onValueChange={(v: Period) => setPeriod(v)}>
                        <SelectTrigger><SelectValue /></SelectTrigger>
                        <SelectContent>
                            <SelectItem value="30d">Last 30 Days</SelectItem>
                            <SelectItem value="3m">Last 3 Months</SelectItem>
                            <SelectItem value="ytd">Year to Date</SelectItem>
                            <SelectItem value="all">All Time</SelectItem>
                        </SelectContent>
                    </Select>
                </div>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                {/* Expense Structure (Pie) */}
                <Card className="glass-card">
                    <CardHeader>
                        <CardTitle>Expense Structure</CardTitle>
                    </CardHeader>
                    <CardContent className={cn("h-[300px]", isPrivacyMode && "blur-sm select-none pointer-events-none")}>
                        {expenseData.data.length === 0 ? (
                            <div className="h-full flex items-center justify-center text-muted-foreground">No expenses for this period</div>
                        ) : (
                            <ResponsiveContainer width="100%" height="100%">
                                <PieChart>
                                    <Pie
                                        data={expenseData.data}
                                        cx="50%"
                                        cy="50%"
                                        innerRadius={60}
                                        outerRadius={80}
                                        paddingAngle={2}
                                        dataKey="value"
                                    >
                                        {expenseData.data.map((entry, index) => (
                                            <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} stroke="none" />
                                        ))}
                                    </Pie>
                                    <Tooltip
                                        contentStyle={{
                                            backgroundColor: "#1e293b",
                                            borderColor: "#475569",
                                            color: "#f8fafc",
                                            borderRadius: "8px"
                                        }}
                                        itemStyle={{ color: "#f8fafc" }}
                                        labelStyle={{ color: "#f8fafc" }}
                                        formatter={(value: number) => [isPrivacyMode ? "****" : formatCurrency(value), 'Amount']}
                                    />
                                    <Legend layout="vertical" align="right" verticalAlign="middle" />
                                </PieChart>
                            </ResponsiveContainer>
                        )}
                    </CardContent>
                </Card>

                {/* Spending Timeline (Area) */}
                <Card className="glass-card">
                    <CardHeader>
                        <CardTitle>Spending Timeline</CardTitle>
                    </CardHeader>
                    <CardContent className={cn("h-[300px]", isPrivacyMode && "blur-sm select-none pointer-events-none")}>
                        {timelineData.length === 0 ? (
                            <div className="h-full flex items-center justify-center text-muted-foreground">No activity for this period</div>
                        ) : (
                            <ResponsiveContainer width="100%" height="100%">
                                <AreaChart data={timelineData}>
                                    <defs>
                                        <linearGradient id="colorSplit" x1="0" y1="0" x2="0" y2="1">
                                            <stop offset="5%" stopColor="#EF4444" stopOpacity={0.3} />
                                            <stop offset="95%" stopColor="#EF4444" stopOpacity={0} />
                                        </linearGradient>
                                    </defs>
                                    <CartesianGrid strokeDasharray="3 3" opacity={0.1} vertical={false} />
                                    <XAxis dataKey="displayDate" fontSize={12} tickLine={false} axisLine={false} minTickGap={30} />
                                    <YAxis hide={isPrivacyMode} fontSize={12} tickLine={false} axisLine={false} tickFormatter={(val) => `€${val}`} />
                                    <Tooltip
                                        formatter={(value: number) => isPrivacyMode ? "****" : formatCurrency(value)}
                                        labelFormatter={(date) => new Date(date).toLocaleDateString()}
                                        contentStyle={{
                                            backgroundColor: "#1e293b",
                                            borderColor: "#475569",
                                            color: "#f8fafc",
                                            borderRadius: "8px"
                                        }}
                                        itemStyle={{ color: "#f8fafc" }}
                                        labelStyle={{ color: "#f8fafc" }}
                                    />
                                    <Area type="monotone" dataKey="amount" stroke="#EF4444" fillOpacity={1} fill="url(#colorSplit)" />
                                </AreaChart>
                            </ResponsiveContainer>
                        )}
                    </CardContent>
                </Card>
            </div>
        </div>
    );
}
