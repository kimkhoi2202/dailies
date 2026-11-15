import { BlurView } from 'expo-blur';
import { Tabs } from 'expo-router';
import { Pressable, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { Icon, type IconName } from '@/components/ui';
import { haptic } from '@/lib/settings';
import { useTheme } from '@/lib/theme';

const icons: Record<string, [IconName, string]> = {
  index: ['home', 'Home'],
  videos: ['videos', 'Videos'],
  you: ['you', 'You'],
};

export default function TabsLayout() {
  const t = useTheme();
  const insets = useSafeAreaInsets();

  return (
    <Tabs
      screenOptions={{ headerShown: false, sceneStyle: { backgroundColor: t.body } }}
      tabBar={({ state, navigateToTab }) => {
        const onVideo = state.routes[state.index].name === 'videos';
        const dark = t.dark || onVideo;
        return (
          <View pointerEvents="box-none" style={{ position: 'absolute', left: 0, right: 0, bottom: Math.max(insets.bottom - 8, 12), alignItems: 'center' }}>
            <BlurView
              intensity={70}
              tint={dark ? 'systemChromeMaterialDark' : 'systemChromeMaterialLight'}
              style={{
                flexDirection: 'row',
                gap: 4,
                padding: 5,
                borderRadius: 30,
                overflow: 'hidden',
                backgroundColor: dark ? 'rgba(30,30,32,0.55)' : 'rgba(248,246,241,0.7)',
                borderWidth: 1,
                borderColor: dark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)',
              }}>
              {state.routes.map((route, index) => {
                const focused = state.index === index;
                const [icon, label] = icons[route.name] ?? ['home', route.name];
                const ink = dark ? '#F3F0E9' : '#151412';
                return (
                  <Pressable
                    key={route.key}
                    accessibilityRole="tab"
                    accessibilityLabel={label}
                    accessibilityState={{ selected: focused }}
                    onPress={() => {
                      haptic('select');
                      if (!focused) navigateToTab(route.key);
                    }}
                    style={{
                      width: 70,
                      height: 48,
                      borderRadius: 24,
                      alignItems: 'center',
                      justifyContent: 'center',
                      backgroundColor: focused ? (dark ? 'rgba(255,255,255,0.16)' : 'rgba(21,20,18,0.09)') : 'transparent',
                    }}>
                    <Icon name={icon} size={23} color={focused ? ink : dark ? 'rgba(243,240,233,0.72)' : 'rgba(21,20,18,0.6)'} />
                  </Pressable>
                );
              })}
            </BlurView>
          </View>
        );
      }}>
      <Tabs.Screen name="index" />
      <Tabs.Screen name="videos" />
      <Tabs.Screen name="you" />
    </Tabs>
  );
}
