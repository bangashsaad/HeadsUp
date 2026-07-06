import { useEffect, useRef, useState } from 'react';
import { FlatList, Pressable, StyleSheet, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useAuth } from '../auth/AuthContext';
import { searchPlayers, getPlayerProfile } from '../api/sports';
import { useTheme, useThemedStyles, spacing, radius, font, fonts } from '../theme';
import { Screen, Card, Avatar, SearchInput } from '../components/ui';

export default function CompareScreen() {
  const { token } = useAuth();
  const { colors } = useTheme();
  const styles = useThemedStyles(makeStyles);
  const [a, setA] = useState(null);
  const [b, setB] = useState(null);

  return (
    <Screen scroll>
      <View style={styles.slots}>
        <Slot player={a} onPick={setA} onClear={() => setA(null)} token={token} styles={styles} colors={colors} />
        <Text style={styles.vs}>VS</Text>
        <Slot player={b} onPick={setB} onClear={() => setB(null)} token={token} styles={styles} colors={colors} />
      </View>

      {a && b ? <Comparison a={a} b={b} token={token} styles={styles} colors={colors} /> : (
        <Text style={styles.hint}>Pick two players to compare their season stats side by side.</Text>
      )}
    </Screen>
  );
}

function Slot({ player, onPick, onClear, token, styles, colors }) {
  const [q, setQ] = useState('');
  const [results, setResults] = useState([]);
  const seq = useRef(0);

  useEffect(() => {
    const term = q.trim();
    if (term.length < 2) {
      setResults([]);
      return;
    }
    const mine = ++seq.current;
    const t = setTimeout(async () => {
      try {
        const res = await searchPlayers(token, term);
        if (mine === seq.current) setResults(res.players || []);
      } catch {
        if (mine === seq.current) setResults([]);
      }
    }, 300);
    return () => clearTimeout(t);
  }, [q, token]);

  if (player) {
    return (
      <View style={styles.slot}>
        <Pressable onPress={onClear} hitSlop={8} style={styles.clear}>
          <Ionicons name="close-circle" size={20} color={colors.placeholder} />
        </Pressable>
        <Avatar name={player.name} size={56} />
        <Text style={styles.slotName} numberOfLines={1}>
          {player.name}
        </Text>
        <Text style={styles.slotMeta} numberOfLines={1}>
          {player.team} · {player.position}
        </Text>
      </View>
    );
  }

  return (
    <View style={styles.slot}>
      <SearchInput value={q} onChangeText={setQ} placeholder="Add player" />
      {results.length > 0 ? (
        <Card padded={false} style={styles.dropdown}>
          <FlatList
            data={results.slice(0, 6)}
            keyExtractor={(item) => String(item.id)}
            keyboardShouldPersistTaps="handled"
            scrollEnabled={false}
            renderItem={({ item }) => (
              <Pressable
                onPress={() => {
                  onPick(item);
                  setQ('');
                  setResults([]);
                }}
                style={({ pressed }) => [styles.resultRow, pressed && { backgroundColor: colors.bgElevated }]}
              >
                <Text style={styles.resultName} numberOfLines={1}>
                  {item.name}
                </Text>
                <Text style={styles.resultMeta}>{item.team}</Text>
              </Pressable>
            )}
          />
        </Card>
      ) : null}
    </View>
  );
}

function Comparison({ a, b, token, styles, colors }) {
  const [pa, setPa] = useState(null);
  const [pb, setPb] = useState(null);

  useEffect(() => {
    let active = true;
    getPlayerProfile(token, a.id).then((p) => active && setPa(p)).catch(() => {});
    getPlayerProfile(token, b.id).then((p) => active && setPb(p)).catch(() => {});
    return () => {
      active = false;
    };
  }, [a.id, b.id, token]);

  if (!pa || !pb) {
    return <Text style={styles.hint}>Loading stats…</Text>;
  }

  if (!pa.available || !pb.available) {
    return <Text style={styles.hint}>Stats aren't available for one of these players yet.</Text>;
  }

  // Align rows by the labels in player A's season tiles.
  const bByLabel = Object.fromEntries((pb.season.tiles || []).map((t) => [t.label, t.value]));
  const rows = (pa.season.tiles || []).map((t) => ({ label: t.label, a: t.value, b: bByLabel[t.label] ?? '—' }));

  const num = (v) => parseFloat(String(v).replace(/[^0-9.\-]/g, ''));

  return (
    <Card padded={false} style={{ marginTop: spacing.lg }}>
      <View style={[styles.cmpRow, styles.cmpHead]}>
        <Text style={[styles.cmpVal, styles.cmpHeadText]} numberOfLines={1}>
          {a.name.split(' ').slice(-1)[0]}
        </Text>
        <Text style={styles.cmpLabelHead}>STAT</Text>
        <Text style={[styles.cmpVal, styles.cmpHeadText]} numberOfLines={1}>
          {b.name.split(' ').slice(-1)[0]}
        </Text>
      </View>
      {rows.map((r, i) => {
        const av = num(r.a);
        const bv = num(r.b);
        const aWin = !isNaN(av) && !isNaN(bv) && av > bv;
        const bWin = !isNaN(av) && !isNaN(bv) && bv > av;
        return (
          <View key={r.label} style={[styles.cmpRow, i < rows.length - 1 && styles.cmpDivider]}>
            <Text style={[styles.cmpVal, aWin && { color: colors.accent, fontWeight: '900' }]}>{r.a}</Text>
            <Text style={styles.cmpLabel}>{r.label}</Text>
            <Text style={[styles.cmpVal, bWin && { color: colors.accent, fontWeight: '900' }]}>{r.b}</Text>
          </View>
        );
      })}
    </Card>
  );
}

const makeStyles = (colors) =>
  StyleSheet.create({
    slots: { flexDirection: 'row', alignItems: 'flex-start', gap: spacing.sm },
    slot: { flex: 1, alignItems: 'center', minHeight: 120 },
    vs: { color: colors.placeholder, fontSize: 17, fontFamily: fonts.hero, letterSpacing: 1, marginTop: 40 },
    clear: { position: 'absolute', top: 0, right: 0, zIndex: 1 },
    slotName: { color: colors.text, fontSize: font.subtitle, fontWeight: '700', marginTop: spacing.sm, textAlign: 'center' },
    slotMeta: { color: colors.muted, fontSize: font.small, marginTop: 2 },
    dropdown: { marginTop: spacing.sm, width: '100%' },
    resultRow: { paddingVertical: 10, paddingHorizontal: spacing.md, borderBottomColor: colors.borderSubtle, borderBottomWidth: StyleSheet.hairlineWidth },
    resultName: { color: colors.text, fontSize: font.body, fontWeight: '600' },
    resultMeta: { color: colors.muted, fontSize: font.small, marginTop: 1 },
    hint: { color: colors.muted, fontSize: font.body, textAlign: 'center', marginTop: spacing.xxl },
    cmpRow: { flexDirection: 'row', alignItems: 'center', paddingVertical: 14, paddingHorizontal: spacing.md },
    cmpHead: { backgroundColor: colors.bgElevated },
    cmpDivider: { borderBottomColor: colors.borderSubtle, borderBottomWidth: StyleSheet.hairlineWidth },
    cmpVal: { flex: 1, textAlign: 'center', color: colors.text, fontSize: font.bodyLg, fontWeight: '700' },
    cmpHeadText: { color: colors.text, fontSize: 15, fontFamily: fonts.condBold },
    cmpLabel: { width: 70, textAlign: 'center', color: colors.muted, fontSize: font.caption, fontWeight: '700' },
    cmpLabelHead: { width: 70, textAlign: 'center', color: colors.placeholder, fontSize: 9, fontFamily: fonts.bodyBlack, letterSpacing: 1 },
  });
