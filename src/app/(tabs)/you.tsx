import { Image } from 'expo-image';
import { router } from 'expo-router';
import { Pressable, ScrollView, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { Avatar, Body, Card, Coin, Display, Icon, IconButton, Label, Row } from '@/components/ui';
import { catalog } from '@/lib/catalog';
import { score } from '@/lib/format';
import { useGames, useMe } from '@/lib/session';
import { Margin, useTheme } from '@/lib/theme';

export default function You() {
  const t = useTheme();
  const insets = useSafeAreaInsets();
  const me = useMe();
  const games = useGames();
  const played = (games ?? []).filter((game) => game.best !== null);

  return (
    <ScrollView bounces={false} overScrollMode="never" showsVerticalScrollIndicator={false} contentContainerStyle={{ paddingTop: insets.top + 10, paddingHorizontal: Margin, paddingBottom: insets.bottom + 96, gap: 14 }}>
      <Row gap={12}>
        <Avatar name={me?.name ?? '?'} color={me?.color ?? t.sunken} size={56} />
        <View style={{ flex: 1 }}>
          <Display size={30}>{me?.name ?? ' '}</Display>
          <Body size={13} color={t.ink2}>{me ? `@${me.handle}` : 'Signing in'}</Body>
        </View>
        <IconButton name="settings" label="Settings" onPress={() => router.push('/settings')} />
      </Row>

      <Row gap={10} style={{ alignItems: 'stretch' }}>
        <Pressable style={{ flex: 1 }} onPress={() => router.push('/gold')}>
          <Card style={{ padding: 12, gap: 2 }}>
            <Row style={{ justifyContent: 'space-between' }}>
              <Label size={10}>Gold</Label>
              <Coin size={14} />
            </Row>
            <Display size={32}>{me?.gold ?? 0}</Display>
            <Body size={11.5} color={t.ink2}>+{me?.today ?? 0} today</Body>
          </Card>
        </Pressable>
        <Card style={{ flex: 1, padding: 12, gap: 2 }}>
          <Label size={10}>Streak</Label>
          <Display size={32}>{me?.streak ?? 0}</Display>
          <Body size={11.5} color={t.ink2}>days running</Body>
        </Card>
        <Card style={{ flex: 1, padding: 12, gap: 2 }}>
          <Label size={10}>Played</Label>
          <Display size={32}>{me?.rounds ?? 0}</Display>
          <Body size={11.5} color={t.ink2}>rounds</Body>
        </Card>
      </Row>

      <Display size={22} style={{ marginTop: 4 }}>Your best scores</Display>
      {played.length === 0 ? (
        <Card style={{ alignItems: 'center', paddingVertical: 30, gap: 6 }}>
          <Icon name="trophy" size={26} color={t.ink3} />
          <Body weight="600">No scores yet</Body>
          <Body size={13} color={t.ink2}>Play a round and your best shows up here.</Body>
        </Card>
      ) : (
        <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 10 }}>
          {played.map((game) => (
            <Pressable key={game.slug} onPress={() => router.push(`/leaderboard/${game.slug}`)} style={{ width: '31%', flexGrow: 1, maxWidth: '32%', aspectRatio: 0.72, borderRadius: 18, borderCurve: 'continuous', overflow: 'hidden', backgroundColor: catalog[game.slug]?.tint }}>
              <Image source={catalog[game.slug]?.cover} style={{ position: 'absolute', width: '100%', height: '100%' }} contentFit="cover" />
              <View style={{ position: 'absolute', left: 0, right: 0, bottom: 0, padding: 8, backgroundColor: 'rgba(0,0,0,0.5)' }}>
                <Display size={24} color="#FFFFFF">{score(game.best ?? 0, game.unit)}</Display>
                <Body size={11} color="rgba(255,255,255,0.85)" lines={1}>{game.title}</Body>
              </View>
            </Pressable>
          ))}
        </View>
      )}

      <Pressable onPress={() => router.push('/how-gold-works')}>
        <Card>
          <Row style={{ justifyContent: 'space-between' }}>
            <Body weight="600">How gold works</Body>
            <Icon name="forward" size={12} color={t.ink2} />
          </Row>
        </Card>
      </Pressable>
    </ScrollView>
  );
}
