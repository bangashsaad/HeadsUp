import { useSyncExternalStore } from 'react';

// Tiny cross-tab signals the tab bar renders: is a draft live right now, and
// how many friend requests are waiting. Screens that learn an answer call the
// setter; the tab bar shows a blinking dot / a count bubble.
function signal(initial) {
  let value = initial;
  const subs = new Set();

  return {
    set(next) {
      if (value === next) return;
      value = next;
      subs.forEach((fn) => fn());
    },
    use() {
      // eslint-disable-next-line react-hooks/rules-of-hooks
      return useSyncExternalStore(
        (cb) => {
          subs.add(cb);
          return () => subs.delete(cb);
        },
        () => value
      );
    },
  };
}

const draftLive = signal(false);
const friendReqs = signal(0);

export function setDraftLive(v) {
  draftLive.set(!!v);
}

export function useDraftLive() {
  return draftLive.use();
}

export function setFriendReqs(n) {
  friendReqs.set(Number(n) || 0);
}

export function useFriendReqs() {
  return friendReqs.use();
}
