import { useState } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogTrigger } from '@/components/ui/dialog';
import { Progress } from '@/components/ui/progress';
import { Plus, Trash2, DollarSign, PiggyBank } from 'lucide-react';
import type { IncomeEntry, ExpenseEntry } from '@/types/finance';
import { format } from 'date-fns';
import { useSettings } from '@/contexts/SettingsContext';
import { cn } from '@/lib/utils';

interface IncomeExpenseModuleProps {
  income: IncomeEntry[];
  expenses: ExpenseEntry[];
  monthlyIncome: number;
  monthlyExpenses: number;
  savingsRate: number;
  onAddIncome: (entry: Omit<IncomeEntry, 'id' | 'createdAt'>) => void;
  onDeleteIncome: (id: string) => void;
  onAddExpense: (entry: Omit<ExpenseEntry, 'id' | 'createdAt'>) => void;
  onDeleteExpense: (id: string) => void;
}

export function IncomeExpenseModule({
  income,
  expenses,
  monthlyIncome,
  monthlyExpenses,
  savingsRate,
  onAddIncome,
  onDeleteIncome,
  onAddExpense,
  onDeleteExpense,
}: IncomeExpenseModuleProps) {
  const { formatCurrency, isPrivacyMode } = useSettings();
  const [incomeOpen, setIncomeOpen] = useState(false);
  const [expenseOpen, setExpenseOpen] = useState(false);
  const [incomeForm, setIncomeForm] = useState({
    type: 'salary' as IncomeEntry['type'],
    amount: 0,
    description: '',
    date: format(new Date(), 'yyyy-MM-dd'),
  });
  const [expenseForm, setExpenseForm] = useState({
    category: '',
    amount: 0,
    description: '',
    date: format(new Date(), 'yyyy-MM-dd'),
  });

  const handleAddIncome = (e: React.FormEvent) => {
    e.preventDefault();
    onAddIncome(incomeForm);
    setIncomeForm({ type: 'salary', amount: 0, description: '', date: format(new Date(), 'yyyy-MM-dd') });
    setIncomeOpen(false);
  };

  const handleAddExpense = (e: React.FormEvent) => {
    e.preventDefault();
    onAddExpense(expenseForm);
    setExpenseForm({ category: '', amount: 0, description: '', date: format(new Date(), 'yyyy-MM-dd') });
    setExpenseOpen(false);
  };



  return (
    <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
      {/* Income Card */}
      <Card className="glass-card">
        <CardHeader className="flex flex-row items-center justify-between">
          <CardTitle className="text-lg font-semibold flex items-center gap-2">
            <DollarSign className="h-5 w-5 text-success" />
            Monthly Income
            <span className="text-sm font-normal text-success ml-2">
              {isPrivacyMode ? "****" : formatCurrency(monthlyIncome)}
            </span>
          </CardTitle>
          <Dialog open={incomeOpen} onOpenChange={setIncomeOpen}>
            <DialogTrigger asChild>
              <Button size="sm" className="gradient-primary">
                <Plus className="h-4 w-4 mr-1" /> Add
              </Button>
            </DialogTrigger>
            <DialogContent>
              <DialogHeader>
                <DialogTitle>Add Income</DialogTitle>
              </DialogHeader>
              <form onSubmit={handleAddIncome} className="space-y-4">
                <div className="grid grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <Label>Type</Label>
                    <Select value={incomeForm.type} onValueChange={(v) => setIncomeForm({ ...incomeForm, type: v as IncomeEntry['type'] })}>
                      <SelectTrigger><SelectValue /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="salary">Salary</SelectItem>
                        <SelectItem value="dividends">Dividends</SelectItem>
                        <SelectItem value="freelance">Freelance</SelectItem>
                        <SelectItem value="other">Other</SelectItem>
                      </SelectContent>
                    </Select>
                  </div>
                  <div className="space-y-2">
                    <Label>Date</Label>
                    <Input type="date" value={incomeForm.date} onChange={(e) => setIncomeForm({ ...incomeForm, date: e.target.value })} />
                  </div>
                </div>
                <div className="space-y-2">
                  <Label>Amount</Label>
                  <Input type="number" value={incomeForm.amount} onChange={(e) => setIncomeForm({ ...incomeForm, amount: +e.target.value })} />
                </div>
                <div className="space-y-2">
                  <Label>Description</Label>
                  <Input value={incomeForm.description} onChange={(e) => setIncomeForm({ ...incomeForm, description: e.target.value })} placeholder="Monthly salary" />
                </div>
                <Button type="submit" className="w-full gradient-primary">Add Income</Button>
              </form>
            </DialogContent>
          </Dialog>
        </CardHeader>
        <CardContent>
          {income.length === 0 ? (
            <div className="text-center py-4 text-muted-foreground text-sm">No income logged this month</div>
          ) : (
            <div className="space-y-2 max-h-48 overflow-y-auto">
              {income.slice(-5).map((i) => (
                <div key={i.id} className="flex items-center justify-between p-2 rounded bg-secondary/30 group">
                  <div>
                    <div className="text-sm font-medium capitalize">{i.type}</div>
                    <div className="text-xs text-muted-foreground">{i.description}</div>
                  </div>
                  <div className="flex items-center gap-2">
                    <span className="text-success font-medium">{isPrivacyMode ? "****" : formatCurrency(i.amount)}</span>
                    <Button variant="ghost" size="icon" className="h-6 w-6 opacity-0 group-hover:opacity-100" onClick={() => onDeleteIncome(i.id)}>
                      <Trash2 className="h-3 w-3 text-destructive" />
                    </Button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      {/* Expenses Card */}
      <Card className="glass-card">
        <CardHeader className="flex flex-row items-center justify-between">
          <CardTitle className="text-lg font-semibold flex items-center gap-2">
            <PiggyBank className="h-5 w-5 text-destructive" />
            Monthly Expenses
            <span className="text-sm font-normal text-destructive ml-2">
              {isPrivacyMode ? "****" : formatCurrency(monthlyExpenses)}
            </span>
          </CardTitle>
          <Dialog open={expenseOpen} onOpenChange={setExpenseOpen}>
            <DialogTrigger asChild>
              <Button size="sm" className="gradient-primary">
                <Plus className="h-4 w-4 mr-1" /> Add
              </Button>
            </DialogTrigger>
            <DialogContent>
              <DialogHeader>
                <DialogTitle>Add Expense</DialogTitle>
              </DialogHeader>
              <form onSubmit={handleAddExpense} className="space-y-4">
                <div className="grid grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <Label>Category</Label>
                    <Input value={expenseForm.category} onChange={(e) => setExpenseForm({ ...expenseForm, category: e.target.value })} placeholder="Housing, Food, etc." />
                  </div>
                  <div className="space-y-2">
                    <Label>Date</Label>
                    <Input type="date" value={expenseForm.date} onChange={(e) => setExpenseForm({ ...expenseForm, date: e.target.value })} />
                  </div>
                </div>
                <div className="space-y-2">
                  <Label>Amount</Label>
                  <Input type="number" value={expenseForm.amount} onChange={(e) => setExpenseForm({ ...expenseForm, amount: +e.target.value })} />
                </div>
                <div className="space-y-2">
                  <Label>Description</Label>
                  <Input value={expenseForm.description} onChange={(e) => setExpenseForm({ ...expenseForm, description: e.target.value })} placeholder="Rent payment" />
                </div>
                <Button type="submit" className="w-full gradient-primary">Add Expense</Button>
              </form>
            </DialogContent>
          </Dialog>
        </CardHeader>
        <CardContent>
          {expenses.length === 0 ? (
            <div className="text-center py-4 text-muted-foreground text-sm">No expenses logged this month</div>
          ) : (
            <div className="space-y-2 max-h-48 overflow-y-auto">
              {expenses.slice(-5).map((e) => (
                <div key={e.id} className="flex items-center justify-between p-2 rounded bg-secondary/30 group">
                  <div>
                    <div className="text-sm font-medium">{e.category}</div>
                    <div className="text-xs text-muted-foreground">{e.description}</div>
                  </div>
                  <div className="flex items-center gap-2">
                    <span className="text-destructive font-medium">{isPrivacyMode ? "****" : formatCurrency(e.amount)}</span>
                    <Button variant="ghost" size="icon" className="h-6 w-6 opacity-0 group-hover:opacity-100" onClick={() => onDeleteExpense(e.id)}>
                      <Trash2 className="h-3 w-3 text-destructive" />
                    </Button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      {/* Savings Rate */}
      <Card className="glass-card lg:col-span-2">
        <CardHeader>
          <CardTitle className="text-lg font-semibold">Savings Rate</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex items-center gap-4">
            <Progress value={Math.max(0, Math.min(100, savingsRate))} className="flex-1 h-3" />
            <span className="text-2xl font-bold text-primary">{savingsRate.toFixed(1)}%</span>
          </div>
          <p className="text-sm text-muted-foreground mt-2">
            Saving <span>{isPrivacyMode ? "****" : formatCurrency(monthlyIncome - monthlyExpenses)}</span> out of <span>{isPrivacyMode ? "****" : formatCurrency(monthlyIncome)}</span> this month
          </p>
        </CardContent>
      </Card>
    </div>
  );
}
