import { useState } from 'react';
import { useFinance } from '@/contexts/FinanceContext';
import { InvestmentTable } from '@/components/dashboard/InvestmentTable';
import { AllocationChart } from '@/components/dashboard/AllocationChart';
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card';
import { TrendingUp, PieChart, FileSpreadsheet } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { exportToCsv } from '@/lib/exportUtils';
import { format } from 'date-fns';
import { useSettings } from '@/contexts/SettingsContext';
import { cn } from '@/lib/utils';

export default function InvestmentsPage() {
    const finance = useFinance();
    const { isPrivacyMode } = useSettings();

    const handleExportCsv = () => {
        const exportData = finance.data.investments.map(inv => ({
            Ticker: inv.symbol,
            Name: inv.name,
            Type: inv.type,
            Quantity: inv.quantity,
            'Avg Buy Price': inv.costBasis / inv.quantity, // approximate avg
            'Current Price': inv.currentValue / inv.quantity, // approximate current
            'Total Value': inv.currentValue,
            'Profit/Loss': inv.currentValue - inv.costBasis
        }));
        const filename = `investments_portfolio_${format(new Date(), 'yyyy-MM-dd')}`;
        exportToCsv(exportData, filename);
    };

    return (
        <div className="min-h-screen bg-background dark p-4 md:p-6 space-y-8">
            <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
                <div>
                    <h1 className="text-3xl font-bold text-gradient">Investments</h1>
                    <p className={cn("text-muted-foreground", isPrivacyMode && "blur-sm select-none")}>Manage your stock and ETF portfolio</p>
                </div>
                <div className="w-full md:w-auto">
                    <Button variant="outline" onClick={handleExportCsv} className={cn("w-full md:w-auto", isPrivacyMode && "blur-sm select-none pointer-events-none")}>
                        <FileSpreadsheet className="h-4 w-4 mr-2" /> Export CSV
                    </Button>
                </div>
            </div>

            <div className="flex flex-col-reverse gap-6 lg:grid lg:grid-cols-3">
                {/* Main List */}
                <div className="lg:col-span-2 space-y-6">
                    <InvestmentTable
                        investments={finance.data.investments}
                        onAdd={finance.addInvestment}
                        onUpdate={finance.updateInvestment}
                        onDelete={finance.deleteInvestment}
                    />
                </div>

                {/* Sidebar / Stats */}
                <div className="space-y-6">
                    <AllocationChart investments={finance.data.investments} groupBy="sector" />
                </div>
            </div>
        </div>
    );
}
