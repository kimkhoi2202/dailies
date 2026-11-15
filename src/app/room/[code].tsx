import { useMutation, useQuery } from 'convex/react';
import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useRef } from 'react';
import { ActivityIndicator, View } from 'react-native';

import { Screen } from '@/components/screen';
import { Avatar, Body, Card, Display, Key, Label, Row } from '@/components/ui';
import { api } from '@/convex/_generated/api';
import { score } from '@/lib/format';
import { useGame } from '@/lib/session';
import { haptic } from '@/lib/settings';
import { useTheme } from '@/lib/theme';

export default function Room() {
  const { code } = useLocalSearchParams<{ code: string }>();
  const t = useTheme();
  const room = useQuery(api.rooms.get, { code });
  const game = useGame(room?.slug ?? '');
  const start = useMutation(api.rooms.start);
  const leave = useMutation(api.rooms.leave);
  const entered = useRef(-1);

  useEffect(() => {
    if (!room) return;
    if (entered.current === -1 && room.status !== 'playing') entered.current = room.round;
    if (room.status !== 'playing' || room.round === entered.current) return;
    entered.current = room.round;
    haptic('success');
    router.push(`/play/${room.slug}?room=${room.code}&round=${room.round}`);
  }, [room]);

  useEffect(
    () => () => {
      leave().catch(() => {});
    },
    // Leaves once, when the room screen closes.
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [],
  );

  if (room === undefined) {
    return (
      <Screen title="Room">
        <ActivityIndicator color={t.ink2} style={{ marginTop: 60 }} />
      </Screen>
    );
  }
  if (room === null) {
    return (
      <Screen title="Room">
        <Card style={{ alignItems: 'center', paddingVertical: 36, gap: 6 }}>
          <Display size={24}>This room is closed</Display>
          <Body color={t.ink2}>Start a new one from any game.</Body>
        </Card>
      </Screen>
    );
  }

  const played = room.round > 0;
  return (
    <Screen
      title={game?.title ?? 'Room'}
      footer={
        room.host ? (
          <Key tone="gold" icon="play" label={played ? 'Play again' : 'Start'} detail="Same level for everyone" onPress={() => start({ code: room.code })} />
        ) : (
          <Key tone="dark" disabled label={room.status === 'playing' ? 'Round in play' : 'Waiting for the host'} onPress={() => {}} />
        )
      }>
      <Card style={{ alignItems: 'center', gap: 2, paddingVertical: 22 }}>
        <Label>Room code</Label>
        <Display size={84} style={{ lineHeight: 88, letterSpacing: 6 }}>{room.code}</Display>
        <Body size={13.5} color={t.ink2}>Friends tap Join on Home and enter this code.</Body>
      </Card>

      <Card style={{ gap: 4 }}>
        <Row style={{ justifyContent: 'space-between', paddingBottom: 6 }}>
          <Label>{room.players.length} of 6 players</Label>
          <Label>{played ? `Round ${room.round}` : 'Not started'}</Label>
        </Row>
        {room.players.map((player, index) => (
          <Row key={player.id} gap={12} style={{ paddingVertical: 7, paddingHorizontal: player.you ? 10 : 0, marginHorizontal: player.you ? -10 : 0, borderRadius: 14, backgroundColor: player.you ? t.goldWash : undefined }}>
            <Display size={24} color={t.ink3} style={{ width: 22 }}>{played ? index + 1 : ''}</Display>
            <Avatar name={player.name} color={player.color} size={30} />
            <View style={{ flex: 1 }}>
              <Body weight="600">{player.you ? 'You' : player.name}</Body>
              <Body size={12} color={t.ink2}>{player.playing ? 'Playing now' : player.done ? 'Finished' : player.host ? 'Host' : 'Ready'}</Body>
            </View>
            {played && <Display size={26}>{score(player.score, game?.unit ?? '')}</Display>}
          </Row>
        ))}
      </Card>
    </Screen>
  );
}
