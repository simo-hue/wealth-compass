
import { useState, useMemo } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { HelpTooltip } from '@/components/ui/tooltip-helper';
import { PieChart, Pie, Cell, ResponsiveContainer, Sector } from 'recharts';
import type { Investment } from '@/types/finance';
import { useSettings } from '@/contexts/SettingsContext';
import { useIsMobile } from '@/hooks/use-mobile';
import { cn } from '@/lib/utils';
import { PieChart as PieChartIcon } from 'lucide-react';

interface AllocationChartProps {
  investments: Investment[];
  groupBy: 'geography' | 'sector' | 'type';
}

const COLORS = [
  '#3b82f6', // Blue
  '#10b981', // Emerald
  '#f59e0b', // Amber
  '#ef4444', // Red
  '#8b5cf6', // Violet
  '#ec4899', // Pink
  '#06b6d4', // Cyan
  '#84cc16', // Lime
];

export function AllocationChart({ investments, groupBy }: AllocationChartProps) {
  const { formatCurrency, isPrivacyMode, convertCurrency } = useSettings();
  const isMobile = useIsMobile();
  const [activeIndex, setActiveIndex] = useState(0);

  const data = useMemo(() => {
    const grouped = investments.reduce((acc, inv) => {
      const key = inv[groupBy];
      const value = convertCurrency(inv.currentValue, inv.currency);
      acc[key] = (acc[key] || 0) + value;
      return acc;
    }, {} as Record<string, number>);

    return Object.entries(grouped)
      .map(([name, value]) => ({ name, value }))
      .sort((a, b) => b.value - a.value);
  }, [investments, groupBy, convertCurrency]);

  const totalValue = useMemo(() => {
    return data.reduce((sum, item) => sum + item.value, 0);
  }, [data]);

  // Custom Active Shape
  const renderActiveShape = (props: any) => {
    const { cx, cy, innerRadius, outerRadius, startAngle, endAngle, fill } = props;
    return (
      <g>
        <text x={cx} y={cy} dy={-10} textAnchor="middle" fill="#9ca3af" fontSize={12} className="font-medium">
          Total Value
        </text>
        <text x={cx} y={cy} dy={20} textAnchor="middle" fill="#FFFFFF" fontSize={isMobile ? 18 : 22} className="font-bold">
          {isPrivacyMode ? "****" : formatCurrency(totalValue)}
        </text>
        <Sector
          cx={cx}
          cy={cy}
          innerRadius={innerRadius}
          outerRadius={outerRadius + 6}
          startAngle={startAngle}
          endAngle={endAngle}
          fill={fill}
          cornerRadius={6}
        />
      </g>
    );
  };

  return (
    <Card className="glass-card border-none bg-black/40 backdrop-blur-xl ring-1 ring-white/5 h-full">
      <CardHeader>
        <CardTitle className="text-lg font-semibold capitalize flex items-center gap-2 text-white/90">
          <PieChartIcon className="h-5 w-5 text-indigo-400" />
          Allocation by {groupBy}
          <HelpTooltip content="How your money is divided among different categories." />
        </CardTitle>
      </CardHeader>
      <CardContent>
        {data.length === 0 ? (
          <div className="h-[300px] flex items-center justify-center text-muted-foreground text-sm">
            No investments yet
          </div>
        ) : (
          <div className="flex flex-col items-center gap-6 h-full">
            {/* Donut Chart */}
            <div className="relative w-full h-[260px] flex-shrink-0">
              <ResponsiveContainer width="100%" height="100%">
                <PieChart>
                  <Pie
                    activeIndex={activeIndex}
                    activeShape={renderActiveShape}
                    data={data}
                    cx="50%"
                    cy="50%"
                    innerRadius={isMobile ? 65 : 80}
                    outerRadius={isMobile ? 85 : 100}
                    paddingAngle={4}
                    dataKey="value"
                    onMouseEnter={(_, index) => setActiveIndex(index)}
                    stroke="none"
                    cornerRadius={5}
                  >
                    {data.map((entry, index) => (
                      <Cell
                        key={`cell-${index}`}
                        fill={COLORS[index % COLORS.length]}
                        className="transition-all duration-300 ease-in-out hover:opacity-100 opacity-90"
                      />
                    ))}
                  </Pie>
                </PieChart>
              </ResponsiveContainer>
            </div>

            {/* Custom Legend - Below Chart */}
            <div className="w-full flex flex-col gap-3 px-2">
              {data.map((item, index) => (
                <div
                  key={item.name}
                  onMouseEnter={() => setActiveIndex(index)}
                  className={cn(
                    "flex items-center justify-between p-3 rounded-lg border border-white/5 transition-all duration-200 cursor-pointer group",
                    activeIndex === index ? "bg-white/10 border-white/10 translate-x-1" : "hover:bg-white/5 hover:border-white/10"
                  )}
                >
                  <div className="flex items-center gap-3">
                    <div
                      className="w-3 h-3 rounded-full shadow-[0_0_8px_rgba(0,0,0,0.5)]"
                      style={{ backgroundColor: COLORS[index % COLORS.length] }}
                    />
                    <div className="flex flex-col">
                      <span className="font-bold text-sm text-white/90 group-hover:text-white transition-colors">
                        {item.name}
                      </span>
                      <span className="text-xs text-white/50 font-medium">
                        {totalValue > 0 ? ((item.value / totalValue) * 100).toFixed(1) : 0}%
                      </span>
                    </div>
                  </div>
                  <div className="text-right">
                    <div className="font-mono text-sm font-medium text-white/80">
                      {isPrivacyMode ? "****" : formatCurrency(item.value)}
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
