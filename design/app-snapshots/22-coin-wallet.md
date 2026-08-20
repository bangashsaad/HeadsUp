# Coin wallet — current iPhone app screen

> **What this file is:** the REAL React Native source of this iPhone screen —
> the current implementation, not a mockup. Redesign it as a phone-frame mockup
> (390pt wide) in the same design language; annotate every interaction; design
> every state (filled / empty / loading / error). The result gets ported back
> into React Native. Names and layout in the code are the truth of what exists
> today.

◎ balance + the ledger: signup grant, daily comeback bonus, stakes escrowed out, pots won. Coins are free and can't be bought — never imply purchases.

## The app's design language (real tokens, from `src/theme.js`)

Dark palette (the shipped look): bg `#0A0B10`, elevated `#0D0F16`, card `#12141D`,
card-elevated `#191C28`, border `#252A3A`, subtle border `#1A1E2B`, text `#F4F5F7`,
dim `#B9BECF`, muted `#8B91A7`, placeholder `#565D73`, **accent lime `#C8FF2E`**
(text on accent: `#0A0B10`), danger `#FF4557`, warning/gold `#FFB021`,
purple `#7C5CFF` (text `#9F8BFF`), cyan `#22E5FF`, pink `#FF4D8D`, green `#39D98A`.
A light palette exists too; dark is the default and the brand.

Type: **Archivo** (body, weights 400–900), **Archivo Black italic** (display —
wordmark, "YOU WIN.", ghost VS), **Barlow Condensed 800 italic** (hero — scores,
section titles, ALL-CAPS pill buttons). Shapes: 999px pill buttons/chips,
8/12/16/20px card radii, 1px borders. Status→color: drafting = red (blinks),
pending/countered = purple, accepted/settled = lime, live dots blink.

UI kit primitives the screens compose (from `src/components/ui/`):

- **Avatar** — Initials tile with a stable per-name tint. Rounded square ("squircle"), per the Reimagined language. (8-digit hex appends alpha.)
- **Badge** — Small uppercase status pill. `tone` is one of the keys in theme `tones`. `dot` shows a leading dot; `blink` makes it pulse (live things blink).
- **BlinkDot** — The little live dot. blink=false renders it steady.
- **Button** — Condensed-italic pill buttons — the Reimagined CTA voice (ENTER ROOM →).
- **Card** — A surface with depth — border + soft shadow. Pass onPress to make it tappable.
- **Chip** — A selectable pill (filters, toggles). Light selection haptic on tap. Mirrors the Segmented recipe: center the label and let Barlow Condensed keep its NATURAL line height — forcing a lineHeight clips the glyphs on iOS.
- **EmptyState** — Friendly centered placeholder: an icon coin, a title, a subtitle, and an optional action node (e.g. a Button).
- **FadeIn** — Fade + slide a list row in on mount, lightly staggered by its index.
- **Field** — Labeled text input with optional password show/hide, a valid ✓, and an error.
- **GhostText** — Outline-only display text — the big translucent "VS" / pick-number watermarks. Rendered as stroked SVG text (RN has no text-stroke). Defaults to a faint stroke of the theme's text color, so it reads in light mode too.
- **Marquee** — Endless horizontal ticker: renders `children` twice and slides one copy's width, looping seamlessly. `speed` is px/second.
- **Pulse** — A soft expanding halo behind its children — the design's pulsing CTA ring.
- **Screen** — Page wrapper: themed bg, keyboard avoidance, and an optional scroll view with pull-to-refresh. No safe-area insets by default (the header owns the top, the tab bar owns the bottom).
- **SearchInput** — Text field with a leading search icon and a clear (×) button.
- **SectionHeader** — Condensed-italic section title, e.g. "YOUR MOVE", with an optional right hint ("3 PENDING"). Accepts a plain string child for back-compat.
- **Segmented** — The ACTIVE | PAST switch: a recessed track with a lime active segment. options: [{ key, label, count }]
- **Skeleton** — A single pulsing placeholder bar.
- **StatTile** — One tile of the 4-up stat grid: big condensed-italic value over a tiny kicker.
- **Type** — The three voices of the Reimagined type system. Tiny 800-weight uppercase tracking label: "SEASON RECORD", "PICK 3 OF 10".

## The screen source (`src/screens/CoinHistoryScreen.js`)

```jsx
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
```
