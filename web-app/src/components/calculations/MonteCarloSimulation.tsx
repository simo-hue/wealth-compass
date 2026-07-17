
import { useState, useMemo, useCallback } from "react";
import { useIsMobile } from "@/hooks/use-mobile";
import { Card, CardHeader, CardTitle, CardContent } from "@/components/ui/card";
import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { Slider } from "@/components/ui/slider";
import { Button } from "@/components/ui/button";
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
import { Play } from "lucide-react";
import { HelpTooltip } from "@/components/ui/tooltip-helper";

export function MonteCarloSimulation() {
    const { formatCurrency } = useSettings();
    const isMobile = useIsMobile();

    // Inputs
    const [initialPortfolio, setInitialPortfolio] = useState(10000);
    const [monthlyContribution, setMonthlyContribution] = useState(500);
    const [expectedReturn, setExpectedReturn] = useState(8); // Mean return
    const [volatility, setVolatility] = useState(15); // Standard deviation
    const [years, setYears] = useState(20);
    const [simulationCount, setSimulationCount] = useState(500);

    // Box-Muller transform for normal distribution
    const randn_bm = () => {
        let u = 0, v = 0;
        while (u === 0) u = Math.random();
        while (v === 0) v = Math.random();
        return Math.sqrt(-2.0 * Math.log(u)) * Math.cos(2.0 * Math.PI * v);
    };

    const runSimulation = useCallback(() => {
        const results = [];
        const simulations = simulationCount;
        const timeStep = 1 / 12; // Monthly steps

        // Convert annual metrics to monthly for GBM
        // Drift (mu) - Volatility Drag = mu - (sigma^2)/2
        const annualMean = expectedReturn / 100;
        const annualVol = volatility / 100;
        // The drift term in the exponent for log-normal process
        const drift = (annualMean - 0.5 * Math.pow(annualVol, 2)) * timeStep;
        // Volatility term
        const vol = annualVol * Math.sqrt(timeStep);

        for (let sim = 0; sim < simulations; sim++) {
            let currentBalance = initialPortfolio;
            const simPath = [currentBalance];

            for (let month = 1; month <= years * 12; month++) {
                const randomShock = randn_bm();
                // Geometric Brownian Motion: S(t+1) = S(t) * exp((mu - 0.5*sigma^2)dt + sigma*sqrt(dt)*Z)
                const growthFactor = Math.exp(drift + vol * randomShock);

                // Apply growth first, then add contribution (contribution made at end of month)
                currentBalance = currentBalance * growthFactor + monthlyContribution;

                // Store only yearly data points to reduce chart complexity
                if (month % 12 === 0) {
                    simPath.push(currentBalance);
                }
            }
            results.push(simPath);
        }
        return results;
    }, [initialPortfolio, monthlyContribution, expectedReturn, volatility, years, simulationCount]);

    // Calculate percentiles from simulation results
    const chartData = useMemo(() => {
        const simulations = runSimulation();
        const data = [];
        const steps = years + 1; // 0 to years

        for (let year = 0; year < steps; year++) {
            const yearValues = simulations.map(sim => sim[year]).sort((a, b) => a - b);

            // Percentiles
            const p10 = yearValues[Math.floor(yearValues.length * 0.1)];
            const p50 = yearValues[Math.floor(yearValues.length * 0.5)];
            const p90 = yearValues[Math.floor(yearValues.length * 0.9)];

            data.push({
                year,
                p10: Math.round(p10),
                p50: Math.round(p50),
                p90: Math.round(p90),
            });
        }
        return data;
    }, [runSimulation, years]); // Depend on runSimulation so it updates when params change

    const finalResult = chartData[chartData.length - 1];

    return (
        <div className="grid gap-6 md:grid-cols-2">
            <Card>
                <CardHeader>
                    <CardTitle>Simulation Parameters</CardTitle>
                </CardHeader>
                <CardContent className="space-y-6">
                    <div className="space-y-2">
                        <div className="flex items-center gap-2">
                            <Label>Initial Portfolio</Label>
                            <HelpTooltip content="The total value of your investments at the start of the simulation." />
                        </div>
                        <div className="flex items-center gap-4">
                            <Input
                                type="number"
                                value={initialPortfolio}
                                onChange={(e) => setInitialPortfolio(Number(e.target.value))}
                                className="w-24"
                            />
                            <Slider
                                value={[initialPortfolio]}
                                onValueChange={(vals) => setInitialPortfolio(vals[0])}
                                max={100000}
                                step={100}
                                className="flex-1"
                            />
                        </div>
                    </div>

                    <div className="space-y-2">
                        <div className="flex items-center gap-2">
                            <Label>Monthly Contribution</Label>
                            <HelpTooltip content="The amount you plan to add to your investments every month." />
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
                        <div className="flex justify-between items-center">
                            <div className="flex items-center gap-2">
                                <Label>Expected Annual Return (%)</Label>
                                <HelpTooltip content="The average yearly growth rate you expect from your portfolio (Mean Return). For example, the S&P 500 historically averages around 7-10%." />
                            </div>
                            <span className="text-xs text-muted-foreground">Mean</span>
                        </div>
                        <div className="flex items-center gap-4">
                            <Input
                                type="number"
                                value={expectedReturn}
                                onChange={(e) => setExpectedReturn(Number(e.target.value))}
                                className="w-24"
                                step={0.1}
                            />
                            <Slider
                                value={[expectedReturn]}
                                onValueChange={(vals) => setExpectedReturn(vals[0])}
                                max={20}
                                step={0.1}
                                className="flex-1"
                            />
                        </div>
                    </div>

                    <div className="space-y-2">
                        <div className="flex justify-between items-center">
                            <div className="flex items-center gap-2">
                                <Label>Volatility (%)</Label>
                                <HelpTooltip content="A measure of how much your returns can fluctuate (Standard Deviation). Higher volatility means higher risk and wider potential outcomes." />
                            </div>
                            <span className="text-xs text-muted-foreground">Standard Deviation</span>
                        </div>
                        <div className="flex items-center gap-4">
                            <Input
                                type="number"
                                value={volatility}
                                onChange={(e) => setVolatility(Number(e.target.value))}
                                className="w-24"
                                step={0.1}
                            />
                            <Slider
                                value={[volatility]}
                                onValueChange={(vals) => setVolatility(vals[0])}
                                max={30}
                                step={0.1}
                                className="flex-1"
                            />
                        </div>
                    </div>

                    <div className="space-y-2">
                        <div className="flex items-center gap-2">
                            <Label>Time Horizon (Years)</Label>
                            <HelpTooltip content="The number of years you plan to hold these investments." />
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
                                max={40}
                                step={1}
                                className="flex-1"
                            />
                        </div>
                    </div>

                    <div className="mt-8 grid grid-cols-1 gap-4">
                        <Button className="w-full" onClick={() => { setSimulationCount(prev => prev === 500 ? 501 : 500) }}>
                            <Play className="mr-2 h-4 w-4" /> Run New Simulation
                        </Button>
                    </div>
                </CardContent>
            </Card>

            <Card>
                <CardHeader>
                    <CardTitle>Projected Outcomes</CardTitle>
                </CardHeader>
                <CardContent className="h-[300px] md:h-[500px] flex flex-col">
                    <div className="grid grid-cols-3 gap-2 mb-4 text-center">
                        <div className="p-2 rounded bg-red-500/10 border border-red-500/20">
                            <p className="text-xs text-muted-foreground">Conservative (10th)</p>
                            <p className="text-sm font-bold text-red-400">{formatCurrency(finalResult?.p10 || 0)}</p>
                        </div>
                        <div className="p-2 rounded bg-yellow-500/10 border border-yellow-500/20">
                            <p className="text-xs text-muted-foreground">Median (50th)</p>
                            <p className="text-sm font-bold text-yellow-400">{formatCurrency(finalResult?.p50 || 0)}</p>
                        </div>
                        <div className="p-2 rounded bg-green-500/10 border border-green-500/20">
                            <p className="text-xs text-muted-foreground">Optimistic (90th)</p>
                            <p className="text-sm font-bold text-green-400">{formatCurrency(finalResult?.p90 || 0)}</p>
                        </div>
                    </div>

                    <div className="flex-1 w-full min-h-0">
                        <ResponsiveContainer width="100%" height="100%">
                            <AreaChart data={chartData} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
                                <defs>
                                    <linearGradient id="colorP90" x1="0" y1="0" x2="0" y2="1">
                                        <stop offset="5%" stopColor="#22c55e" stopOpacity={0.1} />
                                        <stop offset="95%" stopColor="#22c55e" stopOpacity={0} />
                                    </linearGradient>
                                    <linearGradient id="colorP50" x1="0" y1="0" x2="0" y2="1">
                                        <stop offset="5%" stopColor="#eab308" stopOpacity={0.1} />
                                        <stop offset="95%" stopColor="#eab308" stopOpacity={0} />
                                    </linearGradient>
                                    <linearGradient id="colorP10" x1="0" y1="0" x2="0" y2="1">
                                        <stop offset="5%" stopColor="#ef4444" stopOpacity={0.1} />
                                        <stop offset="95%" stopColor="#ef4444" stopOpacity={0} />
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
                                    dataKey="p90"
                                    name="Optimistic (90th)"
                                    stroke="#22c55e"
                                    fill="url(#colorP90)"
                                    strokeDasharray="3 3"
                                />
                                <Area
                                    type="monotone"
                                    dataKey="p50"
                                    name="Median (50th)"
                                    stroke="#eab308"
                                    strokeWidth={2}
                                    fill="url(#colorP50)"
                                />
                                <Area
                                    type="monotone"
                                    dataKey="p10"
                                    name="Conservative (10th)"
                                    stroke="#ef4444"
                                    fill="url(#colorP10)"
                                    strokeDasharray="3 3"
                                />
                            </AreaChart>
                        </ResponsiveContainer>
                    </div>
                </CardContent>
            </Card>
        </div>
    );
}
