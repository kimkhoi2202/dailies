import { useQuery } from 'convex/react';
import { router, useLocalSearchParams } from 'expo-router';

import { Screen } from '@/components/screen';
import { Avatar, Body, Card, Display, Key, Label, Row } from '@/components/ui';
import { api } from '@/convex/_generated/api';
import { score } from '@/lib/format';
import { useGame } from '@/lib/session';
import { useTheme } from '@/lib/theme';

export default function Leaderboard() {
  const { slug } = useLocalSearchParams<{ slug: string }>();
  const t = useTheme();
  const game = useGame(slug);
  const board = useQuery(api.social.leaderboard, { slug });
  const unit = game?.unit ?? '';
  const mine = board?.find((row) => row.you);
  const ahead = mine && mine.rank > 1 ? board?.[mine.rank - 2] : undefined;

  return (
    <Screen
      title={game?.title ?? ''}
      footer={
        <Key
          tone="gold"
          icon="play"
          label="Play"
          detail={ahead ? `Pass ${ahead.handle} at ${score(ahead.score, unit)}` : mine ? 'You lead' : 'Set a score'}
          onPress={() => router.push(`/play/${slug}`)}
        />
      }>
      <Display size={44}>Leaderboard</Display>
      <Label>Best scores{unit ? `, ${unit === '%' ? 'percent' : unit}` : ''}</Label>
      <Card style={{ gap: 2, paddingVertical: 8 }}>
        {board?.length === 0 && <Body color={t.ink2} style={{ paddingVertical: 12 }}>No scores yet. Be the first.</Body>}
        {(board ?? []).map((row, index) => (
          <Row
            key={row.rank}
            gap={12}
            style={{ paddingVertical: index < 3 ? 10 : 7, paddingHorizontal: 10, marginHorizontal: -6, borderRadius: 16, backgroundColor: row.you ? t.goldWash : undefined }}>
            <Display size={index < 3 ? 34 : 22} color={index < 3 ? t.ink : t.ink3} style={{ width: 30 }}>{row.rank}</Display>
            <Avatar name={row.handle} color={row.color} size={index < 3 ? 40 : 30} />
            <Row gap={6} style={{ flex: 1 }}>
              <Body weight="600" size={index < 3 ? 16 : 15}>{row.handle}</Body>
              {row.you && (
                <Label size={9.5} color={t.onInk} style={{ backgroundColor: t.ink, borderRadius: 8, paddingHorizontal: 6, paddingVertical: 2, overflow: 'hidden' }}>
                  You
                </Label>
              )}
            </Row>
            <Display size={index < 3 ? 38 : 24}>{score(row.score, unit)}</Display>
          </Row>
        ))}
      </Card>
    </Screen>
  );
}
