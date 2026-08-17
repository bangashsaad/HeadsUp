import { useCallback, useState } from 'react';
import { ScrollView, StyleSheet, Text, View } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { useFocusEffect } from '@react-navigation/native';
import { useAuth } from '../auth/AuthContext';
import { getRivalry } from '../api/social';
import { useTheme, useThemedStyles, avatarColor, spacing, fonts, withAlpha } from '../theme';
import { Screen, SkeletonList, Button } from '../components/ui';

// One rivalry, whole — from Saad's Reimagined drop: the face-off hero with the
// series score, LAST 5 chips, the bragging-rights tiles, and the history as
// receipts with story lines. Friends with no duels get the honest 0–0 version.
export default function RivalryScreen({ route, navigation }) {
  const { id, username } = route.params;
  const { token, user } = useAuth();
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);
  const [riv, setRiv] = useState(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    try {
      const res = await getRivalry(token, id);
      setRiv(res.rivalry);
    } finally {
      setLoading(false);
    }
  }, [token, id]);

  useFocusEffect(
    useCallback(() => {
      load();
    }, [load])
  );

  function challenge() {
    navigation.navigate('DuelsTab', { screen: 'CreateChallenge', params: { preselect: id }, initial: false });
  }

  if (loading || !riv) {
    return (
      <Screen>
        <SkeletonList count={5} />
      </Screen>
    );
  }

  const theirTint = avatarColor(username);
  const played = riv.played > 0;
  const seriesLine = !played
    ? 'NO DUELS YET'
    : riv.wins > riv.losses
      ? 'YOU LEAD THE SERIES'
      : riv.wins < riv.losses
        ? 'THEY LEAD THE SERIES'
        : 'SERIES ALL SQUARE';

  const chip = (letter) =>
    letter === 'W'
      ? { bg: withAlpha(colors.accent, 0.16), bd: withAlpha(colors.accent, 0.55), ink: colors.accent }
      : letter === 'L'
        ? { bg: withAlpha(colors.danger, 0.14), bd: withAlpha(colors.danger, 0.55), ink: colors.danger }
        : { bg: withAlpha(colors.muted, 0.14), bd: withAlpha(colors.muted, 0.45), ink: colors.muted };

  const outcomePill = (o) =>
    o === 'win'
      ? { label: 'WIN', ...chip('W') }
      : o === 'loss'
        ? { label: 'LOSS', ...chip('L') }
        : { label: 'TIE', ...chip('T') };

  const signed = (n) => (n == null ? '—' : `${n >= 0 ? '+' : '−'}${Math.abs(n).toFixed(1)}`);

  const dateLabel = (iso) => {
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return '';
    return d.toLocaleDateString([], { month: 'short', day: 'numeric' }).toUpperCase();
  };

  return (
    <Screen padded={false}>
      <ScrollView contentContainerStyle={{ paddingBottom: spacing.xxl }} showsVerticalScrollIndicator={false}>
        <LinearGradient
          colors={[withAlpha(colors.purpleText, 0.14), 'transparent']}
          start={{ x: 0.5, y: 0 }}
          end={{ x: 0.5, y: 1 }}
          style={{ paddingHorizontal: spacing.lg, paddingTop: spacing.xs }}
        >
          <View style={styles.heroCard}>
            <View style={styles.faceoff}>
              <View style={styles.corner}>
                <View style={[styles.bigAvatar, { backgroundColor: withAlpha(colors.accent, 0.16), borderColor: withAlpha(colors.accent, 0.5) }]}>
                  <Text style={[styles.bigAvatarText, { color: colors.accent }]}>
                    {(user?.username || '?')[0].toUpperCase()}
                  </Text>
                </View>
                <Text style={styles.cornerName} numberOfLines={1}>{user?.username}</Text>
              </View>
              <View style={styles.scoreCol}>
                <Text style={styles.bigScore} numberOfLines={1}>
                  <Text style={{ color: colors.accent }}>{riv.wins}</Text>
                  <Text style={{ color: colors.placeholder }}> – </Text>
                  <Text style={{ color: colors.text }}>{riv.losses}</Text>
                  {riv.ties > 0 ? <Text style={{ color: colors.placeholder, fontSize: 22 }}> –{riv.ties}</Text> : null}
                </Text>
                <Text style={styles.seriesLine}>{seriesLine}</Text>
              </View>
              <View style={styles.corner}>
                <View style={[styles.bigAvatar, { backgroundColor: theirTint + '26', borderColor: theirTint + '59' }]}>
                  <Text style={[styles.bigAvatarText, { color: theirTint }]}>{username[0].toUpperCase()}</Text>
                </View>
                <Text style={styles.cornerName} numberOfLines={1}>{username}</Text>
              </View>
            </View>

            {played && (
              <View style={styles.formRow}>
                <Text style={styles.formLabel}>LAST {riv.form.length}</Text>
                {riv.form.map((l, i) => {
                  const c = chip(l);
                  return (
                    <View key={i} style={[styles.formChip, { backgroundColor: c.bg, borderColor: c.bd }]}>
                      <Text style={[styles.formChipText, { color: c.ink }]}>{l}</Text>
                    </View>
                  );
                })}
              </View>
            )}
          </View>

          <View style={styles.tiles}>
            <View style={styles.tile}>
              <Text
                style={[
                  styles.tileValue,
                  {
                    color:
                      riv.run && riv.run.startsWith('W')
                        ? colors.accent
                        : riv.run && riv.run.startsWith('L')
                          ? colors.danger
                          : colors.text,
                  },
                ]}
              >
                {riv.run || '—'}
              </Text>
              <Text style={styles.tileKicker}>CURRENT RUN</Text>
            </View>
            <View style={styles.tile}>
              <Text style={styles.tileValue}>{signed(riv.avg_margin)}</Text>
              <Text style={styles.tileKicker}>AVG MARGIN</Text>
            </View>
            <View style={styles.tile}>
              <Text style={styles.tileValue}>{riv.best_win == null ? '—' : `+${riv.best_win.toFixed(1)}`}</Text>
              <Text style={styles.tileKicker}>BEST WIN</Text>
            </View>
          </View>
        </LinearGradient>

        <View style={styles.historyZone}>
          <Text style={styles.historyLabel}>HISTORY</Text>
          {played ? (
            <View style={styles.historyCard}>
              {riv.history.map((h, i) => {
                const pill = outcomePill(h.outcome);
                return (
                  <View key={i} style={[styles.histRow, i < riv.history.length - 1 && styles.histSep]}>
                    <View style={[styles.histPill, { backgroundColor: pill.bg, borderColor: pill.bd }]}>
                      <Text style={[styles.histPillText, { color: pill.ink }]}>{pill.label}</Text>
                    </View>
                    <View style={{ flex: 1, minWidth: 0 }}>
                      <Text style={styles.histScore}>
                        {h.my_points.toFixed(1)} – {h.their_points.toFixed(1)}
                      </Text>
                      {h.story ? <Text style={styles.histStory} numberOfLines={1}>{h.story}</Text> : null}
                    </View>
                    <Text style={styles.histDate}>{dateLabel(h.settled_at)}</Text>
                  </View>
                );
              })}
            </View>
          ) : (
            <Text style={styles.historyEmpty}>The series starts when you send it.</Text>
          )}

          <Button
            title={`⚔ Challenge ${username}`}
            style={{ marginTop: spacing.lg }}
            onPress={challenge}
          />
        </View>
      </ScrollView>
    </Screen>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    heroCard: {
      backgroundColor: colors.card,
      borderWidth: 1,
      borderColor: colors.border,
      borderRadius: 16,
      paddingVertical: 20,
      paddingHorizontal: 14,
      alignItems: 'center',
    },
    faceoff: { flexDirection: 'row', alignItems: 'center', gap: 16 },
    corner: { alignItems: 'center', gap: 6, width: 76 },
    bigAvatar: {
      width: 52,
      height: 52,
      borderRadius: 26,
      borderWidth: 1,
      alignItems: 'center',
      justifyContent: 'center',
    },
    bigAvatarText: { fontFamily: fonts.bodyExtra, fontSize: 20 },
    cornerName: { fontSize: 11, fontFamily: fonts.bodyExtra, color: colors.muted, maxWidth: 76 },
    scoreCol: { alignItems: 'center', gap: 2, paddingHorizontal: 8 },
    bigScore: { fontFamily: fonts.hero, fontSize: 40, lineHeight: 42 },
    seriesLine: { fontSize: 8.5, fontFamily: fonts.bodyBlack, letterSpacing: 2, color: colors.placeholder },
    formRow: { flexDirection: 'row', alignItems: 'center', gap: 5, marginTop: 12 },
    formLabel: { fontSize: 8.5, fontFamily: fonts.bodyBlack, letterSpacing: 1.5, color: colors.placeholder, marginRight: 3 },
    formChip: {
      width: 20,
      height: 20,
      borderRadius: 7,
      borderWidth: 1,
      alignItems: 'center',
      justifyContent: 'center',
    },
    formChipText: { fontSize: 9.5, fontFamily: fonts.bodyBlack },
    tiles: { flexDirection: 'row', gap: 8, marginTop: 10 },
    tile: {
      flex: 1,
      backgroundColor: colors.card,
      borderWidth: 1,
      borderColor: colors.border,
      borderRadius: 12,
      paddingVertical: 11,
      alignItems: 'center',
    },
    tileValue: { fontFamily: fonts.hero, fontSize: 19, color: colors.text },
    tileKicker: { fontSize: 8.5, fontFamily: fonts.bodyBlack, letterSpacing: 1, color: colors.placeholder, marginTop: 2 },
    historyZone: { paddingHorizontal: spacing.lg, paddingTop: spacing.lg },
    historyLabel: { fontSize: 9.5, fontFamily: fonts.bodyBlack, letterSpacing: 1.5, color: colors.placeholder },
    historyCard: {
      backgroundColor: colors.card,
      borderWidth: 1,
      borderColor: colors.border,
      borderRadius: 14,
      marginTop: 8,
      overflow: 'hidden',
    },
    histRow: { flexDirection: 'row', alignItems: 'center', gap: 11, paddingHorizontal: 14, paddingVertical: 11 },
    histSep: { borderBottomWidth: 1, borderBottomColor: colors.borderSubtle },
    histPill: { borderWidth: 1, borderRadius: 999, paddingHorizontal: 10, paddingVertical: 3, flexShrink: 0 },
    histPillText: { fontSize: 9.5, fontFamily: fonts.bodyBlack, letterSpacing: 1 },
    histScore: { fontFamily: fonts.hero, fontSize: 16, color: colors.text },
    histStory: { fontSize: 10, color: colors.muted, marginTop: 1 },
    histDate: { fontSize: 9.5, fontFamily: fonts.bodyExtra, color: colors.placeholder, flexShrink: 0 },
    historyEmpty: { fontSize: 12, color: colors.placeholder, fontFamily: fonts.bodySemi, marginTop: 8 },
  });
