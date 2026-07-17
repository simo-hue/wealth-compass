import { useState, useMemo } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { Slider } from '@/components/ui/slider';
import { HelpTooltip } from '@/components/ui/tooltip-helper';
import { useSettings } from '@/contexts/SettingsContext';
import { AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Legend } from 'recharts';
import { cn } from '@/lib/utils';
import { useIsMobile } from '@/hooks/use-mobile';
import { TrendingDown, TrendingUp, Info } from 'lucide-react';

export default function InflationCalculator() {
    const { formatCurrency } = useSettings();
    const isMobile = useIsMobile();

    // State for inputs
    const [currentAmount, setCurrentAmount] = useState<number>(10000);
    const [inflationRate, setInflationRate] = useState<number>(3);
    const [years, setYears] = useState<number>(20);

    // Calculate projection data
    const data = useMemo(() => {
        const result = [];

        // Future Cost Multiplier: (1 + r)^n
        // Purchasing Power Multiplier: 1 / (1 + r)^n

        for (let i = 0; i <= years; i++) {
            const inflationDec = inflationRate / 100;

            // Future Cost: How much you need in future to buy what costs 'currentAmount' today
            const futureCost = currentAmount * Math.pow(1 + inflationDec, i);

            // Purchasing Power: What 'currentAmount' kept in cash is worth in today's dollars after 'i' years
            const purchasingPower = currentAmount / Math.pow(1 + inflationDec, i);

            result.push({
                year: i,
                futureCost: Math.round(futureCost),
                purchasingPower: Math.round(purchasingPower),
                originalAmount: currentAmount, // Reference line
            });
        }
        return result;
    }, [currentAmount, inflationRate, years]);

    const finalData = data[data.length - 1];

    return (
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 animate-fade-in">
            <div className="lg:col-span-1 space-y-6">
                <Card className="glass-card border-none shadow-xl">
                    <CardHeader>
                        <CardTitle className="text-xl gradient-text flex items-center gap-2">
                            <TrendingDown className="h-5 w-5 text-rose-500" />
                            Inflation Parameters
                        </CardTitle>
                    </CardHeader>
                    <CardContent className="space-y-6">

                        {/* Current Amount Input */}
                        <div className="space-y-4">
                            <div className="flex items-center justify-between">
                                <div className="flex items-center gap-2">
                                    <Label htmlFor="currentAmount">Current Amount</Label>
                                    <HelpTooltip content="The amount of money you have today or the cost of an item today." />
                                </div>
                                <Input
                                    id="currentAmount"
                                    type="number"
                                    value={currentAmount}
                                    onChange={(e) => setCurrentAmount(Number(e.target.value))}
                                    className="w-32 text-right"
                                />
                            </div>
                            <Slider
                                value={[currentAmount]}
                                min={100}
                                max={1000000}
                                step={100}
                                onValueChange={(val) => setCurrentAmount(val[0])}
                                className="py-2"
                            />
                        </div>

                        {/* Inflation Rate Input */}
                        <div className="space-y-4">
                            <div className="flex items-center justify-between">
                                <div className="flex items-center gap-2">
                                    <Label htmlFor="inflationRate">Annual Inflation Rate (%)</Label>
                                    <HelpTooltip content="The average annual rate at which prices actially increase. Historical average is around 3%." />
                                </div>
                                <div className="w-16 text-right font-medium">{inflationRate}%</div>
                            </div>
                            <Slider
                                value={[inflationRate]}
                                min={0}
                                max={15}
                                step={0.1}
                                onValueChange={(val) => setInflationRate(val[0])}
                                className="py-2"
                            />
                        </div>

                        {/* Time Horizon Input */}
                        <div className="space-y-4">
                            <div className="flex items-center justify-between">
                                <div className="flex items-center gap-2">
                                    <Label htmlFor="years">Time Period (Years)</Label>
                                    <HelpTooltip content="The number of years to look into the future." />
                                </div>
                                <div className="w-16 text-right font-medium">{years} Years</div>
                            </div>
                            <Slider
                                value={[years]}
                                min={1}
                                max={50}
                                step={1}
                                onValueChange={(val) => setYears(val[0])}
                                className="py-2"
                            />
                        </div>

                        {/* Summary Statistics */}
                        <div className="pt-4 border-t border-white/10 space-y-3">
                            <div className="flex justify-between items-center text-sm">
                                <span className="text-muted-foreground">Original Value</span>
                                <span className="font-semibold text-foreground">{formatCurrency(currentAmount)}</span>
                            </div>
                            <div className="flex justify-between items-center text-sm">
                                <span className="text-muted-foreground">Future Purchasing Power</span>
                                <span className="font-bold text-rose-400">{formatCurrency(finalData?.purchasingPower || 0)}</span>
                            </div>
                            <div className="flex justify-between items-center text-sm">
                                <span className="text-muted-foreground">Cost in {years} Years</span>
                                <span className="font-bold text-amber-400">{formatCurrency(finalData?.futureCost || 0)}</span>
                            </div>

                            <div className="mt-4 p-3 rounded-lg bg-rose-500/10 border border-rose-500/20 text-xs text-rose-200 flex gap-2 items-start">
                                <Info className="h-4 w-4 mt-0.5 shrink-0" />
                                <p>
                                    In {years} years, your {formatCurrency(currentAmount)} will only buy about
                                    <span className="font-bold text-white px-1">
                                        {Math.round((finalData?.purchasingPower / currentAmount) * 100)}%
                                    </span>
                                    of what it buys today.
                                </p>
                            </div>
                        </div>

                    </CardContent>
                </Card>
            </div>

            <div className="lg:col-span-2 space-y-6">
                <Card className="glass-card border-none shadow-xl h-[300px] md:h-[500px] flex flex-col">
                    <CardHeader>
                        <CardTitle className="text-xl gradient-text">Purchasing Power Erosion</CardTitle>
                    </CardHeader>
                    <CardContent className="flex-1 min-h-0">
                        <ResponsiveContainer width="100%" height="100%">
                            <AreaChart data={data} margin={{ top: 10, right: 30, left: 20, bottom: 5 }}>
                                <defs>
                                    <linearGradient id="colorPurchasingPower" x1="0" y1="0" x2="0" y2="1">
                                        <stop offset="5%" stopColor="#f43f5e" stopOpacity={0.3} />
                                        <stop offset="95%" stopColor="#f43f5e" stopOpacity={0} />
                                    </linearGradient>
                                    <linearGradient id="colorFutureCost" x1="0" y1="0" x2="0" y2="1">
                                        <stop offset="5%" stopColor="#f59e0b" stopOpacity={0.3} />
                                        <stop offset="95%" stopColor="#f59e0b" stopOpacity={0} />
                                    </linearGradient>
                                </defs>
                                <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.1)" vertical={false} />
                                <XAxis
                                    dataKey="year"
                                    stroke="#9ca3af"
                                    tickLine={false}
                                    axisLine={false}
                                    label={{ value: 'Years', position: 'insideBottomRight', offset: -5, fill: '#9ca3af' }}
                                />
                                <YAxis
                                    stroke="#9ca3af"
                                    tickLine={false}
                                    axisLine={false}
                                    tickFormatter={(value) => `$${value / 1000}k`}
                                    hide={isMobile}
                                />
                                <Tooltip
                                    contentStyle={{ backgroundColor: 'rgba(23, 23, 23, 0.9)', borderRadius: '8px', border: '1px solid rgba(255,255,255,0.1)' }}
                                    formatter={(value: number) => [formatCurrency(value), '']}
                                    labelFormatter={(year) => `Year ${year}`}
                                />
                                <Legend />
                                <Area
                                    type="monotone"
                                    dataKey="futureCost"
                                    name="Future Cost of Goods"
                                    stroke="#f59e0b"
                                    fillOpacity={1}
                                    fill="url(#colorFutureCost)"
                                    strokeWidth={2}
                                />
                                <Area
                                    type="monotone"
                                    dataKey="purchasingPower"
                                    name="Real Purchasing Power"
                                    stroke="#f43f5e"
                                    fillOpacity={1}
                                    fill="url(#colorPurchasingPower)"
                                    strokeWidth={2}
                                />
                                {/* Reference line for nominal value (flat) */}
                                <Area
                                    type="monotone"
                                    dataKey="originalAmount"
                                    name="Nominal Value (Cash)"
                                    stroke="#94a3b8"
                                    fill="none"
                                    strokeWidth={1}
                                    strokeDasharray="5 5"
                                />
                            </AreaChart>
                        </ResponsiveContainer>
                    </CardContent>
                </Card>
            </div>
        </div>
    );
}
