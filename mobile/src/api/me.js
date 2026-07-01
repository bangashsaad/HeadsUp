import { apiRequest } from './client';

// Home dashboard buckets + record snapshot.
export const getHome = (token) => apiRequest('/api/home', { token });

// The viewer's record + head-to-head breakdown.
export const getMyStats = (token) => apiRequest('/api/me/stats', { token });

// Standings among the viewer and their friends.
export const getLeaderboard = (token) => apiRequest('/api/leaderboard', { token });
