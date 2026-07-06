import { View, Text } from 'react-native';
import { useTheme, fonts, radius } from '../../theme';

// One tile of the 4-up stat grid: big condensed-italic value over a tiny kicker.
export default function StatTile({ value, label, color, style }) {
  const { colors } = useTheme();
  return (
    <View
      style={[
        {
          flex: 1,
          backgroundColor: colors.card,
          borderWidth: 1,
          borderColor: colors.border,
          borderRadius: radius.md,
          paddingVertical: 10,
          alignItems: 'center',
        },
        style,
      ]}
    >
      <Text style={{ fontFamily: fonts.hero, fontSize: 24, color: color || colors.text }}>{value}</Text>
      <Text
        style={{
          fontSize: 8.5,
          fontFamily: fonts.bodyExtra,
          letterSpacing: 1.5,
          color: colors.placeholder,
          marginTop: 2,
          textTransform: 'uppercase',
        }}
      >
        {label}
      </Text>
    </View>
  );
}
