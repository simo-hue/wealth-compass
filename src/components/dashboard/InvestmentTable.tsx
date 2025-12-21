import { useState } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogTrigger } from '@/components/ui/dialog';
import { Plus, Trash2, TrendingUp } from 'lucide-react';
import type { Investment } from '@/types/finance';
import { cn } from '@/lib/utils';

interface InvestmentTableProps {
  investments: Investment[];
  onAdd: (investment: Omit<Investment, 'id' | 'createdAt' | 'updatedAt'>) => void;
  onUpdate: (id: string, updates: Partial<Investment>) => void;
  onDelete: (id: string) => void;
}

export function InvestmentTable({ investments, onAdd, onUpdate, onDelete }: InvestmentTableProps) {
  const [open, setOpen] = useState(false);
  const [form, setForm] = useState({
    type: 'stock' as Investment['type'],
    symbol: '',
    name: '',
    quantity: 0,
    costBasis: 0,
    currentValue: 0,
    geography: '',
    sector: '',
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    onAdd(form);
    setForm({ type: 'stock', symbol: '', name: '', quantity: 0, costBasis: 0, currentValue: 0, geography: '', sector: '' });
    setOpen(false);
  };

  const formatCurrency = (value: number) =>
    new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(value);

  const getGainLoss = (inv: Investment) => {
    const gain = inv.currentValue - inv.costBasis;
    const percent = inv.costBasis > 0 ? (gain / inv.costBasis) * 100 : 0;
    return { gain, percent };
  };

  return (
    <Card className="glass-card">
      <CardHeader className="flex flex-row items-center justify-between">
        <CardTitle className="text-lg font-semibold flex items-center gap-2">
          <TrendingUp className="h-5 w-5 text-primary" />
          Investment Portfolio
        </CardTitle>
        <Dialog open={open} onOpenChange={setOpen}>
          <DialogTrigger asChild>
            <Button size="sm" className="gradient-primary">
              <Plus className="h-4 w-4 mr-1" /> Add
            </Button>
          </DialogTrigger>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Add Investment</DialogTitle>
            </DialogHeader>
            <form onSubmit={handleSubmit} className="space-y-4">
              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label>Type</Label>
                  <Select value={form.type} onValueChange={(v) => setForm({ ...form, type: v as Investment['type'] })}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="stock">Stock</SelectItem>
                      <SelectItem value="etf">ETF</SelectItem>
                      <SelectItem value="bond">Bond</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-2">
                  <Label>Symbol</Label>
                  <Input value={form.symbol} onChange={(e) => setForm({ ...form, symbol: e.target.value.toUpperCase() })} placeholder="AAPL" />
                </div>
              </div>
              <div className="space-y-2">
                <Label>Name</Label>
                <Input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} placeholder="Apple Inc." />
              </div>
              <div className="grid grid-cols-3 gap-4">
                <div className="space-y-2">
                  <Label>Quantity</Label>
                  <Input type="number" value={form.quantity} onChange={(e) => setForm({ ...form, quantity: +e.target.value })} />
                </div>
                <div className="space-y-2">
                  <Label>Cost Basis</Label>
                  <Input type="number" value={form.costBasis} onChange={(e) => setForm({ ...form, costBasis: +e.target.value })} />
                </div>
                <div className="space-y-2">
                  <Label>Current Value</Label>
                  <Input type="number" value={form.currentValue} onChange={(e) => setForm({ ...form, currentValue: +e.target.value })} />
                </div>
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label>Geography</Label>
                  <Input value={form.geography} onChange={(e) => setForm({ ...form, geography: e.target.value })} placeholder="US" />
                </div>
                <div className="space-y-2">
                  <Label>Sector</Label>
                  <Input value={form.sector} onChange={(e) => setForm({ ...form, sector: e.target.value })} placeholder="Technology" />
                </div>
              </div>
              <Button type="submit" className="w-full gradient-primary">Add Investment</Button>
            </form>
          </DialogContent>
        </Dialog>
      </CardHeader>
      <CardContent>
        {investments.length === 0 ? (
          <div className="text-center py-8 text-muted-foreground">No investments yet. Add your first one!</div>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Symbol</TableHead>
                <TableHead>Name</TableHead>
                <TableHead>Type</TableHead>
                <TableHead className="text-right">Cost Basis</TableHead>
                <TableHead className="text-right">Current Value</TableHead>
                <TableHead className="text-right">Gain/Loss</TableHead>
                <TableHead></TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {investments.map((inv) => {
                const { gain, percent } = getGainLoss(inv);
                return (
                  <TableRow key={inv.id}>
                    <TableCell className="font-mono font-medium">{inv.symbol}</TableCell>
                    <TableCell>{inv.name}</TableCell>
                    <TableCell className="capitalize">{inv.type}</TableCell>
                    <TableCell className="text-right">{formatCurrency(inv.costBasis)}</TableCell>
                    <TableCell className="text-right">{formatCurrency(inv.currentValue)}</TableCell>
                    <TableCell className={cn('text-right font-medium', gain >= 0 ? 'text-success' : 'text-destructive')}>
                      {formatCurrency(gain)} ({percent.toFixed(1)}%)
                    </TableCell>
                    <TableCell>
                      <Button variant="ghost" size="icon" onClick={() => onDelete(inv.id)}>
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
