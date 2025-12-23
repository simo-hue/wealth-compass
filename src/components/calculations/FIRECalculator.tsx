import { useState, useMemo } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { Slider } from '@/components/ui/slider';
import { HelpTooltip } from '@/components/ui/tooltip-helper';
import { useSettings } from '@/contexts/SettingsContext';
import { ComposedChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Legend, ReferenceLine } from 'recharts';
import { Flame, TrendingUp, Target, DollarSign, Wallet } from 'lucide-react';
import { cn } from '@/lib/utils';

export default function FIRECalculator() {
    const { formatCurrency } = useSettings();

    // Inputs
    const [currentAge, setCurrentAge] = useState<number>(() => {
        const birthDate = new Date('2003-07-28');
        const today = new Date();
        let age = today.getFullYear() - birthDate.getFullYear();
        const m = today.getMonth() - birthDate.getMonth();
        if (m < 0 || (m === 0 && today.getDate() < birthDate.getDate())) {
            age--;
        }
        return age;
    });
    const [currentNetWorth, setCurrentNetWorth] = useState<number>(50000);
    const [annualIncome, setAnnualIncome] = useState<number>(80000);
    const [annualExpenses, setAnnualExpenses] = useState<number>(40000);
    const [swr, setSwr] = useState<number>(4.0); // Safe Withdrawal Rate
    const [nominalReturn, setNominalReturn] = useState<number>(7.0);
    const [inflation, setInflation] = useState<number>(3.0);

    // Derived Metrics
    const savings = annualIncome - annualExpenses;
    const savingsRate = (savings / annualIncome) * 100;

    // Targets
    const fireNumber = annualExpenses / (swr / 100);
    const leanFireNumber = (annualExpenses * 0.8) / (swr / 100);
    const fatFireNumber = (annualExpenses * 1.5) / (swr / 100);

    // Projection Logic
    const projectionData = useMemo(() => {
        const data = [];
        let netWorth = currentNetWorth;
        // Calculate Real Return: (1 + nominal) / (1 + inflation) - 1
        // We use real return to keep everything in "Today's Dollars" (Purchasing Power)
        const realReturnRate = ((1 + nominalReturn / 100) / (1 + inflation / 100)) - 1;

        // Limit simulation to age 100 or 60 years
        const maxYears = 60;
        let reachFireAge = null;

        for (let i = 0; i <= maxYears; i++) {
            const age = currentAge + i;

            // Check for FIRE milestones
            if (netWorth >= fireNumber && reachFireAge === null) {
                reachFireAge = age;
            }

            data.push({
                age,
                netWorth: Math.round(netWorth),
                fireTarget: Math.round(fireNumber),
                leanFire: Math.round(leanFireNumber),
                fatFire: Math.round(fatFireNumber),
            });

            // Growth for next year
            // Add savings + Investment Return
            netWorth = netWorth * (1 + realReturnRate) + savings;
        }
        return { data, reachFireAge };
    }, [currentAge, currentNetWorth, savings, nominalReturn, inflation, fireNumber, leanFireNumber, fatFireNumber]);

    const { data: chartData, reachFireAge } = projectionData;

    const yearsToFire = reachFireAge ? reachFireAge - currentAge : '> 60';

    return (
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 animate-fade-in">

            {/* Sidebar Inputs */}
            <div className="lg:col-span-4 space-y-6">
                <Card className="glass-card border-none shadow-xl">
                    <CardHeader>
                        <CardTitle className="text-xl gradient-text flex items-center gap-2">
                            <Flame className="h-5 w-5 text-orange-500" />
                            FIRE Parameters
                        </CardTitle>
                    </CardHeader>
                    <CardContent className="space-y-6">

                        {/* Age & Net Worth */}
                        <div className="grid grid-cols-2 gap-4">
                            <div className="space-y-2">
                                <Label htmlFor="age">Current Age</Label>
                                <Input
                                    id="age"
                                    type="number"
                                    value={currentAge}
                                    onChange={(e) => setCurrentAge(Number(e.target.value))}
                                />
                            </div>
                            <div className="space-y-2">
                                <Label htmlFor="netWorth">Net Worth</Label>
                                <Input
                                    id="netWorth"
                                    type="number"
                                    value={currentNetWorth}
                                    onChange={(e) => setCurrentNetWorth(Number(e.target.value))}
                                />
                            </div>
                        </div>

                        {/* Income & Expenses */}
                        <div className="space-y-4 pt-2 border-t border-white/10">
                            <div className="space-y-3">
                                <div className="flex items-center justify-between">
                                    <div className="flex items-center gap-2">
                                        <Label>Annual Income (Post-Tax)</Label>
                                        <HelpTooltip content="Your total take-home pay per year." />
                                    </div>
                                </div>
                                <div className="flex gap-4 items-center">
                                    <Input
                                        type="number"
                                        value={annualIncome}
                                        onChange={(e) => setAnnualIncome(Number(e.target.value))}
                                    />
                                </div>
                                <Slider value={[annualIncome]} min={20000} max={500000} step={1000} onValueChange={(v) => setAnnualIncome(v[0])} />
                            </div>

                            <div className="space-y-3">
                                <div className="flex items-center justify-between">
                                    <div className="flex items-center gap-2">
                                        <Label>Annual Expenses</Label>
                                        <HelpTooltip content="How much you spend per year. This is the most critical number for FIRE." />
                                    </div>
                                </div>
                                <div className="flex gap-4 items-center">
                                    <Input
                                        type="number"
                                        value={annualExpenses}
                                        onChange={(e) => setAnnualExpenses(Number(e.target.value))}
                                    />
                                </div>
                                <Slider value={[annualExpenses]} min={10000} max={annualIncome} step={500} onValueChange={(v) => setAnnualExpenses(v[0])} />
                            </div>

                            <div className="flex justify-between text-sm pt-2">
                                <span className="text-muted-foreground">Approx. Savings Rate</span>
                                <span className={cn("font-bold", savingsRate > 50 ? "text-green-400" : savingsRate > 20 ? "text-amber-400" : "text-rose-400")}>
                                    {savingsRate.toFixed(1)}%
                                </span>
                            </div>
                        </div>

                        {/* Market Assumptions */}
                        <div className="space-y-4 pt-2 border-t border-white/10">
                            <div className="space-y-3">
                                <div className="flex justify-between">
                                    <div className="flex items-center gap-2">
                                        <Label>Expected Return (Nominal)</Label>
                                        <HelpTooltip content="Average annual stock market return before inflation (e.g., 7-10%)." />
                                    </div>
                                    <span className="text-sm font-bold">{nominalReturn}%</span>
                                </div>
                                <Slider value={[nominalReturn]} min={1} max={15} step={0.1} onValueChange={(v) => setNominalReturn(v[0])} />
                            </div>

                            <div className="space-y-3">
                                <div className="flex justify-between">
                                    <div className="flex items-center gap-2">
                                        <Label>Inflation Rate</Label>
                                        <HelpTooltip content="Average annual price increase. We adjust returns to 'Real Return' using this." />
                                    </div>
                                    <span className="text-sm font-bold">{inflation}%</span>
                                </div>
                                <Slider value={[inflation]} min={0} max={10} step={0.1} onValueChange={(v) => setInflation(v[0])} />
                            </div>

                            <div className="space-y-3">
                                <div className="flex justify-between">
                                    <div className="flex items-center gap-2">
                                        <Label>Safe Withdrawal Rate (SWR)</Label>
                                        <HelpTooltip content="Percentage of portfolio you can withdraw annually. The '4% Rule' is standard." />
                                    </div>
                                    <span className="text-sm font-bold">{swr}%</span>
                                </div>
                                <Slider value={[swr]} min={2} max={6} step={0.1} onValueChange={(v) => setSwr(v[0])} />
                            </div>
                        </div>

                    </CardContent>
                </Card>
            </div>

            {/* Main Calculation & Visuals */}
            <div className="lg:col-span-8 space-y-6">

                {/* Key Metrics Cards */}
                <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                    <Card className="glass-card border-none bg-orange-500/10">
                        <CardHeader className="pb-2">
                            <CardTitle className="text-sm font-medium text-orange-200 flex items-center gap-2">
                                <Target className="h-4 w-4" />
                                FIRE Number
                            </CardTitle>
                        </CardHeader>
                        <CardContent>
                            <div className="text-2xl font-bold text-orange-400">{formatCurrency(fireNumber)}</div>
                            <p className="text-xs text-muted-foreground mt-1">Target Portfolio</p>
                        </CardContent>
                    </Card>

                    <Card className="glass-card border-none bg-green-500/10">
                        <CardHeader className="pb-2">
                            <CardTitle className="text-sm font-medium text-green-200 flex items-center gap-2">
                                <Wallet className="h-4 w-4" />
                                Time to FIRE
                            </CardTitle>
                        </CardHeader>
                        <CardContent>
                            <div className="text-2xl font-bold text-green-400">{yearsToFire} <span className="text-sm font-normal text-muted-foreground">Years</span></div>
                            <p className="text-xs text-muted-foreground mt-1">Age: {reachFireAge || 'N/A'}</p>
                        </CardContent>
                    </Card>

                    <Card className="glass-card border-none bg-blue-500/10">
                        <CardHeader className="pb-2">
                            <CardTitle className="text-sm font-medium text-blue-200 flex items-center gap-2">
                                <DollarSign className="h-4 w-4" />
                                Real Return
                            </CardTitle>
                        </CardHeader>
                        <CardContent>
                            <div className="text-2xl font-bold text-blue-400">
                                {(((1 + nominalReturn / 100) / (1 + inflation / 100) - 1) * 100).toFixed(2)}%
                            </div>
                            <p className="text-xs text-muted-foreground mt-1">Inflation Adjusted</p>
                        </CardContent>
                    </Card>
                </div>

                {/* Chart */}
                <Card className="glass-card border-none shadow-xl h-[500px] flex flex-col">
                    <CardHeader>
                        <CardTitle className="text-xl gradient-text">Path to Financial Independence</CardTitle>
                    </CardHeader>
                    <CardContent className="flex-1 min-h-0">
                        <ResponsiveContainer width="100%" height="100%">
                            <ComposedChart data={chartData} margin={{ top: 30, right: 20, left: 20, bottom: 5 }}>
                                <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.1)" vertical={false} />
                                <XAxis
                                    dataKey="age"
                                    stroke="#9ca3af"
                                    tickLine={false}
                                    axisLine={false}
                                    label={{ value: 'Age', position: 'insideBottomRight', offset: -5, fill: '#9ca3af' }}
                                    type="number"
                                    domain={['dataMin', 'dataMax']}
                                />
                                <YAxis
                                    stroke="#9ca3af"
                                    tickLine={false}
                                    axisLine={false}
                                    tickFormatter={(value) => `$${value / 1000}k`}
                                />
                                <Tooltip
                                    contentStyle={{ backgroundColor: 'rgba(23, 23, 23, 0.9)', borderRadius: '8px', border: '1px solid rgba(255,255,255,0.1)' }}
                                    formatter={(value: number, name: string) => [formatCurrency(value), name]}
                                    labelFormatter={(age) => `Age ${age}`}
                                />
                                <Legend wrapperStyle={{ paddingTop: '20px' }} />

                                {reachFireAge && (
                                    <ReferenceLine x={reachFireAge} stroke="#22c55e" strokeDasharray="3 3" label={{ position: 'top', value: `FIRE Age: ${reachFireAge}`, fill: '#22c55e', fontSize: 12, dy: -10 }} />
                                )}

                                {/* Labels for the lines (using invisible ReferenceLines) */}
                                <ReferenceLine y={fireNumber} stroke="none" label={{ position: 'insideRight', value: 'FIRE', fill: '#f97316', fontSize: 12, dy: -12, fontWeight: 'bold' }} />
                                <ReferenceLine y={fatFireNumber} stroke="none" label={{ position: 'insideRight', value: 'Fat FIRE', fill: '#a855f7', fontSize: 12, dy: -12, fontWeight: 'bold' }} />
                                <ReferenceLine y={leanFireNumber} stroke="none" label={{ position: 'insideRight', value: 'Lean FIRE', fill: '#ef4444', fontSize: 12, dy: -12, fontWeight: 'bold' }} />

                                <Line
                                    type="monotone"
                                    dataKey="fatFire"
                                    name="Fat FIRE"
                                    stroke="#a855f7"
                                    strokeDasharray="3 3"
                                    strokeWidth={2}
                                    dot={false}
                                />
                                <Line
                                    type="monotone"
                                    dataKey="fireTarget"
                                    name="FIRE"
                                    stroke="#f97316"
                                    strokeDasharray="3 3"
                                    strokeWidth={2}
                                    dot={false}
                                />
                                <Line
                                    type="monotone"
                                    dataKey="leanFire"
                                    name="Lean FIRE"
                                    stroke="#ef4444"
                                    strokeDasharray="3 3"
                                    strokeWidth={2}
                                    dot={false}
                                />
                                <Line
                                    type="monotone"
                                    dataKey="netWorth"
                                    name="Projected Net Worth"
                                    stroke="#22c55e"
                                    strokeWidth={3}
                                    dot={false}
                                />
                            </ComposedChart>
                        </ResponsiveContainer>
                    </CardContent>
                </Card>

            </div>

            {/* Definitions Section */}
            <div className="lg:col-span-12 mt-6">
                <Card className="glass-card border-none shadow-xl">
                    <CardHeader>
                        <CardTitle className="text-xl gradient-text">Definitions</CardTitle>
                    </CardHeader>
                    <CardContent className="grid grid-cols-1 md:grid-cols-3 gap-6">
                        <div className="space-y-2">
                            <h3 className="font-bold text-orange-400 flex items-center gap-2">
                                <Flame className="h-4 w-4" /> FIRE
                            </h3>
                            <p className="text-sm text-muted-foreground leading-relaxed">
                                <strong>Financial Independence, Retire Early</strong>. The point where your investment portfolio can indefinitely support your annual expenses.
                                Typically reached when you have <strong>25x</strong> your annual spending invested, based on the 4% Safe Withdrawal Rate rule.
                            </p>
                        </div>

                        <div className="space-y-2">
                            <h3 className="font-bold text-red-400 flex items-center gap-2">
                                <Target className="h-4 w-4" /> Lean FIRE
                            </h3>
                            <p className="text-sm text-muted-foreground leading-relaxed">
                                A minimalist approach to financial independence. The target is lower (usually <strong>80%</strong> of standard expenses),
                                covering only essential living costs like housing, food, and healthcare. It requires a stricter budget but allows for faster retirement.
                            </p>
                        </div>

                        <div className="space-y-2">
                            <h3 className="font-bold text-purple-400 flex items-center gap-2">
                                <Wallet className="h-4 w-4" /> Fat FIRE
                            </h3>
                            <p className="text-sm text-muted-foreground leading-relaxed">
                                A more luxurious path to financial independence. The target is significantly higher (typically <strong>1.5x</strong> standard expenses)
                                to support a higher standard of living, frequent travel, and indulgences without financial stress.
                            </p>
                        </div>
                    </CardContent>
                </Card>
            </div>

        </div>
    );
}
