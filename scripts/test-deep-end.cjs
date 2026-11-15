/* Headless checks for games/deep-end: answer bank, matching, a full round, clip mode and a small screen. Run: node scripts/test-deep-end.cjs */
const fs = require('fs'); const vm = require('vm');
const path = require('path');
let src = fs.readFileSync(path.join(__dirname, '..', 'games/deep-end/game.js'), 'utf8');
src = src.replace('D.game({', 'window.__t = { lookup: lookup, bankFor: bankFor, PROMPTS: PROMPTS, norm: norm, GLYPH: GLYPH }; window.__s = function () { return { phase: phase, idx: idx, prompts: prompts, input: input, points: points, results: results, krill: krill, cam: cam, timeLeft: timeLeft }; };\n  D.game({');
function makeEnv(clip) {
  const ctxStub = new Proxy({}, { get: (t, k) => k in t ? t[k] : (k === 'createPattern' ? () => ({}) : k === 'createRadialGradient' ? () => ({ addColorStop() {} }) : () => {}), set: (t, k, v) => { t[k] = v; return true; } });
  const canvas = () => ({ width: 0, height: 0, getContext: () => ctxStub });
  const calls = { end: [], score: [], haptic: [] };
  let seed = 7; const rand = () => { seed = (seed * 16807) % 2147483647; return (seed - 1) / 2147483646; };
  const D = { W: 390, H: 844, safe: { top: 47, bottom: 34 }, clip: clip, best: 0, ctx: ctxStub, rand, haptic: k => calls.haptic.push(k), tone: () => {}, score: v => calls.score.push(v), end: r => { calls.end.push(r); env.state = 'over'; }, game: impl => { env.impl = impl; } };
  const env = { D, calls, state: 'ready', impl: null };
  const window = { Dailies: D };
  vm.runInNewContext(src, { window, document: { createElement: canvas }, Math, String, Object, Array });
  env.t = window.__t; env.s = window.__s;
  return env;
}
const fail = []; const note = [];
const env = makeEnv(false);
const T = env.t;
// 1-2: data checks
T.PROMPTS.forEach((p, i) => {
  if (p.t.length !== 6) fail.push('tiers ' + p.q);
  for (const ch of p.q) if (ch !== ' ' && !T.GLYPH[ch]) fail.push('glyph ' + ch + ' in ' + p.q);
  const bank = T.bankFor(i);
  const seen = {};
  p.t.forEach((tier, ti) => tier.split(',').forEach(e => e.split('/').forEach(n => {
    const k = T.norm(n); if (!k) { fail.push('empty alias in ' + p.q); return; }
    if (seen[k] && seen[k] !== e.trim()) note.push('dup ' + p.q + ': ' + n.trim() + ' (tier ' + (ti + 1) + ') vs ' + seen[k]);
    seen[k] = seen[k] || e.trim();
  })));
  bank.list.forEach(it => { if (/[^A-Z ]/.test(it.name)) fail.push('name chars ' + it.name); if (it.name.length > 30) note.push('long name ' + it.name); });
});
// 3: lookup cases
const find = q => T.PROMPTS.findIndex(p => p.q === q);
const cases = [
  ['NAME A NOODLE DISH', 'spagetti', 'SPAGHETTI'], ['NAME A NOODLE DISH', 'Pad Thai', 'PAD THAI'], ['NAME A NOODLE DISH', 'pasta', null], ['NAME A NOODLE DISH', 'ramn', null],
  ['NAME A NOODLE DISH', 'phở', 'PHO'], ['NAME A COUNTRY IN AFRICA', 'the gambia', 'GAMBIA'], ['NAME A COUNTRY IN AFRICA', 'côte d’ivoire', 'IVORY COAST'],
  ['NAME A MUSICAL INSTRUMENT', 'theremin', 'THEREMIN'], ['NAME A HERB OR SPICE', 'clove', 'CLOVES'], ['NAME A BIRD', 'eagles', 'EAGLE'],
  ['NAME A BIRD', 'flamingoe', 'FLAMINGO'], ['NAME A CHEESE', 'gruyère', 'GRUYERE'], ['NAME AN OCEAN ANIMAL', 'killer whale', 'ORCA'],
  ['NAME A COLOR', 'grey', 'GRAY'], ['NAME A COLOR', 'reds', 'RED'], ['NAME A COLOR', 'bleu', null], ['NAME A BONE IN THE HUMAN BODY', 'vertebrae', 'VERTEBRA'],
  ['NAME A DOG BREED', 'lab', 'LABRADOR'], ['NAME A CAR BRAND', 'mercedes-benz', 'MERCEDES'], ['NAME A FRUIT', '   ', null]
];
cases.forEach(([q, input, want]) => { const i = find(q); const r = T.lookup(T.bankFor(i), input); const got = r ? r.name : null; if (got !== want) fail.push('lookup ' + q + ' "' + input + '" -> ' + got + ' want ' + want); });
// 5: end-to-end play
function run(env, plan) {
  const { impl, D, calls } = env; impl.reset(1); env.state = 'ready';
  impl.draw(D.ctx, D.W, D.H, 'ready');
  env.state = 'playing'; impl.start();
  let t = 0, guard = 0;
  while (env.state !== 'over' && guard++ < 20000) {
    const s = env.s();
    const act = plan(s, t, env);
    impl.update(1 / 60, env.state); t += 1 / 60;
    if (guard % 7 === 0) impl.draw(D.ctx, D.W, D.H, env.state);
  }
  for (let i = 0; i < 120; i++) { impl.update(1 / 60, env.state); impl.draw(D.ctx, D.W, D.H, env.state); }
  return t;
}
const typed = {};
const t1 = run(env, (s, t, e) => {
  if (s.phase !== 'answer') return;
  const key = s.idx + ':' + (typed[s.idx] || 0);
  if (typed[s.idx] === undefined) typed[s.idx] = 0;
  if (s.idx === 2) return; // let prompt 3 time out
  const bank = T.bankFor(T.PROMPTS.indexOf(s.prompts[s.idx]));
  if (s.idx === 1 && typed[1] === 0) { for (const ch of 'zzzz') e.impl.key(ch); e.impl.key('Enter'); typed[1] = 1; for (let i = 0; i < 4; i++) e.impl.key('Backspace'); return; }
  if (typed[s.idx] >= 2) return;
  const tierWanted = (s.idx % 6) + 1;
  const item = bank.list.find(x => x.tier === tierWanted) || bank.list[0];
  for (const ch of item.name.toLowerCase()) e.impl.key(ch === ' ' ? ' ' : ch);
  // pointer path for DIVE on even prompts
  if (s.idx % 2 === 0) e.impl.pointerDown(390 - 16 - 40, 561, 1, false); else e.impl.key('Enter');
  typed[s.idx] = 2;
});
const s1 = env.s();
if (env.calls.end.length !== 1) fail.push('end calls ' + env.calls.end.length);
const end = env.calls.end[0] || {};
if (end.score !== s1.points * 10) fail.push('end score ' + end.score + ' vs points ' + s1.points);
if (s1.results.length !== 7) fail.push('results ' + s1.results.length);
if (s1.results[2].pts !== 0) fail.push('timeout prompt scored');
note.push('play: ' + JSON.stringify(end) + ' in ' + t1.toFixed(1) + 's, results ' + s1.results.map(r => r.pts).join(','));
note.push('haptics sample ' + env.calls.haptic.slice(0, 12).join(','));
// restart reuse
env.calls.end.length = 0;
const t1b = run(env, (s, t, e) => { if (s.phase === 'answer') { e.impl.key('a'); } });
if (env.calls.end.length !== 1 || env.calls.end[0].score !== 0) fail.push('restart all-timeout run: ' + JSON.stringify(env.calls.end));
// 6: clip bot
for (let k = 0; k < 5; k++) {
  const ce = makeEnv(true);
  ce.impl.reset(k + 3); ce.state = 'playing'; ce.impl.start();
  let t = 0, g = 0;
  while (ce.state !== 'over' && g++ < 6000) { ce.impl.bot(1 / 30); ce.impl.update(1 / 30, ce.state); t += 1 / 30; if (g % 5 === 0) ce.impl.draw(ce.D.ctx, 390, 844, ce.state); }
  note.push('clip ' + k + ': ' + t.toFixed(1) + 's ' + JSON.stringify(ce.calls.end[0]));
  if (ce.state !== 'over') fail.push('clip did not end');
  if (t < 18 || t > 46) fail.push('clip length ' + t.toFixed(1));
}
// small screen layout + resize
const small = makeEnv(false); small.D.W = 320; small.D.H = 568; small.D.safe = { top: 20, bottom: 0 };
small.impl.resize(320, 568); small.impl.reset(2); small.impl.draw(small.D.ctx, 320, 568, 'ready'); small.state = 'playing'; small.impl.start();
for (let i = 0; i < 200; i++) { small.impl.update(1/60, 'playing'); small.impl.draw(small.D.ctx, 320, 568, 'playing'); }
note.forEach(n => console.log(n));
if (fail.length) { fail.forEach(f => console.error('FAIL ' + f)); process.exit(1); }
console.log('deep-end: all checks passed');
