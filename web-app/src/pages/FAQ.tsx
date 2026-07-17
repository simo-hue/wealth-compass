import { motion } from 'framer-motion';
import {
    Accordion,
    AccordionContent,
    AccordionItem,
    AccordionTrigger,
} from "../components/ui/accordion";
import { Search } from 'lucide-react';
import React from 'react';

const faqs = [
    // General
    { q: "What is Wealth Compass?", a: "Wealth Compass is a comprehensive personal finance dashboard designed to give you a 360-degree view of your financial health, from net worth to daily cash flow." },
    { q: "Is Wealth Compass free?", a: "Yes, Wealth Compass is an open-source project and is completely free to use for personal purposes." },
    { q: "Who is this software for?", a: "It is for anyone who wants to take control of their finances, whether you are a student, a professional, or someone planning for retirement." },
    { q: "Do I need technical skills to use it?", a: "While it helps to have some technical knowledge for the self-hosted installation, the user interface is intuitive and easy to use for everyone." },
    { q: "Can I use it on my mobile phone?", a: "Yes, the application is fully responsive and optimized for mobile devices, tablets, and desktops." },
    { q: "Is there a cloud version?", a: "Currently, Wealth Compass is designed to be self-hosted to ensure maximum privacy for your data. There is no official cloud SaaS version." },
    { q: "How do I get started?", a: "You can follow our comprehensive Tutorial page to set up your own instance of Wealth Compass in minutes." },
    { q: "Does it support multiple currencies?", a: "Yes, the system is designed to handle multiple currencies, with real-time conversion rates." },
    { q: "Is it available in other languages?", a: "The primary language is English, but we have started efforts to support Italian and other languages." },
    { q: "Can I contribute to the project?", a: "Absolutely! We welcome contributions from the community on our GitHub repository." },

    // Security & Privacy
    { q: "Is my financial data safe?", a: "Security is our top priority. We use industry-standard encryption and Row Level Security (RLS) to protect your data." },
    { q: "Where is my data stored?", a: "Your data is stored in your own Supabase instance, meaning you have full ownership and control over it." },
    { q: "Does the founder see my data?", a: "No. Since you host the backend yourself on Supabase, no one else has access to your data." },
    { q: "What is 'Privacy Mode'?", a: "Privacy Mode allows you to blur all sensitive financial figures on the screen with one click, perfect for public environments." },
    { q: "Can I export my data?", a: "Yes, you can export your transaction history and other data to CSV formats for external analysis." },
    { q: "Is there 2FA support?", a: "If you use Supabase Auth, you can configure various authentication methods including those with higher security standards." },
    { q: "How often is data backed up?", a: "Supabase provides automated backups, but you can also manually export your data anytime." },
    { q: "Can I delete my account?", a: "Yes, you have full control to delete your data and instance whenever you choose." },
    { q: "Are there tracking cookies?", a: "We prioritize privacy and do not use invasive tracking cookies." },
    { q: "Is the code audited?", a: "Being open source, the code is available for anyone to review and audit for security vulnerabilities." },

    // Features - Dashboard
    { q: "What metrics are on the dashboard?", a: "The dashboard shows Net Worth, Asset Allocation, Total Liquidity, Investment Value, and Monthly Cash Flow." },
    { q: "Can I customize the dashboard layout?", a: "The current layout is optimized for clarity, but future updates may include widget customization." },
    { q: "How often does the Net Worth update?", a: "Net Worth is calculated in real-time based on your current asset values and liabilities." },
    { q: "Does it track liabilities?", a: "Yes, you can track loans, mortgages, and credit card debt to get a true Net Worth figure." },
    { q: "Can I see historical data?", a: "Yes, interactive charts allow you to visualize your financial progress over time." },

    // Features - Investments
    { q: "Which stock markets are supported?", a: "We use Finnhub and Yahoo Finance APIs, covering major global stock markets including US, European, and Asian exchanges." },
    { q: "Does it track dividends?", a: "Dividend tracking is a planned feature. Currently, you can manually add dividend income as cash flow." },
    { q: "How are crypto prices updated?", a: "Crypto prices are fetched in real-time from CoinGecko's API." },
    { q: "Can I track NFTs?", a: "Currently, we focus on fungible tokens, but you can add NFTs as custom assets." },
    { q: "Does it calculate ROI?", a: "Yes, the portfolio view calculates your Return on Investment based on cost basis and current market value." },
    { q: "Can I categorize assets by sector?", a: "Yes, the system automatically or manually assigns sectors to your holdings for diversification analysis." },
    { q: "Does it support ETFs?", a: "Yes, ETFs are fully supported and treated similarly to stocks." },
    { q: "What about mutual funds?", a: "You can track mutual funds if they have a ticker symbol supported by our data providers." },
    { q: "Can I manually update prices?", a: "Yes, for assets without public tickers (like real estate), you can manually update their value." },
    { q: "Is there a limit to how many assets I can track?", a: "No, there is no hard limit on the number of assets you can add." },

    // Features - Cash Flow
    { q: "How do I add transactions?", a: "You can easily add income or expenses via the 'Add Transaction' button on the Cash Flow page." },
    { q: "Can I create custom categories?", a: "Yes, you can define your own categories to organize your spending habits." },
    { q: "Are recurring transactions supported?", a: "We are working on automated recurring transactions for subscriptions and rent." },
    { q: "Does it connect to my bank account?", a: "To ensure privacy and avoid fees, we currently rely on manual entry or CSV import rather than direct bank connections." },
    { q: "Can I set budgets?", a: "Budgeting features are on our roadmap for future releases." },
    { q: "How do I analyze my spending?", a: "The Analytics tab provides pie charts and trend lines to breakdown your expenses by category." },

    // Technical
    { q: "What tech stack is used?", a: "Wealth Compass is built with React, TypeScript, Tailwind CSS, and uses Supabase for the backend." },
    { q: "Do I need a server to run it?", a: "You can run it locally on your computer or deploy it to a static host (like Vercel) connecting to Supabase." },
    { q: "Is Docker supported?", a: "Yes, we provide a Dockerfile for easy containerized deployment." },
    { q: "What are the requirements?", a: "You need Node.js installed if running locally, and a free Supabase account." },
    { q: "How do I update the software?", a: "Simply pull the latest changes from the GitHub repository and rebuild the project." },
    { q: "Can I fork the project?", a: "Yes, you are free to fork the repository and modify it for your own needs." },
    { q: "Is there an API?", a: "The application interacts with Supabase, which provides a RESTful API for your data automatically." },
    { q: "What if I find a bug?", a: "Please open an issue on our GitHub repository describing the problem." },
    { q: "Can I request a feature?", a: "Yes, we love community feedback! Submit your ideas via GitHub issues." },
    { q: "How does the caching work?", a: "We use React Query to cache data and minimize API calls, ensuring the app feels snappy." },

    // Closing
    { q: "Is there a dark mode?", a: "Yes, Wealth Compass is designed with a sleek dark mode by default." },
    { q: "Can I print reports?", a: "You can use your browser's print function, which will capture the current dashboard view." },
    { q: "How do I contact support?", a: "For direct support, you can reach out via the contact details on the Founder page." },
    { q: "Is there a community chat?", a: "Not yet, but we are considering starting a Discord server." },
    { q: "Why did you build this?", a: "To provide a transparent, private alternative to paid finance trackers that sell your data." },
];

export const FAQ = () => {
    const [search, setSearch] = React.useState("");

    const filteredFaqs = faqs.filter(f =>
        f.q.toLowerCase().includes(search.toLowerCase()) ||
        f.a.toLowerCase().includes(search.toLowerCase())
    );

    return (
        <div className="py-20 bg-background min-h-screen">
            <div className="max-w-3xl mx-auto px-4 sm:px-6 lg:px-8">
                <motion.div
                    initial={{ opacity: 0, y: 20 }}
                    animate={{ opacity: 1, y: 0 }}
                    className="text-center mb-12"
                >
                    <h1 className="text-4xl font-bold text-white mb-4">Frequently Asked Questions</h1>
                    <p className="text-gray-400">Everything you need to know about Wealth Compass.</p>
                </motion.div>

                <div className="mb-8 relative">
                    <input
                        type="text"
                        placeholder="Search questions..."
                        value={search}
                        onChange={(e) => setSearch(e.target.value)}
                        className="w-full bg-white/5 border border-white/10 rounded-xl px-12 py-4 text-white placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-emerald-500 transition-all"
                    />
                    <Search className="absolute left-4 top-1/2 -translate-y-1/2 h-5 w-5 text-gray-500" />
                </div>

                <motion.div
                    initial={{ opacity: 0 }}
                    animate={{ opacity: 1 }}
                    transition={{ delay: 0.2 }}
                >
                    <Accordion type="single" collapsible className="w-full space-y-4">
                        {filteredFaqs.map((faq, index) => (
                            <AccordionItem key={index} value={`item-${index}`} className="border border-white/10 rounded-xl px-4 bg-white/5 data-[state=open]:bg-white/10 transition-colors">
                                <AccordionTrigger className="text-left text-lg font-medium text-white hover:no-underline py-4">
                                    {faq.q}
                                </AccordionTrigger>
                                <AccordionContent className="text-gray-400 pb-4">
                                    {faq.a}
                                </AccordionContent>
                            </AccordionItem>
                        ))}
                    </Accordion>

                    {filteredFaqs.length === 0 && (
                        <div className="text-center text-gray-500 py-12">
                            No questions found matching your search.
                        </div>
                    )}
                </motion.div>
            </div>
        </div>
    );
};
