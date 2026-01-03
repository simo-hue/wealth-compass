import { Outlet } from "react-router-dom";
import { Sidebar } from "./Sidebar";
import { Menu } from "lucide-react";
import { Sheet, SheetContent, SheetTrigger, SheetTitle, SheetDescription } from "@/components/ui/sheet";
import { Button } from "@/components/ui/button";

export default function MainLayout() {
    return (
        <div className="flex min-h-screen bg-background text-foreground font-sans antialiased">
            {/* Desktop Sidebar */}
            <div className="hidden md:flex w-64 flex-col sticky top-0 h-screen border-r border-border">
                <Sidebar />
            </div>

            {/* Mobile Header (Hamburger) */}
            <div className="md:hidden fixed top-0 left-0 right-0 z-50 bg-background/80 backdrop-blur-md border-b border-border p-4 flex items-center justify-between">
                <Sheet>
                    <SheetTrigger asChild>
                        <Button variant="ghost" size="icon">
                            <Menu className="h-6 w-6" />
                        </Button>
                    </SheetTrigger>
                    <SheetContent side="left" className="p-0 border-r w-64 bg-card">
                        <SheetTitle className="sr-only">Mobile Menu</SheetTitle>
                        <SheetDescription className="sr-only">Navigation menu</SheetDescription>
                        <Sidebar />
                    </SheetContent>
                </Sheet>
                <span className="font-bold text-lg bg-gradient-to-r from-primary to-accent bg-clip-text text-transparent">Wealth Compass</span>
                <div className="w-8"></div> {/* Spacer for alignment */}
            </div>

            {/* Main Content */}
            <main className="flex-1 overflow-x-hidden pt-16 md:pt-0">
                <Outlet />
            </main>
        </div>
    );
}
