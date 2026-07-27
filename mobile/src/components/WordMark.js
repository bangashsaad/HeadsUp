import { View, Text } from 'react-native';
import { useTheme, fonts } from '../theme';

// The brand lockup: BOUT in Archivo Black italic with a lime full stop —
// "settle it, end of discussion". (HEADS|UP split its color across a compound
// word; BOUT is one word, so the period carries the accent instead.)
export default function WordMark({ size = 21, tag = true, style }) {
  const { colors } = useTheme();
  return (
    <View style={style}>
      <Text style={{ fontFamily: fonts.display, fontSize: size, letterSpacing: -0.5, lineHeight: size * 1.05 }}>
        <Text style={{ color: colors.text }}>BOUT</Text>
        <Text style={{ color: colors.accent }}>.</Text>
      </Text>
      {tag ? (
        <Text
          style={{
            fontSize: Math.max(7.5, size * 0.4),
            fontFamily: fonts.bodyExtra,
            letterSpacing: 3.5,
            color: colors.placeholder,
            marginTop: 3,
          }}
        >
          FANTASY DUELS
        </Text>
      ) : null}
    </View>
  );
}
