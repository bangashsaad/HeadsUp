import { apiRequest } from './client';

// The wallet: current balance + recent movements (grants, stakes, refunds,
// payouts), newest first.
export function getCoins(token) {
  return apiRequest('/api/coins', { token });
}
