import { Image } from 'expo-image';
import { LinearGradient } from 'expo-linear-gradient';
import { router } from 'expo-router';
import { useState } from 'react';
import { Pressable, ScrollView, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { Wordmark } from '@/components/brand';
import { Body, Card, Chip, Display, GoldPill, Icon, IconButton, Label, Meter, Row, Tag } from '@/components/ui';
import { catalog } from '@/lib/catalog';
import { likedPercent, players, score, unitWord } from '@/lib/format';
import { useGames, useMe } from '@/lib/session';
import { haptic } from '@/lib/settings';
import { Margin, OnGold, useTheme } from '@/lib/theme';

const filters = [
  { id: 'all', label: 'All' },
  { id: '2', label: '2 players' },
  { id: '4', label: '4 players' },
  { id: '6', label: '6 players' },
  { id: 'casual', label: 'Casual' },
  { id: 'competitive', label: 'Competitive' },
];

export default function Home() {
  const t = useTheme();
  const insets = useSafeAreaInsets();
  const me = useMe();
  const games = useGames();
  const [filter, setFilter] = useState('all');

  const shown = (games ?? []).filter((game) => {
    if (filter === 'all') return true;
    if (filter === 'casual' || filter === 'competitive') return game.mode === filter;
    return game.minPlayers <= Number(filter) && Number(filter) <= game.maxPlayers;
  });
  const hero = shown[0];
  const played = shown.filter((game) => game.best !== null);
  const popular = [...shown].sort((a, b) => (likedPercent(b.likes, b.dislikes) ?? 0) - (likedPercent(a.likes, a.dislikes) ?? 0));
  const open = (slug: string) => router.push(`/game/${slug}`);

  return (
    <ScrollView
      bounces={false}
      overScrollMode="never"
      showsVerticalScrollIndicator={false}
      contentContainerStyle={{ paddingTop: insets.top + 8, paddingBottom: insets.bottom + 96, gap: 18 }}>
      <Row style={{ paddingHorizontal: Margin, justifyContent: 'space-between' }}>
        <Wordmark />
        <Row gap={8}>
          <GoldPill amount={me?.gold} onPress={() => router.push('/gold')} />
          <IconButton name="players" label="Join a room" onPress={() => router.push('/join')} size={36} />
          <IconButton name="search" label="Search" onPress={() => router.push('/search')} size={36} />
        </Row>
      </Row>

      <ScrollView horizontal bounces={false} showsHorizontalScrollIndicator={false} contentContainerStyle={{ paddingHorizontal: Margin, gap: 8 }}>
        {filters.map((item) => (
          <Chip key={item.id} label={item.label} selected={filter === item.id} onPress={() => setFilter(item.id)} />
        ))}
      </ScrollView>

      {games === undefined ? (
        <View style={{ marginHorizontal: Margin, height: 236, borderRadius: 26, backgroundColor: t.surface }} />
      ) : hero === undefined ? (
        <Card style={{ marginHorizontal: Margin, alignItems: 'center', paddingVertical: 36, gap: 6 }}>
          <Display size={24}>Nothing here yet</Display>
          <Body color={t.ink2}>No game matches that filter.</Body>
        </Card>
      ) : (
        <Pressable
          accessibilityRole="button"
          accessibilityLabel={`Open ${hero.title}`}
          onPress={() => {
            haptic('light');
            open(hero.slug);
          }}
          style={{ marginHorizontal: Margin, height: 236, borderRadius: 26, borderCurve: 'continuous', overflow: 'hidden', backgroundColor: catalog[hero.slug]?.tint }}>
          <Image source={catalog[hero.slug]?.cover} style={{ position: 'absolute', width: '100%', height: '100%' }} contentFit="cover" contentPosition="top" />
          <LinearGradient colors={['rgba(0,0,0,0)', 'rgba(0,0,0,0.78)', 'rgba(0,0,0,0.9)']} style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: 190 }} />
          <View style={{ position: 'absolute', left: 14, top: 14 }}>
            <Tag onDark label={hero.left > 0 ? `${hero.left} gold left today` : 'Limit reached today'} />
          </View>
          <View style={{ position: 'absolute', left: 16, right: 16, bottom: 14, flexDirection: 'row', alignItems: 'flex-end', justifyContent: 'space-between' }}>
            <View style={{ gap: 8, flex: 1 }}>
              <Display size={38} color="#FFFFFF">{hero.title}</Display>
              <Row gap={6}>
                <Tag onDark icon="players" label={players(hero.minPlayers, hero.maxPlayers)} />
                <Tag onDark label={hero.mode === 'casual' ? 'Casual' : 'Competitive'} />
              </Row>
            </View>
            <View style={{ width: 54, height: 54, borderRadius: 27, backgroundColor: t.gold, alignItems: 'center', justifyContent: 'center', borderBottomWidth: 4, borderBottomColor: t.goldLip }}>
              <Icon name="play" size={22} color={OnGold} />
            </View>
          </View>
        </Pressable>
      )}

      {played.length > 0 && (
        <View style={{ gap: 10 }}>
          <Display size={22} style={{ paddingHorizontal: Margin }}>Continue playing</Display>
          <ScrollView horizontal bounces={false} showsHorizontalScrollIndicator={false} contentContainerStyle={{ paddingHorizontal: Margin, gap: 10 }}>
            {played.map((game) => (
              <Pressable key={game.slug} onPress={() => open(game.slug)} style={{ width: 132, borderRadius: 20, borderCurve: 'continuous', overflow: 'hidden', backgroundColor: t.surface }}>
                <Image source={catalog[game.slug]?.cover} style={{ width: 132, height: 132, backgroundColor: catalog[game.slug]?.tint }} contentFit="cover" contentPosition="top" />
                <View style={{ padding: 10, gap: 2 }}>
                  <Display size={18}>{game.title}</Display>
                  <Body size={11.5} color={t.ink2} lines={1}>
                    Your best: {score(game.best ?? 0, game.unit)} {unitWord(game.best ?? 0, game.unit)}
                  </Body>
                </View>
              </Pressable>
            ))}
          </ScrollView>
        </View>
      )}

      {popular.length > 0 && (
        <View style={{ gap: 10, paddingHorizontal: Margin }}>
          <Display size={22}>Most liked</Display>
          <Card style={{ paddingVertical: 4 }}>
            {popular.map((game, index) => {
              const liked = likedPercent(game.likes, game.dislikes);
              return (
                <Pressable
                  key={game.slug}
                  onPress={() => open(game.slug)}
                  style={{ flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 11, borderTopWidth: index === 0 ? 0 : 1, borderTopColor: t.line }}>
                  <Image source={catalog[game.slug]?.icon} style={{ width: 46, height: 46, borderRadius: 12, backgroundColor: catalog[game.slug]?.tint }} contentFit="cover" />
                  <View style={{ flex: 1, gap: 4 }}>
                    <Body weight="600">{game.title}</Body>
                    <Row gap={8}>
                      <View style={{ width: 54 }}>
                        <Meter value={game.today} max={100} height={4} />
                      </View>
                      <Label size={9.5}>{game.left > 0 ? `${game.left} gold left` : 'Limit reached'}</Label>
                    </Row>
                  </View>
                  {liked !== null && (
                    <Row gap={5}>
                      <Icon name="likeFill" size={13} color={t.ink2} />
                      <Display size={22}>{liked}%</Display>
                    </Row>
                  )}
                </Pressable>
              );
            })}
          </Card>
        </View>
      )}
    </ScrollView>
  );
}
