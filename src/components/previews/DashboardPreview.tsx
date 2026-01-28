import { useState } from 'react';
import { motion } from 'framer-motion';
import { Area, AreaChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import { Eye, EyeOff, TrendingUp, Activity } from 'lucide-react';

const data1M = [
    { name: 'Week 1', value: 45000 },
    { name: 'Week 2', value: 46200 },
    { name: 'Week 3', value: 44800 },
    { name: 'Week 4', value: 47500 },
];

const data6M = [
    { name: 'Jan', value: 40000 },
    { name: 'Feb', value: 42000 },
    { name: 'Mar', value: 41500 },
    { name: 'Apr', value: 45000 },
    { name: 'May', value: 47000 },
    { name: 'Jun', value: 49500 },
];

const data1Y = [
    { name: 'Q1', value: 35000 },
    { name: 'Q2', value: 42000 },
    { name: 'Q3', value: 48000 },
    { name: 'Q4', value: 55000 },
];

export const DashboardPreview = () => {
    const [isPrivacyMode, setIsPrivacyMode] = useState(false);
    const [timeRange, setTimeRange] = useState<'1M' | '6M' | '1Y'>('6M');

    const currentData = timeRange === '1M' ? data1M : timeRange === '6M' ? data6M : data1Y;
    const growth = timeRange === '1M' ? '+5.2%' : timeRange === '6M' ? '+18.5%' : '+45.2%';
    const netWorth = isPrivacyMode ? '••••••' : '$49,500.00';

    return (
        <div className="w-full max-w-5xl mx-auto p-4">
            <div className="bg-gray-900/80 backdrop-blur-md rounded-2xl border border-white/10 shadow-2xl overflow-hidden">
                {/* Header / Toolbar */}
                <div className="p-4 border-b border-white/10 flex flex-col sm:flex-row justify-between items-center gap-4">
                    <div className="flex items-center space-x-4">
                        <div className="p-2 bg-blue-500/10 rounded-lg">
                            <Activity className="h-6 w-6 text-blue-400" />
                        </div>
                        <div>
                            <h3 className="text-sm text-gray-400">Total Net Worth</h3>
                            <motion.div
                                key={isPrivacyMode ? 'hidden' : 'visible'}
                                initial={{ opacity: 0, y: -10 }}
                                animate={{ opacity: 1, y: 0 }}
                                className="text-2xl font-bold text-white flex items-center gap-2"
                            >
                                {netWorth}
                                {!isPrivacyMode && (
                                    <span className="text-sm font-medium text-green-400 bg-green-400/10 px-2 py-0.5 rounded-full flex items-center">
                                        <TrendingUp className="h-3 w-3 mr-1" /> {growth}
                                    </span>
                                )}
                            </motion.div>
                        </div>
                    </div>

                    <div className="flex items-center space-x-2 bg-black/40 p-1 rounded-lg">
                        {(['1M', '6M', '1Y'] as const).map((range) => (
                            <button
                                key={range}
                                onClick={() => setTimeRange(range)}
                                className={`px-3 py-1.5 rounded-md text-sm font-medium transition-all ${timeRange === range
                                    ? 'bg-emerald-600 text-white shadow-lg'
                                    : 'text-gray-400 hover:text-white hover:bg-white/5'
                                    }`}
                            >
                                {range}
                            </button>
                        ))}
                    </div>

                    <button
                        onClick={() => setIsPrivacyMode(!isPrivacyMode)}
                        className={`p-2 rounded-lg transition-colors ${isPrivacyMode
                            ? 'bg-blue-500/20 text-blue-400'
                            : 'text-gray-400 hover:text-white hover:bg-white/5'
                            }`}
                        title="Toggle Privacy Mode"
                    >
                        {isPrivacyMode ? <EyeOff className="h-5 w-5" /> : <Eye className="h-5 w-5" />}
                    </button>
                </div>

                {/* Chart Section */}
                <div className="h-[300px] w-full p-4 pl-0">
                    <ResponsiveContainer width="100%" height="100%">
                        <AreaChart data={currentData}>
                            <defs>
                                <linearGradient id="colorValue" x1="0" y1="0" x2="0" y2="1">
                                    <stop offset="5%" stopColor="#3b82f6" stopOpacity={0.3} />
                                    <stop offset="95%" stopColor="#3b82f6" stopOpacity={0} />
                                </linearGradient>
                            </defs>
                            <XAxis
                                dataKey="name"
                                stroke="#6b7280"
                                axisLine={false}
                                tickLine={false}
                                tick={{ fill: '#9ca3af', fontSize: 12 }}
                            />
                            <YAxis
                                hide={true}
                            />
                            <Tooltip
                                contentStyle={{
                                    backgroundColor: '#1f2937',
                                    borderColor: '#374151',
                                    borderRadius: '0.5rem',
                                    color: '#f3f4f6'
                                }}
                                itemStyle={{ color: '#60a5fa' }}
                                formatter={(value: any) => [isPrivacyMode ? '••••••' : `$${(value || 0).toLocaleString()}`, 'Value']}
                            />
                            <Area
                                type="monotone"
                                dataKey="value"
                                stroke="#3b82f6"
                                strokeWidth={3}
                                fillOpacity={1}
                                fill="url(#colorValue)"
                                animationDuration={1500}
                            />
                        </AreaChart>
                    </ResponsiveContainer>
                </div>

                {/* Quick Stats Footer */}
                <div className="grid grid-cols-3 border-t border-white/10 divide-x divide-white/10 bg-white/5">
                    <div className="p-4 text-center">
                        <p className="text-xs text-gray-500 uppercase tracking-wider mb-1">Assets</p>
                        <p className="text-lg font-semibold text-white">{isPrivacyMode ? '••••' : '$52.4k'}</p>
                    </div>
                    <div className="p-4 text-center">
                        <p className="text-xs text-gray-500 uppercase tracking-wider mb-1">Liabilities</p>
                        <p className="text-lg font-semibold text-white">{isPrivacyMode ? '••••' : '$2.9k'}</p>
                    </div>
                    <div className="p-4 text-center">
                        <p className="text-xs text-gray-500 uppercase tracking-wider mb-1">Cash Flow</p>
                        <div className="flex items-center justify-center text-green-400 font-semibold gap-1">
                            <TrendingUp className="h-4 w-4" />
                            {isPrivacyMode ? '••••' : '+$1.2k'}
                        </div>
                    </div>
                </div>
            </div>
        </div>
    );
};
