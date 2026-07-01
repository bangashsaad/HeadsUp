import { apiRequest } from './client';

// Home dashboard buckets + record snapshot.
export const getHome = (token) => apiRequest('/api/home', { token });

// The viewer's record + head-to-head breakdown.
export const getMyStats = (token) => apiRequest('/api/me/stats', { token });

// The viewer's trophy catalog with progress.
export const getAchievements = (token) => apiRequest('/api/me/achievements', { token });

// Standings among the viewer and their friends.
export const getLeaderboard = (token) => apiRequest('/api/leaderboard', { token });
