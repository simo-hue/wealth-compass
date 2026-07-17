import React, { createContext, useContext, useEffect, useState } from 'react';
import { Session, User } from '@supabase/supabase-js';
import { supabase } from '@/lib/supabase';

interface AuthContextType {
    user: User | null;
    session: Session | null;
    loading: boolean;
    signInWithEmail: (email: string, password: string) => Promise<{ error: any }>;
    signOut: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: React.ReactNode }) {
    const [user, setUser] = useState<User | null>(null);
    const [session, setSession] = useState<Session | null>(null);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        // Check active sessions and sets the user
        supabase.auth.getSession().then(({ data: { session } }) => {
            setSession(session);
            setUser(session?.user ?? null);
            setLoading(false);
        });

        // Listen for changes on auth state (sing in, sign out, etc.)
        const { data: { subscription } } = supabase.auth.onAuthStateChange(async (_event, session) => {
            const allowedEmail = import.meta.env.VITE_ALLOWED_EMAIL;

            if (session?.user && allowedEmail && session.user.email !== allowedEmail) {
                await supabase.auth.signOut();
                setSession(null);
                setUser(null);
                // We could use a toast here but this runs outside component render cycle often
                console.warn('Access Restricted: Unauthorized Email');
            } else {
                setSession(session);
                setUser(session?.user ?? null);
            }
            setLoading(false);
        });

        return () => subscription.unsubscribe();
    }, []);

    const signInWithEmail = async (email: string, password: string) => {
        const allowedEmail = import.meta.env.VITE_ALLOWED_EMAIL;

        // If VITE_ALLOWED_EMAIL is set, enforce it. If not set, we're in "open" mode (or misconfigured).
        // Safest to warn if not set, but adhering to user request to fix hardcoding.
        if (allowedEmail && email !== allowedEmail) {
            return { error: { message: 'Unauthorized access. This account is not allowed.' } };
        }

        const { data, error } = await supabase.auth.signInWithPassword({
            email,
            password,
        });

        return { data, error };
    };

    const signOut = async () => {
        await supabase.auth.signOut();
    };

    return (
        <AuthContext.Provider value={{ user, session, loading, signInWithEmail, signOut }}>
            {children}
        </AuthContext.Provider>
    );
}

export const useAuth = () => {
    const context = useContext(AuthContext);
    if (context === undefined) {
        throw new Error('useAuth must be used within an AuthProvider');
    }
    return context;
};
