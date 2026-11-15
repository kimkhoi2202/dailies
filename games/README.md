# Dailies games

Every game is one plain JavaScript file, `games/<slug>/game.js`, drawn on a full-screen 2D canvas. The app runs it in a WebView for a round a person plays, and again as the clip in the Videos feed, where a bot plays it. No imports, no network, no external assets: everything is drawn with canvas calls.

`games/sdk.js` is loaded first and provides `window.Dailies` (alias `D`). `games/_example/game.js` is the smallest working game.

## Build and try

```sh
node scripts/build-games.mjs      # writes dist-games/<slug>.html and src/games/generated.ts
npx serve dist-games              # or open dist-games/<slug>.html directly
```

Query parameters for a standalone page: `?mode=clip` (bot plays, loops for ever), `?seed=7`, `?best=31`, `?autostart=1`, `?sound=1`. Outside the app the runtime logs its messages to the console (`[dailies] {"type":"end",...}`). Test at 390 x 844 and 430 x 932 CSS pixels.

## The game object

```js
(function () {
  var D = window.Dailies;
  D.game({
    reset(seed) {},             // build a fresh round and be ready to draw it. Called before every round
    start() {},                 // the round begins (first touch in play mode, at once in clip mode)
    update(dt, state) {},       // dt in seconds (at most 1/30). state: 'ready' | 'playing' | 'over'
    draw(ctx, W, H, state) {},  // draw the whole frame in CSS pixels
    pointerDown(x, y, id, first) {},  // first is true for the touch that started the round
    pointerMove(x, y, id, down) {},
    pointerUp(x, y, id) {},
    key(k) {},                  // optional, desktop testing
    bot(dt) {},                 // clip mode only: play the game by calling your own input functions
    resize(W, H) {},            // optional
  });
})();
```

## Runtime

| Call | What it does |
| - | - |
| `D.W`, `D.H`, `D.ctx` | Canvas size in CSS pixels and its 2D context. The backing store is scaled for you. |
| `D.safe.top`, `D.safe.bottom` | Status bar and home indicator insets. |
| `D.clip` | True in clip mode. |
| `D.best` | The player's best score in this game, 0 if none. |
| `D.rand()`, `D.randRange(a,b)`, `D.randInt(a,b)`, `D.pick(arr)` | Seeded random numbers. Use these for everything that decides the level, so two phones with the same seed get the same round. `Math.random` is fine for particles. |
| `D.score(n)` | Report the current score while playing. Call it whenever the score changes. |
| `D.end({ score, unit, headline })` | The round is over. `score` is a number, `unit` is what it counts ("floors", "m", "points", "%"), `headline` is a few words for the results screen. Keep drawing afterwards: the app shows results over your last scene. |
| `D.haptic(kind)` | `'light' 'medium' 'heavy' 'success' 'warning' 'error' 'select'`. Use it on every meaningful touch and event. |
| `D.tone({ freq, dur, type, vol, slide })` | A short synth sound. Silent unless the player turned sound on. |
| `D.font(size)`, `D.textFont(size, weight)`, `D.text(str, x, y, opts)`, `D.rr(x, y, w, h, r)` | Big Shoulders Black for numerals and titles, the system font for reading text, and a rounded-rectangle path. |
| `D.clamp`, `D.lerp`, `D.easeOut`, `D.easeInOut`, `D.easeOutBack` | Maths helpers. |

## Rules every game follows

1. Ready state: the game is on screen at once with one short hint in a small capsule near the bottom ("TAP TO DROP"). It starts on the first touch. No menus, no title screen, no countdown.
2. The app draws a close button at the top left and a gold counter at the top right. Keep the rectangle from `y = D.safe.top` to `D.safe.top + 56` free at the left 72 points and the right 120 points. Your own score goes top centre, starting at about `D.safe.top + 60`.
3. Keep touch targets and anything the player must read above `D.H - D.safe.bottom - 16`.
4. Clip mode: the bot plays well, a little imperfectly, and a round lasts 20 to 45 seconds before it ends or is ended. No hint capsule. The app draws a caption over the bottom 250 points and buttons down the right 76 points from 45% to 85% of the height, so keep the action and the score in the upper centre.
5. When the round ends, call `D.end` once, play a short ending (a fall, a flash, a shake) and keep drawing a calm scene.
6. 60 frames a second on an iPhone. Avoid per-frame allocations in hot loops, `shadowBlur` on many shapes and full-screen `getImageData`. Build gradients once per round or per resize.
7. Haptics carry the feel: a light tap for every input, medium for a good hit, success for a perfect or a combo, error for the end.
8. Words: plain and short. No "win", "prize", "reward", "bonus", "jackpot", "lucky", "bet", "spin". No emoji, no exclamation marks in hints.
