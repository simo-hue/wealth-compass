import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Calculator, TrendingUp, TrendingDown, Flame } from "lucide-react";
import { CompoundInterestCalculator } from "@/components/calculations/CompoundInterestCalculator";
import { MonteCarloSimulation } from "@/components/calculations/MonteCarloSimulation";
import InflationCalculator from "@/components/calculations/InflationCalculator";
import FIRECalculator from "@/components/calculations/FIRECalculator";

const CalculationsPage = () => {
    return (
        <div className="space-y-6 animate-fade-in p-4 md:p-6 pb-20">
            <div>
                <h1 className="text-3xl font-bold bg-gradient-to-r from-primary to-accent bg-clip-text text-transparent">
                    Financial Calculations
                </h1>
                <p className="text-muted-foreground mt-2">
                    Professional tools for your financial planning and analysis.
                </p>
            </div>

            <Tabs defaultValue="compound" className="w-full">
                <TabsList className="grid w-full grid-cols-2 md:grid-cols-4 h-auto md:h-10 lg:w-[800px]">
                    <TabsTrigger value="compound" className="flex items-center gap-2">
                        <TrendingUp className="h-4 w-4" />
                        <span className="hidden md:inline">Compound Interest</span>
                        <span className="md:hidden">Compound</span>
                    </TabsTrigger>
                    <TabsTrigger value="montecarlo" className="flex items-center gap-2">
                        <Calculator className="h-4 w-4" />
                        <span className="hidden md:inline">Monte Carlo</span>
                        <span className="md:hidden">Monte Carlo</span>
                    </TabsTrigger>
                    <TabsTrigger value="inflation" className="flex items-center gap-2">
                        <TrendingDown className="h-4 w-4" />
                        <span className="hidden md:inline">Inflation</span>
                        <span className="md:hidden">Inflation</span>
                    </TabsTrigger>
                    <TabsTrigger value="fire" className="flex items-center gap-2">
                        <Flame className="h-4 w-4" />
                        <span className="hidden md:inline">FIRE</span>
                        <span className="md:hidden">FIRE</span>
                    </TabsTrigger>
                </TabsList>

                <TabsContent value="compound" className="mt-6">
                    <CompoundInterestCalculator />
                </TabsContent>

                <TabsContent value="montecarlo" className="mt-6">
                    <MonteCarloSimulation />
                </TabsContent>

                <TabsContent value="inflation" className="mt-6">
                    <InflationCalculator />
                </TabsContent>

                <TabsContent value="fire" className="mt-6">
                    <FIRECalculator />
                </TabsContent>
            </Tabs>
        </div>
    );
};

export default CalculationsPage;
