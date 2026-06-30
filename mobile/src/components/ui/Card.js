import { View, Pressable } from 'react-native';
import { useTheme, radius, spacing, shadow } from '../../theme';

// A surface with depth — border + soft shadow. Pass onPress to make it tappable.
export default function Card({ children, onPress, style, padded = true, elevated = false, ...rest }) {
  const { colors } = useTheme();
  const base = [
    {
      backgroundColor: elevated ? colors.cardElevated : colors.card,
      borderRadius: radius.lg,
      borderWidth: 1,
      borderColor: colors.borderSubtle,
      padding: padded ? spacing.lg : 0,
    },
    shadow.sm,
    style,
  ];

  if (onPress) {
    return (
      <Pressable
        onPress={onPress}
        style={({ pressed }) => [...base, pressed && { opacity: 0.9, transform: [{ scale: 0.99 }] }]}
        {...rest}
      >
        {children}
      </Pressable>
    );
  }

  return (
    <View style={base} {...rest}>
      {children}
    </View>
  );
}
