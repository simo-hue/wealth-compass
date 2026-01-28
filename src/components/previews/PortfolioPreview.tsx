import { TrendingUp, Bitcoin, Building } from 'lucide-react';

const assets = [
    { name: 'Apple Inc.', ticker: 'AAPL', type: 'Stock', value: 14500.50, change: 2.4, icon: TrendingUp, color: 'text-blue-400' },
    { name: 'Bitcoin', ticker: 'BTC', type: 'Crypto', value: 32400.00, change: -1.2, icon: Bitcoin, color: 'text-orange-400' },
    { name: 'Rental Prop.', ticker: 'Real Est.', type: 'Real Estate', value: 250000.00, change: 5.1, icon: Building, color: 'text-green-400' },
    { name: 'NVIDIA', ticker: 'NVDA', type: 'Stock', value: 8900.20, change: 12.5, icon: TrendingUp, color: 'text-blue-400' },
    { name: 'Ethereum', ticker: 'ETH', type: 'Crypto', value: 4500.00, change: 0.8, icon: Bitcoin, color: 'text-orange-400' },
];

export const PortfolioPreview = () => {
    return (
        <div className="bg-gray-900/50 rounded-2xl border border-white/10 overflow-hidden">
            <div className="p-6 border-b border-white/10">
                <h3 className="text-xl font-bold text-white">Live Portfolio</h3>
                <p className="text-xs text-gray-400">Real-time asset tracking</p>
            </div>

            <div className="overflow-x-auto">
                <table className="w-full text-left text-sm">
                    <thead className="bg-white/5 text-gray-400 uppercase text-xs">
                        <tr>
                            <th className="px-6 py-3 font-medium">Asset</th>
                            <th className="px-6 py-3 font-medium text-right">Value</th>
                            <th className="px-6 py-3 font-medium text-right">24h</th>
                        </tr>
                    </thead>
                    <tbody className="divide-y divide-white/5">
                        {assets.map((asset) => (
                            <tr key={asset.ticker} className="hover:bg-white/5 transition-colors">
                                <td className="px-6 py-4 flex items-center gap-3">
                                    <div className={`p-2 rounded-lg bg-gray-800 ${asset.color}`}>
                                        <asset.icon className="h-4 w-4" />
                                    </div>
                                    <div>
                                        <div className="font-medium text-white">{asset.name}</div>
                                        <div className="text-xs text-gray-500">{asset.type}</div>
                                    </div>
                                </td>
                                <td className="px-6 py-4 text-right">
                                    <div className="font-mono text-white">${asset.value.toLocaleString()}</div>
                                </td>
                                <td className="px-6 py-4 text-right">
                                    <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium ${asset.change >= 0 ? 'bg-green-500/10 text-green-400' : 'bg-red-500/10 text-red-400'
                                        }`}>
                                        {asset.change >= 0 ? '+' : ''}{asset.change}%
                                    </span>
                                </td>
                            </tr>
                        ))}
                    </tbody>
                </table>
            </div>
        </div>
    );
};
