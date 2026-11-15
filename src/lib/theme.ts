import { Platform, useColorScheme } from 'react-native';

const light = {
  body: '#ECE8E1',
  surface: '#F8F6F1',
  raised: '#FFFFFF',
  sunken: '#DDD7CC',
  line: '#D8D2C7',
  ink: '#151412',
  ink2: '#57534C',
  ink3: '#6B665D',
  onInk: '#F8F6F1',
  gold: '#F5B301',
  goldLip: '#C48A00',
  goldText: '#855600',
  goldWash: '#F7E7B8',
  keyFace: '#FFFFFF',
  keyLip: '#C9C1B2',
  danger: '#C2331F',
  success: '#1F7A4D',
};

const dark: typeof light = {
  body: '#0E0E0F',
  surface: '#1A1A1C',
  raised: '#252528',
  sunken: '#2B2B2E',
  line: '#2C2C2F',
  ink: '#F3F0E9',
  ink2: '#A9A59D',
  ink3: '#86837B',
  onInk: '#151412',
  gold: '#FFC531',
  goldLip: '#A87A08',
  goldText: '#FFC531',
  goldWash: '#33290F',
  keyFace: '#F3F0E9',
  keyLip: '#8F8A7F',
  danger: '#FF6B57',
  success: '#4CC38A',
};

export const Coin = { face: '#FFCB2E', edge: '#D99400', shine: '#FFE9A6' };
export const OnGold = '#151412';

export const Font = {
  display: 'BigShoulders_900Black',
  displayBold: 'BigShoulders_800ExtraBold',
  mono: Platform.select({ ios: 'Menlo', default: 'monospace' }),
};

export const Radius = { card: 26, tile: 14, key: 22 };
export const Margin = 16;

export type Theme = typeof light & { dark: boolean };

export function useTheme(): Theme {
  const scheme = useColorScheme();
  return scheme === 'light' ? { ...light, dark: false } : { ...dark, dark: true };
}

export const darkTheme: Theme = { ...dark, dark: true };
