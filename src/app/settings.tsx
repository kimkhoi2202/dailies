import { useMutation } from 'convex/react';
import Constants from 'expo-constants';
import { router } from 'expo-router';
import { useState } from 'react';
import { Pressable, Switch, TextInput, View } from 'react-native';

import { Screen } from '@/components/screen';
import { Body, Card, Divider, Icon, Label, Row } from '@/components/ui';
import { api } from '@/convex/_generated/api';
import { useMe } from '@/lib/session';
import { haptic, type Settings, useSettings } from '@/lib/settings';
import { useTheme } from '@/lib/theme';

function Toggle({ label, note, value, onChange }: { label: string; note?: string; value: boolean; onChange: (value: boolean) => void }) {
  const t = useTheme();
  return (
    <Row style={{ justifyContent: 'space-between', paddingVertical: 10 }}>
      <View style={{ flex: 1, paddingRight: 12 }}>
        <Body weight="500">{label}</Body>
        {note && <Body size={12.5} color={t.ink2}>{note}</Body>}
      </View>
      <Switch
        accessibilityLabel={label}
        value={value}
        onValueChange={(next) => {
          haptic('select');
          onChange(next);
        }}
        trackColor={{ true: t.gold, false: t.sunken }}
      />
    </Row>
  );
}

const appearances: { id: Settings['appearance']; label: string }[] = [
  { id: 'system', label: 'System' },
  { id: 'light', label: 'Light' },
  { id: 'dark', label: 'Dark' },
];

export default function SettingsScreen() {
  const t = useTheme();
  const me = useMe();
  const update = useMutation(api.users.update);
  const { settings, change } = useSettings();
  const [name, setName] = useState<string | null>(null);
  const [problem, setProblem] = useState<string | null>(null);

  const saveName = async () => {
    if (name === null || name.trim() === me?.name) return setName(null);
    try {
      await update({ name });
      setProblem(null);
      setName(null);
    } catch {
      setProblem('Names are 2 to 20 characters.');
    }
  };

  return (
    <Screen title="Settings">
      <Label>Your name</Label>
      <Card style={{ paddingVertical: 6 }}>
        <Row gap={10}>
          <TextInput
            testID="name-input"
            value={name ?? me?.name ?? ''}
            onChangeText={setName}
            onBlur={saveName}
            onSubmitEditing={saveName}
            maxLength={20}
            autoCorrect={false}
            returnKeyType="done"
            placeholder="Your name"
            placeholderTextColor={t.ink3}
            style={{ flex: 1, fontSize: 16, fontWeight: '500', color: t.ink, paddingVertical: 10 }}
          />
          <Icon name="pencil" size={14} color={t.ink3} />
        </Row>
      </Card>
      <Body size={12.5} color={problem ? t.danger : t.ink2}>{problem ?? `Friends see you as @${me?.handle ?? ''} on leaderboards and comments.`}</Body>

      <Label style={{ marginTop: 8 }}>Appearance</Label>
      <Row gap={8}>
        {appearances.map((item) => {
          const selected = settings.appearance === item.id;
          return (
            <Pressable
              key={item.id}
              accessibilityRole="button"
              accessibilityState={{ selected }}
              onPress={() => {
                haptic('select');
                change({ appearance: item.id });
              }}
              style={{ flex: 1, height: 48, borderRadius: 16, alignItems: 'center', justifyContent: 'center', backgroundColor: t.surface, borderWidth: 2, borderColor: selected ? t.ink : 'transparent' }}>
              <Body weight="600" size={14}>{item.label}</Body>
            </Pressable>
          );
        })}
      </Row>

      <Label style={{ marginTop: 8 }}>Play</Label>
      <Card style={{ paddingVertical: 4 }}>
        <Toggle label="Haptics" value={settings.haptics} onChange={(haptics) => change({ haptics })} />
        <Divider />
        <Toggle label="Sound" value={settings.sound} onChange={(sound) => change({ sound })} />
        <Divider />
        <Toggle
          label="Fast gold for demos"
          note="Gold arrives 10 times faster so a short round shows it. Turn it off for the real rate."
          value={me?.fastGold ?? true}
          onChange={(fastGold) => update({ fastGold })}
        />
      </Card>

      <Label style={{ marginTop: 8 }}>Help</Label>
      <Pressable onPress={() => router.push('/how-gold-works')}>
        <Card>
          <Row style={{ justifyContent: 'space-between' }}>
            <Body weight="500">How gold works</Body>
            <Icon name="forward" size={12} color={t.ink2} />
          </Row>
        </Card>
      </Pressable>
      <Label size={10} style={{ alignSelf: 'center', marginTop: 10 }}>Dailies {Constants.expoConfig?.version ?? ''}</Label>
    </Screen>
  );
}
