import { useMutation } from 'convex/react';
import { router } from 'expo-router';
import { useState } from 'react';
import { TextInput, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { Body, Display, Key } from '@/components/ui';
import { api } from '@/convex/_generated/api';
import { Font, useTheme } from '@/lib/theme';

export default function Join() {
  const t = useTheme();
  const insets = useSafeAreaInsets();
  const join = useMutation(api.rooms.join);
  const [code, setCode] = useState('');
  const [problem, setProblem] = useState('');

  const submit = async () => {
    try {
      const joined = await join({ code });
      router.replace(`/room/${joined}`);
    } catch {
      setProblem('No open room has that code.');
    }
  };

  return (
    <View style={{ padding: 20, paddingTop: 30, paddingBottom: insets.bottom + 16, gap: 14 }}>
      <Display size={32}>Join a room</Display>
      <Body color={t.ink2}>Enter the four letters on your friend's phone. Everyone plays the same level.</Body>
      <TextInput
        testID="room-code-input"
        value={code}
        onChangeText={(text) => {
          setProblem('');
          setCode(text.replace(/[^a-zA-Z]/g, '').toUpperCase().slice(0, 4));
        }}
        autoFocus
        autoCapitalize="characters"
        autoCorrect={false}
        placeholder="CODE"
        placeholderTextColor={t.ink3}
        returnKeyType="join"
        onSubmitEditing={submit}
        style={{ height: 84, borderRadius: 22, backgroundColor: t.raised, color: t.ink, fontFamily: Font.display, fontSize: 52, letterSpacing: 10, textAlign: 'center' }}
      />
      {problem !== '' && <Body color={t.ink2} weight="600">{problem}</Body>}
      <Key tone="gold" label="Join" disabled={code.length !== 4} onPress={submit} />
    </View>
  );
}
