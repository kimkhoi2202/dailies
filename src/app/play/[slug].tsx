import { useConvexAuth, useMutation, useQuery } from 'convex/react';
import { router, useLocalSearchParams } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useEffect, useRef, useState } from 'react';
import { ActivityIndicator, AppState, Pressable, View } from 'react-native';
import Animated, { FadeIn, SlideInDown } from 'react-native-reanimated';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { type GameHandle, type GameMessage, GameView } from '@/components/game-view';
import { Avatar, Body, Coin, Display, GoldPill, Icon, IconButton, Key, Label, Meter, Row } from '@/components/ui';
import { VoteButton } from '@/components/vote-button';
import { api } from '@/convex/_generated/api';
import type { Id } from '@/convex/_generated/dataModel';
import { catalog } from '@/lib/catalog';
import { localDay } from '@/lib/day';
import { duration, score as formatScore, unitWord, untilMidnight } from '@/lib/format';
import { useGame, useVote } from '@/lib/session';
import { haptic } from '@/lib/settings';
import { Margin, useTheme } from '@/lib/theme';

type Round = { roundId: Id<'rounds'>; seed: number; best: number; goldPerMinute: number; left: number };
type Outcome = { score: number; unit: string; headline?: string; playMs: number; gold?: number; today?: number; left?: number; newBest?: boolean; balance?: number };

const IDLE_MS = 10_000;

export default function Play() {
  const { slug, room: roomCode, round: roomRound } = useLocalSearchParams<{ slug: string; room?: string; round?: string }>();
  const t = useTheme();
  const insets = useSafeAreaInsets();
  const game = useGame(slug);
  const { isAuthenticated } = useConvexAuth();
  const startRound = useMutation(api.rounds.start);
  const finishRound = useMutation(api.rounds.finish);
  const vote = useVote();
  const room = useQuery(api.rooms.get, roomCode ? { code: roomCode } : 'skip');
  const postScore = useMutation(api.rooms.score);
  const lastPost = useRef(0);
  const report = (value: number, done: boolean) => {
    if (!roomCode) return;
    const now = Date.now();
    if (!done && now - lastPost.current < 800) return;
    lastPost.current = now;
    postScore({ code: roomCode, round: Number(roomRound), score: value, done }).catch(() => {});
  };
  const view = useRef<GameHandle>(null);

  const [first, setFirst] = useState<Round | null>(null);
  const [phase, setPhase] = useState<'loading' | 'ready' | 'playing' | 'paused' | 'over'>('loading');
  const [gold, setGold] = useState(0);
  const [outcome, setOutcome] = useState<Outcome | null>(null);
  const [failed, setFailed] = useState(false);
  const round = useRef<Round | null>(null);
  const clock = useRef({ activeMs: 0, lastTick: 0, lastInput: 0, score: 0, wallStart: 0 });

  const begin = async () => {
    setFailed(false);
    try {
      const next = await startRound({ slug, day: localDay(), room: roomCode });
      round.current = next;
      clock.current = { activeMs: 0, lastTick: 0, lastInput: 0, score: 0, wallStart: 0 };
      setGold(0);
      setOutcome(null);
      if (first === null) setFirst(next);
      else view.current?.restart({ seed: next.seed, best: next.best });
      setPhase('ready');
    } catch {
      setFailed(true);
    }
  };

  useEffect(() => {
    if (isAuthenticated && round.current === null) begin();
    // Runs once the phone is signed in.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isAuthenticated]);

  const tick = () => {
    const now = Date.now();
    const state = clock.current;
    if (state.lastTick && now - state.lastInput < IDLE_MS) state.activeMs += now - state.lastTick;
    state.lastTick = now;
    const current = round.current;
    if (current) setGold(Math.min(current.left, Math.floor((state.activeMs / 60000) * current.goldPerMinute)));
  };

  useEffect(() => {
    if (phase !== 'playing') return;
    clock.current.lastTick = Date.now();
    const timer = setInterval(tick, 250);
    return () => clearInterval(timer);
  }, [phase]);

  const pause = () => {
    if (phase !== 'playing') return;
    tick();
    view.current?.pause();
    setPhase('paused');
  };

  useEffect(() => {
    const subscription = AppState.addEventListener('change', (status) => {
      if (status !== 'active') pause();
    });
    return () => subscription.remove();
  });

  const settle = async (result: { score: number; unit: string; headline?: string }) => {
    const current = round.current;
    if (!current) return;
    tick();
    const playMs = clock.current.wallStart ? Date.now() - clock.current.wallStart : 0;
    setOutcome({ ...result, playMs });
    setPhase('over');
    report(result.score, true);
    try {
      const saved = await finishRound({ roundId: current.roundId, score: result.score, activeMs: clock.current.activeMs });
      setOutcome({ ...result, playMs, gold: saved.gold, today: saved.today, left: saved.left, newBest: saved.newBest, balance: saved.balance });
      if (saved.gold > 0) haptic('success');
    } catch {
      setOutcome({ ...result, playMs, gold: 0 });
    }
  };

  const onMessage = (message: GameMessage) => {
    if (message.type === 'start') {
      const now = Date.now();
      clock.current = { activeMs: 0, lastTick: now, lastInput: now, score: 0, wallStart: now };
      setPhase('playing');
    } else if (message.type === 'input') clock.current.lastInput = Date.now();
    else if (message.type === 'score') {
      clock.current.score = message.score;
      report(message.score, false);
    }
    else if (message.type === 'end') settle({ score: message.score ?? clock.current.score, unit: message.unit ?? game?.unit ?? '', headline: message.headline });
  };

  const leave = async () => {
    const current = round.current;
    if (current && phase === 'paused') {
      finishRound({ roundId: current.roundId, score: clock.current.score, activeMs: clock.current.activeMs }).catch(() => {});
    }
    if (phase !== 'over') report(clock.current.score, true);
    router.back();
  };

  const title = game?.title ?? '';
  const limitReached = outcome?.left === 0;

  return (
    <View style={{ flex: 1, backgroundColor: catalog[slug]?.tint ?? '#0E0E0F' }}>
      <StatusBar style="light" hidden={phase === 'playing'} />
      {first ? (
        <GameView ref={view} slug={slug} mode="play" seed={first.seed} best={first.best} onMessage={onMessage} />
      ) : (
        <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', gap: 14 }}>
          {failed ? (
            <>
              <Icon name="offline" size={30} color="#FFFFFF" />
              <Body color="#FFFFFF" weight="600">Could not start the round.</Body>
              <Key small tone="light" label="Try again" onPress={begin} style={{ width: 160 }} />
            </>
          ) : (
            <ActivityIndicator color="#FFFFFF" />
          )}
        </View>
      )}

      {phase !== 'over' && (
        <View pointerEvents="box-none" style={{ position: 'absolute', top: insets.top + 6, left: Margin, right: Margin, flexDirection: 'row', justifyContent: 'space-between' }}>
          <IconButton
            name="close"
            label={phase === 'playing' ? 'Pause' : 'Close'}
            fill="rgba(14,14,15,0.72)"
            color="#F3F0E9"
            onPress={() => (phase === 'playing' ? pause() : leave())}
          />
          <GoldPill amount={gold} prefix="+" onDark />
        </View>
      )}

      {room && phase !== 'over' && (
        <View pointerEvents="none" style={{ position: 'absolute', top: insets.top + 56, left: Margin, gap: 5 }}>
          {room.players.filter((player) => !player.you).slice(0, 5).map((player) => (
            <Row key={player.id} gap={6} style={{ backgroundColor: 'rgba(14,14,15,0.55)', borderRadius: 14, height: 28, paddingLeft: 4, paddingRight: 10, alignSelf: 'flex-start' }}>
              <Avatar name={player.name} color={player.color} size={20} />
              <Display size={17} color="#F3F0E9">{formatScore(player.score, game?.unit ?? '')}</Display>
            </Row>
          ))}
        </View>
      )}

      {phase === 'paused' && (
        <Animated.View entering={FadeIn.duration(140)} style={{ position: 'absolute', left: 0, right: 0, top: 0, bottom: 0, backgroundColor: 'rgba(14,14,15,0.6)', justifyContent: 'flex-end' }}>
          <Animated.View entering={SlideInDown.duration(220)} style={{ backgroundColor: t.surface, borderTopLeftRadius: 30, borderTopRightRadius: 30, borderCurve: 'continuous', padding: 20, paddingBottom: insets.bottom + 16, gap: 12 }}>
            <Display size={34}>Paused</Display>
            <Body color={t.ink2}>
              {gold > 0 ? `You have collected ${gold} gold this round. You keep it if you leave.` : 'Gold counts up while you play.'}
            </Body>
            <Key
              tone="gold"
              icon="play"
              label="Resume"
              onPress={() => {
                view.current?.resume();
                clock.current.lastInput = Date.now();
                setPhase('playing');
              }}
            />
            <Key tone="dark" label={gold > 0 ? 'Leave and keep your gold' : 'Leave'} onPress={leave} />
          </Animated.View>
        </Animated.View>
      )}

      {phase === 'over' && outcome && (
        <Animated.View entering={FadeIn.duration(260)} style={{ position: 'absolute', left: 0, right: 0, top: 0, bottom: 0, backgroundColor: 'rgba(14,14,15,0.92)' }}>
          <View style={{ position: 'absolute', top: insets.top + 6, left: Margin }}>
            <IconButton name="close" label="Close" fill="rgba(14,14,15,0.72)" color="#F3F0E9" onPress={() => router.back()} />
          </View>
          <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', paddingTop: insets.top + 30, gap: 4 }}>
            <Label color="rgba(255,255,255,0.75)">Round time {duration(outcome.playMs)}</Label>
            <Display size={104} color="#FFFFFF" style={{ lineHeight: 104 }}>{formatScore(outcome.score, outcome.unit)}</Display>
            {unitWord(outcome.score, outcome.unit) !== '' && <Display size={30} color="#FFFFFF">{unitWord(outcome.score, outcome.unit)}</Display>}
            {outcome.newBest && (
              <View style={{ marginTop: 8, flexDirection: 'row', alignItems: 'center', gap: 5, backgroundColor: t.gold, borderRadius: 12, height: 24, paddingHorizontal: 10 }}>
                <Icon name="send" size={10} color="#151412" />
                <Label color="#151412" size={10.5}>New best</Label>
              </View>
            )}
            {outcome.headline && <Body color="rgba(255,255,255,0.85)" style={{ marginTop: 8 }}>{outcome.headline}</Body>}
          </View>

          <Animated.View entering={SlideInDown.duration(320)} style={{ backgroundColor: t.surface, borderTopLeftRadius: 30, borderTopRightRadius: 30, borderCurve: 'continuous', padding: 18, paddingBottom: insets.bottom + 14, gap: 12 }}>
            <Row gap={12}>
              <Coin size={38} />
              <Display size={56} style={{ lineHeight: 56 }}>{outcome.gold === undefined ? '+' : `+${outcome.gold}`}</Display>
              <View style={{ flex: 1, gap: 5 }}>
                <Label>Gold collected</Label>
                <Body size={13.5} weight="600">
                  {outcome.today === undefined ? 'Adding it up' : `${outcome.today} of 100 from ${title} today`}
                </Body>
                <Meter value={outcome.today ?? 0} max={100} />
              </View>
            </Row>

            {limitReached && (
              <Row gap={10} style={{ backgroundColor: t.goldWash, borderRadius: 16, padding: 12 }}>
                <Icon name="sun" size={18} color={t.goldText} />
                <View style={{ flex: 1 }}>
                  <Body weight="600">That is all 100 from {title} today</Body>
                  <Body size={12.5} color={t.ink2}>More gold in {untilMidnight(new Date())}. Other games still have gold.</Body>
                </View>
              </Row>
            )}

            {room && (
              <View style={{ backgroundColor: t.raised, borderRadius: 18, paddingHorizontal: 14, paddingVertical: 8, gap: 6 }}>
                {room.players.map((player, index) => (
                  <Row key={player.id} gap={10}>
                    <Display size={18} color={t.ink3} style={{ width: 14 }}>{index + 1}</Display>
                    <Avatar name={player.name} color={player.color} size={22} />
                    <Body weight="600" size={14} style={{ flex: 1 }}>{player.you ? 'You' : player.name}</Body>
                    {player.playing && <Label size={9.5}>Playing</Label>}
                    <Display size={20}>{formatScore(player.score, game?.unit ?? '')}</Display>
                  </Row>
                ))}
              </View>
            )}

            <Row style={{ justifyContent: 'space-between', backgroundColor: t.raised, borderRadius: 18, paddingLeft: 14, paddingRight: 8, height: 52 }}>
              <Body weight="600">Was it good?</Body>
              <Row gap={4}>
                <VoteButton kind="like" size={40} active={game?.vote === 1} ink={t.ink} accent={t.goldText} onPress={() => vote({ slug, value: game?.vote === 1 ? 0 : 1 })} />
                <VoteButton kind="dislike" size={40} active={game?.vote === -1} ink={t.ink} accent={t.goldText} onPress={() => vote({ slug, value: game?.vote === -1 ? 0 : -1 })} />
              </Row>
            </Row>

            <Row gap={10}>
              {roomCode ? (
                <Key tone="gold" label="Back to the room" onPress={() => router.back()} style={{ flex: 1 }} />
              ) : (
                <>
                  <Key testID="again-key" tone="gold" icon="again" label="Again" onPress={begin} style={{ flex: 1 }} />
                  <Key tone="dark" label={limitReached ? 'Find another game' : 'Done'} onPress={() => (limitReached ? router.dismissTo('/') : router.back())} style={{ flex: 1 }} />
                </>
              )}
            </Row>

            <Pressable onPress={() => router.replace(`/leaderboard/${slug}`)} style={{ alignSelf: 'center', paddingVertical: 4 }}>
              <Row gap={4}>
                <Icon name="trophy" size={12} color={t.ink2} />
                <Body size={13} weight="600" color={t.ink2}>See the leaderboard</Body>
              </Row>
            </Pressable>
          </Animated.View>
        </Animated.View>
      )}
    </View>
  );
}
