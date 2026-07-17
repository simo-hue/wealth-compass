
import { useState, useEffect, useMemo } from "react";
import { useIsMobile } from "@/hooks/use-mobile";
import { Card, CardHeader, CardTitle, CardContent } from "@/components/ui/card";
import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { Slider } from "@/components/ui/slider";
import {
    AreaChart,
    Area,
    XAxis,
    YAxis,
    CartesianGrid,
    Tooltip,
    ResponsiveContainer,
    Legend
} from "recharts";
import { useSettings } from "@/contexts/SettingsContext";
import { HelpTooltip } from "@/components/ui/tooltip-helper";

export function CompoundInterestCalculator() {
    const { formatCurrency } = useSettings();
    const isMobile = useIsMobile();

    // State for inputs
    const [initialPrincipal, setInitialPrincipal] = useState(10000);
    const [monthlyContribution, setMonthlyContribution] = useState(500);
    const [interestRate, setInterestRate] = useState(7);
    const [years, setYears] = useState(20);

    // Calculate data for chart
    const data = useMemo(() => {
        const result = [];
        let currentBalance = initialPrincipal;
        let totalContributed = initialPrincipal;

        for (let year = 0; year <= years; year++) {
            result.push({
                year: year,
                balance: Math.round(currentBalance),
                contributed: Math.round(totalContributed),
                interest: Math.round(currentBalance - totalContributed),
            });

            // Calculate next year
            for (let month = 0; month < 12; month++) {
                currentBalance += monthlyContribution;
                currentBalance *= (1 + (interestRate / 100) / 12);
                totalContributed += monthlyContribution;
            }
        }
        return result;
    }, [initialPrincipal, monthlyContribution, interestRate, years]);

    const finalResult = data[data.length - 1];

    return (
        <div className="grid gap-6 md:grid-cols-2">
            <Card>
                <CardHeader>
                    <CardTitle>Configuration</CardTitle>
                </CardHeader>
                <CardContent className="space-y-6">
                    <div className="space-y-2">
                        <div className="flex items-center gap-2">
                            <Label>Initial Principal</Label>
                            <HelpTooltip content="The starting amount of money you are investing." />
                        </div>
                        <div className="flex items-center gap-4">
                            <Input
                                type="number"
                                value={initialPrincipal}
                                onChange={(e) => setInitialPrincipal(Number(e.target.value))}
                                className="w-24"
                            />
                            <Slider
                                value={[initialPrincipal]}
                                onValueChange={(vals) => setInitialPrincipal(vals[0])}
                                max={100000}
                                step={100}
                                className="flex-1"
                            />
                        </div>
                    </div>

                    <div className="space-y-2">
                        <div className="flex items-center gap-2">
                            <Label>Monthly Contribution</Label>
                            <HelpTooltip content="The amount you add to your investment each month." />
                        </div>
                        <div className="flex items-center gap-4">
                            <Input
                                type="number"
                                value={monthlyContribution}
                                onChange={(e) => setMonthlyContribution(Number(e.target.value))}
                                className="w-24"
                            />
                            <Slider
                                value={[monthlyContribution]}
                                onValueChange={(vals) => setMonthlyContribution(vals[0])}
                                max={5000}
                                step={50}
                                className="flex-1"
                            />
                        </div>
                    </div>

                    <div className="space-y-2">
                        <div className="flex items-center gap-2">
                            <Label>Interest Rate (%)</Label>
                            <HelpTooltip content="The annual percentage rate of return you expect to earn." />
                        </div>
                        <div className="flex items-center gap-4">
                            <Input
                                type="number"
                                value={interestRate}
                                onChange={(e) => setInterestRate(Number(e.target.value))}
                                className="w-24"
                                step={0.1}
                            />
                            <Slider
                                value={[interestRate]}
                                onValueChange={(vals) => setInterestRate(vals[0])}
                                max={15}
                                step={0.1}
                                className="flex-1"
                            />
                        </div>
                    </div>

                    <div className="space-y-2">
                        <div className="flex items-center gap-2">
                            <Label>Years to Grow</Label>
                            <HelpTooltip content="The duration for which you plan to keep the money invested." />
                        </div>
                        <div className="flex items-center gap-4">
                            <Input
                                type="number"
                                value={years}
                                onChange={(e) => setYears(Number(e.target.value))}
                                className="w-24"
                            />
                            <Slider
                                value={[years]}
                                onValueChange={(vals) => setYears(vals[0])}
                                max={50}
                                step={1}
                                className="flex-1"
                            />
                        </div>
                    </div>

                    <div className="mt-8 grid grid-cols-2 gap-4">
                        <div className="p-4 rounded-lg bg-secondary/20 border border-secondary">
                            <p className="text-sm text-muted-foreground">Total Contributed</p>
                            <p className="text-xl font-bold">{formatCurrency(finalResult.contributed)}</p>
                        </div>
                        <div className="p-4 rounded-lg bg-primary/10 border border-primary/20">
                            <p className="text-sm text-muted-foreground">Future Value</p>
                            <p className="text-xl font-bold text-primary">{formatCurrency(finalResult.balance)}</p>
                        </div>
                    </div>
                </CardContent>
            </Card>

            <Card>
                <CardHeader>
                    <CardTitle>Growth Projection</CardTitle>
                </CardHeader>
                <CardContent className="h-[300px] md:h-[400px]">
                    <ResponsiveContainer width="100%" height="100%">
                        <AreaChart data={data} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
                            <defs>
                                <linearGradient id="colorBalance" x1="0" y1="0" x2="0" y2="1">
                                    <stop offset="5%" stopColor="#10B981" stopOpacity={0.3} />
                                    <stop offset="95%" stopColor="#10B981" stopOpacity={0} />
                                </linearGradient>
                            </defs>
                            <CartesianGrid strokeDasharray="3 3" opacity={0.1} vertical={false} />
                            <XAxis
                                dataKey="year"
                                tickLine={false}
                                axisLine={false}
                                fontSize={12}
                                label={{ value: 'Years', position: 'insideBottomRight', offset: -5 }}
                            />
                            <YAxis
                                tickFormatter={(val) => `€${val / 1000}k`}
                                tickLine={false}
                                axisLine={false}
                                fontSize={12}
                                hide={isMobile}
                            />
                            <Tooltip
                                contentStyle={{ backgroundColor: '#18181b', border: '1px solid #27272a' }}
                                formatter={(value: number) => formatCurrency(value)}
                                labelFormatter={(label) => `Year ${label}`}
                            />
                            <Legend verticalAlign="top" />
                            <Area
                                type="monotone"
                                dataKey="balance"
                                name="Total Balance"
                                stroke="#10B981"
                                fillOpacity={1}
                                fill="url(#colorBalance)"
                            />
                            <Area
                                type="monotone"
                                dataKey="contributed"
                                name="Principal"
                                stroke="#6366f1"
                                fill="transparent"
                                strokeDasharray="5 5"
                            />
                        </AreaChart>
                    </ResponsiveContainer>
                </CardContent>
            </Card>
        </div>
    );
}
