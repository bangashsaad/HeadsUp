import { createContext, useContext, useEffect, useRef, useState } from 'react';
import * as SecureStore from 'expo-secure-store';
import { setOnUnauthorized, apiRequest } from '../api/client';
import { registerForPush, unregisterPush } from '../push';

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
          registerForPush(saved);
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
    registerForPush(token);
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

  async function changePassword({ currentPassword, newPassword }) {
    await apiRequest('/api/me/password', {
      method: 'PUT',
      token,
      body: { current_password: currentPassword, password: newPassword },
    });
  }

  // Apple-required account deletion: server anonymizes the account, cancels
  // live duels with refunds, and kills every login token — then we clear
  // local state exactly like a sign-out.
  async function deleteAccount(password) {
    await apiRequest('/api/me', { method: 'DELETE', token, body: { password } });
    await SecureStore.deleteItemAsync(TOKEN_KEY);
    setToken(null);
    signOutRef.current = null;
    setUser(null);
  }

  // Email verification (6-digit codes). Verify refreshes the user so the
  // "verify your email" banner disappears the moment it lands.
  async function verifyEmail(code) {
    const data = await apiRequest('/api/me/verify', { method: 'POST', token, body: { code } });
    setUser(data.user);
  }

  function resendVerification() {
    return apiRequest('/api/me/verify/resend', { method: 'POST', token });
  }

  // Password reset for the logged-out: request a code, then trade code + new
  // password. Both unauthenticated.
  function forgotPassword(email) {
    return apiRequest('/api/password/forgot', { method: 'POST', body: { email } });
  }

  function resetPassword({ email, code, password }) {
    return apiRequest('/api/password/reset', { method: 'POST', body: { email, code, password } });
  }

  // Re-pull /api/me (coin balance rides the user object) after anything that
  // moves coins: staking a duel, results landing, the wallet screen opening.
  async function refreshUser() {
    if (!token) return;
    try {
      const data = await apiRequest('/api/me', { token });
      setUser(data.user);
    } catch (_) {
      // transient network error — keep the stale user rather than logging out
    }
  }

  // A 401 on any authenticated call = this token is dead (changed password,
  // purged account). Sign out instead of leaving every screen quietly broken.
  const signOutRef = useRef(null);
  useEffect(() => {
    setOnUnauthorized(() => signOutRef.current?.());
  }, []);

  async function signOut() {
    signOutRef.current = null;
    try {
      if (token) {
        await unregisterPush(token);
        await apiRequest('/api/logout', { method: 'DELETE', token });
      }
    } catch (_) {
      // ignore network errors when logging out — we clear locally regardless
    }
    await SecureStore.deleteItemAsync(TOKEN_KEY);
    setToken(null);
    setUser(null);
  }

  // Latest closure every render; sign-out/delete null it to stop loops.
  signOutRef.current = signOut;

  return (
    <AuthContext.Provider
      value={{
        user,
        token,
        loading,
        signUp,
        signIn,
        signOut,
        changePassword,
        deleteAccount,
        verifyEmail,
        resendVerification,
        forgotPassword,
        resetPassword,
        refreshUser,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used inside an AuthProvider');
  return ctx;
}
