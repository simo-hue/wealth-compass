import { Github, Linkedin, Mail, Compass } from 'lucide-react';
import { Link } from 'react-router-dom';

export const Footer = () => {
    return (
        <footer className="bg-background border-t border-white/10 py-6 md:py-8">
            <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
                <div className="grid grid-cols-2 md:grid-cols-4 gap-x-4 gap-y-6 md:gap-8 mb-6 md:mb-8">
                    <div className="col-span-2">
                        <Link to="/" className="flex items-center space-x-2 mb-2 md:mb-4">
                            <Compass className="h-6 w-6 md:h-8 md:w-8 text-emerald-500" />
                            <span className="text-lg md:text-xl font-bold bg-clip-text text-transparent bg-gradient-to-r from-emerald-400 to-cyan-300">
                                Wealth Compass
                            </span>
                        </Link>
                        <p className="text-gray-400 text-sm max-w-sm hidden md:block">
                            Empowering your financial journey with clarity, privacy, and control.
                            Open source and privacy-first.
                        </p>
                    </div>

                    <div>
                        <h4 className="text-white font-semibold mb-2 md:mb-3 text-sm">Product</h4>
                        <ul className="space-y-1.5 text-sm">
                            <li><Link to="/features" className="text-gray-400 hover:text-white transition-colors">Features</Link></li>
                            <li><Link to="/tutorial" className="text-gray-400 hover:text-white transition-colors">Tutorial</Link></li>
                            <li><Link to="/faq" className="text-gray-400 hover:text-white transition-colors">FAQ</Link></li>
                        </ul>
                    </div>

                    <div>
                        <h4 className="text-white font-semibold mb-2 md:mb-3 text-sm">Connect</h4>
                        <div className="flex space-x-4 mb-3">
                            <a href="https://github.com/simo-hue" target="_blank" rel="noopener noreferrer" className="text-gray-400 hover:text-white transition-colors">
                                <Github className="h-4 w-4" />
                            </a>
                            <a href="https://www.linkedin.com/in/simonemattioli2003/" target="_blank" rel="noopener noreferrer" className="text-gray-400 hover:text-white transition-colors">
                                <Linkedin className="h-4 w-4" />
                            </a>
                            <a href="mailto:simo.mattioli@example.com" className="text-gray-400 hover:text-white transition-colors">
                                <Mail className="h-4 w-4" />
                            </a>
                        </div>
                        <ul className="space-y-1.5 text-sm">
                            <li><Link to="/founder" className="text-gray-400 hover:text-white transition-colors">Founder</Link></li>
                        </ul>
                    </div>
                </div>

                <div className="border-t border-white/10 pt-4 md:pt-6 flex flex-col md:flex-row justify-between items-center text-xs text-gray-500">
                    <p>&copy; {new Date().getFullYear()} Wealth Compass. All rights reserved.</p>
                    <div className="flex space-x-4 md:space-x-6 mt-3 md:mt-0">
                        <Link to="/privacy" className="hover:text-white transition-colors">Privacy Policy</Link>
                        <Link to="/terms" className="hover:text-white transition-colors">Terms of Service</Link>
                    </div>
                </div>
            </div>
        </footer>
    );
};
