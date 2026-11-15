# Hackathon log

- **Project:** Dailies
- **Event:** The Consumer Mobile Hackathon
- **What it does:** A daily feed of small phone games where playing collects gold, with likes, comments, leaderboards and rooms for playing the same level with friends.
- **Live app:** not deployed
- **Repo:** private
- **Frontend:** not deployed
- **Convex deployment:** https://blissful-jackal-368.convex.cloud
- **Components:** @convex-dev/auth (auth, authPassword, authUsername)
- **Convex features:** schema, tables, indexes, queries, mutations, realtime queries
- **Auth:** Convex Auth
- **AI models:** none
- **Started:** 2026-11-15T18:02:39Z
- **Last updated:** 2026-11-15T21:13:57Z

## Log

### 2026-11-15 - 4f9bf7a
Created the repository with a README, a `.gitignore` and `scripts/wt`, a helper
that keeps every branch in its own sibling worktree and copies ignored env files
into new ones (`scripts/wt`, `README.md`).

### 2026-11-15 - b1e6199
Scaffolded the Expo app with Expo Router and TypeScript at the repository root
and wrapped it in a Convex provider that reads the deployment URL from the
environment (`src/app/_layout.tsx`). Provisioned a Convex dev deployment and
added an empty schema, with no tables or functions yet (`convex/schema.ts`).

### 2026-11-15 - e8a5ab6
Moved the development backend to the shared `dailies/dailies` Convex project. Synced the existing functions and verified the Expo client and HTTP action URLs point to the same deployment.

### 2026-11-15 - 4a976ac
Added the game runtime. Each game is one plain JavaScript canvas file under
`games/<slug>/game.js` that runs in a WebView on top of a shared runtime
(`games/sdk.js`): seeded randomness, score, haptics, tones, pause and a bot that
plays the game for the video feed. `scripts/build-games.mjs` bundles them into
the app (`games/README.md`, `src/components/game-view.tsx`).

### 2026-11-15 - eb9cc79
Built the backend. Each phone gets its own account through Convex Auth v2 with
the username and password method, no sign up screen. Rounds start and finish on
the server, which works out gold from active play time with a limit of 100 a day
for one game and 300 a day for one studio. Added likes, comments, best scores
and leaderboards, plus a seed for the six launch games. Convex features: schema,
indexes, queries, mutations, Convex Auth (`convex/schema.ts`, `convex/auth.ts`,
`convex/rounds.ts`, `convex/social.ts`, `convex/games.ts`, `convex/seed.ts`).

### 2026-11-15 - ab3005d
Built the app: Home with filters, a full screen Videos feed where a bot plays
each game, the game page, the play screen with a live gold counter, pause and
results, the gold screen, leaderboards, comments, search, profile and settings
with light and dark appearance. Every screen reads live from Convex with
`useQuery`, and likes use an optimistic update (`src/app/`, `src/lib/session.tsx`).

### 2026-11-15 - 1cf3871
First Revyl build ran on a cloud iPhone and showed the phone never signed in:
an unsigned simulator build has no keychain. Session storage now tries
`expo-secure-store` first and falls back to app storage, and sign in retries
until it works (`src/lib/session.tsx`).

### 2026-11-15 - 589d20b
Added rooms. A host starts a room from any game and gets a four letter code,
friends join with the code, and everyone plays the same seeded level while live
scores from the others show on screen through a Convex query. Rounds played in a
room collect gold like any other round (`convex/rooms.ts`,
`src/app/room/[code].tsx`, `src/app/join.tsx`, `src/app/play/[slug].tsx`).

### 2026-11-15 - 245bbfd
Replaced the Expo app with a native iOS app in Swift (SwiftUI). Eight Capy agents
rewrote it in parallel, file by file, working from a Swift prototype of the same
app that was started on November 14. The prototype was the reference for layout,
tuning and structure; each file was written again today, staying close to it, and
its fonts and brand images were carried over as they are. The app has the Home,
Videos and You tabs, the game page, the play and results screens, gold,
leaderboards, comments, search, settings and the studio screens, and six games
drawn in Swift (`Sources/`, `project.yml`). The store every screen reads is now
backed by Convex through the Swift client: a device account kept in the Keychain,
live queries for the player, the catalog and the gold history, and mutations for
rounds, likes, comments and spending (`Sources/Live/LiveStore.swift`,
`Sources/Convex/`). The backend gained a gold history, spending, comment likes
and a fraction of gold carried between rounds (`convex/ledger.ts`,
`convex/shop.ts`, `convex/rounds.ts`, `convex/social.ts`, `convex/schema.ts`).
The Expo screens and the JavaScript games were removed. Leaderboards, other
players' comments and the catalog's display numbers still show sample data in
the app.

### 2026-11-15 - 75fb5a8
The Swift app now shows live Convex data where it still had sample content:
leaderboards, other players' comments and their like counts, the gold history
and today's totals, each game's likes, plays and approval, the player's name,
and the streak week (`Sources/Live/LiveStore.swift`, `Sources/Live/LiveScreens.swift`,
`Sources/Core/MockData.swift`). Fixed the results screen cutting off a gold
amount of two digits (`Sources/Screens/GameScreens.swift`). Built the app on
Revyl, installed it on a cloud iPhone and played a round by touch; the round and
its gold appeared in Convex under a new device account.

### 2026-11-15 - 6642de8
Added a seventh game, Short Stack: no-limit Texas Hold'em at a table of six, sized
for one sitting of two to three minutes. The rules are a plain Swift model with a
seeded deck: a moving button, blinds that double every three hands, minimum
raises, all in with side pots, showdowns on the best five of seven cards and
split pots. The game plays the five other seats itself, each weighing a quick
sample of showdowns against the price of calling, with a lean of its own. Cards,
suits, chips and the table are drawn in code in one Canvas, and the same painter
draws the game's clip in Videos (`Sources/Games/ShortStackGame.swift`,
`Sources/Games/ShortStackScene.swift`). An older poker app of Khoi's was the
reference for the rules and the feel of the table; the game was written again in
Swift today. It is in the catalog and seeded in Convex with its friends' scores
and comments (`Sources/Core/MockData.swift`, `convex/seed.ts`).
