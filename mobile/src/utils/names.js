// "A'ja Wilson" -> "A. Wilson" — fits half-width roster columns and ticker pills.
export function shortName(full) {
  const parts = String(full || '')
    .trim()
    .split(/\s+/);
  if (parts.length < 2) return full || '';
  return `${parts[0][0]}. ${parts.slice(1).join(' ')}`;
}
