/* Spiral Drop. Drag to turn the tower, drop the ball through the gaps, keep off the red. */
(function () {
  'use strict';
  var D = window.Dailies, ctx = D.ctx;
  var PI = Math.PI, TAU = PI * 2, SEGN = 12, SA = TAU / SEGN;
  var T_GAP = 0, T_SAFE = 1, T_RED = 2, T_LIME = 3, T_PAD = 4, T_KEEP = 5;
  var FLOORS = 14, PER = FLOORS + 1;
  var BALL_A = PI * 0.62, CA = Math.cos(BALL_A), SNA = Math.sin(BALL_A);
  var G = 14.5, V0 = 4.25, VMAX = 10, TILT = 0.36, FOGN = 12, SENS = 0.85, BOT_V = 6.5, BOT_ACC = 55;
  var HINT = 'DRAG TO TURN';

  var THEMES = [
    { bg: ['#07507e', '#3fd0c2', '#1a7cc4', '#0a3a92'], col: ['#70c8f4', '#2f8fd6', '#1b5ea8'], rim: ['#ffb650', '#f6892a', '#d25e18'], fog: '#0d4a9a' },
    { bg: ['#27148a', '#6a4cf0', '#4a2cc4', '#330f86'], col: ['#b592ff', '#7c48ea', '#5126b6'], rim: ['#92f6ec', '#3dd3cd', '#1f9cab'], fog: '#3c1894' },
    { bg: ['#6c1262', '#f0569f', '#ae2a98', '#540f7c'], col: ['#ffaedb', '#f2569f', '#b22a76'], rim: ['#ffea8c', '#ffc932', '#da9212'], fog: '#5c1284' },
    { bg: ['#075a54', '#4cdc92', '#16987a', '#084660'], col: ['#92f6be', '#30c084', '#14865a'], rim: ['#d6b2ff', '#9c6eff', '#6a3ed4'], fog: '#0a5266' },
    { bg: ['#141c68', '#5582f2', '#2a4ec8', '#111662'], col: ['#ffdc8c', '#f5a730', '#c27218'], rim: ['#ffaabc', '#ff6088', '#d43662'], fog: '#161e6e' }
  ];
  var SAND = ['#fff1d6', '#f8dab0', '#e6bb88'], REDT = ['#ff8078', '#f04a5c', '#d42e4c'], REDR = ['#dc3c50', '#b7243e', '#8c1630'];
  var LIMET = ['#e4fb72', '#b9ea3a', '#96d024'], LIMER = ['#98d830', '#70ba1f', '#509214'];
  var PCOL = ['#b8f03a', '#ffffff', '#ff5a66', '#ffd23f', '#5fe0ff', '#ff8ad0', '#f8dab0'];

  function rgb(h) { var n = parseInt(h.slice(1), 16); return [(n >> 16) & 255, (n >> 8) & 255, n & 255]; }
  function mixc(a, b, t) {
    return 'rgb(' + Math.round(a[0] + (b[0] - a[0]) * t) + ',' + Math.round(a[1] + (b[1] - a[1]) * t) + ',' + Math.round(a[2] + (b[2] - a[2]) * t) + ')';
  }
  function rgbs(arr) { return arr.map(rgb); }
  var BLACK = [0, 0, 0];
  var i0;
  for (i0 = 0; i0 < THEMES.length; i0++) {
    THEMES[i0].colC = rgbs(THEMES[i0].col); THEMES[i0].rimC = rgbs(THEMES[i0].rim); THEMES[i0].fogC = rgb(THEMES[i0].fog);
  }
  var SANDC = rgbs(SAND), REDTC = rgbs(REDT), REDRC = rgbs(REDR), LIMETC = rgbs(LIMET), LIMERC = rgbs(LIMER);

  function xorshift(seed) {
    var s = ((seed + 1) * 2654435761) >>> 0 || 1;
    return function () { s ^= s << 13; s >>>= 0; s ^= s >>> 17; s ^= s << 5; s >>>= 0; return s / 4294967296; };
  }
  function clamp(v, a, b) { return v < a ? a : v > b ? b : v; }
  function wrap(a) { a -= Math.floor(a / TAU) * TAU; return a > PI ? a - TAU : a; }

  /* layout */
  var W = 0, H = 0, S = 1, cx = 0, R = 0, RIN = 0, TH = 0, GP = 0, BR = 0, RP = 0, anchorY = 0;
  var pals = {}, bgSlot = [{ c: null, t: -1 }, { c: null, t: -1 }], kelpC = null, KT = 1, ballG = null, trailG = null, hotG = null, shadeG = null, glowG = null;

  function mkCanvas(w, h) {
    var c = document.createElement('canvas');
    c.width = Math.ceil(w * D.dpr); c.height = Math.ceil(h * D.dpr);
    return c;
  }
  function paintBg(slot, t) {
    var x = slot.c.getContext('2d'), b = THEMES[t].bg, g = x.createLinearGradient(0, 0, 0, H), i, rx;
    if (slot.t === t) return;
    slot.t = t;
    x.setTransform(D.dpr, 0, 0, D.dpr, 0, 0);
    g.addColorStop(0, b[0]); g.addColorStop(0.27, b[1]); g.addColorStop(0.62, b[2]); g.addColorStop(1, b[3]);
    x.fillStyle = g; x.fillRect(0, 0, W, H);
    x.fillStyle = 'rgba(255,255,255,0.05)';
    for (i = 0; i < 3; i++) {
      rx = W * (0.2 + i * 0.3);
      x.beginPath(); x.moveTo(rx - 16 * S, 0); x.lineTo(rx + 22 * S, 0); x.lineTo(rx + 70 * S + i * 20, H * 0.75); x.lineTo(rx - 50 * S + i * 20, H * 0.75); x.closePath(); x.fill();
    }
  }
  function paintKelp() {
    var sp = 31 * S, x, col, i, k, lx, ly;
    KT = sp * 8;
    kelpC = mkCanvas(84 * S, KT);
    x = kelpC.getContext('2d'); x.setTransform(D.dpr, 0, 0, D.dpr, 0, 0);
    for (col = 1; col >= 0; col--) {
      x.fillStyle = col ? 'rgba(0,24,70,0.13)' : 'rgba(255,255,255,0.075)';
      x.beginPath();
      for (i = 0; i < 8; i++) {
        lx = (12 + col * 27) * S + Math.sin(i * TAU / 8 * (col ? 1 : 2) + col * 1.7) * 6 * S;
        for (k = -1; k <= 1; k++) {
          ly = (i + 0.5) * sp + k * KT;
          x.moveTo(lx + 30 * S, ly); x.ellipse(lx, ly, 30 * S, 12 * S, 0.3, 0, TAU);
        }
      }
      x.fill();
    }
  }
  function layout() {
    var i;
    W = D.W; H = D.H;
    S = Math.max(0.6, Math.min(W / 390, H / 844));
    cx = W / 2; R = 124 * S; RIN = 21 * S; TH = 13 * S; GP = 72 * S; BR = 17 * S; RP = R * 0.62;
    anchorY = Math.round(H * (D.clip ? 0.39 : 0.41));
    pals = {};
    for (i = 0; i < 2; i++) { bgSlot[i].c = mkCanvas(W, H); bgSlot[i].t = -1; }
    paintKelp();
    ballG = ctx.createRadialGradient(-0.32, -0.38, 0.04, 0, 0, 1);
    ballG.addColorStop(0, '#f8ffc4'); ballG.addColorStop(0.3, '#c4f64a'); ballG.addColorStop(0.75, '#74c81e'); ballG.addColorStop(1, '#3d8a10');
    trailG = ctx.createLinearGradient(0, 0, 0, -1);
    trailG.addColorStop(0, 'rgba(190,245,70,0.75)'); trailG.addColorStop(1, 'rgba(190,245,70,0)');
    hotG = ctx.createLinearGradient(0, 0, 0, -1);
    hotG.addColorStop(0, 'rgba(255,250,150,0.95)'); hotG.addColorStop(0.4, 'rgba(200,245,80,0.6)'); hotG.addColorStop(1, 'rgba(160,240,90,0)');
    shadeG = ctx.createLinearGradient(0, 0, 0, 1);
    shadeG.addColorStop(0, 'rgba(0,10,40,0.42)'); shadeG.addColorStop(1, 'rgba(0,10,40,0)');
    glowG = ctx.createRadialGradient(0, 0, 0.2, 0, 0, 1);
    glowG.addColorStop(0, 'rgba(240,255,140,0.55)'); glowG.addColorStop(1, 'rgba(240,255,140,0)');
  }

  function hgrad(stops, fog, ft, x0, x1) {
    var g = ctx.createLinearGradient(x0, 0, x1, 0), i;
    for (i = 0; i < stops.length; i++) g.addColorStop(i / (stops.length - 1), mixc(stops[i], fog, ft));
    return g;
  }
  function dark(c, k) { return [c[0] * k, c[1] * k, c[2] * k]; }
  function getPal(t) {
    var key = t * 8 + bgTo, P = pals[key], f, ft, th, fog;
    if (P) return P;
    th = THEMES[t]; fog = THEMES[bgTo].fogC;
    P = { top: [], rim: [], red: [], redRim: [], lime: [], limeRim: [], col: [], side: [], sideRed: [], sideLime: [] };
    for (f = 0; f < FOGN; f++) {
      ft = f / (FOGN - 1); ft = ft * 0.84;
      P.top.push(hgrad(SANDC, fog, ft, cx - R, cx + R));
      P.rim.push(hgrad(th.rimC, fog, ft, cx - R, cx + R));
      P.red.push(hgrad(REDTC, fog, ft, cx - R, cx + R));
      P.redRim.push(hgrad(REDRC, fog, ft, cx - R, cx + R));
      P.lime.push(hgrad(LIMETC, fog, ft, cx - R, cx + R));
      P.limeRim.push(hgrad(LIMERC, fog, ft, cx - R, cx + R));
      P.col.push(hgrad(THEMES[bgTo].colC, fog, ft, cx - RIN, cx + RIN));
      P.side.push(mixc(dark(th.rimC[2], 0.82), fog, ft));
      P.sideRed.push(mixc(dark(REDRC[2], 0.85), fog, ft));
      P.sideLime.push(mixc(dark(LIMERC[2], 0.85), fog, ft));
    }
    pals[key] = P;
    return P;
  }

  /* round state */
  var plats = [], genLevelN = 1, lastGapA = null, lastGapW = 0;
  var rot = 0, rotVel = 0, rotEff = 0, dragging = false, dragId = -1, lastX = 0, lastMoveT = 0;
  var ball = { y: 0, vy: 0, sq: 0 };
  var camY = 0, camT = 0, score = 0, scoreStr = '0', scorePop = 0, level = 1, streak = 0, passedIdx = -1, progShow = 0;
  var dead = false, deadT = 0, shake = 0, flash = 0, flashCol = '#fff', bgFrom = 0, bgTo = 0, bgT = 1, time = 0, flight = 0;
  var comboN = 0, comboT = 9, comboPunch = 0, bannerT = 9, bannerText = '', pipPop = 0, hitRed = null;
  var bubbles = [], deco = null;

  var PN = 240, px = new Float32Array(PN), py = new Float32Array(PN), pvx = new Float32Array(PN), pvy = new Float32Array(PN);
  var pl = new Float32Array(PN), pm = new Float32Array(PN), ps = new Float32Array(PN), pg = new Float32Array(PN), pc = new Uint8Array(PN), pHead = 0;
  var DN = 44, debris = [], dHead = 0, RN = 6, rings = [], rHead = 0, UN = 8, pops = [], uHead = 0;
  for (i0 = 0; i0 < DN; i0++) debris.push({ on: false, yAbs: 0, ox: 0, oy: 0, vx: 0, vy: 0, ang: 0, va: 0, a0: 0, a1: 0, c: 0, s: 0, type: 1, P: null, life: 0, max: 1 });
  for (i0 = 0; i0 < RN; i0++) rings.push({ on: false, yAbs: 0, t: 0, max: 1, hot: false });
  for (i0 = 0; i0 < UN; i0++) pops.push({ on: false, text: '', x: 0, yAbs: 0, t: 0, max: 1, size: 20, color: '#fff' });

  var bot = { i: -1, target: 0, wait: 0, vel: 0, fx: 0, t: 0, failAt: 34, flight: -1, rng: null, down: false, idle: false, lazy: 0.5, vmax: 6.5, scanGap: false, scanDist: 9, scanBad: false };

  /* level generation: every random choice comes from D.rand */
  function makePlat(L, j, theme, finish) {
    var segs = new Uint8Array(SEGN), i, k, w, s2, nRed = 0, safeN, pick, lastRed = -1, n, gapA;
    var p = { segs: segs, off: 0, spin: 0, level: L, theme: theme, finish: !!finish, broken: false, dip: 0, runs: [], gaps: [], hasRed: false, spa: [0, 0, 0], spt: [-99, -99, -99], spn: 0 };
    if (finish) {
      for (i = 0; i < SEGN; i++) segs[i] = i % 2 ? T_PAD : T_LIME;
      p.off = D.rand() * TAU;
    } else {
      for (i = 0; i < SEGN; i++) segs[i] = T_SAFE;
      w = L === 1 && j === 0 ? 3 : (D.rand() < (L === 1 ? 0.5 : 0.22) ? 3 : 2);
      for (i = 0; i < w; i++) segs[i] = T_GAP;
      if (L >= 2 && j > 0 && D.rand() < Math.min(0.4, 0.12 * (L - 1))) {
        s2 = w + 2 + D.randInt(0, SEGN - w - 6);
        segs[s2] = T_GAP; segs[s2 + 1] = T_GAP;
      }
      if (j > 0) {
        if (L === 1) nRed = j < 3 ? 0 : (D.rand() < 0.45 ? 1 : 0) + (j > 9 && D.rand() < 0.3 ? 1 : 0);
        else if (L === 2) nRed = D.randInt(1, 2);
        else if (L === 3) nRed = D.randInt(1, 3);
        else if (L === 4) nRed = D.randInt(2, 3);
        else if (L < 7) nRed = D.randInt(2, 4);
        else nRed = D.randInt(3, 5);
      }
      if (lastGapA !== null && j > 0 && D.rand() < 0.5) gapA = lastGapA + D.randRange(-0.5, 0.5);
      else gapA = D.rand() * TAU;
      p.off = gapA - w * SA / 2;
      if (lastGapA !== null) {
        for (i = w; i < SEGN; i++) if (segs[i] === T_SAFE && Math.abs(wrap(p.off + (i + 0.5) * SA - lastGapA)) < lastGapW + SA * 0.5) segs[i] = T_KEEP;
      }
      lastGapA = gapA; lastGapW = w * SA / 2;
      for (k = 0; k < nRed; k++) {
        safeN = 0;
        for (i = 0; i < SEGN; i++) if (segs[i] === T_SAFE) safeN++;
        if (safeN <= 4) break;
        pick = -1;
        if (lastRed >= 0 && D.rand() < 0.5) {
          if (segs[(lastRed + 1) % SEGN] === T_SAFE) pick = (lastRed + 1) % SEGN;
          else if (segs[(lastRed + SEGN - 1) % SEGN] === T_SAFE) pick = (lastRed + SEGN - 1) % SEGN;
        }
        if (pick < 0) {
          n = D.randInt(0, safeN - 1);
          for (i = 0; i < SEGN; i++) if (segs[i] === T_SAFE && n-- === 0) { pick = i; break; }
        }
        segs[pick] = T_RED; lastRed = pick;
      }
      for (i = 0; i < SEGN; i++) if (segs[i] === T_KEEP) segs[i] = T_SAFE;
      if (L >= 2 && j > 0 && D.rand() < Math.min(0.45, 0.1 + 0.07 * (L - 1))) {
        p.spin = (D.rand() < 0.5 ? -1 : 1) * D.randRange(0.45, Math.min(1.5, 0.8 + 0.12 * L));
      }
    }
    buildRuns(p);
    return p;
  }
  function buildRuns(p) {
    var segs = p.segs, start = 0, i, k = 0, s, t, n;
    for (i = 0; i < SEGN; i++) if (segs[i] !== segs[(i + SEGN - 1) % SEGN]) { start = i; break; }
    while (k < SEGN) {
      s = (start + k) % SEGN; t = segs[s]; n = 1;
      while (k + n < SEGN && segs[(start + k + n) % SEGN] === t) n++;
      if (t === T_GAP) p.gaps.push({ c: (s + n / 2) * SA, hw: n * SA / 2 });
      else p.runs.push({ s: s, n: n, type: t, os: segs[(s + SEGN - 1) % SEGN] === T_GAP, oe: segs[(s + n) % SEGN] === T_GAP });
      if (t === T_RED) p.hasRed = true;
      k += n;
    }
  }
  function genLevel() {
    var L = genLevelN++, theme = (L - 1) % THEMES.length, j;
    for (j = 0; j < FLOORS; j++) plats.push(makePlat(L, j, theme, false));
    plats.push(makePlat(L, FLOORS, theme, true));
  }

  /* effects */
  function spawnP(x, yAbs, vx, vy, life, size, col, grav) {
    var i = pHead; pHead = (pHead + 1) % PN;
    px[i] = x; py[i] = yAbs; pvx[i] = vx; pvy[i] = vy; pl[i] = life; pm[i] = life; ps[i] = size; pc[i] = col; pg[i] = grav;
  }
  function burst(x, yAbs, n, col, speed, up, size) {
    var k, a, sp;
    for (k = 0; k < n; k++) {
      a = Math.random() * TAU; sp = speed * (0.35 + Math.random() * 0.8) * S;
      spawnP(x, yAbs, Math.cos(a) * sp, Math.sin(a) * sp * 0.55 - up * S * (0.5 + Math.random()), 0.35 + Math.random() * 0.4, (size || 3) * S * (0.6 + Math.random() * 0.8), col < 0 ? 3 + ((Math.random() * 3) | 0) : col, 900 * S);
    }
  }
  function addDebris(i, a0, a1, type, P, power) {
    var d = debris[dHead], am = (a0 + a1) / 2, sp = (240 + Math.random() * 240) * S * power;
    dHead = (dHead + 1) % DN;
    d.on = true; d.yAbs = i * GP; d.ox = 0; d.oy = 0; d.c = Math.cos(am); d.s = Math.sin(am);
    d.vx = d.c * sp; d.vy = d.s * sp * 0.45 - (70 + Math.random() * 170) * S * power;
    d.ang = 0; d.va = (Math.random() - 0.5) * 7 * power; d.a0 = a0; d.a1 = a1; d.type = type; d.P = P;
    d.life = d.max = 0.5 + Math.random() * 0.3;
  }
  function shatter(p, i, power) {
    var base = rotEff + p.off, P = getPal(p.theme), r, run, k, n, a0;
    for (r = 0; r < p.runs.length; r++) {
      run = p.runs[r]; k = 0;
      while (k < run.n) { n = Math.min(2, run.n - k); a0 = base + (run.s + k) * SA; addDebris(i, a0, a0 + n * SA, run.type, P, power); k += n; }
    }
  }
  function addRing(i, hot) {
    var r = rings[rHead]; rHead = (rHead + 1) % RN;
    r.on = true; r.yAbs = i * GP; r.t = 0; r.max = hot ? 0.5 : 0.36; r.hot = hot;
  }
  function popup(text, x, yAbs, size, color, life) {
    var u = pops[uHead]; uHead = (uHead + 1) % UN;
    u.on = true; u.text = text; u.x = x; u.yAbs = yAbs; u.t = 0; u.max = life || 0.8; u.size = size; u.color = color || '#fff';
  }
  function haptic(k) { if (D.state() === 'playing') D.haptic(k); }
  function addScore(n) {
    score += n; scoreStr = String(score); scorePop = 1;
    popup('+' + n, cx + CA * RP - (38 + (uHead % 2) * 22) * S, anchorY + clamp(ball.y - camY, -0.5, 0.8) * GP + SNA * RP * TILT - BR * 2.4, (20 + Math.min(10, streak * 2)) * S, streak >= 2 ? '#fff27a' : '#ffffff');
  }

  /* collisions */
  function typeAtBall(p) {
    var a = BALL_A - rotEff - p.off, f, idx, fr, t, n;
    a -= Math.floor(a / TAU) * TAU;
    f = a / SA; idx = Math.floor(f) % SEGN; fr = f - Math.floor(f); t = p.segs[idx];
    if (t === T_RED) {
      if (fr < 0.24) { n = p.segs[(idx + SEGN - 1) % SEGN]; if (n !== T_RED) t = n; }
      else if (fr > 0.76) { n = p.segs[(idx + 1) % SEGN]; if (n !== T_RED) t = n; }
    }
    return t;
  }
  function splat(p) {
    var k = p.spn % 3, a = BALL_A - rotEff - p.off;
    p.spa[k] = a + (Math.random() - 0.5) * 0.12; p.spt[k] = time; p.spn++;
  }
  function passFloor(p, i) {
    p.broken = true; passedIdx = i; streak++; flight++;
    shatter(p, i, streak >= 2 ? 1.25 : 0.9);
    addRing(i, streak >= 2);
    addScore(level * streak);
    if (streak >= 2) {
      comboN = streak; comboT = 0; comboPunch = 1;
      burst(cx + CA * RP, i * GP + SNA * RP * TILT, 5, 1, 150, 40, 2.4);
    }
    haptic('select');
    D.tone({ freq: 480 + Math.min(streak, 8) * 70, dur: 0.09, type: 'triangle', vol: 0.09, slide: 760 + streak * 70 });
  }
  function smash(p, i) {
    var pts = p.finish ? level * 5 * Math.max(1, streak) : level * streak * 2, wasCombo = streak >= 2, tmp;
    p.broken = true; passedIdx = i; flight++;
    shatter(p, i, 1.7);
    addRing(i, true);
    burst(cx + CA * RP, i * GP + SNA * RP * TILT, 14, p.finish ? -1 : 6, 300, 120, 3.4);
    ball.y = i - 0.001; ball.vy = -V0 * 0.94; ball.sq = 1;
    shake = Math.max(shake, p.finish ? 0.75 : 0.6);
    if (wasCombo) { comboN = streak; comboT = 0; comboPunch = 1.4; }
    addScore(pts);
    streak = 0;
    if (p.finish) {
      level++; bgFrom = bgTo; bgTo = (level - 1) % THEMES.length; bgT = 0;
      tmp = bgSlot[0]; bgSlot[0] = bgSlot[1]; bgSlot[1] = tmp; paintBg(bgSlot[0], bgTo);
      flash = 0.5; flashCol = '#ffffff'; bannerT = 0; bannerText = 'LEVEL ' + level; pipPop = 1;
      burst(cx, i * GP, 26, -1, 420, 260, 4);
      haptic('success');
      D.tone({ freq: 620, dur: 0.3, type: 'triangle', vol: 0.12, slide: 1240 });
    } else {
      haptic('medium');
      D.tone({ freq: 200, dur: 0.16, type: 'square', vol: 0.08, slide: 70 });
    }
  }
  function bounce(p, i, playing) {
    ball.y = i - 0.001; ball.vy = -V0; ball.sq = 1; p.dip = 1; streak = 0; flight++;
    splat(p);
    burst(cx + CA * RP, i * GP + SNA * RP * TILT, 4, 0, 110, 70, 2.2);
    if (playing) { haptic('light'); D.tone({ freq: 250, dur: 0.07, type: 'sine', vol: 0.08, slide: 170 }); }
  }
  function die(p, i) {
    var bx = cx + CA * RP, yA = ball.y * GP + SNA * RP * TILT;
    dead = true; deadT = 0; shake = 1; flash = 0.55; flashCol = '#ff3048'; hitRed = p || null;
    if (p) { ball.y = i; ball.vy = 0; splat(p); p.dip = 1; }
    burst(bx, yA - BR, 26, 0, 360, 200, 4);
    burst(bx, yA - BR, 10, 2, 260, 120, 3);
    D.haptic('error');
    D.tone({ freq: 320, dur: 0.45, type: 'sawtooth', vol: 0.1, slide: 60 });
    D.end({ score: score, unit: 'points', headline: 'Level ' + level });
  }
  function stepBall(dt, state) {
    var prev = ball.y, i, p, t;
    ball.vy = Math.min(ball.vy + G * dt, VMAX);
    ball.y += ball.vy * dt;
    if (ball.vy <= 0) return;
    i = Math.max(0, Math.floor(prev) + 1);
    while (i <= ball.y && !dead) {
      p = plats[i];
      if (p && !p.broken) {
        t = typeAtBall(p);
        if (state !== 'playing') { bounce(p, i, false); return; }
        if (t === T_GAP) passFloor(p, i);
        else if (p.finish || streak >= 2) { smash(p, i); return; }
        else if (t === T_RED) { die(p, i); return; }
        else { bounce(p, i, true); return; }
      }
      i++;
    }
  }

  /* input */
  function onDown(x, y, id) {
    dragging = true; dragId = id; lastX = x; rotVel = 0; lastMoveT = time;
    D.haptic('light');
  }
  function onMove(x, y, id, down) {
    if (!dragging || id !== dragId || down === false) return;
    var dx = x - lastX, dr = -dx / (R * SENS), gap = Math.max(1 / 120, time - lastMoveT);
    lastX = x; lastMoveT = time;
    rot += dr;
    rotVel = clamp(rotVel * 0.5 + (dr / gap) * 0.5, -14, 14);
  }
  function onUp(x, y, id) {
    if (id !== dragId) return;
    dragging = false; dragId = -1;
    if (time - lastMoveT > 0.08) rotVel = 0;
  }

  /* bot */
  function segType(p, a) { a -= Math.floor(a / TAU) * TAU; return p.segs[Math.floor(a / SA) % SEGN]; }
  function classAt(p, a, m) {
    var t0 = segType(p, a - m), t1 = segType(p, a), t2 = segType(p, a + m);
    if (t0 === T_RED || t1 === T_RED || t2 === T_RED) return 0;
    if (t0 === T_GAP && t1 === T_GAP && t2 === T_GAP) return 3;
    if (t1 === T_GAP) return 1.2;
    if (t0 === T_GAP || t2 === T_GAP) return 1.5;
    return 2;
  }
  function nextAlive() {
    var i = Math.max(0, Math.ceil(ball.y - 1e-6));
    while (i < plats.length && plats[i].broken) i++;
    return i;
  }
  function timeTo(i) {
    var d = Math.max(0, i - ball.y);
    return (-ball.vy + Math.sqrt(ball.vy * ball.vy + 2 * G * d)) / G;
  }
  function gapDist(p, loc) {
    var k, g, d, m = 9;
    for (k = 0; k < p.gaps.length; k++) { g = p.gaps[k]; d = Math.abs(wrap(loc - g.c)) - g.hw; if (d < m) m = d; }
    return m < 0 ? 0 : m;
  }
  function botReach(T, V, A) {
    if (T <= 0) return 0;
    return T <= V / A ? 0.35 * A * T * T : V * (T - 0.65 * V / A);
  }
  function botScan(p, q, aNow, reach, t2, armed) {
    var d, loc, cl, sc, a2, c2, best = -1e9, rnd = bot.rng;
    bot.scanGap = false; bot.scanDist = 9;
    if (reach > PI) reach = PI;
    for (d = -reach; d <= reach + 1e-6; d += 0.1) {
      loc = aNow + d; cl = classAt(p, loc, 0.2);
      if (cl === 3) {
        sc = 10 - Math.abs(d) * 0.7 + rnd() * 0.7;
        if (q) {
          a2 = BALL_A - (rot - d) - q.off - q.spin * t2;
          c2 = q.finish ? 2 : classAt(q, a2, 0.15);
          if (c2 !== 0 && !q.finish && streak === 0 && classAt(q, a2, 0.34) === 0) c2 = 0;
          sc += c2 === 3 ? 4 : c2 === 2 ? 1.5 : c2 !== 0 ? 0 : streak >= 1 ? 1 : (classAt(q, a2 + 0.5, 0.2) >= 1.5 || classAt(q, a2 - 0.5, 0.2) >= 1.5) ? -4 : -30;
        }
      } else if (cl === 2 || (armed && cl === 0)) sc = 3 - gapDist(p, loc) - Math.abs(d) * 0.2 + rnd() * 0.1;
      else if (cl === 0) sc = -100 - Math.abs(d);
      else sc = -6 - Math.abs(d);
      if (sc > best) { best = sc; bot.target = loc; bot.scanGap = cl === 3; bot.scanDist = gapDist(p, loc); bot.scanBad = sc < -50; }
    }
  }
  function botPlan() {
    var i = nextAlive(), p = plats[i], q = plats[i + 1], t = timeTo(i), falling = ball.vy > 1.5, rnd = bot.rng;
    var aNow, armed = streak >= 2, k, c, dr, vX, t2, near = null, nearD = 9, hereOk;
    bot.i = i; bot.vmax = BOT_V;
    bot.wait = falling ? 0 : 0.12 + rnd() * 0.3;
    if (!p) { bot.target = null; return; }
    aNow = BALL_A - rot - p.off - p.spin * t;
    hereOk = classAt(p, aNow, 0.22) === 2;
    if (bot.t > bot.failAt && !armed && !falling && p.hasRed) {
      for (k = 0; k < SEGN; k++) {
        if (p.segs[k] !== T_RED) continue;
        c = (k + 0.5) * SA; dr = Math.abs(wrap(aNow - c));
        if (dr < nearD) { nearD = dr; near = c; }
      }
      if (near !== null && nearD <= botReach(t - bot.wait, BOT_V, BOT_ACC)) { bot.target = aNow + wrap(near - aNow); return; }
    }
    if (p.finish) { bot.target = aNow; return; }
    if (!falling && hereOk && !bot.idle && rnd() < bot.lazy) { bot.idle = true; bot.target = aNow; return; }
    bot.idle = false;
    vX = Math.min(VMAX, Math.sqrt(ball.vy * ball.vy + 2 * G * Math.max(0, i - ball.y)));
    t2 = t + (-vX + Math.sqrt(vX * vX + 2 * G)) / G;
    botScan(p, q, aNow, botReach(t - bot.wait, BOT_V, BOT_ACC), t2, armed);
    if (bot.scanGap || (!bot.scanBad && gapDist(p, aNow) - bot.scanDist > 0.3)) return;
    bot.wait = falling ? 0 : 0.03; bot.vmax = 10;
    botScan(p, q, aNow, botReach(t - bot.wait, 10, BOT_ACC * 1.7), t2, armed);
  }
  function botStep(dt) {
    var p, t, aNow, dr = 0, want, dv, lim = BOT_ACC * (bot.vmax > BOT_V ? 1.7 : 1) * dt;
    bot.t += dt;
    if (dead) return;
    if (!bot.down) { bot.down = true; bot.fx = cx; onDown(bot.fx, H * 0.6, 77); }
    if (bot.t > 43.5 && ball.vy < 0) { die(null, 0); return; }
    if (bot.flight !== flight) { bot.flight = flight; botPlan(); }
    p = plats[bot.i];
    if (bot.wait > 0) bot.wait -= dt;
    else if (p && bot.target !== null) {
      t = timeTo(bot.i);
      aNow = BALL_A - rot - p.off - p.spin * t;
      dr = wrap(aNow - bot.target);
    }
    want = clamp(dr * (bot.vmax > BOT_V ? 15 : 9), -bot.vmax, bot.vmax);
    dv = clamp(want - bot.vel, -lim, lim);
    bot.vel += dv;
    bot.fx -= bot.vel * dt * R * SENS;
    onMove(bot.fx, H * 0.6, 77, true);
  }

  /* drawing */
  function rimPart(y, b0, b1) {
    if (b1 - b0 < 0.004) return;
    ctx.beginPath();
    ctx.ellipse(cx, y, R, R * TILT, 0, b0, b1);
    ctx.ellipse(cx, y + TH, R, R * TILT, 0, b1, b0, true);
    ctx.closePath(); ctx.fill();
  }
  function cutFace(y, a) {
    var c = Math.cos(a), s = Math.sin(a) * TILT;
    ctx.beginPath();
    ctx.moveTo(cx + c * RIN, y + s * RIN); ctx.lineTo(cx + c * R, y + s * R);
    ctx.lineTo(cx + c * R, y + s * R + TH); ctx.lineTo(cx + c * RIN, y + s * RIN + TH);
    ctx.closePath(); ctx.fill();
  }
  function runSides(y, a0, a1, type, os, oe, P, f) {
    var s, e;
    ctx.fillStyle = type === T_RED ? P.sideRed[f] : type >= T_LIME ? P.sideLime[f] : P.side[f];
    if (os && Math.cos(a0) < 0) cutFace(y, a0);
    if (oe && Math.cos(a1) > 0) cutFace(y, a1);
    s = a0 - Math.floor(a0 / TAU) * TAU; e = s + (a1 - a0);
    ctx.fillStyle = type === T_RED ? P.redRim[f] : type >= T_LIME ? P.limeRim[f] : P.rim[f];
    rimPart(y, s, Math.min(e, PI));
    rimPart(y, Math.max(s, TAU), Math.min(e, TAU + PI));
  }
  function runTop(y, a0, a1, type, P, f) {
    ctx.fillStyle = type === T_RED ? P.red[f] : type === T_LIME ? P.lime[f] : P.top[f];
    ctx.beginPath();
    ctx.ellipse(cx, y, R, R * TILT, 0, a0, a1);
    ctx.ellipse(cx, y, RIN, RIN * TILT, 0, a1, a0, true);
    ctx.closePath(); ctx.fill();
  }
  function drawPlat(p, i, y, P, f, alpha) {
    var base = rotEff + p.off, runs = p.runs, n = runs.length, r, run, a0, a1, k, a, c, s, age, sa, d;
    for (r = 0; r < n; r++) {
      run = runs[r]; a0 = base + run.s * SA;
      runSides(y, a0, a0 + run.n * SA, run.type, run.os, run.oe, P, f);
    }
    for (r = 0; r < n; r++) {
      run = runs[r]; a0 = base + run.s * SA; a1 = a0 + run.n * SA + (run.oe ? 0 : 0.008);
      runTop(y, a0, a1, run.type, P, f);
    }
    if (f < 7) {
      ctx.beginPath();
      for (r = 0; r < n; r++) {
        run = runs[r]; a0 = base + run.s * SA;
        for (k = 1; k < run.n; k++) {
          a = a0 + k * SA; c = Math.cos(a); s = Math.sin(a) * TILT;
          ctx.moveTo(cx + c * RIN, y + s * RIN); ctx.lineTo(cx + c * R, y + s * R);
        }
      }
      ctx.strokeStyle = 'rgba(150,84,30,0.14)'; ctx.lineWidth = 1; ctx.stroke();
      ctx.beginPath();
      for (r = 0; r < n; r++) {
        run = runs[r]; a0 = base + run.s * SA; a1 = a0 + run.n * SA;
        ctx.moveTo(cx + Math.cos(a0) * (R - 1), y + Math.sin(a0) * (R - 1) * TILT);
        ctx.ellipse(cx, y, R - 1, (R - 1) * TILT, 0, a0, a1);
      }
      ctx.strokeStyle = 'rgba(255,255,255,0.4)'; ctx.lineWidth = 1.4 * S; ctx.stroke();
    }
    if (hitRed === p && deadT < 0.5) {
      ctx.globalAlpha = alpha * (1 - deadT * 2) * 0.8; ctx.fillStyle = '#ffffff';
      for (r = 0; r < n; r++) {
        run = runs[r];
        if (run.type !== T_RED) continue;
        a0 = base + run.s * SA; ctx.beginPath();
        ctx.ellipse(cx, y, R, R * TILT, 0, a0, a0 + run.n * SA);
        ctx.ellipse(cx, y, RIN, RIN * TILT, 0, a0 + run.n * SA, a0, true);
        ctx.fill();
      }
      ctx.globalAlpha = alpha;
    }
    for (k = 0; k < 3; k++) {
      age = time - p.spt[k];
      if (age > 7) continue;
      sa = base + p.spa[k]; c = Math.cos(sa); s = Math.sin(sa);
      a = cx + c * RP; d = y + s * RP * TILT;
      ctx.globalAlpha = alpha * Math.min(1, (7 - age) / 2) * 0.9;
      ctx.fillStyle = '#93d92c';
      ctx.beginPath();
      ctx.ellipse(a, d, 10 * S, 4.2 * S, 0, 0, TAU);
      ctx.ellipse(a - c * 3 * S + 11 * S * Math.cos(sa * 7), d + 3.4 * S * Math.sin(sa * 7), 3.2 * S, 1.5 * S, 0, 0, TAU);
      ctx.ellipse(a + 12 * S * Math.cos(sa * 13 + 2), d + 4.4 * S * Math.sin(sa * 13 + 2), 2.2 * S, 1.1 * S, 0, 0, TAU);
      ctx.ellipse(a + 15 * S * Math.cos(sa * 5 + 4), d + 5.6 * S * Math.sin(sa * 5 + 4), 1.6 * S, 0.8 * S, 0, 0, TAU);
      ctx.fill();
      ctx.fillStyle = '#c9f562';
      ctx.beginPath(); ctx.ellipse(a - 2 * S, d - 0.8 * S, 5 * S, 1.8 * S, 0, 0, TAU); ctx.fill();
      ctx.globalAlpha = alpha;
    }
  }
  function drawCol(yTop, yBot, P, f, shade) {
    ctx.fillStyle = P.col[f];
    ctx.beginPath();
    ctx.moveTo(cx - RIN, yTop); ctx.lineTo(cx - RIN, yBot);
    ctx.ellipse(cx, yBot, RIN, RIN * TILT, 0, PI, 0, true);
    ctx.lineTo(cx + RIN, yTop); ctx.closePath(); ctx.fill();
    if (shade) {
      ctx.save(); ctx.translate(cx, yTop + TH * 0.4); ctx.scale(1, Math.min(GP * 0.55, yBot - yTop));
      ctx.fillStyle = shadeG; ctx.fillRect(-RIN, 0, RIN * 2, 1); ctx.restore();
    }
  }
  function drawCap(y, P) {
    var w = RIN * 1.36, h = 8 * S;
    ctx.fillStyle = P.rim[0];
    ctx.beginPath(); ctx.ellipse(cx, y, w, w * TILT, 0, 0, PI); ctx.ellipse(cx, y - h, w, w * TILT, 0, PI, 0, true); ctx.closePath(); ctx.fill();
    ctx.fillStyle = P.rim[0];
    ctx.beginPath(); ctx.ellipse(cx, y - h, w, w * TILT, 0, 0, TAU); ctx.fill();
    ctx.fillStyle = 'rgba(255,255,255,0.38)';
    ctx.beginPath(); ctx.ellipse(cx, y - h, w * 0.62, w * 0.62 * TILT, 0, 0, TAU); ctx.fill();
  }
  function drawBg() {
    var i, n, x, off, sw, b, by;
    if (bgT < 1 && bgSlot[1].t >= 0) {
      ctx.drawImage(bgSlot[1].c, 0, 0, W, H);
      ctx.globalAlpha = D.easeInOut(bgT); ctx.drawImage(bgSlot[0].c, 0, 0, W, H); ctx.globalAlpha = 1;
    } else ctx.drawImage(bgSlot[0].c, 0, 0, W, H);
    off = (camY * GP * 0.36) % KT; n = Math.ceil((H + off) / KT);
    sw = Math.sin(time * 0.9) * 5 * S - 8 * S;
    for (i = 0; i < n; i++) ctx.drawImage(kelpC, sw, i * KT - off, 84 * S, KT);
    sw = Math.sin(time * 0.9 + 2) * 5 * S - 8 * S;
    ctx.save(); ctx.translate(W, 0); ctx.scale(-1, 1);
    for (i = 0; i < n; i++) ctx.drawImage(kelpC, sw, i * KT - off - KT * 0.4, 84 * S, KT);
    ctx.drawImage(kelpC, sw, n * KT - off - KT * 0.4, 84 * S, KT);
    ctx.restore();
    ctx.beginPath();
    for (i = 0; i < bubbles.length; i++) {
      b = bubbles[i];
      by = H + 30 - ((b.y * (H + 60) + time * b.sp + camY * GP * b.par) % (H + 60));
      x = b.x * W + Math.sin(time * 0.8 + b.ph) * 6;
      b.sx = x; b.sy = by;
      ctx.moveTo(x + b.r * S, by); ctx.arc(x, by, b.r * S, 0, TAU);
    }
    ctx.strokeStyle = 'rgba(255,255,255,0.38)'; ctx.lineWidth = 1.3; ctx.stroke();
    ctx.fillStyle = 'rgba(255,255,255,0.1)'; ctx.fill();
    ctx.beginPath();
    for (i = 0; i < bubbles.length; i++) {
      b = bubbles[i];
      ctx.moveTo(b.sx, b.sy); ctx.arc(b.sx - b.r * S * 0.38, b.sy - b.r * S * 0.38, b.r * S * 0.22, 0, TAU);
    }
    ctx.fillStyle = 'rgba(255,255,255,0.6)'; ctx.fill();
  }
  function drawBall(bx, by) {
    var sp = ball.vy > 0 ? ball.vy / VMAX : 0, hot = streak >= 2, len, sy, sx;
    if (sp > 0.22 || hot) {
      len = BR * (1 + sp * 5.5 + (hot ? 2.2 : 0));
      ctx.save(); ctx.translate(bx, by); ctx.scale(BR * (hot ? 1.05 : 0.86), len);
      ctx.fillStyle = hot ? hotG : trailG;
      ctx.beginPath(); ctx.moveTo(-1, 0); ctx.quadraticCurveTo(-0.34, -0.55, 0, -1); ctx.quadraticCurveTo(0.34, -0.55, 1, 0); ctx.closePath(); ctx.fill();
      ctx.restore();
    }
    if (hot) {
      ctx.save(); ctx.translate(bx, by); ctx.scale(BR * 2.5, BR * 2.5); ctx.fillStyle = glowG;
      ctx.beginPath(); ctx.arc(0, 0, 1, 0, TAU); ctx.fill(); ctx.restore();
    }
    sy = 1 - 0.36 * ball.sq + 0.22 * sp; sx = 1 + 0.3 * ball.sq - 0.1 * sp;
    ctx.save(); ctx.translate(bx, by + BR * (1 - sy) * (ball.sq > 0.02 ? 1 : 0)); ctx.scale(BR * sx, BR * sy);
    ctx.fillStyle = ballG; ctx.beginPath(); ctx.arc(0, 0, 1, 0, TAU); ctx.fill();
    ctx.strokeStyle = 'rgba(40,100,10,0.45)'; ctx.lineWidth = 0.07; ctx.stroke();
    ctx.fillStyle = 'rgba(255,255,255,0.85)';
    ctx.beginPath(); ctx.ellipse(-0.36, -0.46, 0.27, 0.15, -0.65, 0, TAU); ctx.fill();
    ctx.fillStyle = 'rgba(255,255,255,0.5)';
    ctx.beginPath(); ctx.arc(-0.62, -0.1, 0.07, 0, TAU); ctx.fill();
    ctx.restore();
  }
  function drawHud(state) {
    var top = D.safe.top, hs = Math.min(1.15, W / 390), y = top + 60 + 48 * hs, sc = 1 + 0.16 * scorePop, bw = 58 * hs, by = y + 24 * hs, r = 11.5 * hs, k, x0, x1, pp;
    ctx.save(); ctx.translate(cx, y); ctx.scale(sc, sc);
    D.text(scoreStr, 0, 4, { size: 64 * hs, color: 'rgba(0,30,70,0.32)' });
    D.text(scoreStr, 0, 0, { size: 64 * hs, color: '#ffffff' });
    ctx.restore();
    x0 = cx - bw + r + 3; x1 = cx + bw - r - 3;
    ctx.fillStyle = 'rgba(0,20,60,0.3)'; D.rr(x0, by - 3 * hs, x1 - x0, 6 * hs, 3 * hs); ctx.fill();
    k = clamp(progShow, 0, 1);
    ctx.fillStyle = '#c4f64a'; D.rr(x0, by - 3 * hs, Math.max(6 * hs, (x1 - x0) * k), 6 * hs, 3 * hs); ctx.fill();
    ctx.beginPath(); ctx.arc(x0 + Math.max(3 * hs, (x1 - x0) * k), by, 4.6 * hs, 0, TAU); ctx.fill();
    pp = 1 + 0.35 * pipPop;
    ctx.fillStyle = '#ffffff'; ctx.beginPath(); ctx.arc(cx - bw, by, r * pp, 0, TAU); ctx.fill();
    ctx.fillStyle = 'rgba(0,20,60,0.3)'; ctx.beginPath(); ctx.arc(cx + bw, by, r, 0, TAU); ctx.fill();
    ctx.strokeStyle = 'rgba(255,255,255,0.85)'; ctx.lineWidth = 1.5; ctx.stroke();
    D.text(String(level), cx - bw, by + 5 * hs, { size: 15 * hs * pp, color: '#17365e' });
    D.text(String(level + 1), cx + bw, by + 5 * hs, { size: 15 * hs, color: '#ffffff' });
    if (comboT < 1.1 && comboN >= 2) {
      k = comboT > 0.8 ? 1 - (comboT - 0.8) / 0.3 : 1;
      ctx.save(); ctx.translate(cx + R * 0.68, anchorY - GP * 1.12); ctx.rotate(-0.1); sc = 1 + 0.35 * comboPunch; ctx.scale(sc, sc);
      ctx.globalAlpha = k;
      D.text('COMBO x' + comboN, 0, 0, { size: (22 + Math.min(8, comboN)) * S, color: comboN >= 4 ? '#ffb347' : '#fff27a', stroke: 'rgba(20,20,70,0.55)', strokeWidth: 5 });
      ctx.restore(); ctx.globalAlpha = 1;
    }
    if (bannerT < 1.5) {
      k = bannerT < 0.25 ? D.easeOutBack(bannerT / 0.25) : 1;
      ctx.save(); ctx.translate(cx + R * 0.1, anchorY - GP * 1.36); ctx.scale(k, k);
      ctx.globalAlpha = bannerT > 1.15 ? 1 - (bannerT - 1.15) / 0.35 : 1;
      D.text(bannerText, -R * 0.1, 0, { size: 36 * S, color: '#ffffff', stroke: 'rgba(20,20,70,0.5)', strokeWidth: 6 });
      ctx.restore(); ctx.globalAlpha = 1;
    }
    if (state === 'ready' && !D.clip) drawHint();
  }
  function drawHint() {
    var y = H - D.safe.bottom - 92, w, h = 40, n = Math.sin(time * 4) * 3, x, s;
    ctx.font = D.font(19);
    w = ctx.measureText(HINT).width + 92;
    ctx.fillStyle = 'rgba(6,22,52,0.6)'; D.rr(cx - w / 2, y - h / 2, w, h, h / 2); ctx.fill();
    D.text(HINT, cx, y + 7, { size: 19, color: '#ffffff' });
    ctx.strokeStyle = '#ffffff'; ctx.lineWidth = 2.6; ctx.lineCap = 'round'; ctx.lineJoin = 'round';
    for (s = -1; s <= 1; s += 2) {
      x = cx + s * (w / 2 - 22 + n);
      ctx.beginPath(); ctx.moveTo(x - s * 4, y - 7); ctx.lineTo(x + s * 3, y); ctx.lineTo(x - s * 4, y + 7); ctx.stroke();
      ctx.globalAlpha = 0.45;
      ctx.beginPath(); ctx.moveTo(x - s * 12, y - 7); ctx.lineTo(x - s * 5, y); ctx.lineTo(x - s * 12, y + 7); ctx.stroke();
      ctx.globalAlpha = 1;
    }
    ctx.lineCap = 'butt';
  }
  function drawScene() {
    var camPx = camY * GP, iTop = Math.max(0, Math.floor(camY - anchorY / GP) - 1), iBot = Math.min(plats.length - 1, Math.ceil(camY + (H - anchorY) / GP) + 1);
    var fs = anchorY + GP * 1.5, fe = H * 0.97, i, j, p, y, ft, f, alpha, P, yTop, capY, k, d, pvx0, pvy0, u, r, bx, by, below, h, t;
    P = getPal(bgTo);
    y = anchorY + iBot * GP - camPx;
    if (y < H) { ctx.globalAlpha = 0.3; ctx.fillStyle = P.col[FOGN - 1]; ctx.fillRect(cx - RIN, y, RIN * 2, H - y + 20); ctx.globalAlpha = 1; }
    capY = anchorY - 0.5 * GP - camPx;
    below = -1;
    for (i = iBot; i >= iTop; i--) {
      p = plats[i];
      if (p.broken) continue;
      below = i;
      y = anchorY + i * GP - camPx + p.dip * 3.5 * S;
      ft = clamp((y - fs) / (fe - fs), 0, 1); f = (ft * (FOGN - 1) + 0.5) | 0;
      alpha = ft > 0.5 ? 1 - (ft - 0.5) * 1.4 : 1;
      P = getPal(p.theme);
      ctx.globalAlpha = alpha;
      drawPlat(p, i, y, P, f, alpha);
      j = i - 1;
      while (j >= iTop && plats[j].broken) j--;
      if (j >= iTop) yTop = anchorY + j * GP - camPx + plats[j].dip * 3.5 * S;
      else yTop = Math.max(capY, -20);
      drawCol(yTop, y, P, f, j >= iTop);
      if (j < iTop && capY > -40) drawCap(capY, P);
    }
    ctx.globalAlpha = 1;
    bx = cx + CA * RP;
    if (below >= 0 && !dead) {
      p = plats[below]; h = below - ball.y;
      if (h < 1.6 && typeAtBall(p) !== T_GAP) {
        y = anchorY + below * GP - camPx + p.dip * 3.5 * S + SNA * RP * TILT;
        k = 1 - clamp(h, 0, 1.6) * 0.35;
        ctx.fillStyle = 'rgba(60,30,10,0.22)';
        ctx.beginPath(); ctx.ellipse(bx, y, BR * 0.95 * k, BR * 0.4 * k, 0, 0, TAU); ctx.fill();
      }
    }
    for (k = 0; k < RN; k++) {
      r = rings[k];
      if (!r.on) continue;
      t = r.t / r.max; y = anchorY + r.yAbs - camPx + SNA * RP * TILT;
      ctx.globalAlpha = (1 - t) * (r.hot ? 0.8 : 0.5);
      ctx.strokeStyle = r.hot ? '#fffbd0' : '#ffffff'; ctx.lineWidth = (r.hot ? 3 : 2) * S * (1 - t * 0.6);
      ctx.beginPath(); ctx.ellipse(bx, y, BR * (1.2 + t * (r.hot ? 3.4 : 2.2)), BR * (1.2 + t * (r.hot ? 3.4 : 2.2)) * TILT, 0, 0, TAU); ctx.stroke();
    }
    for (k = 0; k < DN; k++) {
      d = debris[k];
      if (!d.on) continue;
      y = anchorY + d.yAbs - camPx; pvx0 = cx + d.c * RP; pvy0 = y + d.s * RP * TILT;
      ctx.save();
      ctx.globalAlpha = Math.min(1, d.life / d.max * 1.7);
      ctx.translate(pvx0 + d.ox, pvy0 + d.oy); ctx.rotate(d.ang); ctx.translate(-pvx0, -pvy0);
      runSides(y, d.a0, d.a1, d.type, true, true, d.P, 0);
      runTop(y, d.a0, d.a1, d.type, d.P, 0);
      ctx.restore();
    }
    ctx.globalAlpha = 1;
    if (!dead) {
      by = anchorY + ball.y * GP - camPx + SNA * RP * TILT - BR;
      drawBall(bx, by);
    }
    f = -1;
    for (k = 0; k < PN; k++) {
      if (pl[k] <= 0) continue;
      if (pc[k] !== f) { f = pc[k]; ctx.fillStyle = PCOL[f]; }
      ctx.globalAlpha = Math.min(1, pl[k] / pm[k] * 2);
      ctx.beginPath(); ctx.arc(px[k], anchorY + py[k] - camPx, ps[k], 0, TAU); ctx.fill();
    }
    for (k = 0; k < UN; k++) {
      u = pops[k];
      if (!u.on) continue;
      t = u.t / u.max;
      ctx.globalAlpha = t > 0.6 ? 1 - (t - 0.6) / 0.4 : 1;
      i = t < 0.15 ? 0.6 + t / 0.15 * 0.5 : 1.1 - Math.min(0.1, (t - 0.15));
      D.text(u.text, u.x, u.yAbs - D.easeOut(t) * 46 * S, { size: u.size * i, color: u.color, stroke: 'rgba(10,30,70,0.5)', strokeWidth: 4 });
    }
    ctx.globalAlpha = 1;
  }

  var impl = {
    resize: function () { layout(); },
    reset: function (seed) {
      var i, r;
      if (W !== D.W || H !== D.H || !ballG) layout();
      plats = []; genLevelN = 1; lastGapA = null; lastGapW = 0;
      genLevel(); genLevel();
      r = plats[0];
      rot = PI * 0.13 - r.off - r.gaps[0].c; rotVel = 0; rotEff = rot; dragging = false; dragId = -1;
      ball.y = -0.45; ball.vy = 0; ball.sq = 0;
      camY = 0; camT = 0; score = 0; scoreStr = '0'; scorePop = 0; level = 1; streak = 0; passedIdx = -1; progShow = 0;
      dead = false; deadT = 0; shake = 0; flash = 0; bgFrom = 0; bgTo = 0; bgT = 1; time = 0; flight = 0;
      paintBg(bgSlot[0], 0);
      comboN = 0; comboT = 9; comboPunch = 0; bannerT = 9; pipPop = 0; hitRed = null;
      for (i = 0; i < PN; i++) pl[i] = 0;
      for (i = 0; i < DN; i++) debris[i].on = false;
      for (i = 0; i < RN; i++) rings[i].on = false;
      for (i = 0; i < UN; i++) pops[i].on = false;
      deco = xorshift(seed | 0);
      bubbles = [];
      for (i = 0; i < 13; i++) {
        r = deco();
        bubbles.push({ x: r < 0.5 ? 0.02 + deco() * 0.2 : 0.78 + deco() * 0.2, y: deco(), r: 4 + deco() * 6, sp: 14 + deco() * 22, par: 0.35 + deco() * 0.3, ph: deco() * 6, sx: 0, sy: 0 });
      }
      bot.rng = xorshift((seed | 0) * 31 + 7);
      bot.i = -1; bot.target = null; bot.wait = 0.5; bot.vel = 0; bot.t = 0; bot.flight = -1; bot.down = false; bot.idle = false;
      bot.failAt = 30 + bot.rng() * 7;
    },
    start: function () { rot = rotEff; },
    update: function (dt, state) {
      var i, n, d, k, u, r;
      time += dt;
      if (W !== D.W || H !== D.H) layout();
      while (plats.length < ball.y + 26) genLevel();
      if (state === 'playing' && !dragging) { rot += rotVel * dt; rotVel *= Math.exp(-dt * 6.5); }
      rotEff = state === 'ready' ? rot + Math.sin(time * 1.3) * 0.085 : rot;
      n = Math.min(plats.length, Math.ceil(ball.y) + 26);
      for (i = Math.max(0, Math.floor(ball.y)); i < n; i++) {
        d = plats[i];
        if (d.spin && !dead) d.off += d.spin * dt;
        if (d.dip > 0) d.dip = Math.max(0, d.dip - dt * 7);
      }
      if (!dead) stepBall(dt, state);
      else deadT += dt;
      if (ball.y > camT) camT = ball.y;
      camY += (camT - camY) * (1 - Math.exp(-dt * 11));
      ball.sq *= Math.exp(-dt * 11);
      scorePop *= Math.exp(-dt * 9); comboPunch *= Math.exp(-dt * 10); pipPop *= Math.exp(-dt * 6);
      shake *= Math.exp(-dt * 7); flash *= Math.exp(-dt * 6);
      comboT += dt; bannerT += dt;
      if (streak >= 2) comboT = Math.min(comboT, 0.3);
      if (bgT < 1) bgT = Math.min(1, bgT + dt / 0.7);
      progShow += (clamp((passedIdx + 1 - (level - 1) * PER) / PER, 0, 1) - progShow) * (1 - Math.exp(-dt * 10));
      if (progShow > clamp((passedIdx + 1 - (level - 1) * PER) / PER, 0, 1) + 0.3) progShow = 0;
      for (i = 0; i < PN; i++) {
        if (pl[i] <= 0) continue;
        pl[i] -= dt; pvy[i] += pg[i] * dt; px[i] += pvx[i] * dt; py[i] += pvy[i] * dt;
      }
      for (k = 0; k < DN; k++) {
        d = debris[k];
        if (!d.on) continue;
        d.life -= dt;
        if (d.life <= 0) { d.on = false; continue; }
        d.vy += 1000 * S * dt; d.ox += d.vx * dt; d.oy += d.vy * dt; d.ang += d.va * dt;
      }
      for (k = 0; k < RN; k++) { r = rings[k]; if (r.on) { r.t += dt; if (r.t >= r.max) r.on = false; } }
      for (k = 0; k < UN; k++) { u = pops[k]; if (u.on) { u.t += dt; if (u.t >= u.max) u.on = false; } }
      if (streak >= 2 && !dead && Math.random() < dt * 40) {
        spawnP(cx + CA * RP + (Math.random() - 0.5) * BR, ball.y * GP + SNA * RP * TILT - BR * 2, (Math.random() - 0.5) * 30 * S, -40 * S, 0.3, 2.2 * S, 3, 0);
      }
      if (state === 'playing') D.score(score);
    },
    draw: function (c, w, h, state) {
      var sx = 0, sy = 0;
      if (!plats.length) return;
      drawBg();
      if (shake > 0.01) { sx = (Math.random() - 0.5) * shake * 16 * S; sy = (Math.random() - 0.5) * shake * 16 * S; }
      ctx.save(); ctx.translate(sx, sy);
      drawScene();
      ctx.restore();
      if (flash > 0.01) { ctx.globalAlpha = flash * 0.5; ctx.fillStyle = flashCol; ctx.fillRect(0, 0, W, H); ctx.globalAlpha = 1; }
      drawHud(state);
    },
    pointerDown: function (x, y, id) { onDown(x, y, id); },
    pointerMove: function (x, y, id, down) { onMove(x, y, id, down); },
    pointerUp: function (x, y, id) { onUp(x, y, id); },
    key: function (k) {
      if (k === 'ArrowLeft') rot += 0.26;
      else if (k === 'ArrowRight') rot -= 0.26;
    },
    bot: function (dt) { botStep(dt); }
  };
  D.game(impl);
})();
