import { useEffect, useImperativeHandle, useMemo, useRef } from 'react';
import { View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { WebView } from 'react-native-webview';

import { haptic, useSettings } from '@/lib/settings';

import { gameHtml, type GameMessage, type GameViewProps } from './game-host';

export type { GameHandle, GameMessage } from './game-host';

export function GameView({ slug, mode, seed, best = 0, paused = false, onMessage, style, safeTop, safeBottom, ref }: GameViewProps) {
  const insets = useSafeAreaInsets();
  const { settings } = useSettings();
  const web = useRef<WebView<object>>(null);
  const pausedNow = useRef(paused);
  const html = useMemo(
    () => gameHtml(slug, { mode, seed, best, sound: settings.sound, safeTop: safeTop ?? insets.top, safeBottom: safeBottom ?? insets.bottom }),
    // The page is built once. Later changes reach the game through host messages.
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [slug, mode],
  );

  const send = (type: string, data?: object) =>
    web.current?.injectJavaScript(`window.Dailies&&window.Dailies.host(${JSON.stringify(type)},${JSON.stringify(data ?? {})});true;`);

  useImperativeHandle(ref, () => ({
    pause: () => send('pause'),
    resume: () => send('resume'),
    restart: (options) => send('restart', options),
  }));

  useEffect(() => {
    pausedNow.current = paused;
    send(paused ? 'pause' : 'resume');
  }, [paused]);

  return (
    <View style={[{ flex: 1, backgroundColor: '#0E0E0F' }, style]}>
      <WebView<object>
        ref={web}
        originWhitelist={['*']}
        source={{ html }}
        style={{ flex: 1, backgroundColor: 'transparent' }}
        scrollEnabled={false}
        bounces={false}
        overScrollMode="never"
        allowsInlineMediaPlayback
        mediaPlaybackRequiresUserAction={false}
        allowsLinkPreview={false}
        textInteractionEnabled={false}
        automaticallyAdjustContentInsets={false}
        contentInsetAdjustmentBehavior="never"
        pointerEvents={mode === 'clip' ? 'none' : 'auto'}
        onLoadEnd={() => {
          if (pausedNow.current) send('pause');
        }}
        onMessage={(event) => {
          let message: GameMessage;
          try {
            message = JSON.parse(event.nativeEvent.data);
          } catch {
            return;
          }
          if (message.type === 'haptic') haptic(message.kind);
          onMessage?.(message);
        }}
      />
    </View>
  );
}
