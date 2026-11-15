# Dailies

Consumer mobile app built at [The Consumer Mobile Hackathon](https://consumermobilehackathon.com/) (Sunday, November 15, 2026, YC, San Francisco). The app, the backend, and everything else for the hackathon live in this one repository.

The hackathon's required stack is Capy (writes the app), Revyl (runs it on a device and checks it), and Convex (the backend).

## Run it

```sh
npm install
npx convex dev    # syncs convex/ to the dev deployment; writes .env.local on first run
npm run ios       # or: npm start, then scan the QR code with Expo Go
```

The app is an Expo app (Expo Router, TypeScript) at the repository root with screens in `src/app/`, and the Convex backend is in `convex/`. `AGENTS.md` holds the conventions for each sponsor tool, and `hackathon.md` is the public build log.

## How the app is put together

- **Screens** are Expo Router routes in `src/app/`: the Home, Videos and You tabs, the game page, the play screen, gold, leaderboards, comments, search, settings, and rooms (`room/[code]`, `join`).
- **Games** are single plain JavaScript canvas files in `games/<slug>/game.js`. They run in a WebView on top of the small runtime in `games/sdk.js`, which also lets a bot play each game for the Videos feed. `games/README.md` is the contract for writing one, and `games/_example` is the smallest working game.
- **`node scripts/build-games.mjs`** bundles the games into `src/games/generated.ts` (git-ignored) and writes a standalone page for each to `dist-games/`. It runs on `npm install` and `npm start`; run it by hand before any other build, and after editing a game.
- **The backend** is in `convex/`: each phone gets its own account (`auth.ts`, `users.ts`), the server starts and finishes rounds and works out gold (`rounds.ts`), and `social.ts`, `games.ts` and `rooms.ts` hold likes, comments, leaderboards, the catalog and rooms. `npx convex run seed:run` adds the launch games.

To add a game: write `games/<slug>/game.js`, add its cover and icon to `assets/games/`, add it to `src/lib/catalog.ts` and to `convex/seed.ts`, then run the seed.

## Worktrees

The main checkout stays on `main`. Every other branch gets its own worktree in a sibling folder, so no worktree sits inside another one and Metro, TypeScript, and watchman never crawl a second copy of the app.

```
~/Documents/
├── Dailies/                  main checkout, always on main
└── Dailies-worktrees/
    ├── onboarding/           branch onboarding
    └── feat-paywall/         branch feat/paywall
```

`scripts/wt` manages them and works from any worktree:

```sh
scripts/wt new onboarding        # new branch from origin/main in ../Dailies-worktrees/onboarding
scripts/wt new hotfix some-ref   # branch from another ref
scripts/wt ls                    # list every worktree
scripts/wt rm onboarding         # remove the worktree, delete the branch if merged
```

`wt new` also copies the ignored `.env` files (such as Convex's `.env.local`) from the main checkout and installs dependencies, because neither travels with a new worktree.

Capy threads that start in a new worktree keep theirs under `~/.capy/worktrees`; `scripts/wt ls` lists those too.
