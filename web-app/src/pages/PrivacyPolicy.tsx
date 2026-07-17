import { motion } from 'framer-motion';
import { Database, EyeOff, KeyRound, Server, Shield } from 'lucide-react';

const contactEmail = 'mattioli.simone.10@gmail.com';

export const PrivacyPolicy = () => {
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
                            <Shield className="h-8 w-8 text-emerald-400" />
                        </div>
                        <h1 className="text-4xl font-bold text-white">Privacy Policy</h1>
                    </div>
                    <p className="text-gray-400">Effective date: June 6, 2026</p>
                </div>

                <div className="space-y-6 text-gray-300 leading-relaxed">
                    <section className="bg-emerald-500/5 p-6 rounded-2xl border border-emerald-500/20">
                        <h2 className="text-xl font-bold text-white mb-4">Overview</h2>
                        <p>
                            This policy explains how Wealth Compass handles information in the native iOS app
                            and in the separately available self-hosted web application. The iOS app does not
                            require an account, includes no advertising or tracking, and keeps financial records
                            on the user's device.
                        </p>
                    </section>

                    <section className="bg-gray-900/50 p-6 rounded-2xl border border-white/10">
                        <h2 className="text-xl font-bold text-white mb-4 flex items-center gap-2">
                            <Database className="h-5 w-5 text-emerald-400" />
                            1. Native iOS App
                        </h2>
                        <p className="mb-4">
                            Financial records entered in the iOS app, including transactions, recurring
                            schedules, investments, cryptocurrency holdings, liabilities, categories, settings,
                            and net-worth snapshots, are stored locally in the app's sandbox. The developer does
                            not receive or store this information.
                        </p>
                        <ul className="list-disc pl-5 space-y-2 text-gray-400">
                            <li>No registration, account, analytics SDK, advertising SDK, or tracking SDK is used.</li>
                            <li>Optional API keys are stored on the device in the iOS Keychain.</li>
                            <li>Optional reminders are scheduled as local iOS notifications.</li>
                            <li>Biometric authentication is handled by Apple; the app never receives or stores biometric data.</li>
                            <li>Users control JSON backup export through the iOS share sheet and can import a selected backup.</li>
                            <li>All local finance data can be removed from Settings using Delete All Data.</li>
                        </ul>
                    </section>

                    <section className="bg-gray-900/50 p-6 rounded-2xl border border-white/10">
                        <h2 className="text-xl font-bold text-white mb-4 flex items-center gap-2">
                            <Server className="h-5 w-5 text-cyan-400" />
                            2. Network Requests and Providers
                        </h2>
                        <p className="mb-4">
                            The iOS app may contact third-party services to perform a request initiated by app
                            functionality:
                        </p>
                        <ul className="list-disc pl-5 space-y-2 text-gray-400">
                            <li>Frankfurter and European Central Bank reference data for currency exchange rates.</li>
                            <li>Finnhub for optional stock and ETF market prices when the user provides an API key.</li>
                            <li>CoinGecko for optional cryptocurrency prices when the user provides an API key.</li>
                        </ul>
                        <p className="mt-4">
                            Requests include the currency, symbol, or asset identifier needed to return a result.
                            User-provided API keys are sent only to the applicable provider for authentication.
                            Financial records are not sent to these providers. Providers may process ordinary
                            network data, such as an IP address, under their own privacy policies.
                        </p>
                    </section>

                    <section className="bg-gray-900/50 p-6 rounded-2xl border border-white/10">
                        <h2 className="text-xl font-bold text-white mb-4 flex items-center gap-2">
                            <KeyRound className="h-5 w-5 text-purple-400" />
                            3. Self-Hosted Web Application
                        </h2>
                        <p>
                            The open-source web version is separate from the native iOS app. A person or
                            organization that deploys the web version configures its own Supabase project,
                            authentication, database, hosting, and API providers. That operator is responsible
                            for its deployment and privacy practices. The public project website does not offer
                            a developer-operated consumer account service for the iOS app.
                        </p>
                    </section>

                    <section className="bg-gray-900/50 p-6 rounded-2xl border border-white/10">
                        <h2 className="text-xl font-bold text-white mb-4 flex items-center gap-2">
                            <EyeOff className="h-5 w-5 text-emerald-400" />
                            4. Tracking, Advertising, and Sales
                        </h2>
                        <p>
                            Wealth Compass does not sell personal information, show advertising, use the
                            Advertising Identifier, or track users across apps and websites owned by other
                            companies. The native iOS app does not use cookies.
                        </p>
                    </section>

                    <section className="bg-gray-900/50 p-6 rounded-2xl border border-white/10">
                        <h2 className="text-xl font-bold text-white mb-4">5. Data Retention and Your Choices</h2>
                        <p>
                            The developer does not retain iOS financial records because they are not transmitted
                            to the developer. Users may edit individual records, delete all app data from
                            Settings, or remove the app from their device. Exported backup files remain wherever
                            the user chooses to save or share them and must be managed by the user.
                        </p>
                    </section>

                    <section className="bg-gray-900/50 p-6 rounded-2xl border border-white/10">
                        <h2 className="text-xl font-bold text-white mb-4">6. Children</h2>
                        <p>
                            Wealth Compass is a general personal finance utility and is not directed to children.
                            The native app does not knowingly collect personal information from children.
                        </p>
                    </section>

                    <section className="bg-gray-900/50 p-6 rounded-2xl border border-white/10">
                        <h2 className="text-xl font-bold text-white mb-4">7. Changes to This Policy</h2>
                        <p>
                            This policy may be updated when app functionality or legal requirements change. The
                            effective date at the top of this page identifies the latest revision.
                        </p>
                    </section>

                    <section className="bg-gray-900/50 p-6 rounded-2xl border border-white/10">
                        <h2 className="text-xl font-bold text-white mb-4">8. Contact</h2>
                        <p>
                            Wealth Compass is developed by Simone Mattioli in Verona, Italy. For privacy
                            questions, contact{' '}
                            <a href={`mailto:${contactEmail}`} className="text-emerald-400 hover:underline">
                                {contactEmail}
                            </a>.
                        </p>
                    </section>
                </div>
            </motion.div>
        </div>
    );
};
