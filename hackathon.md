# Hackathon log

- **Project:** DEGEN (first called Dailies)
- **Event:** The Consumer Mobile Hackathon
- **What it does:** A daily feed of small phone games where playing collects gold, with likes, comments, leaderboards and rooms for playing the same level with friends.
- **Live app:** not deployed
- **Repo:** private
- **Frontend:** not deployed
- **Convex deployment:** https://blissful-jackal-368.convex.cloud
- **Components:** @convex-dev/auth (auth, authPassword, authUsername)
- **Convex features:** schema, tables, indexes, queries, mutations, actions, HTTP actions, scheduler, environment variables, realtime queries
- **Auth:** Convex Auth
- **AI models:** gpt-6-luna (OpenAI Responses API, from a Convex action)
- **Started:** 2026-11-15T18:02:39Z
- **Last updated:** 2026-11-15T21:13:57Z

- **Last updated:** 2026-11-15T22:57:48Z

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

### 2026-11-15 - 18d94c1
Rebuilt the tab bar as our own floating frosted pill with five slots: Home,
Reels, a raised gold Create key that opens the camera screen (a placeholder for
now), Messages (a placeholder until chats land) and a new Library tab
(`Sources/Live/LiveTabBar.swift`, `Sources/Live/LiveRoot.swift`). The Library
shows the games you played lately from your round history, every game with your
best and the gold it has left today, a bookmark to save games, and rooms you can
start or join with a 4 letter code, with a live lobby that takes everyone into
the same round (`Sources/Screens/LibraryScreen.swift`,
`Sources/Screens/RoomScreens.swift`). Saved games live in Convex
(`convex/library.ts`, a `saved` table in `convex/schema.ts`). Home gained the
player's avatar at the top right, which opens the profile.

### 2026-11-15 - 285f965
Added the studio's game creation pipeline, on the `game-creation` branch.
From the studio a player says what game they want, or asks to be inspired, and
talks to the studio until it has enough to build. The studio is an OpenAI model
(`gpt-6-luna`, Responses API with a JSON schema) behind a Convex action that
reads `OPENAI_API_KEY` from the Convex environment; each reply is a line with
tappable choices, three ideas, or the finished design (`convex/ai.ts`). A
creation and its conversation live in two new tables, the app watches them
with live queries, and when the design is settled a scheduled mutation puts the
game in the `games` table, private to its maker, playing on one of the six
built-in engines with the studio's title, pitch, instructions and colour
(`convex/creations.ts`, `convex/schema.ts`, `convex/games.ts`). In the app:
the wish screen, the talk, the building screen and the game's preview with a
Play key, plus the list of made games in the studio (`Sources/Screens/G4_Create.swift`,
`Sources/Screens/G3_Studio.swift`, `Sources/Live/LiveStore.swift`). The whole
talk was run against the deployment from the CLI: a wish for inspiration got
four moods, a mood got three ideas, and picking one built a game on the Spiral
Drop engine within ten seconds.

### 2026-11-15 - avatar-room
Added the player's avatar, a Profile room and a Shop. The avatar is a small
low-poly chibi built in SceneKit from faceted shapes: 10 body colours, faces,
hair, hats, outfits and held gadgets, all mixed on one figure that idles,
blinks, turns 360 degrees and pops when it puts something on. Small spots such as
the Home top bar and shop cards show a picture rendered from the same model
(`Sources/Avatar/`). The Profile shows the avatar in a decorated room with a
trophy shelf and the room decor the player has placed
(`Sources/Screens/ProfileScreen.swift`, `Sources/Screens/RoomArt.swift`). The
Shop sells items, room decor and bundles for gold, and the Closet equips them
(`Sources/Screens/ShopScreen.swift`). In Convex, the catalog and prices live on
the server (`convex/items.ts`); `shop.buy` and `shop.buyBundle` check the
balance and charge gold in a mutation, writing a gold history row; equipping and
placing decor check ownership (`convex/avatar.ts`). The look and placed decor are
fields on users, and ownership is a new `inventory` table
(`convex/schema.ts`). Seeded players get their own looks and rooms
(`convex/seed.ts`). A convex-test run covered buying, refusing short balances
and repeat buys, and equipping only owned items. An earlier voxel version and an
image-model turnaround were tried first and replaced after owner feedback.



### 2026-11-15 - b72b9a1
Tuned Short Stack. A sitting is seven hands. The other seats now stay in against
a raise of any size once their hand is strong enough, so going all in on every
hand stops working, and they take a little longer to act. Every seat has the same
plate, and the seat to act wears a gold ring that runs down with its time. The
game's clip in Videos is timed to the feed and lights the keys while the table
waits for the player (`Sources/Games/ShortStackGame.swift`,
`Sources/Games/ShortStackScene.swift`). The results screen has one Again key
(`Sources/Screens/GameScreens.swift`).

### 2026-11-15 - 271209b
Renamed the app to DEGEN wherever a person reads the name: under the icon, in
share text, in Settings and in accessibility labels. The logo on Home is drawn in
code, the D mark followed by EGEN, in place of two lockup images
(`Sources/DS/Components.swift`, `project.yml`). The repository, the Xcode
target, the bundle id and the Convex project keep the name Dailies. Replaced the
app icon with one 1024 px image
(`Resources/Assets.xcassets/AppIcon.appiconset`). Prepared the app for App Store
Connect: version 1.0.0, the games category, the export compliance answer, iPhone
as the only device, and a privacy manifest that declares UserDefaults, no
tracking and no collected data (`project.yml`, `Resources/PrivacyInfo.xcprivacy`).
An archive of this commit, signed for the team's App Store Connect account under
its own bundle id, was uploaded to TestFlight as 1.0.0 (3). It is available to
the team's internal testers and is waiting for Apple's beta review, which the
public TestFlight link needs before it opens. After the merge, `main` was built
on Revyl and opened on a cloud iPhone, where Home loaded with all seven games.

### 2026-11-15 - 18d94c1
Rebuilt the tab bar as our own floating frosted pill with five slots: Home,
Reels, a raised gold Create key that opens the camera screen (a placeholder for
now), Messages (a placeholder until chats land) and a new Library tab
(`Sources/Live/LiveTabBar.swift`, `Sources/Live/LiveRoot.swift`). The Library
shows the games you played lately from your round history, every game with your
best and the gold it has left today, a bookmark to save games, and rooms you can
start or join with a 4 letter code, with a live lobby that takes everyone into
the same round (`Sources/Screens/LibraryScreen.swift`,
`Sources/Screens/RoomScreens.swift`). Saved games live in Convex
(`convex/library.ts`, a `saved` table in `convex/schema.ts`). Home gained the
player's avatar at the top right, which opens the profile.

### 2026-11-15 - 285f965
Added the studio's game creation pipeline, on the `game-creation` branch.
From the studio a player says what game they want, or asks to be inspired, and
talks to the studio until it has enough to build. The studio is an OpenAI model
(`gpt-6-luna`, Responses API with a JSON schema) behind a Convex action that
reads `OPENAI_API_KEY` from the Convex environment; each reply is a line with
tappable choices, three ideas, or the finished design (`convex/ai.ts`). A
creation and its conversation live in two new tables, the app watches them
with live queries, and when the design is settled a scheduled mutation puts the
game in the `games` table, private to its maker, playing on one of the six
built-in engines with the studio's title, pitch, instructions and colour
(`convex/creations.ts`, `convex/schema.ts`, `convex/games.ts`). In the app:
the wish screen, the talk, the building screen and the game's preview with a
Play key, plus the list of made games in the studio (`Sources/Screens/G4_Create.swift`,
`Sources/Screens/G3_Studio.swift`, `Sources/Live/LiveStore.swift`). The whole
talk was run against the deployment from the CLI: a wish for inspiration got
four moods, a mood got three ideas, and picking one built a game on the Spiral
Drop engine within ten seconds.

### 2026-11-15 - 3c0aa23
Added money through Whop, on the `whop-money` branch, in three parts. A player
buys a gold pack: a Convex action opens an order and a Whop checkout, the app
shows the checkout in the system browser, and gold is credited only when Whop's
signed `payment.succeeded` webhook reaches the HTTP action at `/whop`
(`convex/whop.ts`, `convex/http.ts`). A studio funds a creator program for one
of its games the same way, choosing what it pays for 1,000 views and a budget.
A clip of that game then earns its maker money for each new viewer, counted
once per viewer and never for the maker, until the budget runs out
(`convex/creators.ts`, new `orders`, `programs`, `clipViews` and `transfers`
tables in `convex/schema.ts`). A creator sends what they have collected to a
Whop account by username. Prices and credits are decided in Convex; the app
holds no Whop key (`Sources/Screens/WhopMoney.swift`). Run against Whop's
sandbox on the dev deployment: a gold pack paid with a test card from a cloud
iPhone on Revyl landed as 500 gold on the phone, a funded program paid a test
creator $1.00 for 20 viewers, and Whop refused the transfer out because the
sandbox key lacks the transfer scope, which the app records and shows without
taking the creator's money. Convex features: HTTP actions, actions, mutations,
queries, indexes, environment variables.
