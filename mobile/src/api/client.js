import Constants from 'expo-constants';

// Where's the backend?
//  - Explicit override: start Metro with EXPO_PUBLIC_API_URL=https://... to force
//    a target (e.g. point the dev build at production for a quick check).
//  - DEV (connected to a Metro dev server): talk to THAT machine's local
//    backend on :4000 — auto-detected, so a changing WiFi IP just follows along.
//  - STANDALONE build (no Metro — e.g. a preview build friends install): use the
//    configured production URL from app.json `extra.apiUrl` (the deployed server).
function resolveApiUrl() {
  if (process.env.EXPO_PUBLIC_API_URL) return process.env.EXPO_PUBLIC_API_URL;

  const hostUri =
    Constants.expoConfig?.hostUri ||
    Constants.expoGoConfig?.debuggerHost ||
    Constants.manifest2?.extra?.expoGo?.debuggerHost ||
    '';

  if (hostUri) {
    const host = hostUri.split(':')[0] || 'localhost';
    return `http://${host}:4000`;
  }

  return Constants.expoConfig?.extra?.apiUrl || 'http://localhost:4000';
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
