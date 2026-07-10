// Team-art helpers for the live-scores screens: ESPN sends a team's primary
// color as bare hex ("78BE20") and a logo URL on every game side.

export function teamColor(side, fallback = '#7C5CFF') {
  const c = side?.color;
  if (!c) return fallback;
  return c.startsWith('#') ? c : `#${c}`;
}

export function lastName(name) {
  const parts = String(name || '').trim().split(' ');
  return parts[parts.length - 1] || '';
}

export function initials(name) {
  const parts = String(name || '').trim().split(' ');
  return ((parts[0]?.[0] || '') + (parts[1]?.[0] || '')).toUpperCase();
}
