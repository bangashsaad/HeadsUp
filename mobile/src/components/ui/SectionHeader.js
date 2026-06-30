import { Text } from 'react-native';
import { useTheme, font, spacing } from '../../theme';

// Small uppercase group label used between list sections.
export default function SectionHeader({ children, style }) {
  const { colors } = useTheme();
  return (
    <Text
      style={[
        {
          color: colors.muted,
          fontSize: font.caption,
          fontWeight: '800',
          textTransform: 'uppercase',
          letterSpacing: 1,
          marginBottom: spacing.sm,
          marginTop: spacing.lg,
        },
        style,
      ]}
    >
      {children}
    </Text>
  );
}
