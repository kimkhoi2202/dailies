import { Text, View } from 'react-native';
import Svg, { Path, Rect } from 'react-native-svg';

import { Font, useTheme } from '@/lib/theme';

export function LogoKey({ size = 30 }: { size?: number }) {
  const t = useTheme();
  return (
    <Svg width={size} height={size * 1.06} viewBox="0 0 32 34">
      <Rect y={3} width={32} height={31} rx={8} fill={t.goldLip} />
      <Rect width={32} height={30} rx={8} fill={t.gold} />
      <Path d="M8.5 5.5h7.2a9.5 9.5 0 0 1 0 19H8.5z" fill="#151412" />
      <Path d="M13.2 10.6l6.4 4.4-6.4 4.4z" fill={t.gold} />
    </Svg>
  );
}

export function Wordmark({ size = 30 }: { size?: number }) {
  const t = useTheme();
  return (
    <View accessibilityRole="header" accessibilityLabel="Dailies" style={{ flexDirection: 'row', alignItems: 'center', gap: 2 }}>
      <LogoKey size={size} />
      <Text style={{ fontFamily: Font.display, fontSize: size * 1.02, lineHeight: size * 1.1, color: t.ink, letterSpacing: 0.3 }}>AILIES</Text>
    </View>
  );
}
