import { Pressable, Text, View } from 'react-native';
import Animated, { Easing, useAnimatedStyle, useSharedValue, withSequence, withSpring, withTiming } from 'react-native-reanimated';

import { compact } from '@/lib/format';
import { haptic } from '@/lib/settings';
import { Font } from '@/lib/theme';

import { Icon } from './ui';

const strokes = [0, 1, 2, 3, 4, 5, 6, 7];

function Stroke({ index, progress, color }: { index: number; progress: { value: number }; color: string }) {
  const angle = (index / strokes.length) * Math.PI * 2;
  const style = useAnimatedStyle(() => {
    const distance = 14 + progress.value * 22;
    return {
      opacity: progress.value === 0 ? 0 : 1 - progress.value,
      transform: [
        { translateX: Math.cos(angle) * distance },
        { translateY: Math.sin(angle) * distance },
        { rotate: `${angle + Math.PI / 2}rad` },
        { scaleY: 1 - progress.value * 0.5 },
      ],
    };
  });
  return <Animated.View pointerEvents="none" style={[{ position: 'absolute', width: 3, height: 9, borderRadius: 2, backgroundColor: color }, style]} />;
}

/** A like or dislike control. A like is a small celebration: the thumb kicks, a ring and eight strokes fly out, and "+1" lifts off. */
export function VoteButton({
  kind,
  active,
  count,
  onPress,
  ink,
  accent,
  size = 44,
  fill,
  label,
}: {
  kind: 'like' | 'dislike';
  active: boolean;
  count?: number;
  onPress: () => void;
  ink: string;
  accent: string;
  size?: number;
  fill?: string;
  label?: string;
}) {
  const kick = useSharedValue(0);
  const burst = useSharedValue(0);

  const thumb = useAnimatedStyle(() => ({
    transform: [{ scale: 1 + kick.value * 0.32 }, { rotate: `${kick.value * (kind === 'like' ? -18 : 18)}deg` }, { translateY: kick.value * (kind === 'like' ? -4 : 4) }],
  }));
  const ring = useAnimatedStyle(() => ({
    opacity: burst.value === 0 ? 0 : 1 - burst.value,
    transform: [{ scale: 0.6 + burst.value * 1.1 }],
  }));
  const plus = useAnimatedStyle(() => ({
    opacity: burst.value === 0 ? 0 : 1 - burst.value * burst.value,
    transform: [{ translateY: -18 - burst.value * 26 }],
  }));

  const press = () => {
    kick.value = withSequence(withTiming(1, { duration: 110, easing: Easing.out(Easing.quad) }), withSpring(0, { damping: 7, stiffness: 220 }));
    if (kind === 'like' && !active) {
      haptic('success');
      burst.value = 0;
      burst.value = withTiming(1, { duration: 520, easing: Easing.out(Easing.cubic) }, () => {
        burst.value = 0;
      });
    } else haptic('light');
    onPress();
  };

  const color = active ? accent : ink;
  return (
    <Pressable accessibilityRole="button" accessibilityLabel={label ?? (kind === 'like' ? 'Like' : 'Dislike')} accessibilityState={{ selected: active }} hitSlop={6} onPress={press} style={{ alignItems: 'center', gap: 4 }}>
      <View style={{ width: size, height: size, borderRadius: size / 2, backgroundColor: fill, alignItems: 'center', justifyContent: 'center' }}>
        {kind === 'like' && (
          <>
            <Animated.View pointerEvents="none" style={[{ position: 'absolute', width: size, height: size, borderRadius: size / 2, borderWidth: 2, borderColor: accent }, ring]} />
            {strokes.map((index) => (
              <Stroke key={index} index={index} progress={burst} color={accent} />
            ))}
            <Animated.Text pointerEvents="none" style={[{ position: 'absolute', fontFamily: Font.display, fontSize: 17, color: accent }, plus]}>
              +1
            </Animated.Text>
          </>
        )}
        <Animated.View style={thumb}>
          <Icon name={kind === 'like' ? (active ? 'likeFill' : 'like') : active ? 'dislikeFill' : 'dislike'} size={size * 0.5} color={color} />
        </Animated.View>
      </View>
      {count !== undefined && <Text style={{ fontSize: 11.5, fontWeight: '700', color: ink, fontVariant: ['tabular-nums'] }}>{compact(count)}</Text>}
    </Pressable>
  );
}
