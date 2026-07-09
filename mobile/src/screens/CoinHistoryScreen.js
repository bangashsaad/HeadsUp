import { useCallback, useState } from 'react';
import { Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useFocusEffect } from '@react-navigation/native';
import { useAuth } from '../auth/AuthContext';
import { getCoins } from '../api/coins';
import { useTheme, useThemedStyles, spacing, font, fonts, withAlpha } from '../theme';
import { Screen, Card, EmptyState, SkeletonList, Kicker, CondTitle } from '../components/ui';

// How each ledger kind reads on the wallet screen.
const KIND_META = {
  grant: { icon: 'gift-outline', label: 'Bonus' },
  stake: { icon: 'lock-closed-outline', label: 'Stake escrowed' },
  refund: { icon: 'arrow-undo-outline', label: 'Stake returned' },
  payout: { icon: 'trophy-outline', label: 'Pot won' },
  burn: { icon: 'flame-outline', label: 'Burned' },
  reversal: { icon: 'swap-horizontal-outline', label: 'Correction' },
};

function fmtWhen(iso) {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  return d.toLocaleDateString([], { month: 'short', day: 'numeric' });
}

export default function CoinHistoryScreen({ navigation }) {
  const { token, refreshUser } = useAuth();
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);
  const [wallet, setWallet] = useState(null);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState(null);

  const load = useCallback(async () => {
    try {
      const res = await getCoins(token);
      setWallet(res);
      setError(null);
    } catch (e) {
      setError(e.message);
    } finally {
      setRefreshing(false);
    }
  }, [token]);

  useFocusEffect(
    useCallback(() => {
      load();
      refreshUser();
      // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [load])
  );

  if (error) {
    return (
      <Screen>
        <EmptyState icon="alert-circle-outline" title="Couldn't load the wallet" subtitle={error} />
      </Screen>
    );
  }

  if (!wallet) {
    return (
      <Screen>
        <SkeletonList count={6} />
      </Screen>
    );
  }

  const entries = wallet.entries || [];

  return (
    <Screen padded={false}>
      <ScrollView
        contentContainerStyle={{ padding: spacing.lg, paddingBottom: spacing.xxl }}
        showsVerticalScrollIndicator={false}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={() => { setRefreshing(true); load(); }} tintColor={colors.accent} />}
      >
        <Card style={styles.balanceCard}>
          <Kicker size={10} tracking={2} color={colors.muted}>
            Coin balance
          </Kicker>
          <CondTitle size={44} color={colors.gold} style={{ marginTop: 4, paddingRight: 4 }}>
            ◎ {(wallet.balance ?? 0).toLocaleString()}
          </CondTitle>
          <Text style={styles.balanceNote}>
            Free house coins — stake them on duels, win the pot. Can't be bought, can't be cashed out. Run dry and a daily
            comeback bonus tops you back up.
          </Text>
        </Card>

        {entries.length === 0 ? (
          <EmptyState
            icon="server-outline"
            title="No movements yet"
            subtitle="Stake a duel and every coin that moves shows up here — the full receipt trail."
          />
        ) : (
          <Card padded={false} style={{ marginTop: spacing.lg }}>
            {entries.map((e, i) => {
              const meta = KIND_META[e.kind] || { icon: 'ellipse-outline', label: e.kind };
              const positive = e.amount > 0;
              const label =
                e.kind === 'grant'
                  ? e.reason === 'signup'
                    ? 'Welcome bonus'
                    : e.reason === 'comeback'
                      ? 'Comeback bonus'
                      : 'Bonus'
                  : meta.label;
              return (
                <Pressable
                  key={e.id}
                  disabled={!e.duel_id}
                  onPress={() => navigation.navigate('DuelsTab', { screen: 'DuelDetail', params: { id: e.duel_id }, initial: false })}
                  style={({ pressed }) => [styles.entryRow, i > 0 && styles.entryDivider, pressed && { opacity: 0.7 }]}
                >
                  <View style={[styles.entryIcon, positive && { backgroundColor: withAlpha(colors.gold, 0.12) }]}>
                    <Ionicons name={meta.icon} size={16} color={positive ? colors.gold : colors.muted} />
                  </View>
                  <View style={{ flex: 1 }}>
                    <Text style={styles.entryLabel}>{label}</Text>
                    <Text style={styles.entrySub}>
                      {e.duel_id ? `Duel #${e.duel_id} · ` : ''}
                      {fmtWhen(e.inserted_at)}
                    </Text>
                  </View>
                  <Text style={[styles.entryAmount, { color: positive ? colors.gold : colors.muted }]}>
                    {positive ? '+' : '−'}◎ {Math.abs(e.amount).toLocaleString()}
                  </Text>
                </Pressable>
              );
            })}
          </Card>
        )}
      </ScrollView>
    </Screen>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    balanceCard: { alignItems: 'center', borderColor: withAlpha(colors.gold, 0.35) },
    balanceNote: {
      color: colors.muted,
      fontSize: font.caption,
      lineHeight: 17,
      textAlign: 'center',
      marginTop: spacing.sm,
      fontFamily: fonts.body,
    },
    entryRow: { flexDirection: 'row', alignItems: 'center', gap: 11, paddingVertical: 11, paddingHorizontal: spacing.lg },
    entryDivider: { borderTopColor: colors.borderSubtle, borderTopWidth: StyleSheet.hairlineWidth },
    entryIcon: {
      width: 32,
      height: 32,
      borderRadius: 10,
      backgroundColor: colors.bgElevated,
      alignItems: 'center',
      justifyContent: 'center',
    },
    entryLabel: { color: colors.text, fontSize: 13, fontFamily: fonts.bodySemi },
    entrySub: { color: colors.muted, fontSize: 10.5, marginTop: 1, fontFamily: fonts.body },
    entryAmount: { fontSize: 15, fontFamily: fonts.condBold, letterSpacing: 0.3 },
  });
