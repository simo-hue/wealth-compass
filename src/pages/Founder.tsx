import { motion } from 'framer-motion';
import { Github, Linkedin, MapPin, Heart, Code, Mountain } from 'lucide-react';

export const Founder = () => {
    return (
        <div className="py-24 bg-background min-h-screen">
            <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8">
                <motion.div
                    initial={{ opacity: 0, scale: 0.95 }}
                    animate={{ opacity: 1, scale: 1 }}
                    className="bg-white/5 border border-white/10 rounded-3xl p-8 md:p-12 backdrop-blur-sm"
                >
                    <div className="flex flex-col md:flex-row items-center md:items-start gap-8">
                        {/* Profile Image Mockup with Initials if no image */}
                        <div className="w-40 h-40 rounded-full bg-gradient-to-br from-emerald-500 to-cyan-400 flex items-center justify-center text-4xl font-bold text-white shadow-2xl shrink-0">
                            SM
                        </div>

                        <div className="text-center md:text-left space-y-4">
                            <h1 className="text-4xl font-bold text-white">Simone Mattioli</h1>
                            <div className="flex flex-wrap items-center justify-center md:justify-start gap-3 text-gray-400">
                                <span className="flex items-center gap-1"><Code className="h-4 w-4" /> Full Stack Developer</span>
                                <span className="flex items-center gap-1"><MapPin className="h-4 w-4" /> Verona, Italy</span>
                            </div>

                            <p className="text-lg text-gray-300 leading-relaxed">
                                I am a Computer Science student at the University of Verona with a passion for building software that solves real problems.
                                My journey involves open-source development, volunteering in educational projects in Brazil, and exploring the great outdoors.
                            </p>

                            <div className="pt-4 flex items-center justify-center md:justify-start gap-4">
                                <a href="https://github.com/simo-hue" target="_blank" rel="noopener noreferrer" className="p-3 rounded-full bg-white/10 hover:bg-white/20 hover:text-emerald-400 transition-colors">
                                    <Github className="h-6 w-6" />
                                </a>
                                <a href="https://www.linkedin.com/in/simonemattioli2003/" target="_blank" rel="noopener noreferrer" className="p-3 rounded-full bg-white/10 hover:bg-white/20 hover:text-emerald-400 transition-colors">
                                    <Linkedin className="h-6 w-6" />
                                </a>
                            </div>
                        </div>
                    </div>

                    <div className="mt-12 grid grid-cols-1 md:grid-cols-2 gap-6">
                        <div className="p-6 rounded-2xl bg-white/5 border border-white/5">
                            <div className="flex items-center gap-3 mb-4">
                                <Heart className="h-6 w-6 text-red-400" />
                                <h3 className="text-xl font-bold text-white">Volunteering</h3>
                            </div>
                            <p className="text-gray-400">
                                Spent time in Brazil helping with education projects in favelas, realizing the power of community and empathy in shaping a better future.
                            </p>
                        </div>

                        <div className="p-6 rounded-2xl bg-white/5 border border-white/5">
                            <div className="flex items-center gap-3 mb-4">
                                <Mountain className="h-6 w-6 text-green-400" />
                                <h3 className="text-xl font-bold text-white">Outdoor Life</h3>
                            </div>
                            <p className="text-gray-400">
                                When not coding, you can find me hiking, skiing, or riding motorcycles through the landscapes of Trentino-Alto Adige.
                            </p>
                        </div>
                    </div>
                </motion.div>
            </div>
        </div>
    );
};
