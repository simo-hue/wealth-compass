import { useFinance } from '@/contexts/FinanceContext';
import { CryptoTable } from '@/components/dashboard/CryptoTable';
import { FileSpreadsheet } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { exportToCsv } from '@/lib/exportUtils';
import { format } from 'date-fns';

export default function CryptoPage() {
    const finance = useFinance();

    const handleExportCsv = () => {
        const exportData = finance.data.crypto.map(c => ({
            Symbol: c.symbol,
            Name: c.name,
            Quantity: c.quantity,
            'Avg Buy Price': c.avgBuyPrice,
            'Current Price': c.currentPrice,
            'Total Value': c.quantity * c.currentPrice
        }));
        const filename = `crypto_portfolio_${format(new Date(), 'yyyy-MM-dd')}`;
        exportToCsv(exportData, filename);
    };

    return (
        <div className="min-h-screen bg-background dark p-6 space-y-8">
            <div className="flex justify-between items-center">
                <div>
                    <h1 className="text-3xl font-bold text-gradient">Crypto Assets</h1>
                    <p className="text-muted-foreground">Manage your cryptocurrency holdings</p>
                </div>
                <Button variant="outline" onClick={handleExportCsv}>
                    <FileSpreadsheet className="h-4 w-4 mr-2" /> Export CSV
                </Button>
            </div>

            <CryptoTable
                holdings={finance.data.crypto}
                onAdd={finance.addCrypto}
                onUpdate={finance.updateCrypto}
                onDelete={finance.deleteCrypto}
            />
        </div>
    );
}
