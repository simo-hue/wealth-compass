import { createContext, useContext, ReactNode } from 'react';
import { useFinanceData } from '@/hooks/useFinanceData';
import { useSettings } from '@/contexts/SettingsContext';
import type { FinancialData } from '@/types/finance';

// Infer return type from the hook
type FinanceContextType = ReturnType<typeof useFinanceData>;

const FinanceContext = createContext<FinanceContextType | undefined>(undefined);

export function FinanceProvider({ children }: { children: ReactNode }) {
    const finance = useFinanceData();
    const { convertCurrency } = useSettings();

    // Wrap calculateTotals to automatically inject the converter
    const calculateTotals = () => {
        return finance.calculateTotals(convertCurrency);
    };



    return (
        <FinanceContext.Provider value={{ ...finance, calculateTotals }}>
            {children}
        </FinanceContext.Provider>
    );
}

export function useFinance() {
    const context = useContext(FinanceContext);
    if (context === undefined) {
        throw new Error('useFinance must be used within a FinanceProvider');
    }
    return context;
}
