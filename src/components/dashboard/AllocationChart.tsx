
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { HelpTooltip } from '@/components/ui/tooltip-helper';
import { PieChart, Pie, Cell, ResponsiveContainer, Legend, Tooltip } from 'recharts';
import type { Investment } from '@/types/finance';
import { useSettings } from '@/contexts/SettingsContext';
import { cn } from '@/lib/utils';

interface AllocationChartProps {
  investments: Investment[];
  groupBy: 'geography' | 'sector' | 'type';
}

const COLORS = [
  'hsl(var(--chart-1))',
  'hsl(var(--chart-2))',
  'hsl(var(--chart-3))',
  'hsl(var(--chart-4))',
  'hsl(var(--chart-5))',
];

export function AllocationChart({ investments, groupBy }: AllocationChartProps) {
  const { formatCurrency, isPrivacyMode } = useSettings();

  const grouped = investments.reduce((acc, inv) => {
    const key = inv[groupBy];
    acc[key] = (acc[key] || 0) + inv.currentValue;
    return acc;
  }, {} as Record<string, number>);

  const data = Object.entries(grouped).map(([name, value]) => ({ name, value }));



  const totalValue = data.reduce((sum, item) => sum + item.value, 0);

  return (
    <Card className="glass-card">
      <CardHeader>
        <CardTitle className="text-lg font-semibold capitalize flex items-center gap-2">
          Allocation by {groupBy}
          <HelpTooltip content="How your money is divided among different categories (Stocks, Crypto, Cash) to manage risk." />
        </CardTitle>
      </CardHeader>
      <CardContent className={cn(isPrivacyMode && "blur-sm select-none pointer-events-none")}>
        {data.length === 0 ? (
          <div className="h-[250px] flex items-center justify-center text-muted-foreground">
            No investments yet
          </div>
        ) : (
          <div>
            <ResponsiveContainer width="100%" height={250}>
              <PieChart>
                <Pie
                  data={data}
                  cx="50%"
                  cy="50%"
                  innerRadius={60}
                  outerRadius={80}
                  paddingAngle={2}
                  dataKey="value"
                >
                  {data.map((entry, index) => (
                    <Cell key={entry.name} fill={COLORS[index % COLORS.length]} />
                  ))}
                </Pie>
                <Tooltip
                  formatter={(value: number) => {
                    if (isPrivacyMode) {
                      const percent = totalValue > 0 ? (value / totalValue) * 100 : 0;
                      return [`${percent.toFixed(1)}%`, 'Allocation'];
                    }
                    return formatCurrency(value);
                  }}
                  contentStyle={{ backgroundColor: "#1A1F2C", borderColor: "#403E43", color: "#FFFFFF" }}
                  itemStyle={{ color: "#FFFFFF" }}
                />
                <Legend
                  formatter={(value) => <span className="text-foreground text-sm">{value}</span>}
                />
              </PieChart>
            </ResponsiveContainer>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
