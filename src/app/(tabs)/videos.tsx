import { Image } from 'expo-image';
import { LinearGradient } from 'expo-linear-gradient';
import { router, usePathname } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useState } from 'react';
import { FlatList, Pressable, Share, Text, useWindowDimensions, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { GameView } from '@/components/game-view';
import { Display, Icon, Row, Tag } from '@/components/ui';
import { VoteButton } from '@/components/vote-button';
import { catalog, type Clip, clips } from '@/lib/catalog';
import { compact, players } from '@/lib/format';
import { type Game, useGames, useVote } from '@/lib/session';
import { haptic } from '@/lib/settings';
import { OnGold, darkTheme } from '@/lib/theme';

function RailButton({ icon, label, onPress }: { icon: 'comment' | 'share'; label: string; onPress: () => void }) {
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={icon === 'comment' ? 'Comments' : 'Share'}
      hitSlop={6}
      onPress={() => {
        haptic('light');
        onPress();
      }}
      style={{ alignItems: 'center', gap: 4 }}>
      <View style={{ width: 44, height: 44, borderRadius: 22, backgroundColor: 'rgba(14,14,15,0.5)', alignItems: 'center', justifyContent: 'center' }}>
        <Icon name={icon} size={21} color="#FFFFFF" />
      </View>
      <Text style={{ fontSize: 11.5, fontWeight: '700', color: '#FFFFFF' }}>{label}</Text>
    </Pressable>
  );
}

function ClipPage({ clip, game, height, live, playing }: { clip: Clip; game: Game | undefined; height: number; live: boolean; playing: boolean }) {
  const insets = useSafeAreaInsets();
  const vote = useVote();
  const entry = catalog[clip.slug];
  const open = () => router.push(`/game/${clip.slug}`);

  return (
    <View style={{ height, backgroundColor: entry?.tint ?? '#0E0E0F' }}>
      {live ? (
        <GameView slug={clip.slug} mode="clip" seed={clip.seed} paused={!playing} />
      ) : (
        <Image source={entry?.cover} style={{ flex: 1 }} contentFit="cover" />
      )}
      <LinearGradient pointerEvents="none" colors={['rgba(0,0,0,0)', 'rgba(0,0,0,0.78)']} style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: 330 }} />

      <View style={{ position: 'absolute', right: 10, bottom: insets.bottom + 92, alignItems: 'center', gap: 16 }}>
        <Pressable
          testID={`clip-play-${clip.slug}`}
          accessibilityRole="button"
          accessibilityLabel={`Play ${game?.title ?? clip.slug}`}
          onPressIn={() => haptic('medium')}
          onPress={open}
          style={{ alignItems: 'center', gap: 4, marginBottom: 6 }}>
          {({ pressed }) => (
            <>
              <View style={{ width: 60, height: 64 }}>
                <View style={{ position: 'absolute', top: 5, width: 60, height: 60, borderRadius: 30, backgroundColor: darkTheme.goldLip }} />
                <View style={{ width: 60, height: 60, borderRadius: 30, backgroundColor: darkTheme.gold, alignItems: 'center', justifyContent: 'center', transform: [{ translateY: pressed ? 5 : 0 }] }}>
                  <Icon name="play" size={26} color={OnGold} />
                </View>
              </View>
              <Text style={{ fontSize: 12, fontWeight: '700', color: '#FFFFFF' }}>Play</Text>
            </>
          )}
        </Pressable>
        <VoteButton kind="like" active={game?.vote === 1} count={game?.likes} ink="#FFFFFF" accent={darkTheme.gold} fill="rgba(14,14,15,0.5)" onPress={() => vote({ slug: clip.slug, value: game?.vote === 1 ? 0 : 1 })} />
        <VoteButton kind="dislike" active={game?.vote === -1} count={game?.dislikes} ink="#FFFFFF" accent={darkTheme.gold} fill="rgba(14,14,15,0.5)" onPress={() => vote({ slug: clip.slug, value: game?.vote === -1 ? 0 : -1 })} />
        <RailButton icon="comment" label={compact(game?.comments ?? 0)} onPress={() => router.push(`/comments/${clip.slug}`)} />
        <RailButton icon="share" label="Share" onPress={() => Share.share({ message: `${game?.title ?? 'A game'} on Dailies. Watch a game. Play it with your friends.` })} />
      </View>

      <Pressable onPress={open} style={{ position: 'absolute', left: 16, right: 86, bottom: insets.bottom + 92, gap: 7 }}>
        {game && (
          <Row gap={6}>
            <Tag onDark icon="players" label={players(game.minPlayers, game.maxPlayers)} />
            <Tag onDark label={game.mode === 'casual' ? 'Casual' : 'Competitive'} />
          </Row>
        )}
        {game && game.left === 0 && (
          <Row gap={5}>
            <Icon name="check" size={11} color="#FFFFFF" />
            <Text style={{ fontSize: 12, fontWeight: '600', color: '#FFFFFF' }}>Limit reached. More gold tomorrow</Text>
          </Row>
        )}
        <Display size={36} color="#FFFFFF">{game?.title ?? ''}</Display>
        {game && (
          <Row gap={4}>
            <Text style={{ fontSize: 12.5, color: 'rgba(255,255,255,0.86)' }}>by {game.studio}</Text>
            <Icon name="verified" size={12} color={darkTheme.gold} />
          </Row>
        )}
        <Text numberOfLines={2} style={{ fontSize: 13.5, lineHeight: 18, color: '#FFFFFF' }}>
          <Text style={{ fontWeight: '700' }}>@{clip.author}</Text>  {clip.caption}
        </Text>
      </Pressable>
    </View>
  );
}

export default function Videos() {
  const { height } = useWindowDimensions();
  const games = useGames();
  const [current, setCurrent] = useState(0);
  const focused = usePathname() === '/videos';

  return (
    <View style={{ flex: 1, backgroundColor: '#0E0E0F' }}>
      {focused && <StatusBar style="light" />}
      <FlatList
        data={clips}
        keyExtractor={(clip) => clip.id}
        pagingEnabled
        bounces={false}
        overScrollMode="never"
        showsVerticalScrollIndicator={false}
        decelerationRate="fast"
        getItemLayout={(_, index) => ({ length: height, offset: height * index, index })}
        windowSize={3}
        initialNumToRender={2}
        maxToRenderPerBatch={2}
        onScroll={(event) => {
          const index = Math.round(event.nativeEvent.contentOffset.y / height);
          if (index !== current) {
            setCurrent(index);
            haptic('select');
          }
        }}
        scrollEventThrottle={32}
        renderItem={({ item, index }) => (
          <ClipPage
            clip={item}
            game={games?.find((game) => game.slug === item.slug)}
            height={height}
            live={Math.abs(index - current) <= 1}
            playing={focused && index === current}
          />
        )}
      />
    </View>
  );
}
