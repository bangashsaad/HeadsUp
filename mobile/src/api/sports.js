import { apiRequest } from './client';

// Fetch the draftable player pool for a sport, with optional name search and
// position filter.
export function listPlayers(token, { sport, q, position, team }) {
  let path = `/api/players?sport=${encodeURIComponent(sport)}`;
  if (q) path += `&q=${encodeURIComponent(q)}`;
  if (position) path += `&position=${encodeURIComponent(position)}`;
  if (team) path += `&team=${encodeURIComponent(team)}`;
  return apiRequest(path, { token });
}

// A player's profile: season averages + a fantasy game log.
export function getPlayerProfile(token, id) {
  return apiRequest(`/api/players/${id}/profile`, { token });
}

// Cross-sport player search by name (real ESPN players only).
export function searchPlayers(token, q) {
  return apiRequest(`/api/players/search?q=${encodeURIComponent(q)}`, { token });
}

// Upcoming games for a sport (schedule).
// Which sports are playable right now (in-season window + real pool).
export function getSportsStatus(token) {
  return apiRequest('/api/sports/status', { token });
}

export function listUpcomingGames(token, sport = 'wnba') {
  return apiRequest(`/api/games/upcoming?sport=${encodeURIComponent(sport)}`, { token });
}

// One ET calendar day of games — past days included (finished games keep
// their box scores browsable).
export function listGamesOn(token, sport = 'wnba', date) {
  return apiRequest(`/api/games/scoreboard?sport=${encodeURIComponent(sport)}&date=${encodeURIComponent(date)}`, { token });
}

// Live/final box score for one game, with a fantasy column per player.
export function getBoxScore(token, sport, eventId) {
  return apiRequest(`/api/games/${eventId}/boxscore?sport=${encodeURIComponent(sport)}`, { token });
}
