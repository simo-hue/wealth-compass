import { useState, useEffect } from 'react';
import { motion } from 'framer-motion';
import { Calculator } from 'lucide-react';

export const GrowthPreview = () => {
    const [principal, setPrincipal] = useState(10000);
    const [years, setYears] = useState(10);
    const [rate, setRate] = useState(7);
    const [result, setResult] = useState(0);

    useEffect(() => {
        const amount = principal * Math.pow((1 + rate / 100), years);
        setResult(Math.round(amount));
    }, [principal, years, rate]);

    return (
        <div className="bg-gray-900/50 rounded-2xl border border-white/10 p-6">
            <div className="flex items-center gap-3 mb-6">
                <div className="p-2 bg-purple-500/20 rounded-lg">
                    <Calculator className="h-6 w-6 text-purple-400" />
                </div>
                <div>
                    <h3 className="text-xl font-bold text-white">Compound Growth</h3>
                    <p className="text-xs text-gray-400">Project your future wealth</p>
                </div>
            </div>

            <div className="space-y-6">
                <div>
                    <div className="flex justify-between text-sm mb-2">
                        <span className="text-gray-400">Initial Investment</span>
                        <span className="text-white font-mono">${principal.toLocaleString()}</span>
                    </div>
                    <input
                        type="range"
                        min="1000"
                        max="100000"
                        step="1000"
                        value={principal}
                        onChange={(e) => setPrincipal(Number(e.target.value))}
                        className="w-full h-2 bg-gray-700 rounded-lg appearance-none cursor-pointer accent-purple-500"
                    />
                </div>

                <div>
                    <div className="flex justify-between text-sm mb-2">
                        <span className="text-gray-400">Time Period</span>
                        <span className="text-white font-mono">{years} Years</span>
                    </div>
                    <input
                        type="range"
                        min="1"
                        max="40"
                        step="1"
                        value={years}
                        onChange={(e) => setYears(Number(e.target.value))}
                        className="w-full h-2 bg-gray-700 rounded-lg appearance-none cursor-pointer accent-purple-500"
                    />
                </div>

                <div>
                    <div className="flex justify-between text-sm mb-2">
                        <span className="text-gray-400">Annual Return</span>
                        <span className="text-white font-mono">{rate}%</span>
                    </div>
                    <input
                        type="range"
                        min="1"
                        max="15"
                        step="0.5"
                        value={rate}
                        onChange={(e) => setRate(Number(e.target.value))}
                        className="w-full h-2 bg-gray-700 rounded-lg appearance-none cursor-pointer accent-purple-500"
                    />
                </div>
            </div>

            <div className="mt-8 pt-6 border-t border-white/10">
                <div className="flex justify-between items-center">
                    <span className="text-gray-400">Projected Value</span>
                    <motion.span
                        key={result}
                        initial={{ scale: 1.1, color: '#a855f7' }}
                        animate={{ scale: 1, color: '#ffffff' }}
                        className="text-2xl font-bold"
                    >
                        ${result.toLocaleString()}
                    </motion.span>
                </div>
                <div className="mt-2 text-right text-xs text-green-400">
                    +${(result - principal).toLocaleString()} profit
                </div>
            </div>
        </div>
    );
};
