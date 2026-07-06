import { Text } from 'react-native';
import { useTheme, fonts } from '../../theme';

// The three voices of the Reimagined type system.

// Tiny 800-weight uppercase tracking label: "SEASON RECORD", "PICK 3 OF 10".
export function Kicker({ children, color, size = 10, tracking = 2, style, ...rest }) {
  const { colors } = useTheme();
  return (
    <Text
      style={[
        { color: color || colors.placeholder, fontSize: size, fontFamily: fonts.bodyExtra, letterSpacing: tracking, textTransform: 'uppercase' },
        style,
      ]}
      {...rest}
    >
      {children}
    </Text>
  );
}

// Barlow Condensed 800 italic display: scores, titles, "YOU'RE ON THE CLOCK".
export function CondTitle({ children, color, size = 22, italic = true, style, ...rest }) {
  const { colors } = useTheme();
  return (
    <Text
      style={[
        {
          color: color || colors.text,
          fontSize: size,
          fontFamily: italic ? fonts.hero : fonts.heroUpright,
          letterSpacing: 0.5,
        },
        style,
      ]}
      {...rest}
    >
      {children}
    </Text>
  );
}

// Archivo Black energy (900 italic): "YOU WIN.", "LOCKED IN.", the wordmark.
export function DisplayTitle({ children, color, size = 34, style, ...rest }) {
  const { colors } = useTheme();
  return (
    <Text style={[{ color: color || colors.text, fontSize: size, fontFamily: fonts.display, letterSpacing: -0.5 }, style]} {...rest}>
      {children}
    </Text>
  );
}
