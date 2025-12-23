import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { TrendingUp, TrendingDown, Minus, type LucideIcon } from 'lucide-react';
import { cn } from '@/lib/utils';
import { useSettings } from '@/contexts/SettingsContext';
import { HelpTooltip } from '@/components/ui/tooltip-helper';

interface StatCardProps {
  title: string;
  value: number;
  icon: LucideIcon;
  trend?: number;
  format?: 'currency' | 'percent';
  className?: string;
  helpText?: string;
}

export function StatCard({ title, value, icon: Icon, trend, format = 'currency', className, helpText }: StatCardProps) {
  const { formatCurrency, isPrivacyMode } = useSettings();

  const formattedValue =
    format === 'currency'
      ? isPrivacyMode ? '****' : formatCurrency(value)
      : `${value.toFixed(1)}%`;

  const TrendIcon = trend && trend > 0 ? TrendingUp : trend && trend < 0 ? TrendingDown : Minus;
  const trendColor = trend && trend > 0 ? 'text-success' : trend && trend < 0 ? 'text-destructive' : 'text-muted-foreground';

  return (
    <Card className={cn('glass-card', className)}>
      <CardHeader className="flex flex-row items-center justify-between pb-2 space-y-0">
        <CardTitle className="text-sm font-medium text-muted-foreground flex items-center gap-2">
          {title}
          {helpText && <HelpTooltip content={helpText} />}
        </CardTitle>
        <Icon className="h-4 w-4 text-muted-foreground" />
      </CardHeader>
      <CardContent>
        <div className="text-2xl font-bold tracking-tight">
          {formattedValue}
        </div>
        {trend !== undefined && (
          <div className={cn('flex items-center gap-1 text-xs mt-1', trendColor)}>
            <TrendIcon className="h-3 w-3" />
            <span>{Math.abs(trend).toFixed(1)}% from last month</span>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
