import { useState } from 'react';
import { format } from 'date-fns';
import { Plus, Trash2, TrendingUp, TrendingDown, Wallet, CalendarIcon, FileSpreadsheet } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogTrigger, DialogFooter } from '@/components/ui/dialog';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { Calendar } from '@/components/ui/calendar';
import { cn } from '@/lib/utils';
import { useFinance } from '@/contexts/FinanceContext';
import { useSettings } from '@/contexts/SettingsContext';
import { CashFlowAnalytics } from '@/components/dashboard/CashFlowAnalytics';
import { exportToCsv } from '@/lib/exportUtils';

export default function CashFlowPage() {
    const { data, addTransaction, deleteTransaction, getMonthlyCashFlow } = useFinance();
    const { formatCurrency } = useSettings();

    const [isAddOpen, setIsAddOpen] = useState(false);
    const [formData, setFormData] = useState({
        type: 'expense' as 'income' | 'expense',
        amount: '',
        category: '',
        description: '',
        date: new Date()
    });

    const cashFlow = getMonthlyCashFlow(new Date());

    const handleExportCsv = () => {
        const exportData = data.transactions.map(t => ({
            Date: t.date,
            Category: t.category,
            Description: t.description,
            Amount: t.amount,
            Type: t.type
        }));
        const filename = `transactions_${format(new Date(), 'yyyy-MM-dd')}`;
        exportToCsv(exportData, filename);
    };

    const handleSubmit = (e: React.FormEvent) => {
        e.preventDefault();
        addTransaction({
            type: formData.type,
            amount: parseFloat(formData.amount),
            category: formData.category,
            description: formData.description,
            date: format(formData.date, 'yyyy-MM-dd')
        });
        setIsAddOpen(false);
        setFormData({ ...formData, amount: '', category: '', description: '' });
    };

    return (
        <div className="min-h-screen bg-background dark p-6 space-y-8">
            <div className="flex items-center justify-between">
                <div>
                    <h1 className="text-3xl font-bold text-gradient">Cash Flow</h1>
                    <p className="text-muted-foreground">Track your income and expenses</p>
                </div>
                <div className="flex gap-2">
                    <Button variant="outline" onClick={handleExportCsv}>
                        <FileSpreadsheet className="h-4 w-4 mr-2" /> Export CSV
                    </Button>
                    <Dialog open={isAddOpen} onOpenChange={setIsAddOpen}>
                        <DialogTrigger asChild>
                            <Button className="gradient-primary">
                                <Plus className="h-4 w-4 mr-2" /> Add Transaction
                            </Button>
                        </DialogTrigger>
                        <DialogContent className="sm:max-w-[425px]">
                            <DialogHeader>
                                <DialogTitle>Add Transaction</DialogTitle>
                                <DialogDescription>Record a new income or expense entry.</DialogDescription>
                            </DialogHeader>
                            <form onSubmit={handleSubmit} className="space-y-4">
                                <div className="grid grid-cols-2 gap-4">
                                    <div className="space-y-2">
                                        <Label>Type</Label>
                                        <Select value={formData.type} onValueChange={(v: any) => setFormData({ ...formData, type: v })}>
                                            <SelectTrigger><SelectValue /></SelectTrigger>
                                            <SelectContent>
                                                <SelectItem value="income">Income</SelectItem>
                                                <SelectItem value="expense">Expense</SelectItem>
                                            </SelectContent>
                                        </Select>
                                    </div>
                                    <div className="space-y-2">
                                        <Label>Amount</Label>
                                        <Input
                                            type="number"
                                            step="0.01"
                                            placeholder="0.00"
                                            value={formData.amount}
                                            onChange={(e) => setFormData({ ...formData, amount: e.target.value })}
                                            required
                                        />
                                    </div>
                                </div>

                                <div className="space-y-2">
                                    <Label>Category</Label>
                                    <Select value={formData.category} onValueChange={(v) => setFormData({ ...formData, category: v })}>
                                        <SelectTrigger><SelectValue placeholder="Select category" /></SelectTrigger>
                                        <SelectContent>
                                            {formData.type === 'income' ? (
                                                <>
                                                    <SelectItem value="Salary">Salary</SelectItem>
                                                    <SelectItem value="Freelance">Freelance</SelectItem>
                                                    <SelectItem value="Dividends">Dividends</SelectItem>
                                                    <SelectItem value="Other">Other</SelectItem>
                                                </>
                                            ) : (
                                                <>
                                                    <SelectItem value="Housing">Housing</SelectItem>
                                                    <SelectItem value="Food">Food</SelectItem>
                                                    <SelectItem value="Transport">Transport</SelectItem>
                                                    <SelectItem value="Utilities">Utilities</SelectItem>
                                                    <SelectItem value="Fuel">Fuel</SelectItem>
                                                    <SelectItem value="Entertainment">Entertainment</SelectItem>
                                                    <SelectItem value="Shopping">Shopping</SelectItem>
                                                    <SelectItem value="Health">Health</SelectItem>
                                                    <SelectItem value="Other">Other</SelectItem>
                                                </>
                                            )}
                                        </SelectContent>
                                    </Select>
                                </div>

                                <div className="space-y-2">
                                    <Label>Date</Label>
                                    <Popover>
                                        <PopoverTrigger asChild>
                                            <Button variant="outline" className={cn("w-full justify-start text-left font-normal", !formData.date && "text-muted-foreground")}>
                                                <CalendarIcon className="mr-2 h-4 w-4" />
                                                {formData.date ? format(formData.date, "PPP") : <span>Pick a date</span>}
                                            </Button>
                                        </PopoverTrigger>
                                        <PopoverContent className="w-auto p-0">
                                            <Calendar mode="single" selected={formData.date} onSelect={(d) => d && setFormData({ ...formData, date: d })} initialFocus />
                                        </PopoverContent>
                                    </Popover>
                                </div>

                                <div className="space-y-2">
                                    <Label>Description</Label>
                                    <Input
                                        placeholder="Optional note..."
                                        value={formData.description}
                                        onChange={(e) => setFormData({ ...formData, description: e.target.value })}
                                    />
                                </div>

                                <DialogFooter>
                                    <Button type="submit">Save Transaction</Button>
                                </DialogFooter>
                            </form>
                        </DialogContent>
                    </Dialog>
                </div>

                {/* Analytics Section */}
                <CashFlowAnalytics />

                {/* Summary Cards */}
                <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                    <Card className="glass-card">
                        <CardHeader className="pb-2">
                            <CardTitle className="text-sm font-medium text-muted-foreground">Monthly Income</CardTitle>
                        </CardHeader>
                        <CardContent>
                            <div className="text-2xl font-bold text-green-500 flex items-center gap-2">
                                <TrendingUp className="h-5 w-5" />
                                {formatCurrency(cashFlow.monthlyIncome)}
                            </div>
                        </CardContent>
                    </Card>
                    <Card className="glass-card">
                        <CardHeader className="pb-2">
                            <CardTitle className="text-sm font-medium text-muted-foreground">Monthly Expenses</CardTitle>
                        </CardHeader>
                        <CardContent>
                            <div className="text-2xl font-bold text-red-500 flex items-center gap-2">
                                <TrendingDown className="h-5 w-5" />
                                {formatCurrency(cashFlow.monthlyExpenses)}
                            </div>
                        </CardContent>
                    </Card>
                    <Card className="glass-card">
                        <CardHeader className="pb-2">
                            <CardTitle className="text-sm font-medium text-muted-foreground">Net Savings</CardTitle>
                        </CardHeader>
                        <CardContent>
                            <div className={cn("text-2xl font-bold flex items-center gap-2", cashFlow.monthlyIncome - cashFlow.monthlyExpenses >= 0 ? "text-primary" : "text-destructive")}>
                                <Wallet className="h-5 w-5" />
                                {formatCurrency(cashFlow.monthlyIncome - cashFlow.monthlyExpenses)}
                            </div>
                            <p className="text-xs text-muted-foreground mt-1">
                                Savings Rate: {cashFlow.savingsRate.toFixed(1)}%
                            </p>
                        </CardContent>
                    </Card>
                </div>

                {/* Transactions Table */}
                <Card className="glass-card">
                    <CardHeader>
                        <CardTitle>Recent Transactions</CardTitle>
                    </CardHeader>
                    <CardContent>
                        <Table>
                            <TableHeader>
                                <TableRow>
                                    <TableHead>Date</TableHead>
                                    <TableHead>Category</TableHead>
                                    <TableHead>Description</TableHead>
                                    <TableHead className="text-right">Amount</TableHead>
                                    <TableHead className="w-[50px]"></TableHead>
                                </TableRow>
                            </TableHeader>
                            <TableBody>
                                {data.transactions.length === 0 ? (
                                    <TableRow>
                                        <TableCell colSpan={5} className="text-center text-muted-foreground py-8">
                                            No transactions found. Add one to get started.
                                        </TableCell>
                                    </TableRow>
                                ) : (
                                    data.transactions.map((t) => (
                                        <TableRow key={t.id}>
                                            <TableCell>{format(new Date(t.date), 'MMM dd, yyyy')}</TableCell>
                                            <TableCell>
                                                <span className="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-secondary">
                                                    {t.category}
                                                </span>
                                            </TableCell>
                                            <TableCell>{t.description || '-'}</TableCell>
                                            <TableCell className={cn("text-right font-medium", t.type === 'income' ? 'text-green-500' : 'text-red-500')}>
                                                {t.type === 'income' ? '+' : '-'}{formatCurrency(t.amount)}
                                            </TableCell>
                                            <TableCell>
                                                <Button variant="ghost" size="icon" onClick={() => deleteTransaction(t.id)} className="h-8 w-8 text-muted-foreground hover:text-destructive">
                                                    <Trash2 className="h-4 w-4" />
                                                </Button>
                                            </TableCell>
                                        </TableRow>
                                    ))
                                )}
                            </TableBody>
                        </Table>
                    </CardContent>
                </Card>
            </div>
            );
}
