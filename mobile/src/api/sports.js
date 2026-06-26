import { apiRequest } from './client';

// Fetch the draftable player pool for a sport, with optional name search and
// position filter.
export function listPlayers(token, { sport, q, position }) {
  let path = `/api/players?sport=${encodeURIComponent(sport)}`;
  if (q) path += `&q=${encodeURIComponent(q)}`;
  if (position) path += `&position=${encodeURIComponent(position)}`;
  return apiRequest(path, { token });
}
