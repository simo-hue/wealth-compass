import { motion } from 'framer-motion';
import { FileText, CheckCircle, AlertTriangle } from 'lucide-react';

export const TermsOfService = () => {
    return (
        <div className="pt-24 pb-20 px-4 sm:px-6 lg:px-8 max-w-4xl mx-auto">
            <motion.div
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                className="space-y-8"
            >
                <div>
                    <div className="flex items-center gap-3 mb-4">
                        <div className="p-3 bg-purple-500/10 rounded-xl">
                            <FileText className="h-8 w-8 text-purple-400" />
                        </div>
                        <h1 className="text-4xl font-bold text-white">Terms of Service</h1>
                    </div>
                    <p className="text-gray-400">Last updated: {new Date().toLocaleDateString()}</p>
                </div>

                <div className="space-y-6 text-gray-300 leading-relaxed">
                    <section className="bg-gray-900/50 p-6 rounded-2xl border border-white/10">
                        <h2 className="text-xl font-bold text-white mb-4 flex items-center gap-2">
                            <CheckCircle className="h-5 w-5 text-green-400" />
                            1. Acceptance of Terms
                        </h2>
                        <p>
                            By accessing or using Wealth Compass, you agree to be bound by these Terms of Service.
                            If you do not agree to these terms, please do not use our services.
                        </p>
                    </section>

                    <section className="bg-gray-900/50 p-6 rounded-2xl border border-white/10">
                        <h2 className="text-xl font-bold text-white mb-4">2. Use License</h2>
                        <p className="mb-4">
                            Permission is granted to temporarily download one copy of the materials (information or software)
                            on Wealth Compass for personal, non-commercial transitory viewing only.
                        </p>
                    </section>

                    <section className="bg-gray-900/50 p-6 rounded-2xl border border-white/10">
                        <h2 className="text-xl font-bold text-white mb-4 flex items-center gap-2">
                            <AlertTriangle className="h-5 w-5 text-orange-400" />
                            3. Disclaimer
                        </h2>
                        <p>
                            The materials on Wealth Compass are provided on an 'as is' basis. Makes no warranties,
                            expressed or implied, and hereby disclaims and negates all other warranties including,
                            without limitation, implied warranties or conditions of merchantability, fitness for a
                            particular purpose, or non-infringement of intellectual property or other violation of rights.
                        </p>
                        <p className="mt-4 text-sm text-gray-400 italic">
                            Wealth Compass does not provide financial advice. All data and projections are for informational purposes only.
                        </p>
                    </section>

                    <section className="bg-gray-900/50 p-6 rounded-2xl border border-white/10">
                        <h2 className="text-xl font-bold text-white mb-4">4. Limitations</h2>
                        <p>
                            In no event shall Wealth Compass or its suppliers be liable for any damages (including,
                            without limitation, damages for loss of data or profit, or due to business interruption)
                            arising out of the use or inability to use the materials on Wealth Compass.
                        </p>
                    </section>
                </div>
            </motion.div>
        </div>
    );
};
