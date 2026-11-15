import { useMutation, useQuery } from 'convex/react';
import { useLocalSearchParams } from 'expo-router';
import { useState } from 'react';
import { KeyboardAvoidingView, Platform, Pressable, ScrollView, TextInput, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { Avatar, Body, Icon, Row } from '@/components/ui';
import { api } from '@/convex/_generated/api';
import { useNow } from '@/lib/day';
import { ago } from '@/lib/format';
import { useMe } from '@/lib/session';
import { haptic } from '@/lib/settings';
import { useTheme } from '@/lib/theme';

export default function Comments() {
  const { slug } = useLocalSearchParams<{ slug: string }>();
  const t = useTheme();
  const insets = useSafeAreaInsets();
  const me = useMe();
  const comments = useQuery(api.social.comments, { slug });
  const add = useMutation(api.social.addComment);
  const [text, setText] = useState('');
  const now = useNow();
  const ready = text.trim().length > 0;

  const send = () => {
    if (!ready) return;
    haptic('light');
    add({ slug, body: text });
    setText('');
  };

  return (
    <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined} style={{ flex: 1 }}>
      <Row gap={8} style={{ paddingHorizontal: 18, paddingTop: 26, paddingBottom: 8 }}>
        <Body weight="700" size={16}>Comments</Body>
        <Body color={t.ink2} size={16}>{comments?.length ?? ''}</Body>
      </Row>
      <ScrollView bounces={false} keyboardShouldPersistTaps="handled" contentContainerStyle={{ paddingHorizontal: 18, paddingBottom: 12, gap: 16 }} style={{ flex: 1 }}>
        {comments?.length === 0 && <Body color={t.ink2}>No comments yet. Say something about it.</Body>}
        {(comments ?? []).map((comment) => (
          <Row key={comment._id} gap={12} style={{ alignItems: 'flex-start' }}>
            <Avatar name={comment.handle} color={comment.color} size={32} />
            <View style={{ flex: 1, gap: 3 }}>
              <Row gap={6}>
                <Body size={12.5} weight="600" color={t.ink2}>@{comment.handle}</Body>
                <Body size={12} color={t.ink3}>{ago(comment.at, now)}</Body>
              </Row>
              <Body size={14.5} style={{ lineHeight: 19 }}>{comment.body}</Body>
            </View>
          </Row>
        ))}
      </ScrollView>
      <Row gap={10} style={{ paddingHorizontal: 14, paddingTop: 8, paddingBottom: insets.bottom + 8, borderTopWidth: 1, borderTopColor: t.line }}>
        <Avatar name={me?.handle ?? '?'} color={me?.color ?? t.sunken} size={34} />
        <View style={{ flex: 1, flexDirection: 'row', alignItems: 'center', backgroundColor: t.raised, borderRadius: 20, paddingLeft: 14, paddingRight: 5, minHeight: 40 }}>
          <TextInput
            testID="comment-input"
            value={text}
            onChangeText={setText}
            placeholder="Add a comment"
            placeholderTextColor={t.ink3}
            maxLength={280}
            returnKeyType="send"
            onSubmitEditing={send}
            style={{ flex: 1, fontSize: 15, color: t.ink, paddingVertical: 8 }}
          />
          <Pressable
            accessibilityLabel="Send comment"
            onPress={send}
            style={{ width: 30, height: 30, borderRadius: 15, backgroundColor: ready ? t.gold : t.sunken, alignItems: 'center', justifyContent: 'center' }}>
            <Icon name="send" size={14} color={ready ? '#151412' : t.ink3} />
          </Pressable>
        </View>
      </Row>
    </KeyboardAvoidingView>
  );
}
