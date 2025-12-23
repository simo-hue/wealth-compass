import { useState } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogTrigger } from '@/components/ui/dialog';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Plus, TrendingUp, Trash2, RefreshCw, Loader2, Pencil } from 'lucide-react';
import type { Investment } from '@/types/finance';
import { cn } from '@/lib/utils';
import { getStockPrice, searchByIsin } from '@/lib/api';
import { formatDistanceToNow } from 'date-fns';
import { toast } from 'sonner';
import { useSettings } from '@/contexts/SettingsContext';
import { HelpTooltip } from '@/components/ui/tooltip-helper';
import { Checkbox } from '@/components/ui/checkbox';
import { DialogDescription } from '@/components/ui/dialog';

interface InvestmentTableProps {
  investments: Investment[];
  onAdd: (investment: Omit<Investment, 'id' | 'createdAt' | 'updatedAt'>) => void;
  onUpdate: (id: string, updates: Partial<Investment>) => void;
  onDelete: (id: string) => void;
}

export function InvestmentTable({ investments, onAdd, onUpdate, onDelete }: InvestmentTableProps) {
  const { formatCurrency, isPrivacyMode, currency: baseCurrency } = useSettings();
  const [open, setOpen] = useState(false);
  const [isUpdating, setIsUpdating] = useState(false);
  const [isAdding, setIsAdding] = useState(false);
  const [manualPriceEnabled, setManualPriceEnabled] = useState(false);
  const [editId, setEditId] = useState<string | null>(null);

  const [form, setForm] = useState({
    symbol: '',
    name: '',
    isin: '',
    type: 'stock' as Investment['type'],
    sector: 'Technology',
    quantity: 0,
    avgBuyPrice: 0,
    currentPrice: 0, // Manual Override
    currency: 'USD',
    geography: 'US',
    feeType: 'fixed' as 'fixed' | 'percent',
    feeValue: 0
  });

  const resetForm = () => {
    setForm({
      symbol: '',
      name: '',
      isin: '',
      type: 'stock',
      sector: 'Technology',
      quantity: 0,
      avgBuyPrice: 0,
      currentPrice: 0,
      currency: 'USD',
      geography: 'US',
      feeType: 'fixed',
      feeValue: 0
    });
    setManualPriceEnabled(false);
    setEditId(null);
  };

  const handleEdit = (inv: Investment) => {
    setForm({
      symbol: inv.symbol,
      name: inv.name,
      isin: inv.isin || '',
      type: inv.type,
      sector: inv.sector,
      quantity: inv.quantity,
      avgBuyPrice: inv.quantity > 0 ? (inv.costBasis - (inv.fees || 0)) / inv.quantity : 0, // derived raw price
      currentPrice: 0, // Reset manual override or maybe derive?
      currency: inv.currency || 'USD',
      geography: inv.geography,
      feeType: 'fixed',
      feeValue: inv.fees || 0
    });
    setEditId(inv.id);
    setOpen(true);
  };

  const handleIsinSearch = async () => {
    if (!form.isin || form.isin.length < 10) return;
    const result = await searchByIsin(form.isin);
    if (result) {
      setForm(prev => ({
        ...prev,
        symbol: result.symbol || prev.symbol,
        name: result.name || prev.name,
        isin: result.isin || prev.isin // Normalize
      }));
      toast.success("Found asset via ISIN");
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsAdding(true);
    try {
      let value = 0;

      // Determine per-share price for valuation
      let pricePerShare = 0;

      if (manualPriceEnabled && form.currentPrice > 0) {
        pricePerShare = form.currentPrice;
      } else if (form.type === 'stock' || form.type === 'etf') {
        const fetched = await getStockPrice(form.symbol);
        if (fetched) {
          pricePerShare = fetched;
          // We trust the user's selected currency for the asset. 
          // (e.g. VWCE.DE returns price in EUR, user selects EUR -> value is correct).
        } else {
          toast.warning('Live price unavailable. Enabling manual entry.');
          setManualPriceEnabled(true);
          setIsAdding(false);
          return; // Stop and let user enter price
        }
      } else {
        // Other assets, fallback to cost basis or manual
        pricePerShare = form.currentPrice > 0 ? form.currentPrice : form.avgBuyPrice;
      }

      value = form.quantity * pricePerShare;

      // Calculate Fees
      let calculatedFees = 0;
      if (form.feeType === 'fixed') {
        calculatedFees = form.feeValue;
      } else {
        // Percentage of total transaction value (qty * price)
        calculatedFees = (form.quantity * form.avgBuyPrice) * (form.feeValue / 100);
      }

      // True Cost Basis = (Qty * AvgPrice) + Fees
      const trueCostBasis = (form.quantity * form.avgBuyPrice) + calculatedFees;

      if (editId) {
        onUpdate(editId, {
          symbol: form.symbol,
          name: form.name,
          type: form.type,
          sector: form.sector,
          quantity: form.quantity,
          costBasis: trueCostBasis,
          currentValue: value,
          currency: form.currency,
          geography: form.geography,
          isin: form.isin,
          fees: calculatedFees,
          updatedAt: new Date().toISOString()
        });
        toast.success('Investment updated');
      } else {
        onAdd({
          symbol: form.symbol,
          name: form.name,
          type: form.type,
          sector: form.sector,
          quantity: form.quantity,
          costBasis: trueCostBasis,
          currentValue: value,
          currency: form.currency,
          geography: form.geography,
          isin: form.isin,
          fees: calculatedFees
        });
        toast.success('Investment added');
      }

      resetForm();
      setOpen(false);
    } catch (error) {
      toast.error(editId ? 'Failed to update investment' : 'Failed to add investment');
    } finally {
      setIsAdding(false);
    }
  };

  const handleUpdateAll = async () => {
    setIsUpdating(true);
    let updatedCount = 0;
    try {
      await Promise.all(investments.map(async (inv) => {
        if (inv.type === 'stock' || inv.type === 'etf') {
          const price = await getStockPrice(inv.symbol);
          if (price) {
            onUpdate(inv.id, {
              currentValue: price * inv.quantity,
              updatedAt: new Date().toISOString()
            });
            updatedCount++;
          }
        }
      }));
      if (updatedCount > 0) toast.success(`Updated ${updatedCount} investments`);
      else toast.info('No updates needed');
    } catch (e) {
      toast.error('Update failed');
    } finally {
      setIsUpdating(false);
    }
  };



  return (
    <Card className="glass-card">
      <CardHeader className="flex flex-row items-center justify-between">
        <CardTitle className="text-lg font-semibold flex items-center gap-2">
          <TrendingUp className="h-5 w-5 text-primary" />
          Investments
        </CardTitle>
        <div className="flex gap-2">
          {investments.length > 0 && (
            <Button variant="outline" size="sm" onClick={handleUpdateAll} disabled={isUpdating}>
              {isUpdating ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : <RefreshCw className="h-4 w-4 mr-1" />}
              Update
            </Button>
          )}
          <Dialog open={open} onOpenChange={setOpen}>
            <DialogTrigger asChild>
              <Button size="sm" className="gradient-primary">
                <Plus className="h-4 w-4 mr-1" /> Add
              </Button>
            </DialogTrigger>
            <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
              <DialogHeader>
                <DialogTitle>Add Investment</DialogTitle>
                <DialogDescription>Fill in the details below to track your asset.</DialogDescription>
              </DialogHeader>
              <form onSubmit={handleSubmit} className="space-y-4">
                {/* ISIN / ID (Smart Search) */}
                <div className="space-y-2">
                  <Label className="flex items-center gap-1">
                    ISIN / ID
                    <HelpTooltip content="The unique 12-character code (e.g., IE00BK5BQT80). Paste here to auto-fill details." />
                  </Label>
                  <div className="flex gap-2">
                    <Input
                      value={form.isin}
                      onChange={(e) => setForm({ ...form, isin: e.target.value })}
                      onBlur={handleIsinSearch}
                      placeholder="IE00BK5BQT80"
                    />
                    <Button type="button" variant="ghost" size="icon" onClick={handleIsinSearch} title="Search by ISIN">
                      <RefreshCw className="h-4 w-4" />
                    </Button>
                  </div>
                </div>

                {/* Symbol & Name */}
                <div className="grid grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <Label className="flex items-center gap-1">
                      Symbol
                      <HelpTooltip content="The unique ticker (e.g., AAPL, BTC, VWCE)." />
                    </Label>
                    <Input value={form.symbol} onChange={(e) => setForm({ ...form, symbol: e.target.value.toUpperCase() })} placeholder="AAPL" required />
                  </div>
                  <div className="space-y-2">
                    <Label>Name</Label>
                    <Input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} placeholder="Apple Inc." required />
                  </div>
                </div>

                {/* Type & Currency */}
                <div className="grid grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <Label>Type</Label>
                    <Select value={form.type} onValueChange={(v: any) => setForm({ ...form, type: v })}>
                      <SelectTrigger><SelectValue /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="stock">Stock</SelectItem>
                        <SelectItem value="etf">ETF</SelectItem>
                        <SelectItem value="bond">Bond</SelectItem>
                        <SelectItem value="real_estate">Real Estate</SelectItem>
                        <SelectItem value="commodity">Commodity</SelectItem>
                        <SelectItem value="other">Other</SelectItem>
                      </SelectContent>
                    </Select>
                  </div>
                  <div className="space-y-2">
                    <Label className="flex items-center gap-1">
                      Asset Trading Currency
                      <HelpTooltip content="The official currency this asset is traded in (e.g., USD for US Stocks). Do not select your local wallet currency unless they match." />
                    </Label>
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

                {/* Sector (Optional/Default) */}
                <div className="grid grid-cols-1">
                  <div className="space-y-2">
                    <Label>Sector</Label>
                    <Select value={form.sector} onValueChange={(v) => setForm({ ...form, sector: v })}>
                      <SelectTrigger><SelectValue /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="Technology">Technology</SelectItem>
                        <SelectItem value="Finance">Finance</SelectItem>
                        <SelectItem value="Real Estate">Real Estate</SelectItem>
                        <SelectItem value="Healthcare">Healthcare</SelectItem>
                        <SelectItem value="Energy">Energy</SelectItem>
                        <SelectItem value="Consumer">Consumer</SelectItem>
                        <SelectItem value="All World">All World</SelectItem>
                        <SelectItem value="Other">Other</SelectItem>
                      </SelectContent>
                    </Select>
                  </div>
                </div>

                {/* Trading Fees */}
                <div className="space-y-2 border p-3 rounded-md bg-muted/20">
                  <Label>Trading Fees</Label>
                  <div className="flex gap-2 mb-2">
                    <Button
                      type="button"
                      variant={form.feeType === 'fixed' ? 'default' : 'outline'}
                      size="sm"
                      onClick={() => setForm({ ...form, feeType: 'fixed' })}
                      className="flex-1"
                    >
                      Fixed Amount
                    </Button>
                    <Button
                      type="button"
                      variant={form.feeType === 'percent' ? 'default' : 'outline'}
                      size="sm"
                      onClick={() => setForm({ ...form, feeType: 'percent' })}
                      className="flex-1"
                    >
                      Percentage %
                    </Button>
                  </div>
                  <div className="grid grid-cols-2 gap-4 items-center">
                    <div className="space-y-1">
                      <Label className="text-xs text-muted-foreground">{form.feeType === 'fixed' ? 'Amount' : 'Percentage'}</Label>
                      <Input
                        type="number"
                        step="any"
                        value={form.feeValue}
                        onChange={(e) => setForm({ ...form, feeValue: +e.target.value })}
                        placeholder="0"
                      />
                    </div>
                    <div className="space-y-1 text-right">
                      <Label className="text-xs text-muted-foreground">Calculated Fee</Label>
                      <div className="font-mono font-medium text-lg">
                        {formatCurrency(form.feeType === 'fixed' ? form.feeValue : (form.quantity * form.avgBuyPrice) * (form.feeValue / 100), form.currency)}
                      </div>
                    </div>
                  </div>
                </div>

                {/* Quantity & Avg Buy Price */}
                <div className="grid grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <Label className="flex items-center gap-1">
                      Quantity
                      <HelpTooltip content="Number of shares or tokens held." />
                    </Label>
                    <Input type="number" step="any" value={form.quantity} onChange={(e) => setForm({ ...form, quantity: +e.target.value })} required />
                  </div>
                  <div className="space-y-2">
                    <Label className="flex items-center gap-1">
                      Average Buy Price
                      <HelpTooltip content="The average price you paid per single share or token." />
                    </Label>
                    <Input
                      type="number" step="any"
                      value={form.avgBuyPrice}
                      onChange={(e) => setForm({ ...form, avgBuyPrice: +e.target.value })}
                      placeholder="Price per share"
                      required
                    />
                  </div>
                </div>

                {/* Manual Price Override */}
                <div className="space-y-2 border p-3 rounded-md bg-muted/20">
                  <div className="flex items-center space-x-2">
                    <Checkbox
                      id="manualPrice"
                      checked={manualPriceEnabled}
                      onCheckedChange={(c: any) => setManualPriceEnabled(c)}
                    />
                    <Label htmlFor="manualPrice">Manually Enter Current Price</Label>
                  </div>
                  {manualPriceEnabled && (
                    <Input
                      type="number"
                      step="any"
                      placeholder="Current Market Price per Share"
                      value={form.currentPrice}
                      onChange={(e) => setForm({ ...form, currentPrice: +e.target.value })}
                    />
                  )}
                </div>

                {/* Live Preview Summary */}
                <div className="p-4 bg-muted/50 rounded-lg border space-y-2">
                  <h4 className="text-sm font-semibold text-muted-foreground flex items-center gap-2">Summary</h4>
                  <div className="flex justify-between items-center">
                    <span className="text-sm">Initial Investment:</span>
                    <span className="text-lg font-bold">
                      {new Intl.NumberFormat('en-US', { style: 'currency', currency: form.currency }).format(form.quantity * form.avgBuyPrice)}
                    </span>
                  </div>
                  <p className="text-[10px] text-muted-foreground">
                    Calculated as (Quantity × Avg Price) + Fees. This will be saved as your True Cost Basis.
                  </p>
                </div>

                <Button type="submit" className="w-full gradient-primary" disabled={isAdding}>
                  {isAdding ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : null}
                  {editId ? 'Save Changes' : 'Add Investment'}
                </Button>
              </form>
            </DialogContent>
          </Dialog>
        </div>
      </CardHeader>
      <CardContent>
        {investments.length === 0 ? (
          <div className="text-center py-8 text-muted-foreground">No investments yet.</div>
        ) : (
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Symbol</TableHead>
                  <TableHead>Name</TableHead>
                  <TableHead className="hidden sm:table-cell">Type</TableHead>
                  <TableHead className="hidden md:table-cell">Sector</TableHead>
                  <TableHead className="text-right">Quantity</TableHead>
                  <TableHead className="text-right flex items-center justify-end gap-1">
                    Value
                    <HelpTooltip content="Current market value of this investment." side="left" />
                  </TableHead>
                  <TableHead></TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {investments.map((inv) => (
                  <TableRow key={inv.id}>
                    <TableCell className="font-mono font-medium">{inv.symbol}</TableCell>
                    <TableCell>
                      <div className="flex flex-col">
                        <span>{inv.name}</span>
                        {inv.isin && <span className="text-[10px] text-muted-foreground">{inv.isin}</span>}
                      </div>
                    </TableCell>
                    <TableCell className="capitalize hidden sm:table-cell">{inv.type.replace('_', ' ')}</TableCell>
                    <TableCell className="hidden md:table-cell">{inv.sector}</TableCell>
                    <TableCell className="text-right">{inv.quantity}</TableCell>
                    <TableCell className="text-right">
                      <div className="flex flex-col items-end">
                        {/* Main Value in Base Currency */}
                        {/* Logic: IF (asset.currency === base_currency) THEN Direct math (No Conversion). ELSE -> Convert. */}
                        {/* formatCurrency handles this check internally. */}
                        <span className="font-medium">
                          {isPrivacyMode ? "****" : formatCurrency(inv.currentValue, inv.currency)}
                        </span>

                        {/* Secondary Value in Original Currency (if different) */}
                        {inv.currency && inv.currency !== baseCurrency && (
                          <span className="text-xs text-muted-foreground">
                            {isPrivacyMode ? "****" : new Intl.NumberFormat('en-US', { style: 'currency', currency: inv.currency }).format(inv.currentValue)}
                          </span>
                        )}

                        {inv.updatedAt && (
                          <span className="text-[10px] text-muted-foreground">
                            {formatDistanceToNow(new Date(inv.updatedAt), { addSuffix: true })}
                          </span>
                        )}
                      </div>
                    </TableCell>
                    <TableCell>
                      <div className="flex justify-end gap-1">
                        <Button variant="ghost" size="icon" onClick={() => handleEdit(inv)}>
                          <Pencil className="h-4 w-4 text-muted-foreground" />
                        </Button>
                        <Button variant="ghost" size="icon" onClick={() => onDelete(inv.id)}>
                          <Trash2 className="h-4 w-4 text-destructive" />
                        </Button>
                      </div>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        )
        }
      </CardContent >
    </Card >
  );
}
