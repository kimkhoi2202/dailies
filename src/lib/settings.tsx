import AsyncStorage from '@react-native-async-storage/async-storage';
import * as Haptics from 'expo-haptics';
import { createContext, type ReactNode, use, useEffect, useState } from 'react';
import { Appearance, Platform } from 'react-native';

export type Settings = { appearance: 'system' | 'light' | 'dark'; haptics: boolean; sound: boolean };

const defaults: Settings = { appearance: 'system', haptics: true, sound: false };
const KEY = 'dailies.settings';
let current = defaults;

const SettingsContext = createContext<{ settings: Settings; change: (patch: Partial<Settings>) => void }>({
  settings: defaults,
  change: () => {},
});

export function SettingsProvider({ children }: { children: ReactNode }) {
  const [settings, setSettings] = useState(defaults);

  useEffect(() => {
    AsyncStorage.getItem(KEY).then((stored) => {
      if (!stored) return;
      current = { ...defaults, ...JSON.parse(stored) };
      setSettings(current);
    });
  }, []);

  useEffect(() => {
    if (Platform.OS !== 'web') Appearance.setColorScheme(settings.appearance === 'system' ? 'unspecified' : settings.appearance);
  }, [settings.appearance]);

  const change = (patch: Partial<Settings>) => {
    current = { ...current, ...patch };
    setSettings(current);
    AsyncStorage.setItem(KEY, JSON.stringify(current));
  };

  return <SettingsContext value={{ settings, change }}>{children}</SettingsContext>;
}

export function useSettings() {
  return use(SettingsContext);
}

export type HapticKind = 'light' | 'medium' | 'heavy' | 'success' | 'warning' | 'error' | 'select';

export function haptic(kind: HapticKind = 'light') {
  if (!current.haptics || Platform.OS === 'web') return;
  if (kind === 'select') Haptics.selectionAsync();
  else if (kind === 'success') Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
  else if (kind === 'warning') Haptics.notificationAsync(Haptics.NotificationFeedbackType.Warning);
  else if (kind === 'error') Haptics.notificationAsync(Haptics.NotificationFeedbackType.Error);
  else if (kind === 'heavy') Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Heavy);
  else if (kind === 'medium') Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
  else Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
}
