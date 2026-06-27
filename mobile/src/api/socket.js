import { Socket } from 'phoenix';
import { API_URL } from './client';

// Derive the websocket URL from the same auto-detected API host (http -> ws).
const WS_URL = API_URL.replace(/^http/, 'ws') + '/socket';

// Open a draft channel for a duel. `token` is the same API token used for REST.
// `handlers` = { onJoin(reply), onUpdate(payload), onError(reply) }.
// Returns { ready, makePick, leave } — makePick returns the Phoenix push so the
// caller can attach .receive('error', ...) for rejected picks.
export function connectDraft(duelId, token, handlers) {
  const socket = new Socket(WS_URL, { params: { token } });
  socket.connect();

  const channel = socket.channel(`draft:${duelId}`, {});
  channel.on('update', (payload) => handlers.onUpdate?.(payload));

  channel
    .join()
    .receive('ok', (reply) => handlers.onJoin?.(reply))
    .receive('error', (reply) => handlers.onError?.(reply));

  return {
    ready: () => channel.push('ready', {}),
    makePick: (playerId) => channel.push('make_pick', { player_id: playerId }),
    cancel: () => channel.push('cancel', {}),
    leave: () => {
      channel.leave();
      socket.disconnect();
    },
  };
}
