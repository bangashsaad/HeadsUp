// Eastern Time, done properly. The old helpers hardcoded ET as UTC-4, which
// is only true during daylight saving — every "tonight"/tip-time label would
// have drifted an hour when EST starts in November, mid-NFL-season. Intl
// carries the real tz database (Hermes ships it on iOS).
const ET = 'America/New_York';

const dayFmt = new Intl.DateTimeFormat('en-CA', { timeZone: ET, year: 'numeric', month: '2-digit', day: '2-digit' });
const timeFmt = new Intl.DateTimeFormat('en-US', { timeZone: ET, hour: 'numeric', minute: '2-digit' });
const weekdayFmt = new Intl.DateTimeFormat('en-US', { timeZone: ET, weekday: 'short' });

// A UTC instant's ET calendar day as "YYYY-MM-DD" (en-CA formats exactly so).
export function etDayISO(msOrIso = Date.now()) {
  const d = new Date(msOrIso);
  if (Number.isNaN(d.getTime())) return '';
  return dayFmt.format(d);
}

// "7:05 PM" in ET.
export function etTime(iso) {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  return timeFmt.format(d);
}

// "Sun" in ET.
export function etWeekday(iso) {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  return weekdayFmt.format(d);
}

// Draft-board label: "7:00 PM ET" today, "Tmw 7:05 PM ET" tomorrow, and the
// real weekday beyond that — a Sunday game drafted on Thursday used to lie
// with "Tmw".
export function nextGameLabel(iso) {
  if (!iso) return null;
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;

  const day = dayFmt.format(d);
  const label = `${timeFmt.format(d)} ET`;
  if (day === etDayISO()) return label;
  if (day === etDayISO(Date.now() + 86_400_000)) return `Tmw ${label}`;
  return `${weekdayFmt.format(d)} ${label}`;
}
