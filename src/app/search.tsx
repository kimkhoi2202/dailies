import { Image } from 'expo-image';
import { router } from 'expo-router';
import { useState } from 'react';
import { Pressable, TextInput, View } from 'react-native';

import { Screen } from '@/components/screen';
import { Body, Card, Chip, Display, Icon, Label, Row } from '@/components/ui';
import { catalog } from '@/lib/catalog';
import { likedPercent, players } from '@/lib/format';
import { useGames } from '@/lib/session';
import { useTheme } from '@/lib/theme';

export default function Search() {
  const t = useTheme();
  const games = useGames();
  const [text, setText] = useState('');
  const [category, setCategory] = useState('All');
  const categories = ['All', ...new Set((games ?? []).map((game) => game.category))];
  const words = text.trim().toLowerCase();
  const results = (games ?? []).filter(
    (game) =>
      (category === 'All' || game.category === category) &&
      (words === '' || `${game.title} ${game.studio} ${game.category} ${game.mode}`.toLowerCase().includes(words)),
  );

  return (
    <Screen title="Search">
      <Row gap={10} style={{ backgroundColor: t.surface, borderRadius: 18, paddingHorizontal: 14, height: 46 }}>
        <Icon name="search" size={16} color={t.ink2} />
        <TextInput
          testID="search-input"
          autoFocus
          value={text}
          onChangeText={setText}
          placeholder="Games and studios"
          placeholderTextColor={t.ink3}
          autoCorrect={false}
          returnKeyType="search"
          style={{ flex: 1, fontSize: 16, color: t.ink }}
        />
      </Row>
      <Row gap={8} style={{ flexWrap: 'wrap' }}>
        {categories.map((item) => (
          <Chip key={item} label={item} selected={category === item} onPress={() => setCategory(item)} />
        ))}
      </Row>
      <Card style={{ paddingVertical: 4 }}>
        {games && results.length === 0 && (
          <View style={{ paddingVertical: 22, alignItems: 'center', gap: 4 }}>
            <Display size={22}>No games found</Display>
            <Body color={t.ink2}>Try a different word.</Body>
          </View>
        )}
        {results.map((game, index) => {
          const liked = likedPercent(game.likes, game.dislikes);
          return (
            <Pressable
              key={game.slug}
              onPress={() => router.push(`/game/${game.slug}`)}
              style={{ flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 10, borderTopWidth: index === 0 ? 0 : 1, borderTopColor: t.line }}>
              <Image source={catalog[game.slug]?.icon} style={{ width: 46, height: 46, borderRadius: 12 }} />
              <View style={{ flex: 1, gap: 2 }}>
                <Body weight="600">{game.title}</Body>
                <Body size={12.5} color={t.ink2}>{players(game.minPlayers, game.maxPlayers)}, {game.mode}, {game.studio}</Body>
                <Label size={9.5}>{game.left > 0 ? `${game.left} gold left today` : 'Limit reached'}</Label>
              </View>
              {liked !== null && <Display size={22}>{liked}%</Display>}
            </Pressable>
          );
        })}
      </Card>
    </Screen>
  );
}
