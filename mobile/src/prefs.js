import { createContext, useContext, useEffect, useState } from 'react';
import * as SecureStore from 'expo-secure-store';
import { setHapticsEnabled } from './haptics';

const HAPTICS_KEY = 'pref_haptics';
const PrefsContext = createContext(null);

export function PreferencesProvider({ children }) {
  const [haptics, setHapticsState] = useState(true);

  useEffect(() => {
    (async () => {
      try {
        const saved = await SecureStore.getItemAsync(HAPTICS_KEY);
        const on = saved == null ? true : saved === '1';
        setHapticsState(on);
        setHapticsEnabled(on);
      } catch (_) {}
    })();
  }, []);

  function setHaptics(on) {
    setHapticsState(on);
    setHapticsEnabled(on);
    SecureStore.setItemAsync(HAPTICS_KEY, on ? '1' : '0').catch(() => {});
  }

  return <PrefsContext.Provider value={{ haptics, setHaptics }}>{children}</PrefsContext.Provider>;
}

export function usePrefs() {
  return useContext(PrefsContext) || { haptics: true, setHaptics: () => {} };
}
