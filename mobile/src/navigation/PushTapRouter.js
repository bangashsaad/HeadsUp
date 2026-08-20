import { useEffect, useRef } from 'react';
import * as Notifications from 'expo-notifications';
import { useAuth } from '../auth/AuthContext';
import { getDuel } from '../api/duels';
import { navigationRef } from './ref';

// Turns a tapped push notification into navigation. Server payloads carry
// `data: { type, duel_id }`:
//   duel   -> the challenge screen        (you were challenged)
//   draft  -> straight into the draft room (you're on the clock)
//   result -> the final scoreboard        (duel settled)
//   friends-> the friends tab             (friend request)
// Handles warm taps (listener) and cold starts (last response), deduped by the
// notification id. Renders nothing; mount once inside the NavigationContainer.
export default function PushTapRouter() {
  const { token } = useAuth();
  const handled = useRef(null);
  const tokenRef = useRef(token);
  tokenRef.current = token;

  useEffect(() => {
    // Cold start: the tap that launched the app.
    Notifications.getLastNotificationResponseAsync()
      .then((response) => response && handle(response))
      .catch(() => {});

    // Warm taps while the app is running/backgrounded.
    const sub = Notifications.addNotificationResponseReceivedListener(handle);
    return () => sub.remove();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  function handle(response) {
    const id = response?.notification?.request?.identifier;
    if (!id || handled.current === id) return;
    handled.current = id;

    const data = response.notification.request.content.data || {};
    route(data, 0);
  }

  // Navigation may not be ready yet on a cold start — retry briefly.
  function route(data, attempt) {
    if (!navigationRef.isReady()) {
      if (attempt < 15) setTimeout(() => route(data, attempt + 1), 300);
      return;
    }

    // initial: false keeps the Duels list beneath the pushed screen, so the
    // back button always works even when the tap is what mounted the stack.
    switch (data.type) {
      case 'duel':
        navigationRef.navigate('DuelsTab', { screen: 'DuelDetail', params: { id: data.duel_id }, initial: false });
        break;

      case 'draft':
        withOpponent(data.duel_id, (opponentName) =>
          navigationRef.navigate('DuelsTab', {
            screen: 'DraftRoom',
            params: { id: data.duel_id, opponentName },
            initial: false,
          })
        );
        break;

      case 'result':
        withOpponent(data.duel_id, (opponentName) =>
          navigationRef.navigate('DuelsTab', {
            screen: 'Results',
            params: { id: data.duel_id, opponentName },
            initial: false,
          })
        );
        break;

      case 'friends':
        navigationRef.navigate('FriendsTab');
        break;

      default:
        break;
    }
  }

  // Best-effort opponent-name lookup so screen headers read right; falls back
  // to the screens' own 'Opponent' default if the fetch fails.
  function withOpponent(duelId, navigate) {
    const apiToken = tokenRef.current;
    if (!apiToken) return navigate(undefined);

    getDuel(apiToken, duelId)
      .then((res) => navigate(res?.duel?.opponent?.username))
      .catch(() => navigate(undefined));
  }

  return null;
}
