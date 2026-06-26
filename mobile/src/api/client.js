import Constants from 'expo-constants';

// Auto-detect the Mac's address from whatever Expo Go is already connected to,
// so we NEVER hardcode a WiFi IP again. If your network changes, this just
// follows along. Falls back to localhost outside of Expo Go.
function resolveApiUrl() {
  const hostUri =
    Constants.expoConfig?.hostUri ||
    Constants.expoGoConfig?.debuggerHost ||
    Constants.manifest2?.extra?.expoGo?.debuggerHost ||
    '';

  const host = hostUri.split(':')[0] || 'localhost';
  return `http://${host}:4000`;
}

export const API_URL = resolveApiUrl();

// A custom error type so screens can show the server's message.
export class ApiError extends Error {
  constructor(message, status, errors) {
    super(message);
    this.status = status;
    this.errors = errors;
  }
}

// One helper for every server call: sets headers, attaches the login token,
// parses JSON, and throws a readable error on failure.
export async function apiRequest(path, { method = 'GET', body, token } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;

  const res = await fetch(`${API_URL}${path}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });

  if (res.status === 204) return null; // No Content (e.g. logout)

  let data = null;
  try {
    data = await res.json();
  } catch (_) {
    // response wasn't JSON; leave data as null
  }

  if (!res.ok) {
    throw new ApiError(
      firstErrorMessage(data) || `Request failed (${res.status})`,
      res.status,
      data?.errors
    );
  }

  return data;
}

// Turn the server's error shapes into one readable sentence.
// Handles { detail: "..." } and field errors like { username: ["taken"] }.
function firstErrorMessage(data) {
  const errors = data?.errors;
  if (!errors) return null;
  if (typeof errors.detail === 'string') return errors.detail;

  const firstField = Object.keys(errors)[0];
  if (firstField) {
    const value = errors[firstField];
    const message = Array.isArray(value) ? value[0] : value;
    return `${firstField} ${message}`;
  }
  return null;
}
