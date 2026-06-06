import { motion } from 'framer-motion';
import { Bell, Database, Github, LifeBuoy, LockKeyhole, Mail, TrendingUp } from 'lucide-react';
import { Link } from 'react-router-dom';

const supportEmail = 'mattioli.simone.10@gmail.com';

export const Support = () => {
    return (
        <div className="pt-24 pb-20 px-4 sm:px-6 lg:px-8 max-w-4xl mx-auto">
            <motion.div
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                className="space-y-8"
            >
                <div>
                    <div className="flex items-center gap-3 mb-4">
                        <div className="p-3 bg-emerald-500/10 rounded-xl">
                            <LifeBuoy className="h-8 w-8 text-emerald-400" />
                        </div>
                        <h1 className="text-4xl font-bold text-white">Wealth Compass Support</h1>
                    </div>
                    <p className="text-gray-400">
                        Help for the native iOS app and the open-source web project.
                    </p>
                </div>

                <section className="bg-emerald-500/5 p-6 rounded-2xl border border-emerald-500/20">
                    <h2 className="text-xl font-bold text-white mb-3">Contact Support</h2>
                    <p className="text-gray-300 mb-4">
                        Include the app version, iOS version, device model, and the steps that caused the issue.
                        Do not send real financial records or API keys.
                    </p>
                    <div className="flex flex-col sm:flex-row gap-3">
                        <a
                            href={`mailto:${supportEmail}?subject=Wealth%20Compass%20Support`}
                            className="inline-flex items-center justify-center gap-2 px-4 py-2 rounded-lg bg-emerald-600 hover:bg-emerald-700 text-white font-semibold"
                        >
                            <Mail className="h-4 w-4" />
                            {supportEmail}
                        </a>
                        <a
                            href="https://github.com/simo-hue/wealth-compass/issues"
                            target="_blank"
                            rel="noopener noreferrer"
                            className="inline-flex items-center justify-center gap-2 px-4 py-2 rounded-lg bg-white/10 hover:bg-white/15 text-white font-semibold"
                        >
                            <Github className="h-4 w-4" />
                            Report a Project Issue
                        </a>
                    </div>
                </section>

                <div className="grid grid-cols-1 md:grid-cols-2 gap-6 text-gray-300">
                    <section className="bg-gray-900/50 p-6 rounded-2xl border border-white/10">
                        <Database className="h-6 w-6 text-emerald-400 mb-3" />
                        <h2 className="text-lg font-bold text-white mb-3">Backup and Data</h2>
                        <p>
                            Open Settings to prepare and share a JSON backup, import an existing Wealth Compass
                            backup, or permanently remove local finance data with Delete All Data.
                        </p>
                    </section>

                    <section className="bg-gray-900/50 p-6 rounded-2xl border border-white/10">
                        <LockKeyhole className="h-6 w-6 text-purple-400 mb-3" />
                        <h2 className="text-lg font-bold text-white mb-3">Biometric Lock</h2>
                        <p>
                            Face ID or Touch ID must be configured in iOS Settings. If authentication is
                            unavailable, confirm that the device supports biometrics and Wealth Compass has
                            permission to use Face ID.
                        </p>
                    </section>

                    <section className="bg-gray-900/50 p-6 rounded-2xl border border-white/10">
                        <Bell className="h-6 w-6 text-cyan-400 mb-3" />
                        <h2 className="text-lg font-bold text-white mb-3">Recurring Reminders</h2>
                        <p>
                            Notification access is requested when reminders are enabled for a recurring
                            transaction. If reminders do not appear, allow notifications for Wealth Compass in
                            iOS Settings and reopen the schedule.
                        </p>
                    </section>

                    <section className="bg-gray-900/50 p-6 rounded-2xl border border-white/10">
                        <TrendingUp className="h-6 w-6 text-orange-400 mb-3" />
                        <h2 className="text-lg font-bold text-white mb-3">Market Prices</h2>
                        <p>
                            Automatic stock and crypto prices are optional. Add and test your own Finnhub or
                            CoinGecko API key in Settings, or enter prices manually. Provider outages and rate
                            limits may temporarily prevent updates.
                        </p>
                    </section>
                </div>

                <section className="bg-gray-900/50 p-6 rounded-2xl border border-white/10 text-gray-300">
                    <h2 className="text-xl font-bold text-white mb-4">Important Information</h2>
                    <ul className="list-disc pl-5 space-y-2 text-gray-400">
                        <li>The iOS app does not connect to banks or financial institutions.</li>
                        <li>It does not execute trades, transfer money, or provide financial advice.</li>
                        <li>Financial records are stored locally and cannot be recovered by the developer.</li>
                        <li>Market prices and exchange rates may be delayed or inaccurate.</li>
                    </ul>
                    <p className="mt-5">
                        Read the <Link to="/privacy" className="text-emerald-400 hover:underline">Privacy Policy</Link>
                        {' '}and <Link to="/terms" className="text-emerald-400 hover:underline">Terms of Service</Link>.
                    </p>
                </section>

                <section className="text-sm text-gray-400">
                    <p>
                        Developer: Simone Mattioli, Verona, Italy
                        <br />
                        Support email: <a href={`mailto:${supportEmail}`} className="text-emerald-400 hover:underline">{supportEmail}</a>
                    </p>
                </section>
            </motion.div>
        </div>
    );
};
