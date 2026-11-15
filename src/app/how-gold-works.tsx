import { router } from 'expo-router';
import { View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { Body, Display, Icon, Key, Row } from '@/components/ui';
import { useTheme } from '@/lib/theme';

const rules = [
  'About 1 gold for each minute you play.',
  'Up to 100 gold a day from one game.',
  'Up to 300 gold a day from one studio.',
  'Watching never earns gold.',
  'Gold cannot be bought or cashed out.',
];

export default function HowGoldWorks() {
  const t = useTheme();
  const insets = useSafeAreaInsets();
  return (
    <View style={{ padding: 20, paddingTop: 30, paddingBottom: insets.bottom + 16, gap: 14 }}>
      <Display size={32}>How gold works</Display>
      <Row gap={12} style={{ backgroundColor: t.goldWash, borderRadius: 18, padding: 14 }}>
        <Icon name="verified" size={22} color={t.goldText} />
        <View style={{ flex: 1 }}>
          <Body weight="600">Every game is reviewed</Body>
          <Body size={12.5} color={t.ink2}>The review sets how much gold a minute gives. It is the same for everyone.</Body>
        </View>
      </Row>
      {rules.map((rule, index) => (
        <Row key={rule} gap={14}>
          <Display size={22} color={t.ink3} style={{ width: 16 }}>{index + 1}</Display>
          <Body style={{ flex: 1 }}>{rule}</Body>
        </Row>
      ))}
      <Key label="Got it" onPress={() => router.back()} style={{ marginTop: 6 }} />
    </View>
  );
}
