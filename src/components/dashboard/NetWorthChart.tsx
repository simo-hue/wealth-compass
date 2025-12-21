import { useState } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts';
import type { TimeRange, ChartDataPoint } from '@/types/finance';
import { cn } from '@/lib/utils';

interface NetWorthChartProps {
  data: ChartDataPoint[];
  onRangeChange: (range: TimeRange) => void;
  currentRange: TimeRange;
}

const ranges: TimeRange[] = ['1M', '6M', '1Y', 'ALL'];

export function NetWorthChart({ data, onRangeChange, currentRange }: NetWorthChartProps) {
  const formatCurrency = (value: number) =>
    new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', notation: 'compact' }).format(value);

  return (
    <Card className="glass-card col-span-full">
      <CardHeader className="flex flex-row items-center justify-between">
        <CardTitle className="text-lg font-semibold">Net Worth Evolution</CardTitle>
        <div className="flex gap-1">
          {ranges.map((range) => (
            <Button
              key={range}
              variant={currentRange === range ? 'default' : 'ghost'}
              size="sm"
              onClick={() => onRangeChange(range)}
              className={cn(
                'text-xs h-7 px-3',
                currentRange === range && 'gradient-primary text-primary-foreground'
              )}
            >
              {range}
            </Button>
          ))}
        </div>
      </CardHeader>
      <CardContent>
        {data.length === 0 ? (
          <div className="h-[300px] flex items-center justify-center text-muted-foreground">
            No data yet. Add some financial entries and take a snapshot to see your progress.
          </div>
        ) : (
          <ResponsiveContainer width="100%" height={300}>
            <LineChart data={data} margin={{ top: 5, right: 30, left: 20, bottom: 5 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="hsl(var(--border))" />
              <XAxis dataKey="date" stroke="hsl(var(--muted-foreground))" fontSize={12} />
              <YAxis stroke="hsl(var(--muted-foreground))" fontSize={12} tickFormatter={formatCurrency} />
              <Tooltip
                contentStyle={{
                  backgroundColor: 'hsl(var(--card))',
                  border: '1px solid hsl(var(--border))',
                  borderRadius: 'var(--radius)',
                }}
                labelStyle={{ color: 'hsl(var(--foreground))' }}
                formatter={(value: number) => [formatCurrency(value), 'Net Worth']}
              />
              <Line
                type="monotone"
                dataKey="value"
                stroke="hsl(var(--primary))"
                strokeWidth={2}
                dot={{ fill: 'hsl(var(--primary))', strokeWidth: 0, r: 4 }}
                activeDot={{ r: 6, fill: 'hsl(var(--primary))' }}
              />
            </LineChart>
          </ResponsiveContainer>
        )}
      </CardContent>
    </Card>
  );
}
