import { apiRequest } from './client';

export const listDuels = (token) => apiRequest('/api/duels', { token });

export const getDuel = (token, id) => apiRequest(`/api/duels/${id}`, { token });

export const getResult = (token, id) => apiRequest(`/api/duels/${id}/result`, { token });

// Live standings for a drafted (unsettled) duel. Throws ApiError 409 once the
// duel is settled / not drafted — caller falls back to the final result.
export const getLiveResult = (token, id) => apiRequest(`/api/duels/${id}/live`, { token });

export const createChallenge = (token, body) =>
  apiRequest('/api/duels', { method: 'POST', token, body });

// action is "accept" | "decline" | "cancel"
export const respondToDuel = (token, id, action) =>
  apiRequest(`/api/duels/${id}/${action}`, { method: 'POST', token });

export const counterChallenge = (token, id, body) =>
  apiRequest(`/api/duels/${id}/counter`, { method: 'POST', token, body });
