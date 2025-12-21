import { useState } from 'react';
import { useFinance } from '@/contexts/FinanceContext';
import { InvestmentTable } from '@/components/dashboard/InvestmentTable';
import { AllocationChart } from '@/components/dashboard/AllocationChart';
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card';
import { TrendingUp, PieChart, FileSpreadsheet } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { exportToCsv } from '@/lib/exportUtils';
import { format } from 'date-fns';

export default function InvestmentsPage() {
    const finance = useFinance();

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
        <div className="min-h-screen bg-background dark p-6 space-y-8">
            <div className="flex justify-between items-center">
                <div>
                    <h1 className="text-3xl font-bold text-gradient">Investments</h1>
                    <p className="text-muted-foreground">Manage your stock and ETF portfolio</p>
                </div>
                <Button variant="outline" onClick={handleExportCsv}>
                    <FileSpreadsheet className="h-4 w-4 mr-2" /> Export CSV
                </Button>
            </div>

            <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
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
                    <Card className="glass-card">
                        <CardHeader>
                            <CardTitle className="flex items-center gap-2"><PieChart className="h-4 w-4" /> Allocation</CardTitle>
                        </CardHeader>
                        <CardContent>
                            <AllocationChart investments={finance.data.investments} groupBy="sector" />
                        </CardContent>
                    </Card>
                </div>
            </div>
        </div>
    );
}
