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

// --- friend groups (private, owner-named recipient tabs) -------------------

export function listFriendGroups(token) {
  return apiRequest('/api/friend-groups', { token });
}

export function createFriendGroup(token, name) {
  return apiRequest('/api/friend-groups', { method: 'POST', token, body: { name } });
}

export function renameFriendGroup(token, id, name) {
  return apiRequest(`/api/friend-groups/${id}`, { method: 'PUT', token, body: { name } });
}

export function setFriendGroupMembers(token, id, userIds) {
  return apiRequest(`/api/friend-groups/${id}/members`, { method: 'PUT', token, body: { user_ids: userIds } });
}

export function deleteFriendGroup(token, id) {
  return apiRequest(`/api/friend-groups/${id}`, { method: 'DELETE', token });
}

// --- blocking --------------------------------------------------------------

export function blockUser(token, userId) {
  return apiRequest(`/api/users/${userId}/block`, { method: 'POST', token });
}

export function unblockUser(token, userId) {
  return apiRequest(`/api/users/${userId}/block`, { method: 'DELETE', token });
}

export function listBlocked(token) {
  return apiRequest('/api/blocks', { token });
}
