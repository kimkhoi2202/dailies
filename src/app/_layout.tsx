import { ConvexAuthProvider } from '@convex-dev/auth/react';
import { BigShoulders_800ExtraBold, BigShoulders_900Black, useFonts } from '@expo-google-fonts/big-shoulders';
import { ConvexReactClient } from 'convex/react';
import { DarkTheme, DefaultTheme, Stack, ThemeProvider } from 'expo-router';
import * as SplashScreen from 'expo-splash-screen';
import { StatusBar } from 'expo-status-bar';
import { type ReactNode, useEffect } from 'react';
import { GestureHandlerRootView } from 'react-native-gesture-handler';

import { api } from '@/convex/_generated/api';
import { tokenStorage, useDeviceSession } from '@/lib/session';
import { SettingsProvider } from '@/lib/settings';
import { useTheme } from '@/lib/theme';

SplashScreen.preventAutoHideAsync();

const convex = new ConvexReactClient(process.env.EXPO_PUBLIC_CONVEX_URL!, { unsavedChangesWarning: false });
const authApi = {
  refreshSession: api.auth.refreshSession,
  signOut: api.auth.signOut,
  isAuthenticated: api.auth.isAuthenticated,
};

function Session({ children }: { children: ReactNode }) {
  useDeviceSession();
  return children;
}

export default function RootLayout() {
  const t = useTheme();
  const [fontsLoaded] = useFonts({ BigShoulders_900Black, BigShoulders_800ExtraBold });

  useEffect(() => {
    if (fontsLoaded) SplashScreen.hideAsync();
  }, [fontsLoaded]);

  if (!fontsLoaded) return null;

  const sheet = { presentation: 'formSheet', sheetGrabberVisible: true, sheetCornerRadius: 30, contentStyle: { backgroundColor: t.surface } } as const;

  return (
    <GestureHandlerRootView style={{ flex: 1, backgroundColor: t.body }}>
      <ConvexAuthProvider client={convex} api={authApi} storage={tokenStorage}>
        <SettingsProvider>
          <ThemeProvider value={t.dark ? DarkTheme : DefaultTheme}>
            <Session>
              <StatusBar style={t.dark ? 'light' : 'dark'} />
              <Stack screenOptions={{ headerShown: false, contentStyle: { backgroundColor: t.body } }}>
                <Stack.Screen name="(tabs)" />
                <Stack.Screen name="game/[slug]" options={{ animation: 'slide_from_bottom' }} />
                <Stack.Screen name="play/[slug]" options={{ presentation: 'fullScreenModal', animation: 'fade', gestureEnabled: false }} />
                <Stack.Screen name="comments/[slug]" options={{ ...sheet, sheetAllowedDetents: [0.62, 1] }} />
                <Stack.Screen name="how-gold-works" options={{ ...sheet, sheetAllowedDetents: [0.66] }} />
              </Stack>
            </Session>
          </ThemeProvider>
        </SettingsProvider>
      </ConvexAuthProvider>
    </GestureHandlerRootView>
  );
}
