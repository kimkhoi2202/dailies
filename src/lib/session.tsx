import { useSignInWithUsernamePassword, useSignUpWithUsernamePassword } from '@convex-dev/auth/methods/username-password/react';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { useConvexAuth, useMutation, useQuery } from 'convex/react';
import * as Crypto from 'expo-crypto';
import * as SecureStore from 'expo-secure-store';
import { useEffect, useRef } from 'react';
import { Platform } from 'react-native';

import { api } from '@/convex/_generated/api';

import { useDay } from './day';

const KEY = 'dailies.device';

export const tokenStorage =
  Platform.OS === 'web'
    ? undefined
    : { getItem: SecureStore.getItemAsync, setItem: SecureStore.setItemAsync, removeItem: SecureStore.deleteItemAsync };

async function deviceCredentials() {
  const stored = Platform.OS === 'web' ? await AsyncStorage.getItem(KEY) : await SecureStore.getItemAsync(KEY);
  if (stored) return JSON.parse(stored) as { username: string; password: string };
  const fresh = {
    username: 'device' + Crypto.randomUUID().replace(/-/g, ''),
    password: Crypto.randomUUID() + Crypto.randomUUID(),
  };
  if (Platform.OS === 'web') await AsyncStorage.setItem(KEY, JSON.stringify(fresh));
  else await SecureStore.setItemAsync(KEY, JSON.stringify(fresh));
  return fresh;
}

/** Signs this phone in with its own account, creating it the first time. */
export function useDeviceSession() {
  const { isLoading, isAuthenticated } = useConvexAuth();
  const { signIn } = useSignInWithUsernamePassword(api.auth);
  const { signUp } = useSignUpWithUsernamePassword(api.auth);
  const busy = useRef(false);

  useEffect(() => {
    if (isLoading || isAuthenticated || busy.current) return;
    busy.current = true;
    let retry: ReturnType<typeof setTimeout> | undefined;
    (async () => {
      const credentials = await deviceCredentials();
      const result = await signIn(credentials);
      if (result.status === 'complete') return;
      if (result.userError.error === 'USER_NOT_FOUND') await signUp(credentials);
    })()
      .catch(() => {})
      .finally(() => {
        busy.current = false;
      });
    return () => clearTimeout(retry);
  }, [isLoading, isAuthenticated, signIn, signUp]);
}

export function useMe() {
  const day = useDay();
  return useQuery(api.users.me, { day });
}

export function useGames() {
  const day = useDay();
  return useQuery(api.games.list, { day });
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
