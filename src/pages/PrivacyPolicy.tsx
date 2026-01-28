import { motion } from 'framer-motion';
import { Shield, Lock, Eye } from 'lucide-react';

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
                        <div className="p-3 bg-blue-500/10 rounded-xl">
                            <Shield className="h-8 w-8 text-blue-400" />
                        </div>
                        <h1 className="text-4xl font-bold text-white">Privacy Policy</h1>
                    </div>
                    <p className="text-gray-400">Last updated: {new Date().toLocaleDateString()}</p>
                </div>

                <div className="space-y-6 text-gray-300 leading-relaxed">
                    <section className="bg-gray-900/50 p-6 rounded-2xl border border-white/10">
                        <h2 className="text-xl font-bold text-white mb-4 flex items-center gap-2">
                            <Lock className="h-5 w-5 text-blue-400" />
                            1. Data Protection
                        </h2>
                        <p>
                            Wealth Compass is built with a privacy-first approach. We do not sell your personal data.
                            Your financial information is encrypted and stored securely. We utilize industry-standard
                            encryption protocols to ensure that your data remains confidential and integral.
                        </p>
                    </section>

                    <section className="bg-gray-900/50 p-6 rounded-2xl border border-white/10">
                        <h2 className="text-xl font-bold text-white mb-4 flex items-center gap-2">
                            <Eye className="h-5 w-5 text-purple-400" />
                            2. Information Collection
                        </h2>
                        <p className="mb-4">
                            We collect only the information necessary to provide you with our services, including:
                        </p>
                        <ul className="list-disc pl-5 space-y-2 text-gray-400">
                            <li>Account information (email, name) for authentication.</li>
                            <li>Financial data you explicitly enter for tracking purposes.</li>
                            <li>Usage data to improve application performance (anonymized).</li>
                        </ul>
                    </section>

                    <section className="bg-gray-900/50 p-6 rounded-2xl border border-white/10">
                        <h2 className="text-xl font-bold text-white mb-4">3. Your Rights</h2>
                        <p>
                            You have the right to access, correct, or delete your personal data at any time.
                            You can export your financial data directly from the settings menu.
                        </p>
                    </section>

                    <section className="bg-gray-900/50 p-6 rounded-2xl border border-white/10">
                        <h2 className="text-xl font-bold text-white mb-4">4. Contact Us</h2>
                        <p>
                            If you have questions about this privacy policy, please contact us at
                            <a href="mailto:privacy@wealthcompass.app" className="text-blue-400 ml-1 hover:underline">privacy@wealthcompass.app</a>.
                        </p>
                    </section>
                </div>
            </motion.div>
        </div>
    );
};
