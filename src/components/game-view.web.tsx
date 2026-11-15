import { createElement, useEffect, useImperativeHandle, useMemo, useRef } from 'react';
import { View } from 'react-native';

import { gameHtml, type GameMessage, type GameViewProps } from './game-view';

export { gameHtml } from './game-view';
export type { GameHandle, GameMessage, GameViewProps } from './game-view';

type GameWindow = Window & { Dailies?: { host: (type: string, data?: object) => void } };

export function GameView({ slug, mode, seed, best = 0, paused = false, onMessage, style, safeTop = 47, safeBottom = 34, ref }: GameViewProps) {
  const frame = useRef<HTMLIFrameElement>(null);
  const handler = useRef(onMessage);
  useEffect(() => {
    handler.current = onMessage;
  });
  const html = useMemo(
    () => gameHtml(slug, { mode, seed, best, safeTop, safeBottom }),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [slug, mode],
  );

  const send = (type: string, data?: object) => (frame.current?.contentWindow as GameWindow | null)?.Dailies?.host(type, data);

  useImperativeHandle(ref, () => ({
    pause: () => send('pause'),
    resume: () => send('resume'),
    restart: (options) => send('restart', options),
  }));

  useEffect(() => {
    send(paused ? 'pause' : 'resume');
  }, [paused]);

  useEffect(() => {
    const listener = (event: MessageEvent) => {
      if (event.source !== frame.current?.contentWindow || typeof event.data !== 'string') return;
      try {
        handler.current?.(JSON.parse(event.data) as GameMessage);
      } catch {}
    };
    window.addEventListener('message', listener);
    return () => window.removeEventListener('message', listener);
  }, []);

  return (
    <View style={[{ flex: 1, backgroundColor: '#0E0E0F' }, style]}>
      {createElement('iframe', {
        ref: frame,
        srcDoc: html,
        onLoad: () => paused && send('pause'),
        style: { border: 0, width: '100%', height: '100%', pointerEvents: mode === 'clip' ? 'none' : 'auto' },
      })}
    </View>
  );
}
