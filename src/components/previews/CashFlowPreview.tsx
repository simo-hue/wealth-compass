import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, Legend } from 'recharts';
import { ArrowUpRight, ArrowDownRight, Wallet } from 'lucide-react';


const data = [
    { name: 'Jan', Income: 4000, Expenses: 2400 },
    { name: 'Feb', Income: 3000, Expenses: 1398 },
    { name: 'Mar', Income: 2000, Expenses: 9800 },
    { name: 'Apr', Income: 2780, Expenses: 3908 },
    { name: 'May', Income: 1890, Expenses: 4800 },
    { name: 'Jun', Income: 2390, Expenses: 3800 },
];

export const CashFlowPreview = () => {
    return (
        <div className="bg-gray-900/50 rounded-2xl border border-white/10 p-6">
            <div className="flex items-center justify-between mb-6">
                <div className="flex items-center gap-3">
                    <div className="p-2 bg-green-500/20 rounded-lg">
                        <Wallet className="h-6 w-6 text-green-400" />
                    </div>
                    <div>
                        <h3 className="text-xl font-bold text-white">Cash Flow</h3>
                        <p className="text-xs text-gray-400">Monthly breakdown</p>
                    </div>
                </div>
                <div className="flex gap-4 text-sm">
                    <div className="flex items-center gap-1 text-green-400">
                        <ArrowUpRight className="h-4 w-4" />
                        <span>$16.8k</span>
                    </div>
                    <div className="flex items-center gap-1 text-red-400">
                        <ArrowDownRight className="h-4 w-4" />
                        <span>$12.4k</span>
                    </div>
                </div>
            </div>

            <div className="h-[300px] w-full">
                <ResponsiveContainer width="100%" height="100%">
                    <BarChart data={data}>
                        <XAxis
                            dataKey="name"
                            stroke="#6b7280"
                            fontSize={12}
                            tickLine={false}
                            axisLine={false}
                        />
                        <YAxis hide />
                        <Tooltip
                            contentStyle={{ backgroundColor: '#111827', borderColor: '#374151', borderRadius: '8px' }}
                            itemStyle={{ fontSize: '12px' }}
                            cursor={{ fill: 'rgba(255,255,255,0.05)' }}
                        />
                        <Legend iconType="circle" wrapperStyle={{ fontSize: '12px', paddingTop: '10px' }} />
                        <Bar dataKey="Income" fill="#10b981" radius={[4, 4, 0, 0]} />
                        <Bar dataKey="Expenses" fill="#ef4444" radius={[4, 4, 0, 0]} />
                    </BarChart>
                </ResponsiveContainer>
            </div>
        </div>
    );
};
