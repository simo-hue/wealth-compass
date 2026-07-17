import { useState } from 'react';
import { format } from 'date-fns';
import { Plus, Trash2, TrendingUp, TrendingDown, Wallet, CalendarIcon, FileSpreadsheet } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
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
import { DeleteConfirmationDialog } from '@/components/ui/delete-confirmation-dialog';

export default function CashFlowPage() {
    const { data, addTransaction, deleteTransaction, getMonthlyCashFlow } = useFinance();
    const { formatCurrency, isPrivacyMode } = useSettings();

    const [isAddOpen, setIsAddOpen] = useState(false);
    const [formData, setFormData] = useState({
        type: 'expense' as 'income' | 'expense',
        amount: '',
        category: '',
        description: '',
        date: new Date()
    });

    const [deleteId, setDeleteId] = useState<string | null>(null);

    const handleDelete = () => {
        if (deleteId) {
            deleteTransaction(deleteId);
            setDeleteId(null);
        }
    };

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
        <div className="min-h-screen bg-background dark p-4 md:p-6 space-y-8">
            <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
                <div>
                    <h1 className="text-3xl font-bold text-gradient">Cash Flow</h1>
                    <p className="text-muted-foreground">Track your income and expenses</p>
                </div>
                <div className="flex gap-2 w-full md:w-auto">
                    <Button variant="outline" onClick={handleExportCsv} className="flex-1 md:flex-none">
                        <FileSpreadsheet className="h-4 w-4 mr-2" /> Export CSV
                    </Button>
                    <Dialog open={isAddOpen} onOpenChange={setIsAddOpen}>
                        <DialogTrigger asChild>
                            <Button className="gradient-primary flex-1 md:flex-none">
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
                            {isPrivacyMode ? "****" : formatCurrency(cashFlow.monthlyIncome)}
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
                            {isPrivacyMode ? "****" : formatCurrency(cashFlow.monthlyExpenses)}
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
                            {isPrivacyMode ? "****" : formatCurrency(cashFlow.monthlyIncome - cashFlow.monthlyExpenses)}
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
                <CardContent className={cn(isPrivacyMode && "blur-sm select-none pointer-events-none")}>
                    {data.transactions.length === 0 ? (
                        <div className="text-center text-muted-foreground py-8">
                            No transactions found. Add one to get started.
                        </div>
                    ) : (
                        <>
                            {/* Mobile View (Cards) */}
                            <div className="md:hidden space-y-4">
                                {data.transactions.map((t) => (
                                    <Card key={t.id} className="p-4 bg-card/50 border-input">
                                        <div className="flex justify-between items-start mb-2">
                                            <div className="space-y-1">
                                                <div className="flex items-center gap-2">
                                                    <span className="font-bold text-base">{format(new Date(t.date), 'MMM dd, yyyy')}</span>
                                                    <Badge variant="secondary" className="text-[10px] h-5 px-1.5 font-normal">
                                                        {t.category}
                                                    </Badge>
                                                </div>
                                                <div className="text-sm text-muted-foreground">{t.description || '-'}</div>
                                            </div>
                                            <div className={cn("font-bold text-base", t.type === 'income' ? 'text-green-500' : 'text-red-500')}>
                                                {t.type === 'income' ? '+' : '-'}{isPrivacyMode ? "****" : formatCurrency(t.amount)}
                                            </div>
                                        </div>
                                        <div className="flex justify-end pt-2 border-t border-border/50">
                                            <Button
                                                variant="ghost"
                                                size="sm"
                                                onClick={() => setDeleteId(t.id)}
                                                className="h-8 text-destructive hover:text-destructive hover:bg-destructive/10"
                                            >
                                                <Trash2 className="h-3.5 w-3.5 mr-1.5" /> Delete
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
                                            <TableHead>Date</TableHead>
                                            <TableHead>Category</TableHead>
                                            <TableHead>Description</TableHead>
                                            <TableHead className="text-right">Amount</TableHead>
                                            <TableHead className="w-[50px]"></TableHead>
                                        </TableRow>
                                    </TableHeader>
                                    <TableBody>
                                        {data.transactions.map((t) => (
                                            <TableRow key={t.id}>
                                                <TableCell>{format(new Date(t.date), 'MMM dd, yyyy')}</TableCell>
                                                <TableCell>
                                                    <span className="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-secondary">
                                                        {t.category}
                                                    </span>
                                                </TableCell>
                                                <TableCell>{t.description || '-'}</TableCell>
                                                <TableCell className={cn("text-right font-medium", t.type === 'income' ? 'text-green-500' : 'text-red-500')}>
                                                    {t.type === 'income' ? '+' : '-'}{isPrivacyMode ? "****" : formatCurrency(t.amount)}
                                                </TableCell>
                                                <TableCell>
                                                    <Button variant="ghost" size="icon" onClick={() => setDeleteId(t.id)} className="h-8 w-8 text-muted-foreground hover:text-destructive">
                                                        <Trash2 className="h-4 w-4" />
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
            </Card>

            <DeleteConfirmationDialog
                open={!!deleteId}
                onOpenChange={(open) => !open && setDeleteId(null)}
                onConfirm={handleDelete}
                title="Delete Transaction"
                description="Are you sure you want to delete this transaction? This action cannot be undone."
            />
        </div >
    );
}
