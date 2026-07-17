import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Switch } from '@/components/ui/switch';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter, DialogTrigger } from '@/components/ui/dialog';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { Settings, Globe, Shield, Database, ArrowLeft, Eye, EyeOff, Download, Trash2, Moon, Sun, Info } from 'lucide-react';
import { useSettings } from '@/contexts/SettingsContext';
import { useFinance } from '@/contexts/FinanceContext';
import { toast } from 'sonner';
import { exportToJson } from '@/lib/exportUtils';

export default function SettingsPage() {
    const navigate = useNavigate();
    const {
        currency, setCurrency,
        currencyRates, // Added this
        isPrivacyMode, togglePrivacyMode
    } = useSettings();
    const { data, clearData } = useFinance();


    const [deleteConfOpen, setDeleteConfOpen] = useState(false);

    // Download Data as JSON Limit
    const handleExport = () => {
        const filename = `wealth-compass-backup-${new Date().toISOString().split('T')[0]}`;
        exportToJson(data, filename);
    };

    const handleDelete = async () => {
        await clearData();
        setDeleteConfOpen(false);
        navigate('/');
    };

    return (
        <div className="min-h-screen bg-background dark p-4 md:p-6">
            <div className="max-w-3xl mx-auto space-y-8">

                {/* Header */}
                <div className="flex items-center gap-4">
                    <Button variant="ghost" size="icon" onClick={() => navigate('/')}>
                        <ArrowLeft className="h-5 w-5" />
                    </Button>
                    <div>
                        <h1 className="text-3xl font-bold text-gradient">Settings</h1>
                        <p className="text-muted-foreground">Manage your preferences and data</p>
                    </div>
                </div>

                {/* Currency */}
                <Card className="glass-card">
                    <CardHeader>
                        <CardTitle className="flex items-center gap-2"><Globe className="h-5 w-5 text-primary" /> Global Currency</CardTitle>
                        <CardDescription>Set your preferred display currency.</CardDescription>
                    </CardHeader>
                    <CardContent className="space-y-4">
                        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                            <div className="space-y-2">
                                <div className="flex items-center gap-2">
                                    <Label>Base Currency</Label>
                                    <Popover>
                                        <PopoverTrigger asChild>
                                            <Button variant="ghost" size="icon" className="h-4 w-4 rounded-full p-0 text-muted-foreground hover:text-primary">
                                                <Info className="h-3 w-3" />
                                                <span className="sr-only">View Market Rates</span>
                                            </Button>
                                        </PopoverTrigger>
                                        <PopoverContent className="w-80 p-0" align="start">
                                            <div className="p-4 border-b border-border bg-secondary/20">
                                                <div className="flex items-center justify-between mb-1">
                                                    <h4 className="font-medium leading-none">Live Market Rates</h4>
                                                    <span className="flex h-2 w-2 rounded-full bg-green-500 shadow-[0_0_8px_rgba(34,197,94,0.5)]" title="Live" />
                                                </div>
                                                <p className="text-xs text-muted-foreground">
                                                    1 {currency} conversions using real-time ECB rates.
                                                </p>
                                            </div>
                                            <div className="p-4 max-h-[300px] overflow-y-auto space-y-2">
                                                {currencyRates ? (
                                                    Object.entries(currencyRates).map(([curr, rate]) => (
                                                        <div key={curr} className="flex justify-between text-sm items-center py-1 border-b border-border/50 last:border-0">
                                                            <span className="font-medium text-muted-foreground">{curr}</span>
                                                            <span className="font-mono text-xs">
                                                                {rate}
                                                            </span>
                                                        </div>
                                                    ))
                                                ) : (
                                                    <div className="text-xs text-muted-foreground italic text-center py-4">Loading rates...</div>
                                                )}
                                            </div>
                                        </PopoverContent>
                                    </Popover>
                                </div>
                                <Select value={currency} onValueChange={(v: any) => setCurrency(v)}>
                                    <SelectTrigger><SelectValue /></SelectTrigger>
                                    <SelectContent>
                                        <SelectItem value="EUR">Euro (EUR)</SelectItem>
                                        <SelectItem value="USD">US Dollar (USD)</SelectItem>
                                        <SelectItem value="GBP">British Pound (GBP)</SelectItem>
                                        <SelectItem value="CHF">Swiss Franc (CHF)</SelectItem>
                                    </SelectContent>
                                </Select>
                            </div>

                            <div className="hidden md:block">
                                {/* Spacer or additional info if needed, keeping grid layout balanced */}
                            </div>
                        </div>
                    </CardContent>
                </Card>





                {/* Data Management */}
                <Card className="glass-card border-destructive/20">
                    <CardHeader>
                        <CardTitle className="flex items-center gap-2 text-destructive"><Database className="h-5 w-5" /> Data Management</CardTitle>
                        <CardDescription>Export your history or wipe data.</CardDescription>
                    </CardHeader>
                    <CardContent className="space-y-4">
                        <div className="space-y-1">
                            <Button variant="outline" className="w-full justify-start" onClick={handleExport} title="Use this file to restore your data if needed. Contains raw database structure.">
                                <Download className="h-4 w-4 mr-2" /> Download Full System Backup
                            </Button>
                            <p className="text-[10px] text-muted-foreground ml-1">
                                Contains complete database dump (Profiles, Assets, Transactions). Use for restore.
                            </p>
                        </div>

                        <Dialog open={deleteConfOpen} onOpenChange={setDeleteConfOpen}>
                            <DialogTrigger asChild>
                                <Button variant="destructive" className="w-full justify-start">
                                    <Trash2 className="h-4 w-4 mr-2" /> Delete All Data
                                </Button>
                            </DialogTrigger>
                            <DialogContent>
                                <DialogHeader>
                                    <DialogTitle>Are you absolutely sure?</DialogTitle>
                                    <DialogDescription>
                                        This action cannot be undone. This will permanently delete your local database and all history.
                                    </DialogDescription>
                                </DialogHeader>
                                <DialogFooter>
                                    <Button variant="outline" onClick={() => setDeleteConfOpen(false)}>Cancel</Button>
                                    <Button variant="destructive" onClick={handleDelete}>Yes, Delete Everything</Button>
                                </DialogFooter>
                            </DialogContent>
                        </Dialog>
                    </CardContent>
                </Card>

            </div>
        </div>
    );
}
