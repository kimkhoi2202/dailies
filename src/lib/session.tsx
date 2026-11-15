import { useSignInWithUsernamePassword, useSignUpWithUsernamePassword } from '@convex-dev/auth/methods/username-password/react';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { useConvexAuth, useMutation, useQuery } from 'convex/react';
import * as Crypto from 'expo-crypto';
import * as SecureStore from 'expo-secure-store';
import { useEffect, useMemo, useState } from 'react';
import { Platform } from 'react-native';

import { api } from '@/convex/_generated/api';

import { catalog } from './catalog';
import { useDay } from './day';

const KEY = 'dailies.device';

/** Keychain first. A build without keychain access, like an unsigned simulator build, falls back to app storage. */
const deviceStorage = {
  async getItem(key: string) {
    try {
      const value = await SecureStore.getItemAsync(key);
      if (value !== null) return value;
    } catch {}
    return AsyncStorage.getItem(key);
  },
  async setItem(key: string, value: string) {
    try {
      await SecureStore.setItemAsync(key, value);
    } catch {
      await AsyncStorage.setItem(key, value);
    }
  },
  async removeItem(key: string) {
    await SecureStore.deleteItemAsync(key).catch(() => {});
    await AsyncStorage.removeItem(key);
  },
};

export const tokenStorage = Platform.OS === 'web' ? undefined : deviceStorage;

async function deviceCredentials() {
  const store = Platform.OS === 'web' ? AsyncStorage : deviceStorage;
  const stored = await store.getItem(KEY);
  if (stored) return JSON.parse(stored) as { username: string; password: string };
  const fresh = {
    username: 'device' + Crypto.randomUUID().replace(/-/g, ''),
    password: Crypto.randomUUID() + Crypto.randomUUID(),
  };
  await store.setItem(KEY, JSON.stringify(fresh));
  return fresh;
}

/** Signs this phone in with its own account, creating it the first time. Tries again until it works. */
export function useDeviceSession() {
  const { isLoading, isAuthenticated } = useConvexAuth();
  const { signIn } = useSignInWithUsernamePassword(api.auth);
  const { signUp } = useSignUpWithUsernamePassword(api.auth);
  const [attempt, setAttempt] = useState(0);

  useEffect(() => {
    if (isLoading || isAuthenticated) return;
    let cancelled = false;
    let retry: ReturnType<typeof setTimeout> | undefined;
    (async () => {
      const credentials = await deviceCredentials();
      if (cancelled) return;
      const result = await signIn(credentials);
      if (result.status === 'complete') return;
      if (result.userError.error !== 'USER_NOT_FOUND') throw new Error(result.userError.error);
      const created = await signUp(credentials);
      if (created.status !== 'complete') throw new Error(created.userError.error);
    })().catch((error) => {
      console.warn('Dailies sign in failed', error);
      if (!cancelled) retry = setTimeout(() => setAttempt((n) => n + 1), 3000);
    });
    return () => {
      cancelled = true;
      clearTimeout(retry);
    };
  }, [isLoading, isAuthenticated, signIn, signUp, attempt]);
}

export function useMe() {
  const day = useDay();
  return useQuery(api.users.me, { day });
}

/** The games on the server that this build of the app carries. */
export function useGames() {
  const day = useDay();
  const games = useQuery(api.games.list, { day });
  return useMemo(() => games?.filter((game) => game.slug in catalog), [games]);
}

export function useGame(slug: string) {
  const games = useGames();
  return games?.find((game) => game.slug === slug);
}

/** Like or dislike a game. The counts change at once and settle when the server answers. */
export function useVote() {
  return useMutation(api.social.vote).withOptimisticUpdate((store, args) => {
    for (const query of store.getAllQueries(api.games.list)) {
      if (!query.value) continue;
      store.setQuery(
        api.games.list,
        query.args,
        query.value.map((row) =>
          row.slug !== args.slug
            ? row
            : {
                ...row,
                vote: args.value,
                likes: row.likes + (args.value === 1 ? 1 : 0) - (row.vote === 1 ? 1 : 0),
                dislikes: row.dislikes + (args.value === -1 ? 1 : 0) - (row.vote === -1 ? 1 : 0),
              },
        ),
      );
    }
  });
}

export type Game = NonNullable<ReturnType<typeof useGames>>[number];
