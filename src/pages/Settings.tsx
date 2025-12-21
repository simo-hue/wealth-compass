import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Switch } from '@/components/ui/switch';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter, DialogTrigger } from '@/components/ui/dialog';
import { Settings, Globe, Shield, Database, ArrowLeft, Eye, EyeOff, Download, Trash2, Moon, Sun } from 'lucide-react';
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
        <div className="min-h-screen bg-background dark p-6">
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
                                <Label>Base Currency</Label>
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

                            <div className="p-4 rounded-lg bg-secondary/50 border border-border/50 space-y-3">
                                <div className="flex items-center justify-between">
                                    <span className="text-sm font-medium">Live Market Rate</span>
                                    <span className="flex h-2 w-2 rounded-full bg-green-500 shadow-[0_0_8px_rgba(34,197,94,0.5)]" />
                                </div>
                                <p className="text-xs text-muted-foreground">
                                    Foreign assets are automatically converted to your Base Currency using real-time ECB rates.
                                </p>

                                <div className="space-y-1 pt-2">
                                    {currencyRates ? (
                                        Object.entries(currencyRates).map(([curr, rate]) => (
                                            <div key={curr} className="flex justify-between text-sm">
                                                <span className="text-muted-foreground">{curr}</span>
                                                <span className="font-mono">
                                                    1 {currency} = {rate} {curr}
                                                </span>
                                            </div>
                                        ))
                                    ) : (
                                        <div className="text-xs text-muted-foreground italic">Loading rates...</div>
                                    )}
                                </div>
                            </div>
                        </div>
                    </CardContent>
                </Card>



                {/* Privacy & Interface */}
                <Card className="glass-card">
                    <CardHeader>
                        <CardTitle className="flex items-center gap-2"><Shield className="h-5 w-5 text-primary" /> Privacy & Interface</CardTitle>
                    </CardHeader>
                    <CardContent className="space-y-6">
                        <div className="flex items-center justify-between">
                            <div className="space-y-0.5">
                                <Label className="text-base">Privacy Mode</Label>
                                <p className="text-sm text-muted-foreground">Blur sensitive monetary values on the dashboard.</p>
                            </div>
                            <Switch checked={isPrivacyMode} onCheckedChange={togglePrivacyMode} />
                        </div>
                        {/* Theme is handled by system/class usually, simple placeholder if needed later */}
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
