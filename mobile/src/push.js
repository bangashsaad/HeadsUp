import * as Device from 'expo-device';
import * as Notifications from 'expo-notifications';
import Constants from 'expo-constants';
import { apiRequest } from './api/client';

// While the app is OPEN, suppress banners/sounds — in-app screens already show
// everything live (draft turns, scores). Pushes are for when you're away.
Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowBanner: false,
    shouldShowList: true,
    shouldPlaySound: false,
    shouldSetBadge: false,
  }),
});

// Ask for permission, fetch this device's Expo push token, and register it with
// the backend. Safe to call on every login/restore: no-ops on simulators, when
// permission is denied, or when push isn't available in this build (e.g. a dev
// client without the APNs key yet) — a failed registration never breaks auth.
export async function registerForPush(apiToken) {
  try {
    if (!Device.isDevice) return;

    const { status: existing } = await Notifications.getPermissionsAsync();
    let status = existing;
    if (existing !== 'granted') {
      ({ status } = await Notifications.requestPermissionsAsync());
    }
    if (status !== 'granted') return;

    const projectId = Constants.expoConfig?.extra?.eas?.projectId;
    const { data: pushToken } = await Notifications.getExpoPushTokenAsync({ projectId });
    if (!pushToken) return;

    await apiRequest('/api/me/push_token', { method: 'PUT', token: apiToken, body: { push_token: pushToken } });
  } catch (_) {
    // push is best-effort — never let it interfere with login
  }
}

// Forget this device's token on the server (called on sign-out so a logged-out
// phone stops getting the previous user's notifications).
export async function unregisterPush(apiToken) {
  try {
    await apiRequest('/api/me/push_token', { method: 'PUT', token: apiToken, body: { push_token: null } });
  } catch (_) {
    // best-effort
  }
}
