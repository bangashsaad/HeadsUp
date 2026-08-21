import { createContext, useCallback, useContext, useEffect, useRef } from 'react';
import { AppState } from 'react-native';
import { useAuth } from '../auth/AuthContext';
import { connectUser } from '../api/socket';

// Live duel events for the whole app: one socket on the user's personal
// channel, and a hook any screen can use to refetch when a duel it cares
// about moves. Coming back to the foreground emits a synthetic `resync`
// (duel_id null) so screens catch anything that happened while suspended.
const Ctx = createContext(null);

export function DuelEventsProvider({ children }) {
  const { user, token } = useAuth();
  const listeners = useRef(new Set());

  const emit = useCallback((event) => {
    listeners.current.forEach((fn) => {
      try {
        fn(event);
      } catch (e) {
        // one bad listener must not break the others
      }
    });
  }, []);

  useEffect(() => {
    if (!user?.id || !token) return undefined;
    const conn = connectUser(user.id, token, {
      onDuelChanged: (payload) => emit({ duel_id: payload.duel_id, status: payload.status }),
    });
    const sub = AppState.addEventListener('change', (state) => {
      if (state === 'active') emit({ duel_id: null, status: 'resync' });
    });
    return () => {
      sub.remove();
      conn.leave();
    };
  }, [user?.id, token, emit]);

  const subscribe = useCallback((fn) => {
    listeners.current.add(fn);
    return () => listeners.current.delete(fn);
  }, []);

  return <Ctx.Provider value={subscribe}>{children}</Ctx.Provider>;
}

// `handler({duel_id, status})` — duel_id is null for a foreground resync.
export function useDuelEvents(handler, deps = []) {
  const subscribe = useContext(Ctx);
  const ref = useRef(handler);
  ref.current = handler;
  useEffect(() => {
    if (!subscribe) return undefined;
    return subscribe((e) => ref.current?.(e));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [subscribe, ...deps]);
}
