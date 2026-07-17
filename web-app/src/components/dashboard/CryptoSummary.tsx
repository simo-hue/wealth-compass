import { useMemo } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { useFinance } from '@/contexts/FinanceContext';
import { useSettings } from '@/contexts/SettingsContext';
import { cn } from '@/lib/utils';
import { Wallet, TrendingUp, TrendingDown, DollarSign } from 'lucide-react';

export function CryptoSummary() {
    const { data } = useFinance();
    const { formatCurrency, isPrivacyMode } = useSettings();

    const summary = useMemo(() => {
        const totalInvested = data.crypto.reduce((sum, c) => sum + (c.quantity * c.avgBuyPrice), 0);
        const totalValue = data.crypto.reduce((sum, c) => sum + (c.quantity * c.currentPrice), 0);
        const totalGain = totalValue - totalInvested;
        const totalGainPercent = totalInvested > 0 ? (totalGain / totalInvested) * 100 : 0;

        return {
            totalValue,
            totalGain,
            totalGainPercent
        };
    }, [data.crypto]);

    return (
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-6">
            {/* Total Balance Card */}
            <Card className="glass-card md:col-span-2 relative overflow-hidden">
                <div className="absolute top-0 right-0 p-4 opacity-10">
                    <Wallet className="h-24 w-24" />
                </div>
                <CardHeader className="pb-2">
                    <CardTitle className="text-sm font-medium text-muted-foreground flex items-center gap-2">
                        <DollarSign className="h-4 w-4" />
                        Total Crypto Balance
                    </CardTitle>
                </CardHeader>
                <CardContent>
                    <div className={cn("text-4xl font-bold tracking-tight", isPrivacyMode && "blur-md select-none")}>
                        {isPrivacyMode ? "$**,***.**" : formatCurrency(summary.totalValue, 'USD')}
                    </div>
                    <p className="text-xs text-muted-foreground mt-1">
                        Current market value of all holdings
                    </p>
                </CardContent>
            </Card>

            {/* Total Profit/Loss Card */}
            <Card className="glass-card relative overflow-hidden">
                <CardHeader className="pb-2">
                    <CardTitle className="text-sm font-medium text-muted-foreground flex items-center gap-2">
                        {summary.totalGain >= 0 ? <TrendingUp className="h-4 w-4 text-success" /> : <TrendingDown className="h-4 w-4 text-destructive" />}
                        Total Profit/Loss
                    </CardTitle>
                </CardHeader>
                <CardContent>
                    <div className={cn("text-2xl font-bold", summary.totalGain >= 0 ? "text-success" : "text-destructive", isPrivacyMode && "blur-md select-none text-foreground")}>
                        {isPrivacyMode ? "+$*,***.**" : `${summary.totalGain >= 0 ? '+' : ''}${formatCurrency(summary.totalGain, 'USD')}`}
                    </div>
                    <div className={cn("flex items-center text-xs mt-1", summary.totalGain >= 0 ? "text-success" : "text-destructive", isPrivacyMode && "blur-sm opacity-50")}>
                        <span className="font-medium">
                            {summary.totalGain >= 0 ? '+' : ''}{summary.totalGainPercent.toFixed(2)}%
                        </span>
                        <span className="text-muted-foreground ml-1">all time</span>
                    </div>
                </CardContent>
            </Card>
        </div>
    );
}
