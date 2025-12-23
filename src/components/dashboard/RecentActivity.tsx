import { format } from 'date-fns';
import { useFinance } from '@/contexts/FinanceContext';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { useSettings } from '@/contexts/SettingsContext';
import { cn } from '@/lib/utils';
import { ArrowUpRight, ArrowDownLeft, Wallet } from 'lucide-react';

export function RecentActivity() {
    const { data } = useFinance();
    const { formatCurrency } = useSettings();

    // Combine transactions and maybe investment updates? 
    // For now, just transactions as "Activity".
    const activity = [...data.transactions]
        .sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime())
        .slice(0, 5);

    return (
        <Card className="glass-card">
            <CardHeader>
                <CardTitle>Recent Activity</CardTitle>
            </CardHeader>
            <CardContent>
                <div className="space-y-4">
                    {activity.length === 0 ? (
                        <p className="text-muted-foreground text-sm">No recent activity.</p>
                    ) : (
                        activity.map((t) => (
                            <div key={t.id} className="flex items-center justify-between">
                                <div className="flex items-center gap-3">
                                    <div className={cn(
                                        "p-2 rounded-full bg-secondary",
                                        t.type === 'income' ? "text-green-500" : "text-red-500"
                                    )}>
                                        {t.type === 'income' ? <ArrowDownLeft className="h-4 w-4" /> : <ArrowUpRight className="h-4 w-4" />}
                                    </div>
                                    <div>
                                        <p className="text-sm font-medium">{t.description || t.category}</p>
                                        <p className="text-xs text-muted-foreground">{format(new Date(t.date), 'MMM dd')}</p>
                                    </div>
                                </div>
                                <div className={cn("font-medium", t.type === 'income' ? "text-green-500" : "text-red-500")}>
                                    {t.type === 'income' ? '+' : '-'}{formatCurrency(t.amount)}
                                </div>
                            </div>
                        ))
                    )}
                </div>
            </CardContent>
        </Card>
    );
}
