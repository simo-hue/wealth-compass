import { useState } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogTrigger } from '@/components/ui/dialog';
import { Plus, Trash2, CreditCard } from 'lucide-react';
import type { Liability } from '@/types/finance';

interface LiabilitiesTableProps {
  liabilities: Liability[];
  onAdd: (liability: Omit<Liability, 'id' | 'createdAt' | 'updatedAt'>) => void;
  onUpdate: (id: string, updates: Partial<Liability>) => void;
  onDelete: (id: string) => void;
}

export function LiabilitiesTable({ liabilities, onAdd, onUpdate, onDelete }: LiabilitiesTableProps) {
  const [open, setOpen] = useState(false);
  const [form, setForm] = useState({
    type: 'loan' as Liability['type'],
    name: '',
    principal: 0,
    currentBalance: 0,
    interestRate: 0,
    monthlyPayment: 0,
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    onAdd(form);
    setForm({ type: 'loan', name: '', principal: 0, currentBalance: 0, interestRate: 0, monthlyPayment: 0 });
    setOpen(false);
  };

  const formatCurrency = (value: number) =>
    new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(value);

  const totalDebt = liabilities.reduce((sum, l) => sum + l.currentBalance, 0);

  return (
    <Card className="glass-card">
      <CardHeader className="flex flex-row items-center justify-between">
        <CardTitle className="text-lg font-semibold flex items-center gap-2">
          <CreditCard className="h-5 w-5 text-destructive" />
          Liabilities
          <span className="text-sm font-normal text-muted-foreground ml-2">
            Total: {formatCurrency(totalDebt)}
          </span>
        </CardTitle>
        <Dialog open={open} onOpenChange={setOpen}>
          <DialogTrigger asChild>
            <Button size="sm" className="gradient-primary">
              <Plus className="h-4 w-4 mr-1" /> Add
            </Button>
          </DialogTrigger>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Add Liability</DialogTitle>
            </DialogHeader>
            <form onSubmit={handleSubmit} className="space-y-4">
              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label>Type</Label>
                  <Select value={form.type} onValueChange={(v) => setForm({ ...form, type: v as Liability['type'] })}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="mortgage">Mortgage</SelectItem>
                      <SelectItem value="loan">Loan</SelectItem>
                      <SelectItem value="credit_card">Credit Card</SelectItem>
                      <SelectItem value="other">Other</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-2">
                  <Label>Name</Label>
                  <Input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} placeholder="Home Mortgage" />
                </div>
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label>Principal</Label>
                  <Input type="number" value={form.principal} onChange={(e) => setForm({ ...form, principal: +e.target.value })} />
                </div>
                <div className="space-y-2">
                  <Label>Current Balance</Label>
                  <Input type="number" value={form.currentBalance} onChange={(e) => setForm({ ...form, currentBalance: +e.target.value })} />
                </div>
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label>Interest Rate (%)</Label>
                  <Input type="number" step="0.01" value={form.interestRate} onChange={(e) => setForm({ ...form, interestRate: +e.target.value })} />
                </div>
                <div className="space-y-2">
                  <Label>Monthly Payment</Label>
                  <Input type="number" value={form.monthlyPayment} onChange={(e) => setForm({ ...form, monthlyPayment: +e.target.value })} />
                </div>
              </div>
              <Button type="submit" className="w-full gradient-primary">Add Liability</Button>
            </form>
          </DialogContent>
        </Dialog>
      </CardHeader>
      <CardContent>
        {liabilities.length === 0 ? (
          <div className="text-center py-8 text-muted-foreground">No liabilities. Great job staying debt-free!</div>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Name</TableHead>
                <TableHead>Type</TableHead>
                <TableHead className="text-right">Principal</TableHead>
                <TableHead className="text-right">Balance</TableHead>
                <TableHead className="text-right">Rate</TableHead>
                <TableHead className="text-right">Monthly</TableHead>
                <TableHead></TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {liabilities.map((l) => (
                <TableRow key={l.id}>
                  <TableCell className="font-medium">{l.name}</TableCell>
                  <TableCell className="capitalize">{l.type.replace('_', ' ')}</TableCell>
                  <TableCell className="text-right">{formatCurrency(l.principal)}</TableCell>
                  <TableCell className="text-right text-destructive">{formatCurrency(l.currentBalance)}</TableCell>
                  <TableCell className="text-right">{l.interestRate}%</TableCell>
                  <TableCell className="text-right">{formatCurrency(l.monthlyPayment)}</TableCell>
                  <TableCell>
                    <Button variant="ghost" size="icon" onClick={() => onDelete(l.id)}>
                      <Trash2 className="h-4 w-4 text-destructive" />
                    </Button>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  );
}
