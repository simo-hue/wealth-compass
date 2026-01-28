import React from 'react';
import { Link, useLocation } from 'react-router-dom';
import { Menu, X, Rocket, Shield, Users, HelpCircle, BookOpen } from 'lucide-react';
import { cn } from '../../lib/utils';

export const Navbar = () => {
    const [isOpen, setIsOpen] = React.useState(false);
    const location = useLocation();

    const navItems = [
        { name: 'Features', path: '/features', icon: Rocket },
        { name: 'Founder', path: '/founder', icon: Users },
        { name: 'FAQ', path: '/faq', icon: HelpCircle },
        { name: 'Tutorial', path: '/tutorial', icon: BookOpen },
    ];

    return (
        <nav className="fixed w-full z-50 bg-background/80 backdrop-blur-md border-b border-white/10">
            <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
                <div className="flex items-center justify-between h-16">
                    <Link to="/" className="flex items-center space-x-2">
                        <Shield className="h-8 w-8 text-emerald-500" />
                        <span className="text-xl font-bold bg-gradient-to-r from-emerald-400 to-cyan-300 bg-clip-text text-transparent">
                            Wealth Compass
                        </span>
                    </Link>

                    {/* Desktop Menu */}
                    <div className="hidden md:block">
                        <div className="ml-10 flex items-baseline space-x-4">
                            {navItems.map((item) => (
                                <Link
                                    key={item.name}
                                    to={item.path}
                                    className={cn(
                                        "flex items-center space-x-2 px-3 py-2 rounded-md text-sm font-medium transition-colors duration-200",
                                        location.pathname === item.path
                                            ? "text-emerald-400 bg-emerald-500/10"
                                            : "text-gray-300 hover:text-white hover:bg-white/5"
                                    )}
                                >
                                    <item.icon className="h-4 w-4" />
                                    <span>{item.name}</span>
                                </Link>
                            ))}
                            <Link
                                to="/tutorial"
                                className="ml-4 px-4 py-2 rounded-full bg-emerald-600 hover:bg-emerald-700 text-white text-sm font-bold transition-all duration-200 shadow-[0_0_15px_rgba(16,185,129,0.5)] hover:shadow-[0_0_25px_rgba(16,185,129,0.6)]"
                            >
                                Start
                            </Link>
                        </div>
                    </div>

                    {/* Mobile menu button */}
                    <div className="md:hidden">
                        <button
                            onClick={() => setIsOpen(!isOpen)}
                            className="inline-flex items-center justify-center p-2 rounded-md text-gray-400 hover:text-white hover:bg-gray-700 focus:outline-none"
                        >
                            {isOpen ? <X className="h-6 w-6" /> : <Menu className="h-6 w-6" />}
                        </button>
                    </div>
                </div>
            </div>

            {/* Mobile Menu */}
            {isOpen && (
                <div className="md:hidden bg-background/95 backdrop-blur-xl border-b border-white/10">
                    <div className="px-2 pt-2 pb-3 space-y-1 sm:px-3">
                        {navItems.map((item) => (
                            <Link
                                key={item.name}
                                to={item.path}
                                onClick={() => setIsOpen(false)}
                                className={cn(
                                    "flex items-center space-x-3 px-3 py-3 rounded-md text-base font-medium",
                                    location.pathname === item.path
                                        ? "text-emerald-400 bg-emerald-500/10"
                                        : "text-gray-300 hover:text-white hover:bg-white/5"
                                )}
                            >
                                <item.icon className="h-5 w-5" />
                                <span>{item.name}</span>
                            </Link>
                        ))}
                        <Link
                            to="/tutorial"
                            onClick={() => setIsOpen(false)}
                            className="mt-4 flex w-full items-center justify-center px-4 py-3 rounded-md bg-emerald-600 text-white font-bold"
                        >
                            Start
                        </Link>
                    </div>
                </div>
            )}
        </nav>
    );
};
