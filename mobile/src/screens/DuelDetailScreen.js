import { useCallback, useEffect, useRef, useState } from 'react';
import { ActivityIndicator, Pressable, Share, StyleSheet, Text, View } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { useAuth } from '../auth/AuthContext';
import { getDuel, respondToDuel, getLiveResult } from '../api/duels';
import { formatDateTime } from '../utils/datetime';
import { useTheme, useThemedStyles, spacing, radius, font, statusTone } from '../theme';
import { Screen, Card, Avatar, Badge, Button, SectionHeader } from '../components/ui';

const SPORT_LABEL = {
  nfl: '🏈 Football',
  nba: '🏀 Basketball',
  wnba: '🏀 WNBA',
  mlb: '⚾️ Baseball',
};

function clockLabel(secs) {
  if (!secs) return '—';
  if (secs < 3600) return `${secs}s per pick`;
  return `${secs / 3600}h per pick (async)`;
}

const cap = (s) => (s ? s.charAt(0).toUpperCase() + s.slice(1) : s);
const prettyKey = (k) => k.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());

export default function DuelDetailScreen({ route, navigation }) {
  const { id } = route.params;
  const { token } = useAuth();
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);
  const [duel, setDuel] = useState(null);
  const [error, setError] = useState(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    try {
      const res = await getDuel(token, id);
      setDuel(res.duel);
    } catch (e) {
      setError(e.message);
    }
  }, [token, id]);

  useFocusEffect(
    useCallback(() => {
      load();
    }, [load])
  );

  async function act(action) {
    setBusy(true);
    setError(null);
    try {
      await respondToDuel(token, id, action);
      navigation.goBack();
    } catch (e) {
      setError(e.message);
      setBusy(false);
    }
  }

  function Term({ label, value, first }) {
    return (
      <View style={[styles.term, !first && styles.termDivider]}>
        <Text style={styles.termLabel}>{label}</Text>
        <Text style={styles.termValue}>{value}</Text>
      </View>
    );
  }

  if (!duel) {
    return (
      <View style={styles.loading}>
        <ActivityIndicator size="large" color={colors.accent} />
      </View>
    );
  }

  const isOpponentPending = duel.role === 'opponent' && duel.status === 'pending';
  const isChallengerPending = duel.role === 'challenger' && duel.status === 'pending';
  const scoring = Object.entries(duel.scoring_rules || {});
  const shareable = ['pending', 'accepted', 'drafting', 'drafted', 'settled'].includes(duel.status);

  function shareMatchup() {
    const stage =
      duel.status === 'drafted'
        ? 'Lineups are locked — scoring is live!'
        : duel.status === 'settled'
          ? 'The final is in.'
          : duel.status === 'pending'
            ? 'The challenge is on the table.'
            : `We draft ${formatDateTime(duel.draft_starts_at)}.`;
    Share.share({
      message: `⚔️ Heads Up fantasy duel: me vs ${duel.opponent.username} — ${SPORT_LABEL[duel.sport] || duel.sport}. ${stage}`,
    }).catch(() => {});
  }

  return (
    <Screen scroll>
      <View style={styles.header}>
        <View style={styles.side}>
          <Avatar name="You" size={56} />
          <Text style={styles.sideName}>You</Text>
        </View>
        <Text style={styles.vs}>VS</Text>
        <View style={styles.side}>
          <Avatar name={duel.opponent.username} size={56} />
          <Text style={styles.sideName} numberOfLines={1}>
            {duel.opponent.username}
          </Text>
        </View>
      </View>

      <View style={styles.statusRow}>
        <Badge label={duel.status} tone={statusTone(duel.status)} dot />
      </View>

      {error ? <Text style={styles.error}>{error}</Text> : null}

      <Card padded={false}>
        <Term label="Sport" value={SPORT_LABEL[duel.sport] || duel.sport} first />
        <Term label="Draft type" value={cap(duel.draft_type)} />
        <Term label="Lineup" value={`${cap((duel.lineup_template || '').split('_')[1] || '')} · ${duel.roster_size} slots`} />
        <Term label="Pick clock" value={clockLabel(duel.pick_clock_seconds)} />
        <Term label="Draft starts" value={formatDateTime(duel.draft_starts_at)} />
      </Card>

      <SectionHeader>Scoring chart</SectionHeader>
      <Card padded={false}>
        {scoring.map(([key, value], i) => (
          <Term key={key} label={prettyKey(key)} value={String(value)} first={i === 0} />
        ))}
      </Card>

      <View style={styles.actions}>
        {isOpponentPending ? (
          <>
            <Button title="Accept Challenge" icon="checkmark-circle" onPress={() => act('accept')} disabled={busy} />
            <View style={styles.twoUp}>
              <Button title="Counter" variant="outline" full={false} style={{ flex: 1 }} onPress={() => goCounter(navigation, duel)} disabled={busy} />
              <Button title="Decline" variant="danger" full={false} style={{ flex: 1 }} onPress={() => act('decline')} disabled={busy} />
            </View>
          </>
        ) : null}

        {isChallengerPending ? (
          <Button title="Cancel challenge" variant="danger" icon="close-circle" onPress={() => act('cancel')} disabled={busy} />
        ) : null}

        {duel.status === 'accepted' || duel.status === 'drafting' ? (
          <Button
            title={duel.status === 'drafting' ? 'Resume Live Draft' : 'Enter Draft Room'}
            icon="play"
            onPress={() => navigation.navigate('DraftRoom', { id: duel.id, opponentName: duel.opponent.username })}
          />
        ) : null}

        {duel.status === 'drafted' ? (
          <>
            <LiveScore
              token={token}
              id={duel.id}
              styles={styles}
              colors={colors}
              onOpen={() => navigation.navigate('LiveMatchup', { id: duel.id, opponentName: duel.opponent.username })}
            />
            <Button
              title="Watch Live Matchup"
              icon="pulse"
              onPress={() => navigation.navigate('LiveMatchup', { id: duel.id, opponentName: duel.opponent.username })}
            />
            <Button
              title="View Drafted Lineups"
              variant="outline"
              icon="list"
              onPress={() => navigation.navigate('DraftRoom', { id: duel.id, opponentName: duel.opponent.username })}
            />
            <Text style={styles.locked}>⏳ Lineups locked — the winner is declared once the games finish.</Text>
          </>
        ) : null}

        {duel.status === 'settled' ? (
          <Button
            title={
              duel.my_outcome === 'win'
                ? 'View Result — You won! 🏆'
                : duel.my_outcome === 'tie'
                  ? 'View Result — Tie 🤝'
                  : 'View Result'
            }
            icon="podium"
            onPress={() => navigation.navigate('Results', { id: duel.id, opponentName: duel.opponent.username })}
          />
        ) : null}

        {shareable ? <Button title="Share matchup" icon="share-outline" variant="outline" onPress={shareMatchup} /> : null}
      </View>
    </Screen>
  );
}

function LiveScore({ token, id, styles, colors, onOpen }) {
  const [live, setLive] = useState(null);
  const [started, setStarted] = useState(false);
  const timer = useRef(null);

  useFocusEffect(
    useCallback(() => {
      let active = true;
      const tick = async () => {
        try {
          const res = await getLiveResult(token, id);
          if (active) {
            setLive(res);
            setStarted(true);
          }
        } catch (e) {
          // 409 once settled / not live — stop polling, leave last snapshot.
          if (active) setStarted(true);
        }
      };
      tick();
      timer.current = setInterval(tick, 20000);
      return () => {
        active = false;
        if (timer.current) clearInterval(timer.current);
      };
    }, [token, id])
  );

  if (!live) {
    return (
      <Card style={styles.liveCard}>
        <Text style={styles.liveHead}>LIVE SCORE</Text>
        <Text style={styles.liveWaiting}>{started ? 'Waiting on the first game to tip off…' : 'Loading…'}</Text>
      </Card>
    );
  }

  const me = live.challenger.is_me ? live.challenger : live.opponent;
  const them = live.challenger.is_me ? live.opponent : live.challenger;
  const meLeads = live.leader_id && me.user.id === live.leader_id;
  const themLead = live.leader_id && them.user.id === live.leader_id;
  const g = live.games || {};
  const gameLine = [g.final ? `${g.final} final` : null, g.live ? `${g.live} live` : null, g.upcoming ? `${g.upcoming} upcoming` : null]
    .filter(Boolean)
    .join(' · ');

  return (
    <Pressable onPress={onOpen} style={({ pressed }) => pressed && { opacity: 0.85 }}>
      <Card style={styles.liveCard}>
        <View style={styles.liveTop}>
          <Text style={styles.liveHead}>LIVE SCORE</Text>
          {g.live > 0 ? <Badge label="LIVE" tone="danger" dot /> : null}
        </View>
        <View style={styles.liveRow}>
          <LiveSide label="You" total={me.total} lead={meLeads} colors={colors} styles={styles} />
          <Text style={styles.liveDash}>–</Text>
          <LiveSide label={them.user.username} total={them.total} lead={themLead} colors={colors} styles={styles} />
        </View>
        <Text style={styles.liveGames}>{gameLine || 'No games in the window yet'} › tap for full matchup</Text>
      </Card>
    </Pressable>
  );
}

function LiveSide({ label, total, lead, colors, styles }) {
  return (
    <View style={styles.liveSide}>
      <Text style={[styles.liveTotal, lead && { color: colors.accent }]}>{(total ?? 0).toFixed(1)}</Text>
      <Text style={styles.liveName} numberOfLines={1}>
        {label}
      </Text>
      {lead ? <Text style={styles.liveLeading}>LEADING</Text> : <Text style={styles.liveLeadingSpacer} />}
    </View>
  );
}

function goCounter(navigation, duel) {
  navigation.navigate('Counter', {
    id: duel.id,
    initial: {
      sport: duel.sport,
      lineup_template: duel.lineup_template,
      pick_clock_seconds: duel.pick_clock_seconds,
    },
  });
}

const makeStyles = (colors) =>
  StyleSheet.create({
    loading: { flex: 1, backgroundColor: colors.bg, alignItems: 'center', justifyContent: 'center' },
    header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', marginBottom: spacing.md },
    side: { alignItems: 'center', flex: 1 },
    sideName: { color: colors.text, fontSize: font.body, fontWeight: '700', marginTop: spacing.sm, maxWidth: '90%' },
    vs: { color: colors.placeholder, fontSize: font.body, fontWeight: '800', letterSpacing: 1, paddingHorizontal: spacing.md },
    statusRow: { alignItems: 'center', marginBottom: spacing.lg },
    error: { color: colors.danger, textAlign: 'center', marginBottom: spacing.md },
    term: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingVertical: 13, paddingHorizontal: spacing.lg },
    termDivider: { borderTopColor: colors.borderSubtle, borderTopWidth: StyleSheet.hairlineWidth },
    termLabel: { color: colors.muted, fontSize: font.body },
    termValue: { color: colors.text, fontSize: font.body, fontWeight: '600' },
    actions: { marginTop: spacing.xl, gap: spacing.md },
    twoUp: { flexDirection: 'row', gap: spacing.md },
    locked: { color: colors.muted, fontSize: font.body, textAlign: 'center', marginTop: spacing.sm, lineHeight: 21 },
    liveCard: { borderColor: colors.accentBorder },
    liveTop: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: spacing.sm, marginBottom: spacing.sm },
    liveHead: { color: colors.muted, fontSize: font.caption, fontWeight: '800', letterSpacing: 1, textAlign: 'center' },
    liveWaiting: { color: colors.muted, fontSize: font.body, textAlign: 'center', marginTop: spacing.xs },
    liveRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center' },
    liveSide: { flex: 1, alignItems: 'center' },
    liveTotal: { color: colors.text, fontSize: font.hero, fontWeight: '900' },
    liveName: { color: colors.muted, fontSize: font.small, marginTop: 2, maxWidth: '90%' },
    liveLeading: { color: colors.accent, fontSize: 10, fontWeight: '800', letterSpacing: 1, marginTop: 2 },
    liveLeadingSpacer: { fontSize: 10, marginTop: 2, height: 13 },
    liveDash: { color: colors.placeholder, fontSize: font.title, fontWeight: '800', paddingHorizontal: spacing.sm },
    liveGames: { color: colors.muted, fontSize: font.caption, textAlign: 'center', marginTop: spacing.sm },
  });
