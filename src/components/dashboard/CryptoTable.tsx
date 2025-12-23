import { useState, useEffect } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogTrigger } from '@/components/ui/dialog';
import { Plus, Trash2, Bitcoin, RefreshCw, Loader2, Search, Pencil } from 'lucide-react';
import { Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList } from '@/components/ui/command';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import type { CryptoHolding } from '@/types/finance';
import { cn } from '@/lib/utils';
import { getCryptoPrice, searchCoinGecko, getBatchCryptoPrices, type CoinResult } from '@/lib/api';
import { formatDistanceToNow } from 'date-fns';
import { toast } from 'sonner';
import { useSettings } from '@/contexts/SettingsContext';
import { HelpTooltip } from '@/components/ui/tooltip-helper';

interface CryptoTableProps {
  holdings: CryptoHolding[];
  onAdd: (holding: Omit<CryptoHolding, 'id' | 'createdAt' | 'updatedAt'>) => void;
  onUpdate: (id: string, updates: Partial<CryptoHolding>) => void;
  onDelete: (id: string) => void;
}

export function CryptoTable({ holdings, onAdd, onUpdate, onDelete }: CryptoTableProps) {
  const { formatCurrency, isPrivacyMode } = useSettings();
  const [open, setOpen] = useState(false);
  const [isUpdating, setIsUpdating] = useState(false);
  const [isAdding, setIsAdding] = useState(false);

  // Search state
  const [searchOpen, setSearchOpen] = useState(false);
  const [searchResults, setSearchResults] = useState<CoinResult[]>([]);
  const [searchQuery, setSearchQuery] = useState('');
  const [isSearching, setIsSearching] = useState(false);
  const [editId, setEditId] = useState<string | null>(null);

  const [form, setForm] = useState({
    symbol: '',
    name: '',
    quantity: 0,
    avgBuyPrice: 0,
    currentPrice: 0,
    coinId: '', // Hidden field to store CoinGecko ID if found
    feeType: 'fixed' as 'fixed' | 'percent',
    feeValue: 0
  });

  const resetForm = () => {
    setForm({ symbol: '', name: '', quantity: 0, avgBuyPrice: 0, currentPrice: 0, coinId: '', feeType: 'fixed', feeValue: 0 });
    setEditId(null);
  };

  const handleEdit = (holding: CryptoHolding) => {
    // Reverse calc to get Raw Price (Effective - Fees)
    const totalCost = holding.avgBuyPrice * holding.quantity;
    const rawCost = totalCost - (holding.fees || 0);
    const rawAvgPrice = holding.quantity > 0 ? rawCost / holding.quantity : 0;

    setForm({
      symbol: holding.symbol,
      name: holding.name,
      quantity: holding.quantity,
      avgBuyPrice: rawAvgPrice,
      currentPrice: holding.currentPrice,
      coinId: holding.coinId || '',
      feeType: 'fixed',
      feeValue: holding.fees || 0
    });
    setEditId(holding.id);
    setOpen(true);
  };

  // Debounced search
  useEffect(() => {
    const timer = setTimeout(async () => {
      if (searchQuery.length >= 2) {
        setIsSearching(true);
        const results = await searchCoinGecko(searchQuery);
        setSearchResults(results);
        setIsSearching(false);
      } else {
        setSearchResults([]);
      }
    }, 500);
    return () => clearTimeout(timer);
  }, [searchQuery]);

  const handleSelectCoin = async (coin: CoinResult) => {
    setForm(prev => ({
      ...prev,
      symbol: coin.symbol.toUpperCase(),
      name: coin.name,
      coinId: coin.id
    }));
    setSearchOpen(false);

    // Auto-fetch price on selection
    const price = await getCryptoPrice(coin.id);
    if (price) {
      setForm(prev => ({ ...prev, currentPrice: price }));
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsAdding(true);

    try {
      let price = form.currentPrice;
      // If no price entered, try to fetch it using ID if we have it, or symbol
      if (price === 0) {
        // Prefer coinId if we have it from search
        const lookup = form.coinId || form.symbol;
        if (lookup) {
          const fetchedPrice = await getCryptoPrice(lookup);
          if (fetchedPrice) {
            price = fetchedPrice;
          } else {
            toast.warning(`Could not fetch price. Saved with $0.`);
          }
        }
      }

      // Calculate Fees
      let calculatedFees = 0;
      if (form.feeType === 'fixed') {
        calculatedFees = form.feeValue;
      } else {
        calculatedFees = (form.quantity * form.avgBuyPrice) * (form.feeValue / 100);
      }

      // Effective Avg Buy Price (True Cost Basis per unit)
      // Total Cost = (Qty * RawPrice) + Fees
      // EffectivePrice = TotalCost / Qty
      const trueCostBasis = (form.quantity * form.avgBuyPrice) + calculatedFees;
      const effectiveAvgBuyPrice = trueCostBasis / form.quantity;

      if (editId) {
        onUpdate(editId, {
          symbol: form.symbol,
          name: form.name,
          quantity: form.quantity,
          avgBuyPrice: effectiveAvgBuyPrice,
          currentPrice: price,
          currency: 'USD',
          fees: calculatedFees,
          coinId: form.coinId,
          updatedAt: new Date().toISOString()
        });
        toast.success('Crypto holding updated');
      } else {
        onAdd({
          symbol: form.symbol,
          name: form.name,
          quantity: form.quantity,
          avgBuyPrice: effectiveAvgBuyPrice,
          currentPrice: price,
          currency: 'USD',
          fees: calculatedFees,
          coinId: form.coinId
        });
        toast.success('Crypto holding added successfully');
      }

      resetForm();
      setOpen(false);
    } catch (error) {
      toast.error(editId ? 'Failed to update crypto holding' : 'Failed to add crypto holding');
    } finally {
      setIsAdding(false);
    }
  };

  const refreshPrices = async (force: boolean = false) => {
    setIsUpdating(true);
    try {
      // Collect IDs (prefer coinId, fallback to name/symbol if missing)
      // Note: name/symbol fallback is imperfect but helpful for legacy data
      // For getBatchCryptoPrices, we need objects { symbol, coinId }
      const itemsToFetch = holdings.map(h => ({
        symbol: h.symbol,
        coinId: h.coinId || (h.name ? h.name.toLowerCase() : undefined) // fallback logic moved here or kept simple
      }));

      if (itemsToFetch.length === 0) return;

      const prices = await getBatchCryptoPrices(itemsToFetch, force);

      // Update Holdings
      let updatedCount = 0;
      // We need to map prices back to holdings.
      // The prices object uses keys that are IDs.
      // We need to know which holding corresponds to which ID.
      // We can iterate holdings and check if their ID (or fallback) has a price.

      holdings.forEach(h => {
        // Resolve the ID used for this holding
        const lookupId = h.coinId || h.name.toLowerCase();
        // Check if we have a price for this ID
        // Note: the batch function returns prices keyed by the ID used (coinId or symbol fallback)
        // Actually getBatchCryptoPrices returns prices keyed by the ID found/used. 
        // If we passed coinId, it used coinId. If we passed symbol fallback, it used likely that.
        // Let's check both or strict?
        // In getBatchCryptoPrices implementation: 
        // items.forEach(item => { if (item.coinId) ... else ... })
        // It returns Record<string, number>. Keys are the IDs.

        if (lookupId && prices[lookupId] !== undefined) {
          onUpdate(h.id, {
            currentPrice: prices[lookupId],
            updatedAt: new Date().toISOString()
          });
          updatedCount++;
        }
      });

      if (force) {
        if (updatedCount > 0) toast.success(`Updated prices for ${updatedCount} assets`);
        else toast.info('No prices needed update');
      }
    } catch (error) {
      toast.error('Failed to update prices. Rate limit or API error.');
    } finally {
      setIsUpdating(false);
    }
  };

  const handleUpdateAll = () => refreshPrices(true);

  // Auto-refresh on mount (cached)
  useEffect(() => {
    if (holdings.length > 0) {
      refreshPrices(false);
    }
  }, []);

  const getGainLoss = (h: CryptoHolding) => {
    const costBasis = h.quantity * h.avgBuyPrice;
    const currentValue = h.quantity * h.currentPrice;
    const gain = currentValue - costBasis;
    const percent = costBasis > 0 ? (gain / costBasis) * 100 : 0;
    return { costBasis, currentValue, gain, percent };
  };



  return (
    <Card className="glass-card">
      <CardHeader className="flex flex-row items-center justify-between">
        <CardTitle className="text-lg font-semibold flex items-center gap-2">
          <Bitcoin className="h-5 w-5 text-warning" />
          Crypto Holdings
        </CardTitle>
        <div className={cn("flex gap-2", isPrivacyMode && "blur-sm select-none pointer-events-none")}>
          {holdings.length > 0 && (
            <Button
              variant="outline"
              size="sm"
              onClick={handleUpdateAll}
              disabled={isUpdating}
            >
              {isUpdating ? (
                <Loader2 className="h-4 w-4 animate-spin mr-1" />
              ) : (
                <RefreshCw className="h-4 w-4 mr-1" />
              )}
              Update Prices
            </Button>
          )}
          <Button size="sm" className="gradient-primary" onClick={() => { resetForm(); setOpen(true); }}>
            <Plus className="h-4 w-4 mr-1" /> Add
          </Button>

          <Dialog open={open} onOpenChange={(val) => { if (!val) resetForm(); setOpen(val); }}>
            <DialogContent>
              <DialogHeader>
                <DialogTitle>{editId ? 'Edit Crypto Holding' : 'Add Crypto Holding'}</DialogTitle>
                <DialogDescription>
                  {editId ? 'Update the details of your crypto holding.' : 'Enter the details of your new crypto holding.'}
                </DialogDescription>
              </DialogHeader>
              <form onSubmit={handleSubmit} className="space-y-4">

                {/* Search / Symbol Input */}
                <div className="space-y-2">
                  <Label className="flex items-center gap-1">
                    Asset Search (CoinGecko)
                    <HelpTooltip content="Search for a cryptocurrency to auto-fill its symbol and name." />
                  </Label>
                  <Popover open={searchOpen} onOpenChange={setSearchOpen}>
                    <PopoverTrigger asChild>
                      <Button variant="outline" role="combobox" aria-expanded={searchOpen} className="w-full justify-between">
                        {form.symbol ? `${form.name} (${form.symbol})` : "Search coin..."}
                        <Search className="ml-2 h-4 w-4 shrink-0 opacity-50" />
                      </Button>
                    </PopoverTrigger>
                    <PopoverContent className="w-[400px] p-0">
                      <Command shouldFilter={false}>
                        <CommandInput placeholder="Search Bitcoin..." value={searchQuery} onValueChange={setSearchQuery} />
                        <CommandList>
                          {isSearching && <CommandEmpty>Searching...</CommandEmpty>}
                          {!isSearching && searchResults.length === 0 && <CommandEmpty>No results found.</CommandEmpty>}
                          <CommandGroup heading="Results">
                            {searchResults.map((coin) => (
                              <CommandItem
                                key={coin.id}
                                value={coin.id}
                                onSelect={() => handleSelectCoin(coin)}
                              >
                                <span>{coin.name}</span>
                                <span className="ml-2 text-muted-foreground uppercase">{coin.symbol}</span>
                              </CommandItem>
                            ))}
                          </CommandGroup>
                        </CommandList>
                      </Command>
                    </PopoverContent>
                  </Popover>
                  <p className="text-[10px] text-muted-foreground">Search to auto-fill details and fetch price.</p>
                </div>

                <div className="grid grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <Label>Symbol</Label>
                    <Input value={form.symbol} onChange={(e) => setForm({ ...form, symbol: e.target.value.toUpperCase() })} placeholder="BTC" required />
                  </div>
                  <div className="space-y-2">
                    <Label>Name</Label>
                    <Input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} placeholder="Bitcoin" required />
                  </div>
                </div>
                <div className="grid grid-cols-3 gap-4">
                  <div className="space-y-2">
                    <Label>Quantity</Label>
                    <Input type="number" step="any" value={form.quantity} onChange={(e) => setForm({ ...form, quantity: +e.target.value })} required />
                  </div>
                  <div className="space-y-2">
                    <Label>Avg Buy Price</Label>
                    <Input type="number" step="any" value={form.avgBuyPrice} onChange={(e) => setForm({ ...form, avgBuyPrice: +e.target.value })} required />
                  </div>
                  <div className="space-y-2">
                    <Label>Current Price</Label>
                    <Input
                      type="number"
                      step="any"
                      value={form.currentPrice}
                      onChange={(e) => setForm({ ...form, currentPrice: +e.target.value })}
                      placeholder="Auto-fetch if 0"
                    />
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
                        {new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(form.feeType === 'fixed' ? form.feeValue : (form.quantity * form.avgBuyPrice) * (form.feeValue / 100))}
                      </div>
                    </div>
                  </div>
                </div>
                <Button type="submit" className="w-full gradient-primary" disabled={isAdding}>
                  {isAdding ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : null}
                  {editId ? 'Save Changes' : 'Add Crypto'}
                </Button>
              </form>
            </DialogContent>
          </Dialog>
        </div>
      </CardHeader>
      <CardContent className={cn(isPrivacyMode && "blur-sm select-none pointer-events-none")}>
        {holdings.length === 0 ? (
          <div className="text-center py-8 text-muted-foreground">No crypto holdings yet. Add your first one!</div>
        ) : (
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Symbol</TableHead>
                  <TableHead>Name</TableHead>
                  <TableHead className="text-right">Quantity</TableHead>
                  <TableHead className="text-right hidden sm:table-cell">Avg Buy</TableHead>
                  <TableHead className="text-right hidden sm:table-cell">Current</TableHead>
                  <TableHead className="text-right">Value</TableHead>
                  <TableHead className="text-right flex items-center justify-end gap-1">
                    Gain/Loss
                    <HelpTooltip content="The theoretical profit or loss you would make if you sold your investments right now at the current market price (Unrealized P&L)." side="left" />
                  </TableHead>
                  <TableHead></TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {holdings.map((h) => {
                  const { currentValue, gain, percent } = getGainLoss(h);
                  return (
                    <TableRow key={h.id}>
                      <TableCell className="font-mono font-medium">{h.symbol}</TableCell>
                      <TableCell>{h.name}</TableCell>
                      <TableCell className="text-right font-mono">{h.quantity}</TableCell>
                      <TableCell className="text-right hidden sm:table-cell">{isPrivacyMode ? "****" : formatCurrency(h.avgBuyPrice)}</TableCell>
                      <TableCell className="text-right hidden sm:table-cell">
                        <div className="flex flex-col items-end">
                          <span className={cn(isPrivacyMode && "font-mono")}>{isPrivacyMode ? "****" : formatCurrency(h.currentPrice)}</span>
                          {h.updatedAt && (
                            <span className="text-[10px] text-muted-foreground">
                              {formatDistanceToNow(new Date(h.updatedAt), { addSuffix: true })}
                            </span>
                          )}
                        </div>
                      </TableCell>
                      <TableCell className="text-right">{isPrivacyMode ? "****" : formatCurrency(currentValue)}</TableCell>
                      <TableCell className={cn('text-right font-medium', gain >= 0 ? 'text-success' : 'text-destructive')}>
                        {isPrivacyMode ? "****" : formatCurrency(gain)} ({percent.toFixed(1)}%)
                      </TableCell>
                      <TableCell>
                        <div className="flex justify-end gap-1">
                          <Button variant="ghost" size="icon" onClick={() => handleEdit(h)}>
                            <Pencil className="h-4 w-4 text-muted-foreground" />
                          </Button>
                          <Button variant="ghost" size="icon" onClick={() => onDelete(h.id)}>
                            <Trash2 className="h-4 w-4 text-destructive" />
                          </Button>
                        </div>
                      </TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
