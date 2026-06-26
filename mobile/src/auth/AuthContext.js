import { createContext, useContext, useEffect, useState } from 'react';
import * as SecureStore from 'expo-secure-store';
import { apiRequest } from '../api/client';

const TOKEN_KEY = 'auth_token';
const AuthContext = createContext(null);

export function AuthProvider({ children }) {
  const [token, setToken] = useState(null);
  const [user, setUser] = useState(null);
  const [loading, setLoading] = useState(true); // true while restoring session on launch

  // On app launch: if we saved a token last time, verify it's still valid.
  useEffect(() => {
    (async () => {
      try {
        const saved = await SecureStore.getItemAsync(TOKEN_KEY);
        if (saved) {
          const data = await apiRequest('/api/me', { token: saved });
          setToken(saved);
          setUser(data.user);
        }
      } catch (_) {
        // token invalid/expired or server unreachable — forget it
        await SecureStore.deleteItemAsync(TOKEN_KEY);
      } finally {
        setLoading(false);
      }
    })();
  }, []);

  async function persist({ token, user }) {
    await SecureStore.setItemAsync(TOKEN_KEY, token);
    setToken(token);
    setUser(user);
  }

  async function signUp({ username, email, password }) {
    const data = await apiRequest('/api/register', {
      method: 'POST',
      body: { username, email, password },
    });
    await persist(data);
  }

  async function signIn({ email, password }) {
    const data = await apiRequest('/api/login', {
      method: 'POST',
      body: { email, password },
    });
    await persist(data);
  }

  async function signOut() {
    try {
      if (token) await apiRequest('/api/logout', { method: 'DELETE', token });
    } catch (_) {
      // ignore network errors when logging out — we clear locally regardless
    }
    await SecureStore.deleteItemAsync(TOKEN_KEY);
    setToken(null);
    setUser(null);
  }

  return (
    <AuthContext.Provider value={{ user, token, loading, signUp, signIn, signOut }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used inside an AuthProvider');
  return ctx;
}
