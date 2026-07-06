import { useSyncExternalStore } from 'react';

// A tiny cross-tab signal: is any draft live right now? Screens that learn the
// answer (Home, Duels, Draft hub) call setDraftLive; the tab bar blinks.
let draftLive = false;
const subs = new Set();

export function setDraftLive(v) {
  const next = !!v;
  if (draftLive === next) return;
  draftLive = next;
  subs.forEach((fn) => fn());
}

export function useDraftLive() {
  return useSyncExternalStore(
    (cb) => {
      subs.add(cb);
      return () => subs.delete(cb);
    },
    () => draftLive
  );
}
