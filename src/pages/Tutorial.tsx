import { motion } from 'framer-motion';
import { Terminal, Database, Play, CheckCircle } from 'lucide-react';

const steps = [
    {
        title: "Prerequisites",
        icon: Terminal,
        content: (
            <ul className="list-disc list-inside space-y-2 text-gray-400">
                <li>Node.js 18+ installed on your machine</li>
                <li>A free Supabase account</li>
                <li>Git installed</li>
                <li>Basic familiarity with the command line</li>
            </ul>
        )
    },
    {
        title: "Clone the Repository",
        icon: Database,
        code: "git clone https://github.com/simo-hue/wealth-compass.git\ncd wealth-compass"
    },
    {
        title: "Install Dependencies",
        icon: Play,
        code: "npm install"
    },
    {
        title: "Configure Supabase",
        icon: Database,
        content: (
            <div className="space-y-2 text-gray-400">
                <p>1. Create a new project in Supabase.</p>
                <p>2. Go to Project Settings &rarr; API to get your URL and Anon Key.</p>
                <p>3. Create a <code>.env</code> file in the root directory:</p>
            </div>
        ),
        code: "VITE_SUPABASE_URL=your_project_url\nVITE_SUPABASE_ANON_KEY=your_anon_key"
    },
    {
        title: "Run the Development Server",
        icon: CheckCircle,
        code: "npm run dev",
        content: (
            <p className="text-gray-400 mt-2">
                Open <code className="text-blue-400">http://localhost:5173</code> in your browser to see the app running!
            </p>
        )
    }
];

export const Tutorial = () => {
    return (
        <div className="py-20 bg-background text-white">
            <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8">
                <motion.div
                    initial={{ opacity: 0, y: 20 }}
                    animate={{ opacity: 1, y: 0 }}
                    className="text-center mb-16"
                >
                    <h1 className="text-4xl font-bold bg-gradient-to-r from-blue-400 to-cyan-300 bg-clip-text text-transparent mb-4">
                        Getting Started
                    </h1>
                    <p className="text-gray-400 text-lg">
                        Follow this step-by-step guide to get Wealth Compass up and running on your local machine.
                    </p>
                </motion.div>

                <div className="space-y-12">
                    {steps.map((step, index) => (
                        <motion.div
                            key={index}
                            initial={{ opacity: 0, x: -20 }}
                            whileInView={{ opacity: 1, x: 0 }}
                            viewport={{ once: true }}
                            transition={{ delay: index * 0.1 }}
                            className="relative pl-8 md:pl-0"
                        >
                            <div className="hidden md:flex flex-col items-center absolute left-0 top-0 h-full w-12 -ml-6">
                                <div className="w-12 h-12 rounded-full bg-blue-600/20 border border-blue-500/50 flex items-center justify-center text-blue-400 font-bold z-10">
                                    {index + 1}
                                </div>
                                {index !== steps.length - 1 && <div className="w-0.5 h-full bg-blue-500/20 mt-2" />}
                            </div>

                            <div className="md:ml-12 p-6 rounded-2xl bg-white/5 border border-white/10 hover:bg-white/10 transition-colors">
                                <div className="flex items-center gap-4 mb-4">
                                    <div className="md:hidden w-8 h-8 rounded-full bg-blue-600/20 border border-blue-500/50 flex items-center justify-center text-blue-400 font-bold text-sm">
                                        {index + 1}
                                    </div>
                                    <h3 className="text-2xl font-bold text-white flex items-center gap-3">
                                        <step.icon className="h-6 w-6 text-blue-400" />
                                        {step.title}
                                    </h3>
                                </div>

                                {step.content && <div className="mb-4">{step.content}</div>}

                                {step.code && (
                                    <div className="bg-black/50 rounded-lg p-4 font-mono text-sm text-green-400 overflow-x-auto border border-white/5 shadow-inner">
                                        <pre>{step.code}</pre>
                                    </div>
                                )}
                            </div>
                        </motion.div>
                    ))}
                </div>
            </div>
        </div>
    );
};
