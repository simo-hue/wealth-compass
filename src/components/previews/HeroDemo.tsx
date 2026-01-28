import { useState, useEffect } from 'react';
import { motion, useMotionValue, useSpring, useTransform } from 'framer-motion';
import { Area, AreaChart, ResponsiveContainer, Tooltip, XAxis, PieChart, Pie, Cell, YAxis } from 'recharts';
import {
    LayoutDashboard, ArrowLeftRight, TrendingUp, Bitcoin, Settings, Calculator,
    LogOut, RefreshCw, Camera, Info, Wallet, ArrowUpRight
} from 'lucide-react';

// Mock Data
const netWorthData = [
    { name: 'Dec 21', value: 10500 }, { name: 'Dec 25', value: 11200 },
    { name: 'Dec 30', value: 11800 }, { name: 'Jan 05', value: 11500 },
    { name: 'Jan 10', value: 11900 }, { name: 'Jan 15', value: 12200 },
    { name: 'Jan 20', value: 11713 }, { name: 'Jan 25', value: 12100 }
];

const allocationData = [
    { name: 'Investments', value: 6206, color: '#10b981' },
    { name: 'Crypto', value: 1744, color: '#f59e0b' },
    { name: 'Cash', value: 3762, color: '#1208a2ff' },
];

const activities = [
    { id: 1, name: 'Groceries', date: 'Jan 27', amount: -1.36, type: 'expense' },
    { id: 3, name: 'Dinner', date: 'Jan 26', amount: -74.00, type: 'expense' },
];

export const HeroDemo = () => {
    // 3D Tilt Logic
    const x = useMotionValue(0);
    const y = useMotionValue(0);
    const rotateX = useTransform(y, [-100, 100], [2, -2]);
    const rotateY = useTransform(x, [-100, 100], [-2, 2]);
    const springConfig = { stiffness: 300, damping: 30 };
    const rotateXSpring = useSpring(rotateX, springConfig);
    const rotateYSpring = useSpring(rotateY, springConfig);

    const handleMouseMove = (e: React.MouseEvent<HTMLDivElement>) => {
        const rect = e.currentTarget.getBoundingClientRect();
        const width = rect.width;
        const height = rect.height;
        const mouseX = e.clientX - rect.left;
        const mouseY = e.clientY - rect.top;
        const xPct = mouseX / width - 0.5;
        const yPct = mouseY / height - 0.5;
        x.set(xPct * 200);
        y.set(yPct * 200);
    };

    const handleMouseLeave = () => {
        x.set(0); y.set(0);
    };

    // Live Simulation
    const [currentNetWorth, setCurrentNetWorth] = useState(11713.09);
    useEffect(() => {
        const interval = setInterval(() => {
            if (Math.random() > 0.5) {
                setCurrentNetWorth(prev => prev + (Math.random() - 0.5) * 50);
            }
        }, 1500);
        return () => clearInterval(interval);
    }, []);

    return (
        <div style={{ perspective: '1200px' }} className="w-full max-w-[1400px] mx-auto p-4 sm:p-8">
            <motion.div
                style={{ rotateX: rotateXSpring, rotateY: rotateYSpring }}
                onMouseMove={handleMouseMove}
                onMouseLeave={handleMouseLeave}
                className="bg-[#0B0E11] rounded-3xl border border-white/10 shadow-2xl overflow-hidden relative flex flex-col md:flex-row h-auto md:h-[700px]"
            >
                {/* Sidebar */}
                <div className="w-64 bg-[#0B0E11] border-r border-white/5 p-6 flex flex-col hidden md:flex">
                    <div className="mb-10">
                        <h2 className="text-xl font-bold text-[#10b981]">Wealth Compass</h2>
                        <p className="text-xs text-gray-500 mt-1">Personal Finance System</p>
                    </div>

                    <nav className="space-y-2 flex-1">
                        {[
                            { icon: LayoutDashboard, label: 'Dashboard', active: true },
                            { icon: ArrowLeftRight, label: 'Cash Flow' },
                            { icon: TrendingUp, label: 'Investments' },
                            { icon: Bitcoin, label: 'Crypto' },
                            { icon: Settings, label: 'Settings' },
                            { icon: Calculator, label: 'Calculations' },
                        ].map((item) => (
                            <div key={item.label} className={`flex items-center gap-3 px-4 py-3 rounded-lg text-sm font-medium transition-colors cursor-default ${item.active ? 'bg-white/5 text-white' : 'text-gray-400 hover:text-white'}`}>
                                <item.icon size={18} />
                                {item.label}
                            </div>
                        ))}
                    </nav>

                    <div className="mt-auto pt-6 border-t border-white/5">
                        <div className="flex items-center gap-3 px-4 py-3 text-gray-400 hover:text-white cursor-default">
                            <LogOut size={18} />
                            <span className="text-sm font-medium">Sign Out</span>
                        </div>
                    </div>
                </div>

                {/* Main Content */}
                <div className="flex-1 overflow-visible md:overflow-y-auto bg-[#0B0E11] p-6 sm:p-8">
                    {/* Header */}
                    <div className="flex justify-between items-start mb-8">
                        <div>
                            <h1 className="text-2xl font-bold text-white mb-1">Dashboard</h1>
                            <p className="text-sm text-gray-500">Financial Command Center</p>
                        </div>
                        <div className="hidden sm:flex gap-3">
                            <button
                                className="flex items-center gap-2 px-4 py-2 bg-white/5 hover:bg-white/10 text-white rounded-lg text-sm font-medium transition-colors border border-white/5"
                            >
                                <RefreshCw size={14} /> Refresh
                            </button>
                            <button className="flex items-center gap-2 px-4 py-2 bg-[#10b981] hover:bg-[#059669] text-[#0B0E11] rounded-lg text-sm font-bold transition-colors shadow-lg shadow-emerald-900/20">
                                <Camera size={14} /> Snapshot
                            </button>
                        </div>
                    </div>

                    {/* KPI Cards */}
                    <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
                        {[
                            { label: 'Net Worth', value: `€${currentNetWorth.toLocaleString(undefined, { maximumFractionDigits: 2 })}`, icon: Info, change: true },
                            { label: 'Cash Balance', value: '€3,762.32', icon: Wallet, change: null },
                            { label: 'Investments', value: '€6,206.41', icon: TrendingUp, change: true },
                            { label: 'Crypto', value: '€1,744.36', icon: Bitcoin, change: null },
                        ].map((card, i) => (
                            <div key={i} className="bg-[#151A21] p-5 rounded-xl border border-white/5 hover:border-white/10 transition-colors">
                                <div className="flex justify-between items-start mb-4">
                                    <div className="flex items-center gap-2 text-gray-400 text-xs font-medium">
                                        {card.label} <card.icon size={12} />
                                    </div>
                                    {card.change !== null && <TrendingUp size={14} className="text-emerald-500" />}
                                </div>
                                <div className="text-2xl font-bold text-white tracking-tight">{card.value}</div>
                            </div>
                        ))}
                    </div>

                    {/* Dashboard Grid */}
                    <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
                        {/* Main Chart */}
                        <div className="lg:col-span-2 bg-[#151A21] p-6 rounded-2xl border border-white/5">
                            <div className="flex justify-between items-center mb-6">
                                <h3 className="text-white font-semibold">Net Worth Evolution</h3>
                                <div className="hidden sm:flex bg-[#0B0E11] rounded-lg p-1">
                                    {['1W', '1M', '6M', '1Y', 'ALL'].map((r, i) => (
                                        <div key={r} className={`px-3 py-1 text-xs font-medium rounded-md cursor-default ${i === 3 ? 'bg-[#10b981] text-[#0B0E11]' : 'text-gray-400'}`}>{r}</div>
                                    ))}
                                </div>
                            </div>
                            <div className="h-[300px] w-full">
                                <ResponsiveContainer>
                                    <AreaChart data={netWorthData}>
                                        <defs>
                                            <linearGradient id="colorNw" x1="0" y1="0" x2="0" y2="1">
                                                <stop offset="5%" stopColor="#10b981" stopOpacity={0.4} />
                                                <stop offset="95%" stopColor="#10b981" stopOpacity={0} />
                                            </linearGradient>
                                        </defs>
                                        <XAxis dataKey="name" axisLine={false} tickLine={false} tick={{ fill: '#6b7280', fontSize: 10 }} dy={10} />
                                        <YAxis hide domain={['auto', 'auto']} />
                                        <Tooltip
                                            contentStyle={{ backgroundColor: '#0B0E11', borderColor: '#374151', borderRadius: '8px', color: '#fff' }}
                                            itemStyle={{ color: '#34d399', fontWeight: 600 }}
                                            formatter={(value: any) => [`€${value}`, 'Net Worth']}
                                        />
                                        <Area type="monotone" dataKey="value" stroke="#10b981" strokeWidth={2} fillOpacity={1} fill="url(#colorNw)" />
                                    </AreaChart>
                                </ResponsiveContainer>
                            </div>
                        </div>

                        {/* Side Widgets */}
                        <div className="space-y-6">
                            {/* Asset Allocation */}
                            <div className="bg-[#151A21] p-6 rounded-2xl border border-white/5">
                                <h3 className="text-white font-semibold mb-6">Asset Allocation</h3>
                                <div className="h-[200px] relative">
                                    <ResponsiveContainer>
                                        <PieChart>
                                            <Pie
                                                data={allocationData}
                                                innerRadius={60}
                                                outerRadius={80}
                                                paddingAngle={5}
                                                dataKey="value"
                                                stroke="#10b981"
                                            >
                                                {allocationData.map((entry, index) => (
                                                    <Cell key={`cell-${index}`} fill={entry.color} />
                                                ))}
                                            </Pie>
                                        </PieChart>
                                    </ResponsiveContainer>
                                    {/* Legend */}
                                    <div className="flex justify-center gap-4 mt-[-20px]">
                                        {allocationData.map((item) => (
                                            <div key={item.name} className="flex items-center gap-2">
                                                <div className="w-2 h-2 rounded-full" style={{ backgroundColor: item.color }} />
                                                <span className="text-xs text-gray-400">{item.name}</span>
                                            </div>
                                        ))}
                                    </div>
                                </div>
                            </div>

                            {/* Recent Activity */}
                            <div className="bg-[#151A21] p-6 rounded-2xl border border-white/5">
                                <h3 className="text-white font-semibold mb-4">Recent Activity</h3>
                                <div className="space-y-4">
                                    {activities.map((a) => (
                                        <div key={a.id} className="flex items-center justify-between">
                                            <div className="flex items-center gap-3">
                                                <div className="p-2 rounded-lg bg-[#27272a] text-red-400">
                                                    <ArrowUpRight size={14} />
                                                </div>
                                                <div>
                                                    <div className="text-sm text-white font-medium">{a.name}</div>
                                                    <div className="text-xs text-gray-500">{a.date}</div>
                                                </div>
                                            </div>
                                            <span className="text-sm font-medium text-red-400">€{a.amount}</span>
                                        </div>
                                    ))}
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </motion.div>
        </div>
    );
};
