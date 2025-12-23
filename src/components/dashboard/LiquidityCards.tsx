import { useState } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogTrigger } from '@/components/ui/dialog';
import { Plus, Trash2, Wallet } from 'lucide-react';
import type { LiquidityAccount } from '@/types/finance';
import { useSettings } from '@/contexts/SettingsContext';
import { cn } from '@/lib/utils';

interface LiquidityCardsProps {
  accounts: LiquidityAccount[];
  onAdd: (account: Omit<LiquidityAccount, 'id' | 'createdAt' | 'updatedAt'>) => void;
  onUpdate: (id: string, updates: Partial<LiquidityAccount>) => void;
  onDelete: (id: string) => void;
}

export function LiquidityCards({ accounts, onAdd, onUpdate, onDelete }: LiquidityCardsProps) {
  const { formatCurrency, convertCurrency, isPrivacyMode, currency: baseCurrency } = useSettings();
  const [open, setOpen] = useState(false);
  const [form, setForm] = useState({
    type: 'checking' as LiquidityAccount['type'],
    name: '',
    balance: 0,
    currency: 'USD',
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    onAdd(form);
    setForm({ type: 'checking', name: '', balance: 0, currency: 'USD' });
    setOpen(false);
  };

  const totalLiquidity = accounts.reduce((sum, a) => sum + convertCurrency(a.balance, a.currency), 0);


  return (
    <Card className="glass-card">
      <CardHeader className="flex flex-row items-center justify-between">
        <CardTitle className="text-lg font-semibold flex items-center gap-2">
          <Wallet className="h-5 w-5 text-accent" />
          Cash & Liquidity
          <span className="text-sm font-normal text-muted-foreground ml-2">
            Total: {isPrivacyMode ? "****" : formatCurrency(totalLiquidity)}
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
              <DialogTitle>Add Cash Account</DialogTitle>
            </DialogHeader>
            <form onSubmit={handleSubmit} className="space-y-4">
              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label>Type</Label>
                  <Select value={form.type} onValueChange={(v) => setForm({ ...form, type: v as LiquidityAccount['type'] })}>
                    <SelectTrigger><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="checking">Checking</SelectItem>
                      <SelectItem value="savings">Savings</SelectItem>
                      <SelectItem value="cash">Cash</SelectItem>
                      <SelectItem value="money_market">Money Market</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
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
              </div>
              <div className="space-y-2">
                <Label>Name</Label>
                <Input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} placeholder="Main Checking" />
              </div>
              <div className="space-y-2">
                <Label>Balance</Label>
                <Input type="number" value={form.balance} onChange={(e) => setForm({ ...form, balance: +e.target.value })} />
              </div>
              <Button type="submit" className="w-full gradient-primary">Add Account</Button>
            </form>
          </DialogContent>
        </Dialog>
      </CardHeader>
      <CardContent>
        {accounts.length === 0 ? (
          <div className="text-center py-8 text-muted-foreground">No cash accounts yet. Add your first one!</div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {accounts.map((a) => (
              <div key={a.id} className="p-4 rounded-lg bg-secondary/50 border border-border/50 relative group">
                <Button
                  variant="ghost"
                  size="icon"
                  className="absolute top-2 right-2 opacity-0 group-hover:opacity-100 transition-opacity"
                  onClick={() => onDelete(a.id)}
                >
                  <Trash2 className="h-4 w-4 text-destructive" />
                </Button>
                <div className="text-sm text-muted-foreground capitalize">{a.type.replace('_', ' ')}</div>
                <div className="font-medium">{a.name}</div>
                <div className="text-xl font-bold text-primary mt-1">
                  {isPrivacyMode ? "****" : formatCurrency(a.balance, a.currency)}
                </div>
                {a.currency && a.currency !== baseCurrency && (
                  <div className="text-xs text-muted-foreground">
                    {isPrivacyMode ? "****" : new Intl.NumberFormat('en-US', { style: 'currency', currency: a.currency }).format(a.balance)}
                  </div>
                )}
              </div>
            ))
            }
          </div >
        )}
      </CardContent >
    </Card >
  );
}
