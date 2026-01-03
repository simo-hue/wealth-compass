import { useState } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogTrigger } from '@/components/ui/dialog';
import { Plus, Trash2, CreditCard } from 'lucide-react';
import type { Liability } from '@/types/finance';
import { useSettings } from '@/contexts/SettingsContext';
import { cn } from '@/lib/utils';

interface LiabilitiesTableProps {
  liabilities: Liability[];
  onAdd: (liability: Omit<Liability, 'id' | 'createdAt' | 'updatedAt'>) => void;
  onUpdate: (id: string, updates: Partial<Liability>) => void;
  onDelete: (id: string) => void;
}

export function LiabilitiesTable({ liabilities, onAdd, onUpdate, onDelete }: LiabilitiesTableProps) {
  const { formatCurrency, convertCurrency, isPrivacyMode, currency: baseCurrency } = useSettings();
  const [open, setOpen] = useState(false);
  const [form, setForm] = useState({
    type: 'loan' as Liability['type'],
    name: '',
    principal: 0,
    currentBalance: 0,
    currency: 'USD',
    interestRate: 0,
    monthlyPayment: 0,
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    onAdd(form);
    setForm({ type: 'loan', name: '', principal: 0, currentBalance: 0, currency: 'USD', interestRate: 0, monthlyPayment: 0 });
    setOpen(false);
  };

  const totalDebt = liabilities.reduce((sum, l) => sum + convertCurrency(l.currentBalance, l.currency), 0);


  return (
    <Card className="glass-card">
      <CardHeader className="flex flex-row items-center justify-between">
        <CardTitle className="text-lg font-semibold flex items-center gap-2">
          <CreditCard className="h-5 w-5 text-destructive" />
          Liabilities
          <span className="text-sm font-normal text-muted-foreground ml-2">
            Total: {isPrivacyMode ? "****" : formatCurrency(totalDebt)}
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
              <DialogDescription>Enter the details of your liability (e.g. Mortgage, Loan).</DialogDescription>
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
                  <Label>Currency</Label>
                  <Select value={form.currency} onValueChange={(v) => setForm({ ...form, currency: v })}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="USD">USD ($)</SelectItem>
                      <SelectItem value="EUR">EUR (€)</SelectItem>
                      <SelectItem value="GBP">GBP (£)</SelectItem>
                      <SelectItem value="CHF">CHF (Fr)</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-2">
                  <Label>Monthly Payment</Label>
                  <Input type="number" value={form.monthlyPayment} onChange={(e) => setForm({ ...form, monthlyPayment: +e.target.value })} />
                </div>
              </div>
              <div className="space-y-2">
                <Label>Interest Rate (%)</Label>
                <Input type="number" step="0.01" value={form.interestRate} onChange={(e) => setForm({ ...form, interestRate: +e.target.value })} />
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
          <>
            {/* Mobile View (Cards) */}
            <div className="md:hidden space-y-4">
              {liabilities.map((l) => (
                <Card key={l.id} className="p-4 bg-card/50 border-input">
                  <div className="flex justify-between items-start mb-3">
                    <div>
                      <div className="font-bold text-lg">{l.name}</div>
                      <Badge variant="secondary" className="text-[10px] h-5 px-1.5 uppercase mt-1">
                        {l.type.replace('_', ' ')}
                      </Badge>
                    </div>
                    <div className="text-right">
                      <div className="font-bold text-base text-destructive">
                        {isPrivacyMode ? "****" : formatCurrency(l.currentBalance, l.currency)}
                      </div>
                      {l.currency && l.currency !== baseCurrency && (
                        <div className="text-[10px] text-muted-foreground">
                          {new Intl.NumberFormat('en-US', { style: 'currency', currency: l.currency }).format(l.currentBalance)}
                        </div>
                      )}
                    </div>
                  </div>

                  <div className="grid grid-cols-2 gap-2 text-xs mb-3 p-2 bg-muted/20 rounded-md">
                    <div>
                      <span className="text-muted-foreground">Monthly Payment</span>
                      <div className="font-medium">{isPrivacyMode ? "****" : formatCurrency(l.monthlyPayment, l.currency)}</div>
                    </div>
                    <div>
                      <span className="text-muted-foreground">Props / Rate</span>
                      <div className="font-medium">
                        {isPrivacyMode ? "****" : formatCurrency(l.principal, l.currency)} @ {l.interestRate}%
                      </div>
                    </div>
                  </div>

                  <div className="flex justify-end gap-2">
                    <Button variant="ghost" size="sm" className="h-8 text-destructive hover:text-destructive hover:bg-destructive/10" onClick={() => onDelete(l.id)}>
                      <Trash2 className="h-3.5 w-3.5 mr-1.5" /> Remove
                    </Button>
                  </div>
                </Card>
              ))}
            </div>

            {/* Desktop View (Table) */}
            <div className="hidden md:block overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Name</TableHead>
                    <TableHead className="hidden sm:table-cell">Type</TableHead>
                    <TableHead className="text-right">Principal</TableHead>
                    <TableHead className="text-right">Balance</TableHead>
                    <TableHead className="text-right hidden sm:table-cell">Rate</TableHead>
                    <TableHead className="text-right">Monthly</TableHead>
                    <TableHead></TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {liabilities.map((l) => (
                    <TableRow key={l.id}>
                      <TableCell className="font-medium">{l.name}</TableCell>
                      <TableCell className="capitalize hidden sm:table-cell">{l.type.replace('_', ' ')}</TableCell>
                      <TableCell className="text-right">{isPrivacyMode ? "****" : formatCurrency(l.principal, l.currency)}</TableCell>
                      <TableCell className="text-right text-destructive">
                        <div className="flex flex-col items-end">
                          <span>{isPrivacyMode ? "****" : formatCurrency(l.currentBalance, l.currency)}</span>
                          {l.currency && l.currency !== baseCurrency && (
                            <span className="text-[10px] text-muted-foreground">
                              {new Intl.NumberFormat('en-US', { style: 'currency', currency: l.currency }).format(l.currentBalance)}
                            </span>
                          )}
                        </div>
                      </TableCell>
                      <TableCell className="text-right hidden sm:table-cell">{l.interestRate}%</TableCell>
                      <TableCell className="text-right">{isPrivacyMode ? "****" : formatCurrency(l.monthlyPayment, l.currency)}</TableCell>
                      <TableCell>
                        <Button variant="ghost" size="icon" onClick={() => onDelete(l.id)}>
                          <Trash2 className="h-4 w-4 text-destructive" />
                        </Button>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          </>
        )}
      </CardContent>
    </Card >
  );
}
