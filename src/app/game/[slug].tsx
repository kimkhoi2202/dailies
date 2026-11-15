import { useMutation, useQuery } from 'convex/react';
import { router, useLocalSearchParams, usePathname } from 'expo-router';
import { Pressable, ScrollView, useWindowDimensions, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { GameView } from '@/components/game-view';
import { Avatar, Body, Card, Coin, Display, GoldPill, Icon, IconButton, Key, Label, Meter, Row, Tag } from '@/components/ui';
import { VoteButton } from '@/components/vote-button';
import { api } from '@/convex/_generated/api';
import { catalog } from '@/lib/catalog';
import { compact, likedPercent, players, score, untilMidnight } from '@/lib/format';
import { useGame, useMe, useVote } from '@/lib/session';
import { Margin, useTheme } from '@/lib/theme';

export default function GameScreen() {
  const { slug } = useLocalSearchParams<{ slug: string }>();
  const t = useTheme();
  const insets = useSafeAreaInsets();
  const { height } = useWindowDimensions();
  const me = useMe();
  const game = useGame(slug);
  const board = useQuery(api.social.leaderboard, { slug });
  const vote = useVote();
  const createRoom = useMutation(api.rooms.create);
  const onTop = usePathname() === `/game/${slug}`;
  const heroHeight = Math.round(height * 0.44);
  const liked = game ? likedPercent(game.likes, game.dislikes) : null;
  const rate = game ? (Number.isInteger(game.goldPerMinute) ? String(game.goldPerMinute) : game.goldPerMinute.toFixed(1)) : '1';

  return (
    <View style={{ flex: 1, backgroundColor: t.body }}>
      <ScrollView bounces={false} overScrollMode="never" showsVerticalScrollIndicator={false} contentContainerStyle={{ paddingBottom: insets.bottom + 96 }}>
        <View style={{ height: heroHeight, borderBottomLeftRadius: 30, borderBottomRightRadius: 30, borderCurve: 'continuous', overflow: 'hidden', backgroundColor: catalog[slug]?.tint }}>
          <GameView slug={slug} mode="clip" seed={3} paused={!onTop} safeTop={insets.top} safeBottom={0} />
        </View>

        <View style={{ padding: Margin, gap: 12 }}>
          <Row style={{ justifyContent: 'space-between', alignItems: 'flex-start' }}>
            <View style={{ flex: 1, gap: 3 }}>
              <Display size={38}>{game?.title ?? ' '}</Display>
              <Row gap={4}>
                <Body size={13} color={t.ink2}>by {game?.studio ?? ''}</Body>
                <Icon name="verified" size={12} color={t.goldText} />
              </Row>
            </View>
            <Row gap={14} style={{ backgroundColor: t.surface, borderRadius: 22, paddingHorizontal: 14, height: 44 }}>
              <Row gap={5}>
                <VoteButton kind="like" size={30} active={game?.vote === 1} ink={t.ink} accent={t.goldText} onPress={() => vote({ slug, value: game?.vote === 1 ? 0 : 1 })} />
                <Body size={13} weight="700">{compact(game?.likes ?? 0)}</Body>
              </Row>
              <Row gap={5}>
                <VoteButton kind="dislike" size={30} active={game?.vote === -1} ink={t.ink} accent={t.goldText} onPress={() => vote({ slug, value: game?.vote === -1 ? 0 : -1 })} />
                <Body size={13} weight="700">{compact(game?.dislikes ?? 0)}</Body>
              </Row>
            </Row>
          </Row>

          {game && (
            <Row gap={6}>
              <Tag icon="players" label={players(game.minPlayers, game.maxPlayers)} />
              <Tag label={game.mode === 'casual' ? 'Casual' : 'Competitive'} />
              <Tag label={game.category} />
            </Row>
          )}

          <Body color={t.ink2} size={14.5} style={{ lineHeight: 20 }}>{game?.how ?? ''}</Body>

          <Pressable onPress={() => router.push('/how-gold-works')}>
            <Card style={{ gap: 10 }}>
              <Row style={{ justifyContent: 'space-between' }}>
                <Label>Gold</Label>
                <Row gap={2}>
                  <Body size={12.5} weight="600">How gold works</Body>
                  <Icon name="forward" size={11} color={t.ink2} />
                </Row>
              </Row>
              <Row gap={10}>
                <Coin size={30} />
                <Display size={40}>{rate}</Display>
                <View style={{ flex: 1 }}>
                  <Body weight="600">gold a minute</Body>
                  <Body size={12} color={t.ink2}>Set by review</Body>
                </View>
                <View style={{ alignItems: 'flex-end' }}>
                  <Body weight="600">{game?.today ?? 0} of 100 today</Body>
                  <Body size={12} color={t.goldText}>
                    {game && game.left === 0 ? `More gold in ${untilMidnight(new Date())}` : `${game?.left ?? 100} still to collect`}
                  </Body>
                </View>
              </Row>
              <Meter value={game?.today ?? 0} max={100} />
            </Card>
          </Pressable>

          {game && game.maxPlayers > 1 && (
            <Card style={{ gap: 10 }}>
              <Row style={{ justifyContent: 'space-between' }}>
                <Label>Play together</Label>
                <Body size={12.5} color={t.ink2}>Up to {game.maxPlayers} on the same level</Body>
              </Row>
              <Row gap={10}>
                <Key small tone="dark" icon="players" label="Start a room" style={{ flex: 1 }} onPress={() => createRoom({ slug }).then((code) => router.push(`/room/${code}`), () => {})} />
                <Key small tone="dark" label="Join with a code" style={{ flex: 1 }} onPress={() => router.push('/join')} />
              </Row>
            </Card>
          )}

          <Row gap={10}>
            {[
              ['Plays', compact(game?.plays ?? 0), 'all time'],
              ['Liked', liked === null ? '–' : `${liked}%`, 'of votes'],
              ['Your best', game?.best == null ? '–' : score(game.best, game.unit), game?.unit === '%' ? 'of the map' : (game?.unit ?? '')],
            ].map(([label, value, note]) => (
              <Card key={label} style={{ flex: 1, padding: 12, gap: 2 }}>
                <Label size={10}>{label}</Label>
                <Display size={28}>{value}</Display>
                <Body size={11.5} color={t.ink2}>{note}</Body>
              </Card>
            ))}
          </Row>

          <Card style={{ gap: 4 }}>
            <Pressable onPress={() => router.push(`/leaderboard/${slug}`)}>
              <Row style={{ justifyContent: 'space-between', paddingBottom: 6 }}>
                <Label>Best scores{game ? `, ${game.unit === '%' ? 'percent' : game.unit}` : ''}</Label>
                <Row gap={2}>
                  <Body size={12.5} weight="600">Leaderboard</Body>
                  <Icon name="forward" size={11} color={t.ink2} />
                </Row>
              </Row>
            </Pressable>
            {(board ?? []).slice(0, 3).map((row) => (
              <Row key={row.rank} gap={12} style={{ paddingVertical: 7, paddingHorizontal: row.you ? 10 : 0, marginHorizontal: row.you ? -10 : 0, borderRadius: 14, backgroundColor: row.you ? t.goldWash : undefined }}>
                <Display size={24} color={t.ink3} style={{ width: 22 }}>{row.rank}</Display>
                <Avatar name={row.handle} color={row.color} size={30} />
                <Body weight="600" style={{ flex: 1 }}>{row.you ? 'You' : row.handle}</Body>
                <Display size={26}>{score(row.score, game?.unit ?? '')}</Display>
              </Row>
            ))}
          </Card>

          <Pressable onPress={() => router.push(`/comments/${slug}`)}>
            <Card>
              <Row style={{ justifyContent: 'space-between' }}>
                <Row gap={10}>
                  <Icon name="comment" size={18} color={t.ink} />
                  <Body weight="600">{game?.comments ?? 0} comments</Body>
                </Row>
                <Icon name="forward" size={12} color={t.ink2} />
              </Row>
            </Card>
          </Pressable>
        </View>
      </ScrollView>

      <View style={{ position: 'absolute', top: insets.top + 6, left: Margin, right: Margin, flexDirection: 'row', justifyContent: 'space-between' }}>
        <IconButton name="down" label="Close" onPress={() => router.back()} fill="rgba(14,14,15,0.72)" color="#F3F0E9" />
        <GoldPill amount={me?.gold} onDark onPress={() => router.push('/gold')} />
      </View>

      <View style={{ position: 'absolute', left: Margin, right: Margin, bottom: insets.bottom + 10 }}>
        <Key
          testID="play-key"
          tone="gold"
          icon="play"
          label="Play"
          detail={game ? (game.left > 0 ? `${game.left} gold left today` : 'Keep playing for fun') : undefined}
          onPress={() => router.push(`/play/${slug}`)}
        />
      </View>
    </View>
  );
}
