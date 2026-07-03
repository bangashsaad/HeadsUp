import { apiRequest } from './client';

// All the friend-related server calls in one place. Each takes the login token.

export function searchUsers(token, query) {
  const q = encodeURIComponent(query);
  return apiRequest(`/api/users/search?q=${q}`, { token });
}

export function listFriends(token) {
  return apiRequest('/api/friends', { token });
}

// A user's public profile: relationship to you, their record, your H2H vs them.
export function getUserProfile(token, id) {
  return apiRequest(`/api/users/${id}`, { token });
}

export function listRequests(token) {
  return apiRequest('/api/friends/requests', { token });
}

export function sendFriendRequest(token, userId) {
  return apiRequest('/api/friends', { method: 'POST', token, body: { user_id: userId } });
}

export function acceptRequest(token, friendshipId) {
  return apiRequest(`/api/friends/requests/${friendshipId}/accept`, { method: 'POST', token });
}

export function deleteRequest(token, friendshipId) {
  return apiRequest(`/api/friends/requests/${friendshipId}`, { method: 'DELETE', token });
}
