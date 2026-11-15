import { router } from 'expo-router';
import type { ReactNode } from 'react';
import { ScrollView, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { Margin, useTheme } from '@/lib/theme';

import { Body, IconButton } from './ui';

export function Screen({ title, right, children, footer }: { title: string; right?: ReactNode; children: ReactNode; footer?: ReactNode }) {
  const t = useTheme();
  const insets = useSafeAreaInsets();
  return (
    <View style={{ flex: 1, backgroundColor: t.body, paddingTop: insets.top }}>
      <View style={{ height: 52, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: Margin }}>
        <IconButton name="back" label="Back" size={36} onPress={() => router.back()} />
        <Body weight="600" size={16}>{title}</Body>
        <View style={{ width: 36, alignItems: 'flex-end' }}>{right}</View>
      </View>
      <ScrollView
        bounces={false}
        overScrollMode="never"
        showsVerticalScrollIndicator={false}
        keyboardShouldPersistTaps="handled"
        contentContainerStyle={{ padding: Margin, paddingBottom: insets.bottom + (footer ? 96 : 24), gap: 12 }}>
        {children}
      </ScrollView>
      {footer && <View style={{ position: 'absolute', left: Margin, right: Margin, bottom: insets.bottom + 10 }}>{footer}</View>}
    </View>
  );
}
