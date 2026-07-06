import Svg, { Text as SvgText } from 'react-native-svg';
import { fonts } from '../../theme';

// Outline-only display text — the big translucent "VS" / pick-number watermarks.
// Rendered as stroked SVG text (RN has no text-stroke).
export default function GhostText({
  children,
  size = 34,
  color = 'rgba(244,245,247,0.09)',
  strokeWidth = 1.2,
  family = fonts.display,
  width,
  height,
  style,
}) {
  const label = String(children);
  const w = width ?? Math.ceil(size * Math.max(1, label.length) * 0.78);
  const h = height ?? Math.ceil(size * 1.25);
  return (
    <Svg width={w} height={h} style={style} pointerEvents="none">
      <SvgText
        x={w / 2}
        y={h * 0.8}
        fontSize={size}
        fontFamily={family}
        textAnchor="middle"
        fill="none"
        stroke={color}
        strokeWidth={strokeWidth}
      >
        {label}
      </SvgText>
    </Svg>
  );
}
