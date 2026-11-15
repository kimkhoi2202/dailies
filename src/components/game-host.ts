import type { Ref } from 'react';
import type { StyleProp, ViewStyle } from 'react-native';

import { GAME_HEAD, GAME_SDK, GAME_SOURCES } from '@/games/generated';
import type { HapticKind } from '@/lib/settings';

export type GameMessage =
  | { type: 'ready' }
  | { type: 'start'; seed: number }
  | { type: 'input' }
  | { type: 'score'; score: number }
  | { type: 'haptic'; kind: HapticKind }
  | { type: 'end'; score?: number; unit?: string; headline?: string };

export type GameHandle = {
  pause: () => void;
  resume: () => void;
  restart: (options: { seed: number; best: number }) => void;
};

export type GameViewProps = {
  slug: string;
  mode: 'play' | 'clip';
  seed: number;
  best?: number;
  paused?: boolean;
  onMessage?: (message: GameMessage) => void;
  style?: StyleProp<ViewStyle>;
  safeTop?: number;
  safeBottom?: number;
  ref?: Ref<GameHandle>;
};

export function gameHtml(slug: string, config: object) {
  return `${GAME_HEAD}<script>window.DAILIES_CONFIG=${JSON.stringify(config)}</script><script>${GAME_SDK}</script><script>${GAME_SOURCES[slug] ?? ''}</script></body></html>`;
}
