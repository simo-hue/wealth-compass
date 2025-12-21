import { useState } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogTrigger } from '@/components/ui/dialog';
import { Plus, Trash2, Bitcoin } from 'lucide-react';
import type { CryptoHolding } from '@/types/finance';
import { cn } from '@/lib/utils';

interface CryptoTableProps {
  holdings: CryptoHolding[];
  onAdd: (holding: Omit<CryptoHolding, 'id' | 'createdAt' | 'updatedAt'>) => void;
  onUpdate: (id: string, updates: Partial<CryptoHolding>) => void;
  onDelete: (id: string) => void;
}

export function CryptoTable({ holdings, onAdd, onUpdate, onDelete }: CryptoTableProps) {
  const [open, setOpen] = useState(false);
  const [form, setForm] = useState({
    symbol: '',
    name: '',
    quantity: 0,
    avgBuyPrice: 0,
    currentPrice: 0,
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    onAdd(form);
    setForm({ symbol: '', name: '', quantity: 0, avgBuyPrice: 0, currentPrice: 0 });
    setOpen(false);
  };

  const formatCurrency = (value: number) =>
    new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(value);

  const getGainLoss = (h: CryptoHolding) => {
    const costBasis = h.quantity * h.avgBuyPrice;
    const currentValue = h.quantity * h.currentPrice;
    const gain = currentValue - costBasis;
    const percent = costBasis > 0 ? (gain / costBasis) * 100 : 0;
    return { costBasis, currentValue, gain, percent };
  };

  return (
    <Card className="glass-card">
      <CardHeader className="flex flex-row items-center justify-between">
        <CardTitle className="text-lg font-semibold flex items-center gap-2">
          <Bitcoin className="h-5 w-5 text-warning" />
          Crypto Holdings
        </CardTitle>
        <Dialog open={open} onOpenChange={setOpen}>
          <DialogTrigger asChild>
            <Button size="sm" className="gradient-primary">
              <Plus className="h-4 w-4 mr-1" /> Add
            </Button>
          </DialogTrigger>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Add Crypto Holding</DialogTitle>
            </DialogHeader>
            <form onSubmit={handleSubmit} className="space-y-4">
              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label>Symbol</Label>
                  <Input value={form.symbol} onChange={(e) => setForm({ ...form, symbol: e.target.value.toUpperCase() })} placeholder="BTC" />
                </div>
                <div className="space-y-2">
                  <Label>Name</Label>
                  <Input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} placeholder="Bitcoin" />
                </div>
              </div>
              <div className="grid grid-cols-3 gap-4">
                <div className="space-y-2">
                  <Label>Quantity</Label>
                  <Input type="number" step="any" value={form.quantity} onChange={(e) => setForm({ ...form, quantity: +e.target.value })} />
                </div>
                <div className="space-y-2">
                  <Label>Avg Buy Price</Label>
                  <Input type="number" step="any" value={form.avgBuyPrice} onChange={(e) => setForm({ ...form, avgBuyPrice: +e.target.value })} />
                </div>
                <div className="space-y-2">
                  <Label>Current Price</Label>
                  <Input type="number" step="any" value={form.currentPrice} onChange={(e) => setForm({ ...form, currentPrice: +e.target.value })} />
                </div>
              </div>
              <Button type="submit" className="w-full gradient-primary">Add Crypto</Button>
            </form>
          </DialogContent>
        </Dialog>
      </CardHeader>
      <CardContent>
        {holdings.length === 0 ? (
          <div className="text-center py-8 text-muted-foreground">No crypto holdings yet. Add your first one!</div>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Symbol</TableHead>
                <TableHead>Name</TableHead>
                <TableHead className="text-right">Quantity</TableHead>
                <TableHead className="text-right">Avg Buy</TableHead>
                <TableHead className="text-right">Current</TableHead>
                <TableHead className="text-right">Value</TableHead>
                <TableHead className="text-right">Gain/Loss</TableHead>
                <TableHead></TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {holdings.map((h) => {
                const { currentValue, gain, percent } = getGainLoss(h);
                return (
                  <TableRow key={h.id}>
                    <TableCell className="font-mono font-medium">{h.symbol}</TableCell>
                    <TableCell>{h.name}</TableCell>
                    <TableCell className="text-right">{h.quantity.toLocaleString()}</TableCell>
                    <TableCell className="text-right">{formatCurrency(h.avgBuyPrice)}</TableCell>
                    <TableCell className="text-right">{formatCurrency(h.currentPrice)}</TableCell>
                    <TableCell className="text-right">{formatCurrency(currentValue)}</TableCell>
                    <TableCell className={cn('text-right font-medium', gain >= 0 ? 'text-success' : 'text-destructive')}>
                      {formatCurrency(gain)} ({percent.toFixed(1)}%)
                    </TableCell>
                    <TableCell>
                      <Button variant="ghost" size="icon" onClick={() => onDelete(h.id)}>
                        <Trash2 className="h-4 w-4 text-destructive" />
                      </Button>
                    </TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  );
}
