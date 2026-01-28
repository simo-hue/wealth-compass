import { Link, useLocation } from "react-router-dom";
import { cn } from "@/lib/utils";
import {
    LayoutDashboard,
    ArrowRightLeft,
    TrendingUp,
    Bitcoin,
    Settings,
    LogOut,
    Shield,
    Calculator
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { useAuth } from "@/contexts/AuthContext";
import { Separator } from "@/components/ui/separator";
import { Switch } from "@/components/ui/switch";
import { useSettings } from "@/contexts/SettingsContext";

const sidebarItems = [
    {
        title: "Dashboard",
        icon: LayoutDashboard,
        href: "/sw/dashboard",
    },
    {
        title: "Cash Flow",
        icon: ArrowRightLeft,
        href: "/sw/cash-flow",
    },
    {
        title: "Investments",
        icon: TrendingUp,
        href: "/sw/investments",
    },
    {
        title: "Crypto",
        icon: Bitcoin,
        href: "/sw/crypto",
    },
    {
        title: "Settings",
        icon: Settings,
        href: "/sw/settings",
    },
    {
        title: "Calculations",
        icon: Calculator,
        href: "/sw/calculations",
    },
];

interface SidebarProps {
    onNavigate?: () => void;
}

export function Sidebar({ onNavigate }: SidebarProps) {
    const location = useLocation();
    const { signOut } = useAuth();
    const { isPrivacyMode, togglePrivacyMode } = useSettings();

    return (
        <div className="h-full w-full bg-card flex flex-col">
            <div className="p-6">
                <h1 className="text-2xl font-bold bg-gradient-to-r from-primary to-accent bg-clip-text text-transparent">
                    Wealth Compass
                </h1>
                <p className="text-xs text-muted-foreground mt-1">Personal Finance System</p>
            </div>

            <Separator className="mb-4" />

            <div className="flex-1 px-4 space-y-2">
                {sidebarItems.map((item) => (
                    <Link key={item.href} to={item.href} onClick={onNavigate}>
                        <Button
                            variant={location.pathname === item.href ? "secondary" : "ghost"}
                            className={cn(
                                "w-full justify-start gap-3",
                                location.pathname === item.href && "bg-secondary/50 font-medium"
                            )}
                        >
                            <item.icon className="h-5 w-5" />
                            {item.title}
                        </Button>
                    </Link>
                ))}
            </div>

            <div className="p-4 border-t border-border flex items-center gap-2">
                <Button variant="ghost" className="flex-1 justify-start gap-3 text-muted-foreground hover:text-destructive" onClick={() => signOut()}>
                    <LogOut className="h-5 w-5" />
                    Sign Out
                </Button>
                <div className="flex items-center gap-2" title="Toggle Privacy Mode">
                    <Shield className="h-4 w-4 text-muted-foreground" />
                    <Switch checked={isPrivacyMode} onCheckedChange={togglePrivacyMode} />
                </div>
            </div>
        </div>
    );
}
