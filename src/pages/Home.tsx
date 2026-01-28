import { motion } from 'framer-motion';
import { ArrowRight, BarChart2, Lock, Smartphone } from 'lucide-react';
import { Link } from 'react-router-dom';
import { HeroDemo } from '../components/previews/HeroDemo';

export const Home = () => {
    return (
        <div className="overflow-hidden">
            {/* Hero Section */}
            <section className="relative pt-20 pb-32 lg:pt-32 lg:pb-48">
                <div className="absolute top-0 left-0 w-full h-full bg-[radial-gradient(ellipse_at_top,_var(--tw-gradient-stops))] from-emerald-900/20 via-background to-background -z-10" />

                <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 text-center">
                    <motion.div
                        initial={{ opacity: 0, y: 20 }}
                        animate={{ opacity: 1, y: 0 }}
                        transition={{ duration: 0.8 }}
                    >
                        <h1 className="text-4xl md:text-7xl font-extrabold tracking-tight mb-8 bg-gradient-to-b from-white to-white/60 bg-clip-text text-transparent">
                            Master Your <br />
                            <span className="bg-gradient-to-r from-emerald-400 to-cyan-300 bg-clip-text text-transparent">
                                Financial Destiny
                            </span>
                        </h1>
                        <p className="mt-4 text-xl text-gray-400 max-w-2xl mx-auto mb-10">
                            The modern, privacy-focused dashboard to track your net worth,
                            analyze investments, and manage cash flow with clarity.
                        </p>

                        <div className="flex flex-col sm:flex-row justify-center gap-4">
                            <Link
                                to="/tutorial"
                                className="px-8 py-4 rounded-full bg-emerald-600 hover:bg-emerald-700 text-white font-bold text-lg transition-all shadow-[0_0_20px_rgba(16,185,129,0.3)] hover:shadow-[0_0_30px_rgba(16,185,129,0.5)] flex items-center justify-center gap-2"
                            >
                                Start Free <ArrowRight className="h-5 w-5" />
                            </Link>
                            <Link
                                to="/features"
                                className="px-8 py-4 rounded-full bg-white/5 hover:bg-white/10 text-white font-semibold text-lg border border-white/10 transition-colors backdrop-blur-sm"
                            >
                                Explore Features
                            </Link>
                        </div>
                    </motion.div>

                    {/* Interactive Dashboard Preview */}
                    <div className="mt-20 relative mx-auto z-10">
                        <HeroDemo />
                    </div>              </div>
            </section>

            {/* Feature Grid */}
            <section className="py-24 bg-background border-t border-white/5">
                <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
                    <div className="grid md:grid-cols-3 gap-8">
                        {[
                            { icon: BarChart2, title: "Deep Analytics", desc: "Visualize your asset allocation, historical net worth, and expense patterns with beautiful interactive charts." },
                            { icon: Lock, title: "Privacy First", desc: "Your data is yours. With local encryption and privacy modes, keep your financial details secure." },
                            { icon: Smartphone, title: "Fully Responsive", desc: "Access your dashboard from any device. Mobile-first design ensures a perfect experience on the go." }
                        ].map((feature, idx) => (
                            <motion.div
                                key={idx}
                                initial={{ opacity: 0, y: 20 }}
                                whileInView={{ opacity: 1, y: 0 }}
                                viewport={{ once: true }}
                                transition={{ delay: idx * 0.1 }}
                                className="p-6 rounded-2xl bg-white/5 border border-white/10 hover:bg-white/10 transition-colors"
                            >
                                <feature.icon className="h-10 w-10 text-emerald-400 mb-4" />
                                <h3 className="text-xl font-bold text-white mb-2">{feature.title}</h3>
                                <p className="text-gray-400">{feature.desc}</p>
                            </motion.div>
                        ))}
                    </div>
                </div>
            </section>
        </div>
    );
};
