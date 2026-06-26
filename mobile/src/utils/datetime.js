const MONTHS = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

// Format an ISO timestamp like "Jun 27, 7:30 PM" without relying on Intl.
export function formatDateTime(iso) {
  if (!iso) return '';
  const d = new Date(iso);
  let hours = d.getHours();
  const ampm = hours >= 12 ? 'PM' : 'AM';
  hours = hours % 12 || 12;
  const mins = String(d.getMinutes()).padStart(2, '0');
  return `${MONTHS[d.getMonth()]} ${d.getDate()}, ${hours}:${mins} ${ampm}`;
}
