import { Info } from 'lucide-react';
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip';
import { cn } from '@/lib/utils';

interface HelpTooltipProps {
    content: string;
    className?: string;
    side?: 'top' | 'right' | 'bottom' | 'left';
}

export function HelpTooltip({ content, className, side = 'top' }: HelpTooltipProps) {
    return (
        <TooltipProvider>
            <Tooltip delayDuration={300}>
                <TooltipTrigger asChild>
                    <Info className={cn("h-3.5 w-3.5 text-muted-foreground/70 hover:text-primary cursor-help transition-colors", className)} />
                </TooltipTrigger>
                <TooltipContent side={side} className="max-w-xs text-sm">
                    <p>{content}</p>
                </TooltipContent>
            </Tooltip>
        </TooltipProvider>
    );
}
