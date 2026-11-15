import { useQuery } from 'convex/react';
import { Image } from 'expo-image';
import { router } from 'expo-router';
import { Pressable, View } from 'react-native';

import { Screen } from '@/components/screen';
import { Body, Card, Coin, Display, Icon, Label, Meter, Row } from '@/components/ui';
import { api } from '@/convex/_generated/api';
import { catalog } from '@/lib/catalog';
import { useNow } from '@/lib/day';
import { ago, duration, untilMidnight } from '@/lib/format';
import { useGames, useMe } from '@/lib/session';
import { useTheme } from '@/lib/theme';

export default function Gold() {
  const t = useTheme();
  const me = useMe();
  const games = useGames();
  const history = useQuery(api.rounds.history, me ? {} : 'skip');
  const now = useNow();
  const title = (slug: string) => games?.find((game) => game.slug === slug)?.title ?? slug;
  const earned = (me?.earnings ?? []).filter((row) => row.gold > 0).sort((a, b) => b.gold - a.gold);
  const studios = Object.entries(
    (me?.earnings ?? []).reduce<Record<string, number>>((sum, row) => ({ ...sum, [row.studio]: (sum[row.studio] ?? 0) + row.gold }), {}),
  ).filter(([, gold]) => gold > 0);

  return (
    <Screen title="Your gold">
      <Row gap={12} style={{ paddingVertical: 6 }}>
        <Coin size={48} />
        <Display size={92} style={{ lineHeight: 92 }}>{me ? me.gold.toLocaleString('en-US') : '–'}</Display>
      </Row>
      <Label>+{me?.today ?? 0} gold today</Label>

      <Row gap={12} style={{ alignItems: 'stretch' }}>
        <Card style={{ flex: 1, gap: 4 }}>
          <Label size={10}>{"Today's gold"}</Label>
          <Display size={40}>{me?.today ?? 0}</Display>
          <Body size={12} color={t.goldText}>Limits reset in {untilMidnight(new Date(now))}</Body>
        </Card>
        <Card style={{ flex: 1, gap: 4 }}>
          <Label size={10}>Streak</Label>
          <Row gap={6} style={{ alignItems: 'baseline' }}>
            <Display size={40}>{me?.streak ?? 0}</Display>
            <Body size={13} color={t.ink2}>{me?.streak === 1 ? 'day' : 'days'}</Body>
          </Row>
          <Body size={12} color={t.ink2}>{me?.playedToday ? 'Today is counted' : 'Collect 1 gold to count today'}</Body>
        </Card>
      </Row>

      <Card style={{ gap: 4 }}>
        <Label>Where it came from today</Label>
        {earned.length === 0 && <Body color={t.ink2} style={{ paddingVertical: 10 }}>Nothing yet today. You collect about 1 gold for each minute you play.</Body>}
        {earned.map((row) => (
          <Pressable key={row.gameSlug} onPress={() => router.push(`/game/${row.gameSlug}`)}>
            <Row gap={12} style={{ paddingVertical: 8 }}>
              <Image source={catalog[row.gameSlug]?.icon} style={{ width: 40, height: 40, borderRadius: 10 }} />
              <View style={{ flex: 1, gap: 5 }}>
                <Body weight="600">{title(row.gameSlug)}</Body>
                <Row gap={8}>
                  <View style={{ width: 70 }}>
                    <Meter value={row.gold} max={100} height={4} />
                  </View>
                  <Label size={9.5}>{row.gold >= 100 ? 'Limit reached' : `${row.gold} of 100`}</Label>
                </Row>
              </View>
              <Display size={28}>+{row.gold}</Display>
            </Row>
          </Pressable>
        ))}
      </Card>

      {studios.length > 0 && (
        <Card style={{ gap: 10 }}>
          <Label>{"Today's limits by studio"}</Label>
          {studios.map(([studio, gold]) => (
            <View key={studio} style={{ gap: 5 }}>
              <Row style={{ justifyContent: 'space-between' }}>
                <Body weight="600" size={14}>{studio}</Body>
                <Label size={9.5}>{gold} of 300</Label>
              </Row>
              <Meter value={gold} max={300} height={4} />
            </View>
          ))}
        </Card>
      )}

      {history && history.length > 0 && (
        <Card style={{ gap: 2 }}>
          <Label>Recent rounds</Label>
          {history.slice(0, 12).map((round) => (
            <Row key={round._id} gap={12} style={{ paddingVertical: 7 }}>
              <Image source={catalog[round.gameSlug]?.icon} style={{ width: 34, height: 34, borderRadius: 9 }} />
              <View style={{ flex: 1 }}>
                <Body weight="600" size={14}>{title(round.gameSlug)}</Body>
                <Body size={12} color={t.ink2}>{duration(round.playMs)} played, {ago(round.endedAt, now)} ago</Body>
              </View>
              <Display size={22} color={round.gold > 0 ? t.ink : t.ink3}>+{round.gold}</Display>
            </Row>
          ))}
        </Card>
      )}

      <Pressable onPress={() => router.push('/how-gold-works')}>
        <Card>
          <Row style={{ justifyContent: 'space-between' }}>
            <Body weight="600">How gold works</Body>
            <Icon name="forward" size={12} color={t.ink2} />
          </Row>
        </Card>
      </Pressable>
    </Screen>
  );
}
