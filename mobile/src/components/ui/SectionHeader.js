import { View, Text } from 'react-native';
import { useTheme, fonts, spacing } from '../../theme';

// Condensed-italic section title, e.g. "YOUR MOVE", with an optional right hint
// ("3 PENDING"). Accepts a plain string child for back-compat.
export default function SectionHeader({ children, hint, style }) {
  const { colors } = useTheme();
  return (
    <View
      style={[
        {
          flexDirection: 'row',
          alignItems: 'baseline',
          justifyContent: 'space-between',
          marginBottom: spacing.sm,
          marginTop: spacing.lg,
        },
        style,
      ]}
    >
      <Text
        style={{
          color: colors.text,
          fontFamily: fonts.hero,
          fontSize: 17,
          letterSpacing: 1,
          textTransform: 'uppercase',
        }}
      >
        {children}
      </Text>
      {hint ? (
        <Text style={{ color: colors.placeholder, fontSize: 10, fontFamily: fonts.bodyExtra, letterSpacing: 1, textTransform: 'uppercase' }}>
          {hint}
        </Text>
      ) : null}
    </View>
  );
}
