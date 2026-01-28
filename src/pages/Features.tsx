import { motion } from 'framer-motion';
import { TrendingUp, Wallet, Shield, Calculator, Bitcoin, Activity } from 'lucide-react';
import { AllocationPreview, GrowthPreview, CashFlowPreview, PortfolioPreview } from '../components/previews';

const features = [
    {
        title: "Interactive Dashboard",
        description: "A complete 360-degree view of your financial health. Track net worth history, asset allocation by sector, and key liquidity metrics at a glance.",
        icon: Activity,
        color: "text-emerald-400",
        bg: "bg-emerald-400/10"
    },
    {
        title: "Cash Flow Management",
        description: "Track income and expenses with ease. Analyze your monthly savings rate and get detailed breakdowns of where your money goes.",
        icon: Wallet,
        color: "text-green-400",
        bg: "bg-green-400/10"
    },
    {
        title: "Investment Portfolio",
        description: "Real-time tracking for Stocks & ETFs via Finnhub/Yahoo Finance. Monitor cost basis, current value, and sector exposure automatically.",
        icon: TrendingUp,
        color: "text-purple-400",
        bg: "bg-purple-400/10"
    },
    {
        title: "Crypto Tracker",
        description: "Live crypto prices from CoinGecko. Track holdings, average buy price, and current portfolio value without manual updates.",
        icon: Bitcoin,
        color: "text-orange-400",
        bg: "bg-orange-400/10"
    },
    {
        title: "Financial Calculators",
        description: "Plan for the future with built-in tools: Compound Interest projections, FIRE timeline estimation, Inflation impact, and Monte Carlo simulations.",
        icon: Calculator,
        color: "text-red-400",
        bg: "bg-red-400/10"
    },
    {
        title: "Privacy & Security",
        description: "Your data is secured with Row Level Security (RLS). Use Privacy Mode to instantly blur sensitive figures when viewing in public.",
        icon: Shield,
        color: "text-cyan-400",
        bg: "bg-cyan-400/10"
    }
];

export const Features = () => {
    return (
        <div className="py-20 bg-background text-white">
            <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
                <motion.div
                    initial={{ opacity: 0, y: 20 }}
                    animate={{ opacity: 1, y: 0 }}
                    className="text-center mb-20"
                >
                    <h2 className="text-4xl font-bold bg-gradient-to-r from-emerald-400 to-cyan-300 bg-clip-text text-transparent mb-4">
                        Powerful Features
                    </h2>
                    <p className="text-gray-400 max-w-2xl mx-auto text-lg">
                        Everything you need to manage your wealth, all in one private, secure place.
                    </p>
                </motion.div>

                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
                    {features.map((feature, index) => (
                        <motion.div
                            key={index}
                            initial={{ opacity: 0, y: 20 }}
                            whileInView={{ opacity: 1, y: 0 }}
                            viewport={{ once: true }}
                            transition={{ delay: index * 0.1 }}
                            className="p-8 rounded-2xl bg-white/5 border border-white/10 hover:bg-white/10 transition-colors group"
                        >
                            <div className={`w-14 h-14 rounded-xl ${feature.bg} flex items-center justify-center mb-6 group-hover:scale-110 transition-transform`}>
                                <feature.icon className={`h-8 w-8 ${feature.color}`} />
                            </div>
                            <h3 className="text-xl font-bold mb-3">{feature.title}</h3>
                            <p className="text-gray-400 leading-relaxed">
                                {feature.description}
                            </p>
                        </motion.div>
                    ))}
                </div>

                {/* Interactive Demos Section */}
                <div className="mt-32">
                    <motion.div
                        initial={{ opacity: 0, y: 20 }}
                        whileInView={{ opacity: 1, y: 0 }}
                        viewport={{ once: true }}
                        className="text-center mb-16"
                    >
                        <h2 className="text-3xl font-bold text-white mb-4">Experience the Power</h2>
                        <p className="text-gray-400">Interact with these live previews to see what Wealth Compass can do.</p>
                    </motion.div>

                    <div className="grid md:grid-cols-2 gap-12">
                        <motion.div
                            initial={{ opacity: 0, x: -20 }}
                            whileInView={{ opacity: 1, x: 0 }}
                            viewport={{ once: true }}
                        >
                            <h3 className="text-xl font-bold text-white mb-6 text-center">Smart Allocation Visualization</h3>
                            <AllocationPreview />
                        </motion.div>

                        <motion.div
                            initial={{ opacity: 0, x: 20 }}
                            whileInView={{ opacity: 1, x: 0 }}
                            viewport={{ once: true }}
                        >
                            <h3 className="text-xl font-bold text-white mb-6 text-center">Powerful Projections</h3>
                            <GrowthPreview />
                        </motion.div>

                        <motion.div
                            initial={{ opacity: 0, x: -20 }}
                            whileInView={{ opacity: 1, x: 0 }}
                            viewport={{ once: true }}
                        >
                            <h3 className="text-xl font-bold text-white mb-6 text-center">Real-time Cash Flow</h3>
                            <CashFlowPreview />
                        </motion.div>

                        <motion.div
                            initial={{ opacity: 0, x: 20 }}
                            whileInView={{ opacity: 1, x: 0 }}
                            viewport={{ once: true }}
                        >
                            <h3 className="text-xl font-bold text-white mb-6 text-center">Live Asset Tracking</h3>
                            <PortfolioPreview />
                        </motion.div>
                    </div>
                </div>
            </div>
        </div>
    );
};
