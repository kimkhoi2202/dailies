import { SymbolView, type SFSymbol } from 'expo-symbols';
import type { ReactNode } from 'react';
import { Pressable, type StyleProp, Text, type TextStyle, View, type ViewStyle } from 'react-native';

import { compact } from '@/lib/format';
import { haptic } from '@/lib/settings';
import { Coin as CoinColors, Font, OnGold, Radius, useTheme } from '@/lib/theme';

const symbols = {
  home: ['house.fill', '⌂'],
  videos: ['play.rectangle.on.rectangle.fill', '▣'],
  you: ['person.fill', '●'],
  search: ['magnifyingglass', '⌕'],
  close: ['xmark', '✕'],
  back: ['chevron.left', '‹'],
  down: ['chevron.down', '⌄'],
  forward: ['chevron.right', '›'],
  like: ['hand.thumbsup', '👍'],
  likeFill: ['hand.thumbsup.fill', '👍'],
  dislike: ['hand.thumbsdown', '👎'],
  dislikeFill: ['hand.thumbsdown.fill', '👎'],
  comment: ['bubble.left.fill', '💬'],
  share: ['arrowshape.turn.up.right.fill', '↗'],
  play: ['play.fill', '▶'],
  players: ['person.2.fill', '⚇'],
  settings: ['gearshape.fill', '⚙'],
  info: ['info.circle', 'ⓘ'],
  again: ['arrow.counterclockwise', '↺'],
  check: ['checkmark', '✓'],
  send: ['arrow.up', '↑'],
  trophy: ['trophy.fill', '★'],
  flame: ['flame.fill', '♨'],
  plus: ['plus', '+'],
  sun: ['sun.max.fill', '☀'],
  verified: ['checkmark.seal.fill', '✔'],
  clock: ['clock', '◷'],
  bolt: ['bolt.fill', 'ϟ'],
  pencil: ['pencil', '✎'],
  offline: ['wifi.slash', '⚠'],
} as const satisfies Record<string, readonly [SFSymbol, string]>;

export type IconName = keyof typeof symbols;

export function Icon({ name, size = 20, color }: { name: IconName; size?: number; color: string }) {
  const [ios, glyph] = symbols[name];
  return (
    <SymbolView
      name={{ ios }}
      size={size}
      tintColor={color}
      weight="semibold"
      fallback={<Text style={{ fontSize: size * 0.85, color, lineHeight: size, width: size, textAlign: 'center' }}>{glyph}</Text>}
    />
  );
}

export function Display({ children, size = 28, color, style }: { children: ReactNode; size?: number; color?: string; style?: StyleProp<TextStyle> }) {
  const t = useTheme();
  return (
    <Text
      style={[{ fontFamily: Font.display, fontSize: size, lineHeight: size * 1.02, color: color ?? t.ink, textTransform: 'uppercase' }, style]}
      numberOfLines={2}>
      {children}
    </Text>
  );
}

export function Label({ children, color, size = 11, style }: { children: ReactNode; color?: string; size?: number; style?: StyleProp<TextStyle> }) {
  const t = useTheme();
  return (
    <Text style={[{ fontFamily: Font.mono, fontSize: size, fontWeight: '600', letterSpacing: 0.6, color: color ?? t.ink2, textTransform: 'uppercase' }, style]}>
      {children}
    </Text>
  );
}

export function Body({ children, color, size = 15, weight = '400', style, lines }: { children: ReactNode; color?: string; size?: number; weight?: TextStyle['fontWeight']; style?: StyleProp<TextStyle>; lines?: number }) {
  const t = useTheme();
  return (
    <Text numberOfLines={lines} style={[{ fontSize: size, fontWeight: weight, color: color ?? t.ink }, style]}>
      {children}
    </Text>
  );
}

export function Card({ children, style, fill }: { children: ReactNode; style?: StyleProp<ViewStyle>; fill?: string }) {
  const t = useTheme();
  return <View style={[{ backgroundColor: fill ?? t.surface, borderRadius: Radius.card, borderCurve: 'continuous', padding: 16 }, style]}>{children}</View>;
}

const LIP = 5;

export function Key({
  label,
  icon,
  detail,
  tone = 'light',
  small,
  disabled,
  onPress,
  style,
  testID,
}: {
  label: string;
  icon?: IconName;
  detail?: string;
  tone?: 'gold' | 'light' | 'dark';
  small?: boolean;
  disabled?: boolean;
  onPress: () => void;
  style?: StyleProp<ViewStyle>;
  testID?: string;
}) {
  const t = useTheme();
  const face = tone === 'gold' ? t.gold : tone === 'dark' ? t.raised : t.keyFace;
  const lip = tone === 'gold' ? t.goldLip : tone === 'dark' ? (t.dark ? '#111113' : t.sunken) : t.keyLip;
  const ink = tone === 'dark' ? t.ink : OnGold;
  const height = small ? 44 : 56;
  return (
    <Pressable
      testID={testID}
      accessibilityRole="button"
      accessibilityLabel={label}
      disabled={disabled}
      onPressIn={() => haptic('light')}
      onPress={onPress}
      style={[{ height: height + LIP, opacity: disabled ? 0.5 : 1 }, style]}>
      {({ pressed }) => (
        <>
          <View style={{ position: 'absolute', left: 0, right: 0, top: LIP, height, borderRadius: Radius.key, borderCurve: 'continuous', backgroundColor: lip }} />
          <View
            style={{
              height,
              borderRadius: Radius.key,
              borderCurve: 'continuous',
              backgroundColor: face,
              transform: [{ translateY: pressed ? LIP : 0 }],
              flexDirection: 'row',
              alignItems: 'center',
              justifyContent: detail ? 'space-between' : 'center',
              gap: 8,
              paddingHorizontal: 18,
            }}>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
              {icon && <Icon name={icon} size={small ? 15 : 18} color={ink} />}
              <Text numberOfLines={1} style={{ fontFamily: Font.display, fontSize: small ? 17 : 22, color: ink, letterSpacing: 0.4, textTransform: 'uppercase' }}>
                {label}
              </Text>
            </View>
            {detail && <Label color={ink} size={10}>{detail}</Label>}
          </View>
        </>
      )}
    </Pressable>
  );
}

export function IconButton({ name, onPress, size = 40, label, fill, color }: { name: IconName; onPress: () => void; size?: number; label: string; fill?: string; color?: string }) {
  const t = useTheme();
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={label}
      hitSlop={8}
      onPressIn={() => haptic('light')}
      onPress={onPress}
      style={({ pressed }) => ({
        width: size,
        height: size,
        borderRadius: size / 2,
        backgroundColor: fill ?? t.surface,
        alignItems: 'center',
        justifyContent: 'center',
        transform: [{ scale: pressed ? 0.94 : 1 }],
      })}>
      <Icon name={name} size={size * 0.42} color={color ?? t.ink} />
    </Pressable>
  );
}

export function Chip({ label, selected, onPress, icon }: { label: string; selected?: boolean; onPress?: () => void; icon?: IconName }) {
  const t = useTheme();
  const ink = selected ? t.onInk : t.ink;
  return (
    <Pressable
      disabled={!onPress}
      onPress={() => {
        haptic('select');
        onPress?.();
      }}
      style={({ pressed }) => ({
        flexDirection: 'row',
        alignItems: 'center',
        gap: 5,
        height: 34,
        paddingHorizontal: 14,
        borderRadius: 17,
        backgroundColor: selected ? t.ink : t.surface,
        transform: [{ scale: pressed ? 0.96 : 1 }],
      })}>
      {icon && <Icon name={icon} size={12} color={ink} />}
      <Text style={{ fontSize: 13, fontWeight: '600', color: ink }}>{label}</Text>
    </Pressable>
  );
}

export function Tag({ label, icon, onDark }: { label: string; icon?: IconName; onDark?: boolean }) {
  const t = useTheme();
  const ink = onDark ? '#FFFFFF' : t.ink2;
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 5, height: 24, paddingHorizontal: 9, borderRadius: 12, backgroundColor: onDark ? 'rgba(0,0,0,0.45)' : t.sunken }}>
      {icon && <Icon name={icon} size={11} color={ink} />}
      <Text style={{ fontSize: 11.5, fontWeight: '600', color: ink }}>{label}</Text>
    </View>
  );
}

export function Coin({ size = 18 }: { size?: number }) {
  return (
    <View style={{ width: size, height: size, borderRadius: size / 2, backgroundColor: CoinColors.edge, alignItems: 'center', justifyContent: 'center' }}>
      <View style={{ width: size * 0.82, height: size * 0.82, borderRadius: size, backgroundColor: CoinColors.face, marginTop: -size * 0.08, alignItems: 'center', justifyContent: 'center' }}>
        <View style={{ width: size * 0.5, height: size * 0.5, borderRadius: size, borderWidth: Math.max(1, size * 0.07), borderColor: CoinColors.shine, opacity: 0.9 }} />
      </View>
    </View>
  );
}

export function GoldPill({ amount, onPress, prefix = '', onDark }: { amount: number | undefined; onPress?: () => void; prefix?: string; onDark?: boolean }) {
  const t = useTheme();
  return (
    <Pressable
      disabled={!onPress}
      accessibilityLabel={`${amount ?? 0} gold`}
      onPress={() => {
        haptic('light');
        onPress?.();
      }}
      style={{ flexDirection: 'row', alignItems: 'center', gap: 6, height: 36, paddingLeft: 9, paddingRight: 13, borderRadius: 18, backgroundColor: onDark ? 'rgba(14,14,15,0.72)' : t.surface }}>
      <Coin size={18} />
      <Text style={{ fontFamily: Font.display, fontSize: 20, color: onDark ? '#F3F0E9' : t.ink, fontVariant: ['tabular-nums'] }}>
        {amount === undefined ? '–' : prefix + compact(amount)}
      </Text>
    </Pressable>
  );
}

export function Avatar({ name, color, size = 32 }: { name: string; color: string; size?: number }) {
  return (
    <View style={{ width: size, height: size, borderRadius: size / 2, backgroundColor: color, alignItems: 'center', justifyContent: 'center' }}>
      <Text style={{ fontFamily: Font.display, fontSize: size * 0.5, color: '#FFFFFF' }}>{name.slice(0, 1).toUpperCase()}</Text>
    </View>
  );
}

export function Meter({ value, max, color, height = 5 }: { value: number; max: number; color?: string; height?: number }) {
  const t = useTheme();
  return (
    <View style={{ height, borderRadius: height / 2, backgroundColor: t.sunken, overflow: 'hidden' }}>
      <View style={{ width: `${Math.min(100, Math.max(0, (value / max) * 100))}%`, height, borderRadius: height / 2, backgroundColor: color ?? t.gold }} />
    </View>
  );
}

export function Row({ children, style, gap = 8 }: { children: ReactNode; style?: StyleProp<ViewStyle>; gap?: number }) {
  return <View style={[{ flexDirection: 'row', alignItems: 'center', gap }, style]}>{children}</View>;
}

export function Divider() {
  const t = useTheme();
  return <View style={{ height: 1, backgroundColor: t.line }} />;
}
