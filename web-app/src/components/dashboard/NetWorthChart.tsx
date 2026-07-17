import { useState } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { format } from 'date-fns';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Area, AreaChart } from 'recharts';
import type { TimeRange, ChartDataPoint } from '@/types/finance';
import { cn } from '@/lib/utils';
import { useSettings } from '@/contexts/SettingsContext';
import { TrendingUp } from 'lucide-react';

interface NetWorthChartProps {
  data: ChartDataPoint[];
  onRangeChange: (range: TimeRange) => void;
  currentRange: TimeRange;
}

const ranges: TimeRange[] = ['1W', '1M', '6M', '1Y', 'ALL'];

export function NetWorthChart({ data, onRangeChange, currentRange }: NetWorthChartProps) {
  const { formatCurrency, isPrivacyMode, currencySymbol } = useSettings();

  return (
    <Card className="glass-card col-span-full border-none bg-black/40 backdrop-blur-xl ring-1 ring-white/5">
      <CardHeader className="flex flex-row items-center justify-between">
        <CardTitle className="text-lg font-semibold flex items-center gap-2 text-white/90">
          <TrendingUp className="h-5 w-5 text-emerald-400" />
          Net Worth Evolution
        </CardTitle>
        <div className="flex gap-1 bg-white/5 p-1 rounded-lg">
          {ranges.map((range) => (
            <Button
              key={range}
              variant="ghost"
              size="sm"
              onClick={() => onRangeChange(range)}
              className={cn(
                'text-xs h-7 px-3 rounded-md transition-all',
                currentRange === range
                  ? 'bg-emerald-500/20 text-emerald-400 font-medium'
                  : 'text-white/60 hover:text-white hover:bg-white/10'
              )}
            >
              {range}
            </Button>
          ))}
        </div>
      </CardHeader>
      <CardContent>
        {data.length === 0 ? (
          <div className="h-[300px] flex items-center justify-center text-muted-foreground text-sm">
            No data yet. Add some financial entries and take a snapshot to see your progress.
          </div>
        ) : (
          <div className="relative h-[300px] w-full">
            <ResponsiveContainer width="100%" height="100%">
              <AreaChart data={data} margin={{ top: 5, right: 20, left: 20, bottom: 5 }}>
                <defs>
                  <linearGradient id="colorNetWorth" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor="#10b981" stopOpacity={0.3} />
                    <stop offset="95%" stopColor="#10b981" stopOpacity={0} />
                  </linearGradient>
                </defs>
                <CartesianGrid strokeDasharray="3 3" opacity={0.05} vertical={false} stroke="#ffffff" />
                <XAxis
                  dataKey="date"
                  stroke="#9ca3af"
                  fontSize={12}
                  tickLine={false}
                  axisLine={false}
                  tick={{ fill: '#9ca3af' }}
                  dy={10}
                  minTickGap={30}
                />
                <YAxis
                  hide={isPrivacyMode}
                  stroke="#9ca3af"
                  fontSize={12}
                  tickLine={false}
                  axisLine={false}
                  tick={{ fill: '#9ca3af' }}
                  tickFormatter={(val) => `${currencySymbol}${Math.abs(val) >= 1000 ? (val / 1000).toFixed(0) + 'k' : val}`}
                />
                <Tooltip
                  cursor={{ stroke: '#10b981', strokeWidth: 1, strokeDasharray: '3 3' }}
                  content={({ active, payload, label }) => {
                    if (active && payload && payload.length) {
                      return (
                        <div className="bg-black/80 backdrop-blur-xl border border-white/10 p-3 rounded-xl shadow-xl">
                          <div className="text-white/50 text-xs mb-1">
                            {format(new Date(label), 'MMM d, yyyy')}
                          </div>
                          <div className="flex items-center gap-2">
                            <div className="font-mono text-lg font-bold text-emerald-400">
                              {isPrivacyMode ? "****" : formatCurrency(payload[0].value as number)}
                            </div>
                          </div>
                        </div>
                      );
                    }
                    return null;
                  }}
                />
                <Area
                  type="linear"
                  dataKey="value"
                  stroke="#10b981"
                  strokeWidth={2}
                  fillOpacity={1}
                  fill="url(#colorNetWorth)"
                  activeDot={{ r: 6, fill: "#10b981", stroke: "#000", strokeWidth: 2 }}
                />
              </AreaChart>
            </ResponsiveContainer>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
