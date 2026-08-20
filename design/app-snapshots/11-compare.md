# Compare players — current iPhone app screen

> **What this file is:** the REAL React Native source of this iPhone screen —
> the current implementation, not a mockup. Redesign it as a phone-frame mockup
> (390pt wide) in the same design language; annotate every interaction; design
> every state (filled / empty / loading / error). The result gets ported back
> into React Native. Names and layout in the code are the truth of what exists
> today.

Two players side by side: season averages, fantasy projection, recent games — the draft-decision helper.

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

## The screen source (`src/screens/CompareScreen.js`)

```jsx
import { useEffect, useRef, useState } from 'react';
import { FlatList, Pressable, StyleSheet, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useAuth } from '../auth/AuthContext';
import { searchPlayers, getPlayerProfile } from '../api/sports';
import { useTheme, useThemedStyles, spacing, radius, font, fonts } from '../theme';
import { Screen, Card, Avatar, SearchInput } from '../components/ui';
import PlayerAvatar from '../components/PlayerAvatar';

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
        <PlayerAvatar uri={player.headshot_url} name={player.name} size={56} />
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
```

## Shared component it uses: `PlayerAvatar.js`

```jsx
import { useState } from 'react';
import { Image, View } from 'react-native';
import Avatar from './ui/Avatar';
import { useTheme } from '../theme';

// A player's face, with the initials Avatar as the fallback. Used anywhere a
// real athlete appears — draft board, rosters, live matchup, results.
//
// Falls back for two reasons: placeholder pools (NBA/NFL rows aren't seeded
// from ESPN yet, so they have no photo) and load failures. Either way the row
// looks deliberate rather than broken.
export default function PlayerAvatar({ uri, name, size = 36, style }) {
  const { colors } = useTheme();
  const [failed, setFailed] = useState(false);

  if (!uri || failed) return <Avatar name={name} size={size} style={style} />;

  return (
    <View
      style={[
        {
          width: size,
          height: size,
          borderRadius: size / 2,
          overflow: 'hidden',
          backgroundColor: colors.cardElevated,
        },
        style,
      ]}
    >
      <Image
        source={{ uri }}
        style={{ width: size, height: size }}
        resizeMode="cover"
        onError={() => setFailed(true)}
      />
    </View>
  );
}
```
