import { useCallback, useState } from 'react';
import { ScrollView, StyleSheet, Text, View, Pressable, RefreshControl } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { LinearGradient } from 'expo-linear-gradient';
import { useAuth } from '../auth/AuthContext';
import { getHome } from '../api/me';
import { listUpcomingGames } from '../api/sports';
import { setDraftLive } from '../state/attention';
import { useTheme, useThemedStyles, spacing, fonts, withAlpha } from '../theme';
import { Screen, Avatar, Button, Badge, SkeletonList, SectionHeader, Marquee, GhostText, Pulse, Kicker, CondTitle, BlinkDot } from '../components/ui';
import WordMark from '../components/WordMark';

const SPORT_EMOJI = { nfl: '🏈', nba: '🏀', wnba: '🏀', mlb: '⚾️' };

// Games whose ET wall-clock day is today.
function todays(games) {
  const now = new Date(Date.now() - 4 * 3600 * 1000);
  const key = (d) => `${d.getUTCFullYear()}-${d.getUTCMonth()}-${d.getUTCDate()}`;
  const todayKey = key(now);
  return (games || []).filter((g) => key(new Date(new Date(g.date).getTime() - 4 * 3600 * 1000)) === todayKey);
}

function tipTime(iso) {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  return d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
}

function fmtDate(iso) {
  if (!iso) return '';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  return d.toLocaleDateString([], { month: 'short', day: 'numeric' });
}

export default function HomeScreen({ navigation }) {
  const { token, user } = useAuth();
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);
  const [home, setHome] = useState(null);
  const [games, setGames] = useState([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  const load = useCallback(async () => {
    // Dashboard (DB-only, fast) drives the screen; games load separately so the
    // ESPN-backed schedule never blocks the landing content.
    try {
      const h = await getHome(token);
      setHome(h);
      setDraftLive((h?.draft_ready || []).some((d) => d.status === 'drafting'));
    } finally {
      setLoading(false);
      setRefreshing(false);
    }

    Promise.all([
      listUpcomingGames(token, 'wnba').catch(() => ({ games: [] })),
      listUpcomingGames(token, 'mlb').catch(() => ({ games: [] })),
    ]).then(([wnba, mlb]) => {
      setGames([...todays(wnba.games), ...todays(mlb.games)].sort((a, b) => new Date(a.date) - new Date(b.date)));
    });
  }, [token]);

  useFocusEffect(
    useCallback(() => {
      load();
    }, [load])
  );

  function openDetail(d) {
    navigation.navigate('DuelsTab', { screen: 'DuelDetail', params: { id: d.id }, initial: false });
  }
  function openDraft(d) {
    navigation.navigate('DuelsTab', {
      screen: 'DraftRoom',
      params: { id: d.id, opponentName: d.opponent?.username },
      initial: false,
    });
  }

  if (loading) {
    return (
      <Screen edges={['top']}>
        <SkeletonList count={6} />
      </Screen>
    );
  }

  const rec = home?.record || {};
  const played = (rec.wins ?? 0) + (rec.losses ?? 0) + (rec.ties ?? 0);
  const winPct = rec.win_pct != null ? Math.round(rec.win_pct <= 1 ? rec.win_pct * 100 : rec.win_pct) : null;
  const ptDiff = (rec.points_for ?? 0) - (rec.points_against ?? 0);
  const form = (rec.recent || []).slice(-5);

  // Most urgent first: a live draft beats an unanswered challenge beats a
  // ready draft. The top item becomes the hero; the rest stay compact.
  const drafting = (home?.draft_ready || []).filter((d) => d.status === 'drafting');
  const ready = (home?.draft_ready || []).filter((d) => d.status !== 'drafting');
  const queue = [
    ...drafting.map((d) => ({ d, kind: 'drafting' })),
    ...(home?.needs_response || []).map((d) => ({ d, kind: 'respond' })),
    ...ready.map((d) => ({ d, kind: 'ready' })),
  ];
  const hero = queue[0];
  const rest = queue.slice(1);
  const receipts = (home?.recent_results || []).slice(0, 3);

  return (
    <Screen padded={false} edges={['top']}>
      <ScrollView
        contentContainerStyle={{ paddingBottom: spacing.xxl }}
        showsVerticalScrollIndicator={false}
        refreshControl={
          <RefreshControl refreshing={refreshing} onRefresh={() => { setRefreshing(true); load(); }} tintColor={colors.accent} />
        }
      >
        {/* Brand header + season record, under a soft purple glow */}
        <LinearGradient
          colors={[withAlpha(colors.purple, 0.18), 'transparent']}
          start={{ x: 0.15, y: 0 }}
          end={{ x: 0.55, y: 1 }}
          style={styles.headerZone}
        >
          <View style={styles.brandRow}>
            <WordMark size={21} />
            <View style={styles.brandRight}>
              {rec.streak?.count > 0 ? (
                <View style={styles.streakChip}>
                  <Text
                    style={[
                      styles.streakText,
                      { color: rec.streak.type === 'win' ? colors.gold : rec.streak.type === 'loss' ? colors.danger : colors.muted },
                    ]}
                  >
                    {rec.streak.type === 'win' ? `🔥 W${rec.streak.count}` : rec.streak.type === 'loss' ? `L${rec.streak.count}` : `T${rec.streak.count}`}
                  </Text>
                </View>
              ) : null}
              <Pressable onPress={() => navigation.navigate('YouTab')} hitSlop={6}>
                <Avatar name={user?.username || '?'} size={38} />
              </Pressable>
            </View>
          </View>

          <View style={styles.recordRow}>
            <View>
              <Kicker size={9.5} tracking={2}>
                Season record
              </Kicker>
              <Text style={styles.recordBig}>
                {rec.wins ?? 0}
                <Text style={{ color: colors.placeholder }}>–</Text>
                {rec.losses ?? 0}
                {rec.ties ? <Text style={{ color: colors.placeholder, fontSize: 30 }}>–{rec.ties}</Text> : null}
              </Text>
            </View>
            <View style={styles.formCol}>
              <View style={{ flexDirection: 'row', gap: 4 }}>
                {form.length === 0 ? (
                  <Text style={styles.formEmpty}>NO DUELS YET</Text>
                ) : (
                  form.map((l, i) => (
                    <View
                      key={i}
                      style={[
                        styles.formChip,
                        l === 'W' && { backgroundColor: withAlpha(colors.accent, 0.25), borderColor: colors.accent },
                        l === 'L' && { backgroundColor: withAlpha(colors.danger, 0.18), borderColor: colors.danger },
                      ]}
                    >
                      <Text
                        style={[
                          styles.formChipText,
                          { color: l === 'W' ? colors.accent : l === 'L' ? colors.danger : colors.muted },
                        ]}
                      >
                        {l}
                      </Text>
                    </View>
                  ))
                )}
              </View>
              <Text style={styles.recordSub}>
                {played > 0
                  ? `${winPct ?? 0}% WIN · ${ptDiff >= 0 ? '+' : ''}${Math.round(ptDiff * 10) / 10} PT DIFF`
                  : 'FIRST DUEL PENDING'}
              </Text>
            </View>
          </View>
        </LinearGradient>

        <View style={{ paddingHorizontal: spacing.lg }}>
          <SectionHeader hint={queue.length > 0 ? `${queue.length} PENDING` : 'ALL QUIET'}>Your move</SectionHeader>
        </View>

        <View style={{ paddingHorizontal: spacing.lg, gap: 10 }}>
          {hero ? (
            <HeroCard item={hero} onDetail={openDetail} onDraft={openDraft} styles={styles} colors={colors} />
          ) : (
            <View style={styles.heroCard}>
              <View style={styles.ghostWrap} pointerEvents="none">
                <GhostText size={82} color={withAlpha(colors.text, 0.08)} strokeWidth={1}>
                  VS
                </GhostText>
              </View>
              <CondTitle size={28} style={{ marginTop: spacing.xs, paddingRight: 6 }}>
                ALL QUIET. TOO QUIET.
              </CondTitle>
              <Text style={styles.heroSub}>Somebody out there thinks they can beat you. Set the terms.</Text>
              <Button
                title="New challenge"
                style={{ marginTop: spacing.md }}
                onPress={() => navigation.navigate('DuelsTab', { screen: 'CreateChallenge', initial: false })}
              />
            </View>
          )}

          {rest.length > 0 ? (
            <View style={styles.miniGrid}>
              {rest.map((item) => (
                <MiniCard
                  key={`mini-${item.d.id}`}
                  item={item}
                  onPress={() => (item.kind === 'respond' ? openDetail(item.d) : openDraft(item.d))}
                  styles={styles}
                  colors={colors}
                />
              ))}
            </View>
          ) : null}

          {(home?.awaiting || []).length > 0 ? (
            <Text style={styles.awaiting}>
              ⏳ {home.awaiting.length} duel{home.awaiting.length > 1 ? 's' : ''} in play — scores landing on the LIVE tab
            </Text>
          ) : null}
        </View>

        {/* Scores marquee, full bleed */}
        {games.length > 0 ? (
          <View style={styles.tickerStrip}>
            <Marquee speed={34}>
              {games.slice(0, 10).map((g) => (
                <View key={g.id} style={styles.tickerItem}>
                  {g.state === 'in' ? (
                    <>
                      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 4 }}>
                        <BlinkDot color={colors.danger} size={5} />
                        <Text style={[styles.tickerTag, { color: colors.danger }]}>LIVE</Text>
                      </View>
                      <Text style={styles.tickerMain}>
                        {g.away.abbrev} {g.away.score ?? ''} — {g.home.abbrev} {g.home.score ?? ''}
                      </Text>
                    </>
                  ) : g.state === 'post' ? (
                    <>
                      <Text style={[styles.tickerTag, { color: colors.placeholder }]}>FINAL</Text>
                      <Text style={styles.tickerMain}>
                        {g.away.abbrev} {g.away.score ?? ''} — {g.home.abbrev} {g.home.score ?? ''}
                      </Text>
                    </>
                  ) : (
                    <>
                      <Text style={[styles.tickerTag, { color: colors.accent }]}>{tipTime(g.date)}</Text>
                      <Text style={styles.tickerMain}>
                        {g.away.abbrev} @ {g.home.abbrev}
                      </Text>
                    </>
                  )}
                </View>
              ))}
            </Marquee>
          </View>
        ) : null}

        {/* Receipts */}
        {receipts.length > 0 ? (
          <View style={{ paddingHorizontal: spacing.lg }}>
            <SectionHeader hint={`LAST ${receipts.length}`}>The receipts</SectionHeader>
            <View style={{ gap: 8 }}>
              {receipts.map((d) => {
                const won = d.my_outcome === 'win';
                const tie = d.my_outcome === 'tie';
                const tint = won ? colors.accent : tie ? colors.muted : colors.danger;
                return (
                  <Pressable
                    key={`res-${d.id}`}
                    onPress={() =>
                      navigation.navigate('DuelsTab', {
                        screen: 'Results',
                        params: { id: d.id, opponentName: d.opponent?.username },
                        initial: false,
                      })
                    }
                    style={({ pressed }) => [styles.receiptRow, { borderLeftColor: tint }, pressed && { opacity: 0.85 }]}
                  >
                    <CondTitle size={17} color={tint} style={{ width: 26 }}>
                      {won ? 'W' : tie ? 'T' : 'L'}
                    </CondTitle>
                    <View style={{ flex: 1 }}>
                      <Text style={styles.receiptTitle}>vs {d.opponent?.username || 'opponent'}</Text>
                      <Text style={styles.receiptSub}>
                        {SPORT_EMOJI[d.sport] || '🎯'} {String(d.sport || '').toUpperCase()}
                        {d.settled_at ? ` · ${fmtDate(d.settled_at)}` : ''}
                      </Text>
                    </View>
                    <Text style={styles.receiptView}>VIEW</Text>
                  </Pressable>
                );
              })}
            </View>
          </View>
        ) : null}
      </ScrollView>
    </Screen>
  );
}

// The single most urgent thing, full width and loud.
function HeroCard({ item, onDetail, onDraft, styles, colors }) {
  const { d, kind } = item;
  const opp = (d.opponent?.username || 'your rival').toUpperCase();
  const sportLabel = `${String(d.sport || '').toUpperCase()} · ${d.roster_size} SLOTS`;

  const cfg =
    kind === 'drafting'
      ? {
          grad: [withAlpha(colors.danger, 0.12), colors.card, withAlpha(colors.purple, 0.12)],
          border: colors.dangerBorder,
          chip: <Badge label="Draft live" tone="danger" blink />,
          title: 'BACK ON THE CLOCK.',
          sub: d.group ? `${d.party_size}-way snake draft — jump in` : `vs ${d.opponent?.username || '?'} · snake draft — jump in`,
          cta: 'ENTER ROOM →',
          pulse: true,
          go: () => onDraft(d),
        }
      : kind === 'respond'
        ? {
            grad: [withAlpha(colors.purple, 0.16), colors.card, colors.card],
            border: colors.purpleBorder,
            chip: <Badge label="Challenge" tone="info" blink />,
            title: d.group ? `${opp}'S ${d.party_size}-WAY THROWDOWN.` : `${opp} CALLED YOU OUT.`,
            sub: `${SPORT_EMOJI[d.sport] || '🎯'} ${String(d.sport || '').toUpperCase()} · ${d.roster_size} rounds · set your answer`,
            cta: 'RESPOND →',
            pulse: false,
            go: () => onDetail(d),
          }
        : {
            grad: [withAlpha(colors.accent, 0.14), colors.card, withAlpha(colors.purple, 0.10)],
            border: colors.accentBorder,
            chip: <Badge label="Ready" tone="accent" />,
            title: `DRAFT VS ${opp} ANYTIME.`,
            sub: `${SPORT_EMOJI[d.sport] || '🎯'} ${String(d.sport || '').toUpperCase()} · ${d.roster_size} rounds · the room is open`,
            cta: 'TO THE ROOM →',
            pulse: true,
            go: () => onDraft(d),
          };

  return (
    <Pressable onPress={cfg.go} style={({ pressed }) => [pressed && { transform: [{ scale: 0.98 }] }]}>
      <LinearGradient colors={cfg.grad} start={{ x: 0, y: 0 }} end={{ x: 1, y: 1 }} style={[styles.heroCard, { borderColor: cfg.border }]}>
        <View style={styles.ghostWrap} pointerEvents="none">
          <GhostText size={82} color={withAlpha(colors.text, 0.09)} strokeWidth={1}>
            VS
          </GhostText>
        </View>
        <View style={styles.heroTop}>
          {cfg.chip}
          <Kicker size={10} tracking={1} color={colors.muted}>
            {sportLabel}
          </Kicker>
        </View>
        <CondTitle size={30} style={{ marginTop: spacing.md, lineHeight: 32, paddingRight: 6 }}>
          {cfg.title}
        </CondTitle>
        <View style={styles.heroBottom}>
          <Text style={[styles.heroSub, { flex: 1, marginTop: 0 }]} numberOfLines={2}>
            {cfg.sub}
          </Text>
          <Pulse color={withAlpha(colors.accent, 0.35)} disabled={!cfg.pulse}>
            <View style={styles.heroCta}>
              <Text style={styles.heroCtaText}>{cfg.cta}</Text>
            </View>
          </Pulse>
        </View>
      </LinearGradient>
    </Pressable>
  );
}

// Compact follow-ups under the hero, two per row.
function MiniCard({ item, onPress, styles, colors }) {
  const { d, kind } = item;
  const opp = d.opponent?.username || '?';
  const cfg =
    kind === 'drafting'
      ? { label: 'LIVE', color: colors.danger, title: `Draft vs ${opp}\nis live`, meta: 'jump back in' }
      : kind === 'respond'
        ? {
            label: 'CHALLENGE',
            color: colors.purpleText,
            title: d.group ? `${opp}'s ${d.party_size}-way\nthrowdown` : `${opp} called\nyou out`,
            meta: `${SPORT_EMOJI[d.sport] || '🎯'} ${String(d.sport || '').toUpperCase()} · ${d.roster_size} rounds · tap to respond`,
          }
        : {
            label: 'READY',
            color: colors.accent,
            title: `Draft vs ${opp}\nanytime`,
            meta: `${SPORT_EMOJI[d.sport] || '🎯'} ${String(d.sport || '').toUpperCase()} · ${d.roster_size} rounds`,
          };

  return (
    <Pressable onPress={onPress} style={({ pressed }) => [styles.miniCard, pressed && { transform: [{ scale: 0.97 }] }]}>
      <View style={styles.miniTop}>
        <Text style={[styles.miniLabel, { color: cfg.color }]}>{cfg.label}</Text>
        <BlinkDot color={cfg.color} size={7} blink={kind !== 'ready'} />
      </View>
      <Text style={styles.miniTitle} numberOfLines={2}>
        {cfg.title}
      </Text>
      <Text style={styles.miniMeta} numberOfLines={1}>
        {cfg.meta}
      </Text>
    </Pressable>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    headerZone: { paddingHorizontal: spacing.lg, paddingTop: spacing.sm, paddingBottom: spacing.xs },
    brandRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
    brandRight: { flexDirection: 'row', alignItems: 'center', gap: 8 },
    streakChip: {
      backgroundColor: colors.card,
      borderWidth: 1,
      borderColor: colors.border,
      borderRadius: 999,
      paddingVertical: 5,
      paddingHorizontal: 10,
    },
    streakText: { fontFamily: fonts.hero, fontSize: 15 },
    recordRow: { flexDirection: 'row', alignItems: 'flex-end', gap: 14, marginTop: spacing.lg },
    recordBig: { fontFamily: fonts.hero, fontSize: 52, lineHeight: 52, color: colors.text, paddingRight: 6 },
    formCol: { paddingBottom: 8, gap: 6 },
    formChip: {
      width: 16,
      height: 16,
      borderRadius: 5,
      borderWidth: 1,
      borderColor: colors.border,
      backgroundColor: colors.card,
      alignItems: 'center',
      justifyContent: 'center',
    },
    formChipText: { fontSize: 9, fontFamily: fonts.bodyBlack },
    formEmpty: { fontSize: 10, fontFamily: fonts.bodyExtra, color: colors.placeholder, letterSpacing: 1 },
    recordSub: { fontSize: 10, fontFamily: fonts.bodyBold, color: colors.muted, letterSpacing: 0.3 },
    heroCard: {
      borderRadius: 16,
      borderWidth: 1,
      borderColor: colors.border,
      backgroundColor: colors.card,
      padding: spacing.lg,
      overflow: 'hidden',
    },
    ghostWrap: { position: 'absolute', right: -6, top: -16 },
    heroTop: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
    heroSub: { color: colors.muted, fontSize: 12, fontFamily: fonts.bodySemi, marginTop: 6, lineHeight: 17 },
    heroBottom: { flexDirection: 'row', alignItems: 'center', gap: spacing.md, marginTop: spacing.md },
    heroCta: {
      backgroundColor: colors.accent,
      borderRadius: 999,
      paddingVertical: 9,
      paddingHorizontal: 16,
    },
    heroCtaText: { color: colors.onAccent, fontFamily: fonts.hero, fontSize: 15, letterSpacing: 0.5 },
    miniGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: 10 },
    miniCard: {
      flexBasis: '47%',
      flexGrow: 1,
      borderRadius: 14,
      borderWidth: 1,
      borderColor: colors.border,
      backgroundColor: colors.card,
      padding: 13,
    },
    miniTop: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
    miniLabel: { fontSize: 10, fontFamily: fonts.bodyBlack, letterSpacing: 1.2 },
    miniTitle: { fontFamily: fonts.condBold, fontSize: 19, lineHeight: 20, color: colors.text, marginTop: 7 },
    miniMeta: { fontSize: 11, color: colors.muted, marginTop: 6, fontFamily: fonts.bodySemi },
    awaiting: { color: colors.placeholder, fontSize: 12, textAlign: 'center', marginTop: 4, fontFamily: fonts.bodySemi },
    tickerStrip: {
      marginTop: spacing.lg,
      borderTopWidth: 1,
      borderBottomWidth: 1,
      borderColor: colors.borderSubtle,
      backgroundColor: colors.bgElevated,
      paddingVertical: 9,
    },
    tickerItem: { flexDirection: 'row', alignItems: 'center', gap: 8, marginRight: 26 },
    tickerTag: { fontFamily: fonts.condBold, fontSize: 14 },
    tickerMain: { fontFamily: fonts.condBold, fontSize: 14, color: colors.text },
    receiptRow: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 11,
      backgroundColor: colors.card,
      borderWidth: 1,
      borderColor: colors.border,
      borderLeftWidth: 3,
      borderRadius: 12,
      paddingVertical: 11,
      paddingHorizontal: 13,
    },
    receiptTitle: { fontSize: 13.5, fontFamily: fonts.bodyBold, color: colors.text },
    receiptSub: { fontSize: 11, color: colors.muted, marginTop: 1, fontFamily: fonts.body },
    receiptView: { fontSize: 10, fontFamily: fonts.bodyExtra, color: colors.placeholder, letterSpacing: 1 },
  });
