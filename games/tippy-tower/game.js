/* Tippy Tower: tap to drop the sliding slab onto the tower. Overhang is cut off, perfects keep the size. */
(function () {
  'use strict';
  var D = window.Dailies;
  var PI = Math.PI, TAU = PI * 2;
  var clamp = D.clamp, lerp = D.lerp;

  var SIZE = 100, TH = 15, RANGE = 158, AX = 0.88, AY = 0.47;
  var PLATE = 138, PLATE_H = 10, COLUMN = 104, GROW = 8, MIN_OVERLAP = 2, GRAV = 1150;
  var SEA_Y = [26, 80, 108], SEA_R = [30, 25, 34], SEA_STEP = [37, 31, 42], SEA_OFF = [9, -6, 15];

  var STOPS = [[38, 196, 190], [58, 204, 138], [150, 220, 84], [246, 214, 72], [255, 152, 74], [255, 104, 150], [156, 112, 240]];
  var PER = 5, CYC = STOPS.length * PER;
  var colT = [], colL = [], colR = [];
  (function () {
    function mix(c, m, t) { return 'rgb(' + Math.round(lerp(c[0], m[0], t)) + ',' + Math.round(lerp(c[1], m[1], t)) + ',' + Math.round(lerp(c[2], m[2], t)) + ')'; }
    for (var i = 0; i < CYC; i++) {
      var f = i / PER, a = STOPS[Math.floor(f)], b = STOPS[(Math.floor(f) + 1) % STOPS.length], t = f - Math.floor(f);
      var c = [lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t)];
      colT.push(mix(c, [255, 255, 255], 0.2));
      colL.push(mix(c, [24, 44, 120], 0.2));
      colR.push(mix(c, [34, 22, 104], 0.46));
    }
  })();
  var STONE = CYC;
  colT.push('#F3E6E0'); colL.push('#D6C2CE'); colR.push('#B49DC2');
  var PILLAR = CYC + 1;
  colT.push('#B79CCB'); colL.push('#A98BC2'); colR.push('#8669B0');

  var W = 0, H = 0, S = 1, SX = 1, SY = 1, aStart = 0, aEnd = 0;
  var gDusk, gNight, gSunHalo, gSunDisc, gMoon, gSheen, gCloudDusk, gCloudNight, gTop, gSeaDusk = [], gSeaNight = [];

  var tower = [], count = 0;
  var mov = { on: false, axis: 0, o: 0, dir: 1, v: 0, age: 0 };
  var score = 0, streak = 0, maxStreak = 0, perfects = 0, over = false, overT = 0, pulled = false, passedBest = false;
  var tAnim = 0, roundT = 0, landT = 9, landPerfect = false, scoreT = 9, hintA = 1, flashA = 0;
  var camX = 0, camXT = 0, camY = 0, camYT = 0, zoom = 1, zoomT = 1, ay = 0, ayT = 0, shake = 0, shakeX = 0, shakeY = 0;
  var jitter = new Float32Array(600), seaR = new Float32Array(64);
  var stars = new Float32Array(70 * 4), clouds = [], flocks = [], balloons = [];
  var botRng = null, bot = { plan: -1, target: 0, failAt: 30, hot: 0, run: 0, cap: 4 };
  var VXs = new Float32Array(8), VYs = new Float32Array(8);
  var FACES = [[1, 3, 7, 5], [0, 4, 6, 2], [2, 3, 7, 6], [0, 1, 5, 4], [4, 5, 7, 6], [0, 2, 3, 1]];

  var parts = [], debris = [], rings = [], pops = [], iPart = 0, iDeb = 0, iRing = 0, iPop = 0, i0;
  for (i0 = 0; i0 < 120; i0++) parts.push({ on: false, kind: 0, x: 0, y: 0, vx: 0, vy: 0, g: 0, age: 0, life: 1, size: 1, ci: 0 });
  for (i0 = 0; i0 < 14; i0++) debris.push({ on: false, x: 0, y: 0, z: 0, w: 0, h: 0, d: 0, vx: 0, vy: 0, vz: 0, axis: 0, ang: 0, vang: 0, ci: 0, front: false, age: 0 });
  for (i0 = 0; i0 < 10; i0++) rings.push({ on: false, cx: 0, cz: 0, w: 0, d: 0, y: 0, age: 0, life: 1 });
  for (i0 = 0; i0 < 6; i0++) pops.push({ on: false, text: '', x: 0, y: 0, age: 0, life: 1, size: 20, color: '#fff' });

  function smooth(t) { return t * t * (3 - 2 * t); }
  function wrap(v, a, b) { var r = b - a; v = (v - a) % r; return (v < 0 ? v + r : v) + a; }
  function speedFor(n) { return (132 + 2.5 * Math.min(n, 64)) * (1 + jitter[n % 600] * Math.min(0.03 + n * 0.0025, 0.13)); }
  function tolFor(v) { return clamp(v * 0.04, 6.5, 10); }

  function layout() {
    W = D.W; H = D.H;
    if (!W || !H) return;
    S = Math.min(W, 480) * 0.00352; SX = AX * S; SY = AY * S;
    aStart = H * (D.clip ? 0.43 : 0.46); aEnd = Math.max(H * (D.clip ? 0.35 : 0.39), D.safe.top + 255);
    var c = D.ctx, g, i;
    g = c.createLinearGradient(0, 0, 0, H);
    g.addColorStop(0, '#2B2176'); g.addColorStop(0.24, '#51308F'); g.addColorStop(0.44, '#8E459C'); g.addColorStop(0.6, '#DC6C8D'); g.addColorStop(0.74, '#F19A8C'); g.addColorStop(1, '#F6B892');
    gDusk = g;
    g = c.createLinearGradient(0, 0, 0, H);
    g.addColorStop(0, '#121747'); g.addColorStop(0.4, '#282777'); g.addColorStop(0.75, '#4C3BA2'); g.addColorStop(1, '#7052C0');
    gNight = g;
    g = c.createRadialGradient(0, 0, 0, 0, 0, 120 * S);
    g.addColorStop(0, 'rgba(255,226,170,0.75)'); g.addColorStop(0.3, 'rgba(255,190,150,0.42)'); g.addColorStop(1, 'rgba(255,150,140,0)');
    gSunHalo = g;
    g = c.createRadialGradient(-6 * S, -8 * S, 2, 0, 0, 34 * S);
    g.addColorStop(0, '#FFF7D2'); g.addColorStop(1, '#FFDF9A');
    gSunDisc = g;
    g = c.createRadialGradient(0, 0, 0, 0, 0, 70 * S);
    g.addColorStop(0, 'rgba(236,232,255,0.5)'); g.addColorStop(0.3, 'rgba(200,196,255,0.16)'); g.addColorStop(1, 'rgba(180,180,255,0)');
    gMoon = g;
    g = c.createLinearGradient(-40 * S, -SIZE * SY, 30 * S, SIZE * SY);
    g.addColorStop(0, 'rgba(255,255,255,0.34)'); g.addColorStop(0.55, 'rgba(255,255,255,0.05)'); g.addColorStop(1, 'rgba(20,10,90,0.1)');
    gSheen = g;
    g = c.createLinearGradient(0, -40, 0, 2);
    g.addColorStop(0, 'rgba(244,182,200,0.95)'); g.addColorStop(1, 'rgba(190,120,172,0.9)');
    gCloudDusk = g;
    g = c.createLinearGradient(0, -40, 0, 2);
    g.addColorStop(0, 'rgba(150,140,226,0.95)'); g.addColorStop(1, 'rgba(98,84,186,0.9)');
    gCloudNight = g;
    g = c.createLinearGradient(0, 0, 0, D.safe.top + 190);
    g.addColorStop(0, 'rgba(18,10,60,0.34)'); g.addColorStop(1, 'rgba(18,10,60,0)');
    gTop = g;
    for (i = 0; i < 3; i++) {
      var y = SEA_Y[i] * S;
      g = c.createLinearGradient(0, y - 6 * S, 0, y + 400 * S);
      if (i === 0) { g.addColorStop(0, '#E98FA4'); g.addColorStop(0.2, '#CF73A2'); g.addColorStop(1, '#8F55A8'); }
      else { g.addColorStop(0, i === 1 ? '#EE9AAC' : '#F2A6B2'); g.addColorStop(0.09, i === 1 ? '#DB7CA6' : '#E086AA'); g.addColorStop(0.3, '#B263AE'); g.addColorStop(0.62, '#7C48A8'); g.addColorStop(1, '#55369C'); }
      gSeaDusk[i] = g;
      g = c.createLinearGradient(0, y - 6 * S, 0, y + 400 * S);
      if (i === 0) { g.addColorStop(0, '#8E80D6'); g.addColorStop(0.3, '#6B5AC2'); g.addColorStop(1, '#44359A'); }
      else { g.addColorStop(0, i === 1 ? '#A294E4' : '#B4A8EE'); g.addColorStop(0.12, '#8472D2'); g.addColorStop(0.45, '#5E4BB6'); g.addColorStop(1, '#3A2D8C'); }
      gSeaNight[i] = g;
    }
  }

  function spawn() {
    mov.axis = count % 2 === 1 ? 0 : 1;
    mov.o = -RANGE; mov.dir = 1; mov.v = speedFor(count); mov.age = 0; mov.on = true;
  }

  function addPart(kind, x, y, vx, vy, g, life, size, ci) {
    var p = parts[iPart]; iPart = (iPart + 1) % parts.length;
    p.on = true; p.kind = kind; p.x = x; p.y = y; p.vx = vx; p.vy = vy; p.g = g; p.age = 0; p.life = life; p.size = size; p.ci = ci;
  }
  function addPop(text, x, y, size, color, life) {
    var p = pops[iPop]; iPop = (iPop + 1) % pops.length;
    p.on = true; p.text = text; p.x = x; p.y = y; p.age = 0; p.life = life; p.size = size; p.color = color;
  }
  function addRing(s, y, delay) {
    var r = rings[iRing]; iRing = (iRing + 1) % rings.length;
    r.on = true; r.cx = s.cx; r.cz = s.cz; r.w = s.w; r.d = s.d; r.y = y; r.age = -delay; r.life = 0.62;
  }
  function addDebris(x, z, w, d, level, axis, sgn, whole, ci) {
    var p = debris[iDeb]; iDeb = (iDeb + 1) % debris.length;
    var va = sgn * (16 + Math.random() * 26) + mov.dir * mov.v * (whole ? 0.5 : 0.16);
    p.on = true; p.x = x; p.z = z; p.y = (level + 0.5) * TH; p.w = w; p.h = TH; p.d = d;
    p.vx = axis === 0 ? va : 0; p.vz = axis === 1 ? va : 0; p.vy = whole ? 0 : 30;
    p.axis = axis; p.ang = 0; p.vang = -(va < 0 ? -1 : 1) * (whole ? 1.1 + Math.random() * 0.5 : 2 + Math.random() * 1.6);
    p.ci = ci; p.front = sgn > 0; p.age = 0;
  }

  function fxPerfect(s, level) {
    var yTop = (level + 1) * TH, X = (s.cx - s.cz) * SX, Y = (s.cx + s.cz) * SY - yTop * S, i, n, u, e, x, z, px, py, sp;
    addRing(s, yTop, 0);
    if (streak >= 2) addRing(s, yTop, 0.1);
    if (streak >= 4) addRing(s, yTop, 0.2);
    n = Math.min(10 + streak * 2, 24);
    for (i = 0; i < n; i++) {
      u = (Math.random() * 2 - 1) * 0.5; e = i & 3;
      x = e === 0 ? u * s.w : e === 1 ? s.w / 2 : e === 2 ? u * s.w : -s.w / 2;
      z = e === 0 ? -s.d / 2 : e === 1 ? u * s.d : e === 2 ? s.d / 2 : u * s.d;
      px = (x - z) * SX; py = (x + z) * SY; sp = 0.5 + Math.random() * 1.1;
      addPart(1, X + px, Y + py, px * sp, py * sp - 26 - Math.random() * 30, -30, 0.5 + Math.random() * 0.5, (2.4 + Math.random() * 3.2) * S, 0);
    }
    addPop(streak > 1 ? 'PERFECT x' + streak : 'PERFECT', X, Y - 18 * S, Math.min(21 + streak, 27) * S / 1.37, '#FFFFFF', 0.95);
  }
  function fxCut(x, z, w, d, level, ci) {
    var X = (x - z) * SX, Y = (x + z) * SY - (level + 0.5) * TH * S, i, u, px, py;
    for (i = 0; i < 7; i++) {
      u = Math.random() - 0.5;
      px = (u * w - (Math.random() - 0.5) * d) * SX; py = (u * w + (Math.random() - 0.5) * d) * SY;
      addPart(0, X + px, Y + py, px * 0.8 + (Math.random() - 0.5) * 40, -40 - Math.random() * 70, 520, 0.45 + Math.random() * 0.35, (1.6 + Math.random() * 2) * S, ci);
    }
  }

  function finish() {
    over = true; overT = 0; pulled = false; shake = 10; flashA = 0.3;
    D.haptic('error');
    D.tone({ freq: 210, slide: 48, dur: 0.5, type: 'sawtooth', vol: 0.1 });
    var headline = score === 0 ? 'Missed the first drop'
      : D.best > 0 && score > D.best ? 'New best tower'
      : maxStreak >= 3 ? 'Perfect streak x' + maxStreak
      : perfects > 1 ? perfects + ' perfect drops'
      : score === 1 ? 'One floor up' : 'Tower of ' + score + ' floors';
    D.end({ score: score, unit: 'floors', headline: headline });
  }

  function drop() {
    if (!mov.on || over) return;
    var top = tower[count - 1], ax = mov.axis, size = ax === 0 ? top.w : top.d;
    var o = mov.o, ao = Math.abs(o), sgn = o < 0 ? -1 : 1, level = count, ci = level % CYC;
    var cx = top.cx, cz = top.cz, w = top.w, d = top.d, s;
    mov.on = false;
    if (ao >= size - MIN_OVERLAP) {
      addDebris(ax === 0 ? cx + o : cx, ax === 1 ? cz + o : cz, w, d, level, ax, sgn, true, ci);
      finish();
      return;
    }
    if (ao <= tolFor(mov.v)) {
      streak += 1; perfects += 1;
      if (streak > maxStreak) maxStreak = streak;
      if (streak >= 2) { if (ax === 0) w = Math.min(SIZE, w + GROW); else d = Math.min(SIZE, d + GROW); }
      s = { cx: cx, cz: cz, w: w, d: d }; tower[count++] = s;
      landPerfect = true;
      fxPerfect(s, level);
      D.haptic('success');
      D.tone({ freq: 523 * Math.pow(2, [0, 2, 4, 7, 9, 12, 14, 16][Math.min(streak - 1, 7)] / 12), dur: 0.2, type: 'triangle', vol: 0.14 });
    } else {
      streak = 0;
      if (ax === 0) { s = { cx: cx + o / 2, cz: cz, w: size - ao, d: d }; addDebris(cx + sgn * size / 2 + o / 2, cz, ao, d, level, ax, sgn, false, ci); fxCut(cx + sgn * (size - ao / 2) / 2 + o / 2, cz, 2, d, level, ci); }
      else { s = { cx: cx, cz: cz + o / 2, w: w, d: size - ao }; addDebris(cx, cz + sgn * size / 2 + o / 2, w, ao, level, ax, sgn, false, ci); fxCut(cx, cz + sgn * (size - ao / 2) / 2 + o / 2, w, 2, level, ci); }
      tower[count++] = s;
      landPerfect = false;
      shake = Math.min(6, 1.5 + ao * 0.09);
      D.haptic(ao < size * 0.18 ? 'medium' : 'light');
      D.tone({ freq: 250, slide: 170, dur: 0.11, type: 'triangle', vol: 0.12 });
    }
    score = count - 1; scoreT = 0; landT = 0;
    D.score(score);
    if (D.best > 0 && score > D.best && !passedBest) {
      passedBest = true;
      addPop('NEW BEST', (s.cx - s.cz) * SX, (s.cx + s.cz) * SY - (level + 1) * TH * S - 52 * S, 20 * S / 1.37, '#FFD766', 1.3);
    }
    spawn();
  }

  function planBot() {
    var top = tower[count - 1], size = mov.axis === 0 ? top.w : top.d, tol = tolFor(mov.v), r = botRng, n = count, sg = r() < 0.5 ? -1 : 1;
    bot.plan = count;
    if ((n >= bot.failAt && roundT > 21) || roundT > 39) {
      bot.target = size + 16 + r() * 12 < RANGE - 6 && r() < 0.6 ? size + 14 + r() * 10 : -(size + 8 + r() * 12);
      if (bot.target < -RANGE + 12) bot.target = -RANGE + 12;
    } else if (n >= bot.failAt - 3) {
      bot.target = sg * Math.max(tol + 2, size * (0.04 + 0.09 * (n - bot.failAt + 4) + r() * 0.04));
    } else {
      var perfect;
      if (bot.hot > 0) { bot.hot -= 1; perfect = true; }
      else if (n > 2 && r() < 0.15) { bot.hot = 2 + Math.floor(r() * 3); perfect = true; }
      else perfect = r() < 0.56;
      if (bot.run >= bot.cap) { perfect = false; bot.hot = 0; }
      if (perfect) { bot.run += 1; bot.target = (r() * 2 - 1) * tol * 0.45; }
      else { bot.run = 0; bot.cap = 3 + Math.floor(r() * 4); bot.target = sg * (tol + 0.8 + r() * size * 0.045); }
    }
  }

  function box(ctx, cx, cz, w, d, yb, h, ci, hi) {
    var x0 = cx - w / 2, x1 = cx + w / 2, z0 = cz - d / 2, z1 = cz + d / 2, yt = (yb + h) * S, hp = h * S + 0.6;
    var ax = (x0 - z0) * SX, ayy = (x0 + z0) * SY - yt, bx = (x1 - z0) * SX, by = (x1 + z0) * SY - yt;
    var fx = (x1 - z1) * SX, fy = (x1 + z1) * SY - yt, lx = (x0 - z1) * SX, ly = (x0 + z1) * SY - yt;
    ctx.fillStyle = colR[ci];
    ctx.beginPath(); ctx.moveTo(ax, ayy); ctx.lineTo(bx, by); ctx.lineTo(bx, by + hp); ctx.lineTo(fx, fy + hp); ctx.lineTo(lx, ly + hp); ctx.lineTo(lx, ly); ctx.closePath(); ctx.fill();
    ctx.fillStyle = colL[ci];
    ctx.beginPath(); ctx.moveTo(lx, ly); ctx.lineTo(fx, fy); ctx.lineTo(fx, fy + hp); ctx.lineTo(lx, ly + hp); ctx.closePath(); ctx.fill();
    ctx.fillStyle = colT[ci];
    ctx.beginPath(); ctx.moveTo(ax, ayy); ctx.lineTo(bx, by); ctx.lineTo(fx, fy); ctx.lineTo(lx, ly); ctx.closePath(); ctx.fill();
    if (hi) { ctx.beginPath(); ctx.moveTo(lx, ly); ctx.lineTo(fx, fy); ctx.lineTo(bx, by); ctx.stroke(); }
  }
  function silhouette(ctx, cx, cz, w, d, yb, h) {
    var x0 = cx - w / 2, x1 = cx + w / 2, z0 = cz - d / 2, z1 = cz + d / 2, yt = (yb + h) * S, hp = h * S + 0.6;
    ctx.beginPath();
    ctx.moveTo((x0 - z0) * SX, (x0 + z0) * SY - yt); ctx.lineTo((x1 - z0) * SX, (x1 + z0) * SY - yt); ctx.lineTo((x1 - z0) * SX, (x1 + z0) * SY - yt + hp);
    ctx.lineTo((x1 - z1) * SX, (x1 + z1) * SY - yt + hp); ctx.lineTo((x0 - z1) * SX, (x0 + z1) * SY - yt + hp); ctx.lineTo((x0 - z1) * SX, (x0 + z1) * SY - yt);
    ctx.closePath();
  }
  function topPath(ctx, cx, cz, w, d, y, sc) {
    var hw = w / 2 * sc, hd = d / 2 * sc, x0 = cx - hw, x1 = cx + hw, z0 = cz - hd, z1 = cz + hd, yy = y * S;
    ctx.beginPath();
    ctx.moveTo((x0 - z0) * SX, (x0 + z0) * SY - yy); ctx.lineTo((x1 - z0) * SX, (x1 + z0) * SY - yy);
    ctx.lineTo((x1 - z1) * SX, (x1 + z1) * SY - yy); ctx.lineTo((x0 - z1) * SX, (x0 + z1) * SY - yy);
    ctx.closePath();
  }
  function sheen(ctx, cx, cz, w, d, y) {
    var X = (cx - cz) * SX, Y = (cx + cz) * SY - y * S;
    ctx.translate(X, Y);
    topPath(ctx, 0, 0, w, d, 0, 1);
    ctx.fillStyle = gSheen; ctx.fill();
    ctx.translate(-X, -Y);
  }

  function drawDebris(ctx, p) {
    var ca = Math.cos(p.ang), sa = Math.sin(p.ang), hw = p.w / 2, hh = p.h / 2, hd = p.d / 2, i, f, x, y, z, t, q, s;
    for (i = 0; i < 8; i++) {
      x = (i & 1) ? hw : -hw; y = (i & 2) ? hh : -hh; z = (i & 4) ? hd : -hd;
      if (p.axis === 0) { t = x * ca - y * sa; y = x * sa + y * ca; x = t; }
      else { t = z * ca - y * sa; y = z * sa + y * ca; z = t; }
      x += p.x; y += p.y; z += p.z;
      VXs[i] = (x - z) * SX; VYs[i] = (x + z) * SY - y * S;
    }
    if (p.age > 1.1) ctx.globalAlpha = clamp(1 - (p.age - 1.1) / 0.7, 0, 1);
    for (f = 0; f < 6; f++) {
      x = 0; y = 0; z = 0; s = (f & 1) ? -1 : 1;
      if (f < 2) x = s; else if (f < 4) y = s; else z = s;
      if (p.axis === 0) { t = x * ca - y * sa; y = x * sa + y * ca; x = t; }
      else { t = z * ca - y * sa; y = z * sa + y * ca; z = t; }
      if (x + y * 2 * AY + z <= 0.001) continue;
      q = FACES[f];
      ctx.fillStyle = f === 2 ? colT[p.ci] : f >= 4 ? colL[p.ci] : colR[p.ci];
      ctx.beginPath(); ctx.moveTo(VXs[q[0]], VYs[q[0]]); ctx.lineTo(VXs[q[1]], VYs[q[1]]); ctx.lineTo(VXs[q[2]], VYs[q[2]]); ctx.lineTo(VXs[q[3]], VYs[q[3]]); ctx.closePath(); ctx.fill();
    }
    ctx.globalAlpha = 1;
  }

  function drawSea(ctx, layer, halfW, night) {
    var y = SEA_Y[layer] * S, step = SEA_STEP[layer] * S, rb = SEA_R[layer] * S, off = SEA_OFF[layer] * S;
    var n = Math.ceil(halfW / step) + 1, i, k, r, cx, cy;
    ctx.beginPath();
    for (i = -n; i <= n; i++) {
      k = ((i + 512) * 7 + layer * 19) & 63;
      r = rb * (0.8 + 0.5 * seaR[k]);
      cx = i * step + off; cy = y + r * 0.72 + seaR[(k + 11) & 63] * rb * 0.3;
      ctx.moveTo(cx + r, cy); ctx.arc(cx, cy, r, 0, TAU);
    }
    ctx.rect(-(n + 1) * step, y + rb * 0.8, 2 * (n + 1) * step, 2600 * S);
    ctx.lineWidth = 3; ctx.strokeStyle = layer === 0 ? 'rgba(255,214,220,0.3)' : 'rgba(255,226,232,0.6)'; ctx.stroke();
    ctx.fillStyle = gSeaDusk[layer]; ctx.fill();
    if (night > 0.01) { ctx.globalAlpha = night; ctx.fillStyle = gSeaNight[layer]; ctx.fill(); ctx.globalAlpha = 1; }
    if (layer > 0) {
      ctx.beginPath();
      for (i = -n; i <= n; i++) {
        k = ((i + 512) * 5 + layer * 23) & 63;
        r = rb * (0.9 + 0.5 * seaR[k]);
        cx = (i + 0.5) * step + off; cy = y + rb * (1.75 + seaR[(k + 7) & 63] * 0.7);
        ctx.moveTo(cx + Math.cos(PI * 1.14) * r, cy + Math.sin(PI * 1.14) * r); ctx.arc(cx, cy, r, PI * 1.14, PI * 1.86);
      }
      ctx.lineWidth = 1.6; ctx.strokeStyle = 'rgba(255,226,236,0.2)'; ctx.stroke();
    }
  }

  function drawCloud(ctx, c, x, y, night) {
    var sc = c.s;
    ctx.translate(x, y); ctx.scale(c.flip * sc, sc);
    ctx.beginPath();
    ctx.moveTo(-47, 0); ctx.arc(-32, 0, 15, PI, TAU); ctx.arc(-7, -14, 23, PI, TAU); ctx.arc(22, -7, 18, PI, TAU); ctx.arc(38, 0, 12, PI, TAU);
    ctx.closePath();
    ctx.globalAlpha = c.a * (1 - night); ctx.fillStyle = gCloudDusk; ctx.fill();
    if (night > 0.01) { ctx.globalAlpha = c.a * night * 0.8; ctx.fillStyle = gCloudNight; ctx.fill(); }
    ctx.globalAlpha = 1;
    ctx.scale(c.flip / sc, 1 / sc); ctx.translate(-x, -y);
  }

  function gore(ctx, r, k1, k2) {
    var nw = r * 0.2, top = -r, bot = r * 1.22;
    ctx.beginPath();
    ctx.moveTo(0, top);
    ctx.bezierCurveTo(k1 * r * 1.36, top, k1 * r * 1.16, r * 0.42, k1 * nw, bot);
    ctx.lineTo(k2 * nw, bot);
    ctx.bezierCurveTo(k2 * r * 1.16, r * 0.42, k2 * r * 1.36, top, 0, top);
    ctx.fill();
  }
  function drawBalloon(ctx, x, y, r, night) {
    ctx.translate(x, y);
    ctx.strokeStyle = 'rgba(70,40,90,0.7)'; ctx.lineWidth = 1;
    ctx.beginPath(); ctx.moveTo(-r * 0.2, r * 1.2); ctx.lineTo(-r * 0.16, r * 1.62); ctx.moveTo(r * 0.2, r * 1.2); ctx.lineTo(r * 0.16, r * 1.62); ctx.stroke();
    ctx.fillStyle = '#EE6480'; gore(ctx, r, -1, 1);
    ctx.fillStyle = '#FFEDE0'; gore(ctx, r, -0.62, -0.2); gore(ctx, r, 0.2, 0.62);
    ctx.fillStyle = 'rgba(60,20,110,0.2)'; gore(ctx, r, 0.3, 1);
    ctx.fillStyle = 'rgba(255,255,255,0.22)'; gore(ctx, r, -0.86, -0.5);
    ctx.fillStyle = '#7A4B58'; ctx.fillRect(-r * 0.2, r * 1.6, r * 0.4, r * 0.3);
    if (night > 0.3) { ctx.globalAlpha = (night - 0.3) * 0.5; ctx.fillStyle = '#2A2477'; gore(ctx, r, -1, 1); ctx.globalAlpha = 1; }
    ctx.translate(-x, -y);
  }

  D.game({
    resize: function () { layout(); },

    reset: function (seed) {
      var i, c;
      layout();
      for (i = 0; i < 600; i++) jitter[i] = D.rand() * 2 - 1;
      for (i = 0; i < 64; i++) seaR[i] = D.rand();
      for (i = 0; i < 70; i++) { stars[i * 4] = D.rand(); stars[i * 4 + 1] = D.rand(); stars[i * 4 + 2] = 1 + D.rand() * 1.7; stars[i * 4 + 3] = D.rand() * TAU; }
      clouds.length = 0;
      for (i = 0; i < 8; i++) {
        c = { x0: D.rand(), y0: (i + D.rand() * 0.7) / 8, s: 0.55 + D.rand() * 0.75, par: 0, vx: (2 + D.rand() * 6) * (D.rand() < 0.5 ? -1 : 1), flip: D.rand() < 0.5 ? -1 : 1, a: 0.5 + D.rand() * 0.4 };
        c.par = 0.2 + c.s * 0.32;
        clouds.push(c);
      }
      clouds.sort(function (a, b) { return a.s - b.s; });
      flocks.length = 0;
      for (i = 0; i < 2; i++) flocks.push({ x0: D.rand(), y0: 0.12 + i * 0.5 + D.rand() * 0.2, vx: (14 + D.rand() * 12) * (i ? -1 : 1), n: 3 + D.randInt(0, 2), ph: D.rand() * 9, sz: 4.5 + D.rand() * 2 });
      balloons.length = 0;
      balloons.push({ x0: 0.74 + D.rand() * 0.12, y0: -70 - D.rand() * 40, r: 15 + D.rand() * 4, ph: D.rand() * 9 });
      balloons.push({ x0: 0.1 + D.rand() * 0.14, y0: -820 - D.rand() * 200, r: 11 + D.rand() * 4, ph: D.rand() * 9 });
      botRng = D.makeRng(((seed | 0) * 2654435761 + 97) >>> 0);
      bot.plan = -1; bot.hot = 0; bot.run = 0; bot.cap = 3 + Math.floor(botRng() * 4); bot.failAt = 25 + Math.floor(botRng() * 10);
      tower.length = 0; count = 0;
      tower[count++] = { cx: 0, cz: 0, w: SIZE, d: SIZE };
      score = 0; streak = 0; maxStreak = 0; perfects = 0; over = false; overT = 0; pulled = false; passedBest = false;
      roundT = 0; landT = 9; scoreT = 9; hintA = 1; flashA = 0; shake = 0; shakeX = 0; shakeY = 0;
      camX = camXT = 0; camY = camYT = -TH * S; zoom = zoomT = 1; ay = ayT = aStart;
      for (i = 0; i < parts.length; i++) parts[i].on = false;
      for (i = 0; i < debris.length; i++) debris[i].on = false;
      for (i = 0; i < rings.length; i++) rings[i].on = false;
      for (i = 0; i < pops.length; i++) pops[i].on = false;
      spawn();
      if (!D.clip) mov.o = -RANGE * 0.62;
    },

    start: function () { roundT = 0; if (D.clip) { mov.o = -RANGE; mov.dir = 1; mov.age = 0; } },

    update: function (dt, state) {
      var i, p, k, top;
      tAnim += dt; landT += dt; scoreT += dt;
      if (state === 'playing') roundT += dt;
      if (mov.on && !over) {
        mov.age += dt;
        mov.o += mov.dir * mov.v * dt;
        if (mov.o > RANGE) { mov.o = 2 * RANGE - mov.o; mov.dir = -1; }
        else if (mov.o < -RANGE) { mov.o = -2 * RANGE - mov.o; mov.dir = 1; }
      }
      if (state !== 'ready' && score > 0) hintA = Math.max(0, hintA - dt * 4);
      top = tower[count - 1];
      if (!over) {
        zoomT = 1; camYT = -count * TH * S; camXT = (top.cx - top.cz) * SX * 0.7;
        ayT = lerp(aStart, aEnd, smooth(clamp((count - 1) / 9, 0, 1)));
      } else {
        overT += dt;
        if (!pulled && overT > 0.3) {
          pulled = true;
          var yTop = D.safe.top + 160, yBot = D.clip ? H - 240 : H - D.safe.bottom - 110;
          var towerPx = (count * TH + 70) * S, z = Math.min(1, (yBot - yTop) / towerPx);
          zoomT = z; camXT *= 0.5;
          camYT = -count * TH * S - (yTop + ((yBot - yTop) - towerPx * z) * 0.5 - ayT) / z;
        }
      }
      k = 1 - Math.exp(-dt * (over ? (D.clip ? 4.5 : 3) : 6.5));
      camX += (camXT - camX) * k; camY += (camYT - camY) * k; zoom += (zoomT - zoom) * k; ay += (ayT - ay) * k;
      if (shake > 0.05) { shakeX = (Math.random() * 2 - 1) * shake; shakeY = (Math.random() * 2 - 1) * shake; shake *= Math.exp(-dt * 11); }
      else { shake = 0; shakeX = 0; shakeY = 0; }
      if (flashA > 0) flashA = Math.max(0, flashA - dt * 1.1);
      for (i = 0; i < parts.length; i++) {
        p = parts[i]; if (!p.on) continue;
        p.age += dt; if (p.age >= p.life) { p.on = false; continue; }
        p.vy += p.g * dt; p.x += p.vx * dt; p.y += p.vy * dt;
        if (p.kind === 1) { p.vx *= 1 - 2.2 * dt; p.vy *= 1 - 1.4 * dt; }
      }
      for (i = 0; i < debris.length; i++) {
        p = debris[i]; if (!p.on) continue;
        p.age += dt; if (p.age > 1.8) { p.on = false; continue; }
        p.vy -= GRAV * dt; p.x += p.vx * dt; p.y += p.vy * dt; p.z += p.vz * dt; p.ang += p.vang * dt;
      }
      for (i = 0; i < rings.length; i++) { p = rings[i]; if (p.on) { p.age += dt; if (p.age >= p.life) p.on = false; } }
      for (i = 0; i < pops.length; i++) { p = pops[i]; if (p.on) { p.age += dt; if (p.age >= p.life) p.on = false; } }
    },

    draw: function (ctx, W_, H_, state) {
      var i, j, k, p, s, c, x, y, a, tt, fl, h, ci, n;
      var baseY = ay - camY * zoom, alt = baseY - aStart;
      var night = smooth(clamp((alt / (TH * S) - 3) / 24, 0, 1));

      ctx.fillStyle = gDusk; ctx.fillRect(0, 0, W, H);
      if (night > 0.01) { ctx.globalAlpha = night; ctx.fillStyle = gNight; ctx.fillRect(0, 0, W, H); ctx.globalAlpha = 1; }

      if (night > 0.05) {
        ctx.fillStyle = '#FFFFFF';
        for (i = 0; i < 70; i++) {
          j = i * 4; a = night * (0.25 + 0.75 * Math.abs(Math.sin(tAnim * 1.3 + stars[j + 3])));
          ctx.globalAlpha = a * (1 - stars[j + 1] * 0.6);
          s = stars[j + 2];
          ctx.fillRect(stars[j] * W, wrap(stars[j + 1] * H * 0.86 + alt * 0.04, 0, H * 0.86), s, s);
        }
        ctx.globalAlpha = 1;
        if (night > 0.3) {
          a = (night - 0.3) / 0.7; x = W * 0.17; y = lerp(H * 0.42, H * 0.27, a);
          ctx.globalAlpha = a; ctx.translate(x, y);
          ctx.fillStyle = gMoon; ctx.beginPath(); ctx.arc(0, 0, 70 * S, 0, TAU); ctx.fill();
          ctx.fillStyle = '#F3F0FF'; ctx.beginPath(); ctx.arc(0, 0, 13 * S, 0, TAU); ctx.fill();
          ctx.fillStyle = 'rgba(170,160,230,0.5)'; ctx.beginPath(); ctx.arc(-4 * S, -3 * S, 3 * S, 0, TAU); ctx.arc(4 * S, 4 * S, 2.2 * S, 0, TAU); ctx.fill();
          ctx.translate(-x, -y); ctx.globalAlpha = 1;
        }
      }

      y = aStart + 26 * S + alt * 0.88;
      if (y < H + 130 * S) {
        x = W * 0.12;
        ctx.globalAlpha = 1 - night * 0.6; ctx.translate(x, y);
        ctx.fillStyle = gSunHalo; ctx.beginPath(); ctx.arc(0, 0, 120 * S, 0, TAU); ctx.fill();
        ctx.fillStyle = gSunDisc; ctx.beginPath(); ctx.arc(0, 0, 33 * S, 0, TAU); ctx.fill();
        ctx.translate(-x, -y); ctx.globalAlpha = 1;
      }

      for (i = 0; i < clouds.length; i++) {
        c = clouds[i];
        drawCloud(ctx, c, wrap(c.x0 * W + tAnim * c.vx, -90, W + 90), wrap(c.y0 * (H + 260) + alt * c.par, -70, H + 190) , night);
      }

      ctx.lineWidth = 1.5; ctx.lineCap = 'round';
      ctx.strokeStyle = night > 0.5 ? 'rgba(206,198,255,0.5)' : 'rgba(74,36,104,0.7)';
      ctx.beginPath();
      for (i = 0; i < flocks.length; i++) {
        c = flocks[i];
        x = wrap(c.x0 * W + tAnim * c.vx, -80, W + 420); y = wrap(c.y0 * H + alt * 0.5, -60, H + 500);
        if (x > W + 60 || y > H) continue;
        for (j = 0; j < c.n; j++) {
          var bx = x + (j % 2 ? 1 : -1) * Math.ceil(j / 2) * 15 * (c.vx > 0 ? -1 : 1) * 0.9 + j * 3, by = y + Math.ceil(j / 2) * 8 + (j % 2) * 3;
          var f = Math.sin(tAnim * 7 + c.ph + j * 1.3) * c.sz * 0.45, sz = c.sz;
          ctx.moveTo(bx - sz, by + f); ctx.quadraticCurveTo(bx - sz * 0.5, by - sz * 0.55, bx, by); ctx.quadraticCurveTo(bx + sz * 0.5, by - sz * 0.55, bx + sz, by + f);
        }
      }
      ctx.stroke();

      for (i = 0; i < balloons.length; i++) {
        c = balloons[i];
        y = wrap(c.y0 + alt * 0.7, -1300, H + 500) + Math.sin(tAnim * 0.9 + c.ph) * 4;
        if (y > -60 && y < H + 60) drawBalloon(ctx, c.x0 * W + Math.sin(tAnim * 0.23 + c.ph) * 16, y, c.r * S, night);
      }

      ctx.fillStyle = gTop; ctx.fillRect(0, 0, W, D.safe.top + 190);

      // world layer
      ctx.save();
      ctx.translate(W / 2 - camX * zoom + shakeX, ay + shakeY);
      ctx.scale(zoom, zoom);
      ctx.translate(0, -camY);
      var halfW = W / 2 / zoom + Math.abs(camX) + 50;
      var wyTop = camY - ay / zoom, wyBot = camY + (H - ay) / zoom;
      var seaOn = wyBot > SEA_Y[0] * S - 10;
      if (seaOn) {
        drawSea(ctx, 0, halfW, night);
        box(ctx, 0, 0, COLUMN, COLUMN, -900, 900 - PLATE_H, PILLAR, false);
        box(ctx, 0, 0, PLATE, PLATE, -PLATE_H, PLATE_H, STONE, false);
      }
      for (i = 0; i < debris.length; i++) if (debris[i].on && !debris[i].front) drawDebris(ctx, debris[i]);

      var thp = TH * S, iMin = clamp(Math.floor((-wyBot - 80 * S) / thp), 0, count - 1), iMax = clamp(Math.floor((-wyTop + 80 * S) / thp), 0, count - 1);
      var hi = zoom > 0.6, topH = TH;
      ctx.strokeStyle = 'rgba(255,255,255,0.45)'; ctx.lineWidth = 1.1;
      for (i = iMin; i <= iMax; i++) {
        s = tower[i]; h = TH;
        if (i === count - 1 && landT < 0.26 && count > 1) { k = landT / 0.26; h = TH * (1 - 0.34 * Math.sin(k * PI) * (1 - k)); topH = h; }
        box(ctx, s.cx, s.cz, s.w, s.d, i * TH, h, i % CYC, hi);
        if (landT < 0.7 && count > 1) {
          j = count - 1 - i;
          if (j < (landPerfect ? 12 : 1)) {
            tt = landT - j * 0.03;
            if (tt > 0 && tt < 0.32) {
              fl = (landPerfect ? 0.75 : 0.3) * Math.pow(0.8, j) * (1 - tt / 0.32);
              silhouette(ctx, s.cx, s.cz, s.w, s.d, i * TH, h);
              ctx.globalAlpha = fl; ctx.fillStyle = '#FFFFFF'; ctx.fill(); ctx.globalAlpha = 1;
            }
          }
        }
      }
      s = tower[count - 1];
      if (iMax === count - 1) sheen(ctx, s.cx, s.cz, s.w, s.d, (count - 1) * TH + topH);

      if (mov.on) {
        var mx = mov.axis === 0 ? s.cx + mov.o : s.cx, mz = mov.axis === 1 ? s.cz + mov.o : s.cz, my = count * TH;
        a = clamp(mov.age / 0.16, 0, 1);
        if (a < 1) my += (1 - D.easeOut(a)) * 12;
        // speed streaks trailing behind the slab
        var tx = (mov.axis === 0 ? -SX : SX) * mov.dir, ty = -SY * mov.dir, e0x, e0y, e1x, e1y, len;
        if (mov.axis === 0) { x = mov.dir > 0 ? mx - s.w / 2 : mx + s.w / 2; e0x = (x - (mz - s.d / 2)) * SX; e0y = (x + mz - s.d / 2) * SY; e1x = (x - (mz + s.d / 2)) * SX; e1y = (x + mz + s.d / 2) * SY; }
        else { x = mov.dir > 0 ? mz - s.d / 2 : mz + s.d / 2; e0x = (mx - s.w / 2 - x) * SX; e0y = (mx - s.w / 2 + x) * SY; e1x = (mx + s.w / 2 - x) * SX; e1y = (mx + s.w / 2 + x) * SY; }
        e0y -= (my + TH) * S; e1y -= (my + TH) * S;
        ctx.lineWidth = 1.6;
        for (k = 0; k < 2; k++) {
          ctx.strokeStyle = k ? 'rgba(255,255,255,0.3)' : 'rgba(255,255,255,0.16)';
          ctx.beginPath();
          for (j = 0; j < 4; j++) {
            tt = j / 3; len = (k ? 22 : 58) * (0.6 + ((j * 37) % 5) * 0.16) * (mov.v / 190);
            x = lerp(e0x, e1x, tt); y = lerp(e0y, e1y, tt) + (j === 3 || j === 0 ? TH * S * 0.5 : 0);
            ctx.moveTo(x + tx * 3, y + ty * 3); ctx.lineTo(x + tx * len, y + ty * len);
          }
          ctx.stroke();
        }
        ctx.strokeStyle = 'rgba(255,255,255,0.45)'; ctx.lineWidth = 1.1;
        box(ctx, mx, mz, s.w, s.d, my, TH, count % CYC, true);
        sheen(ctx, mx, mz, s.w, s.d, my + TH);
        ctx.globalAlpha = 1;
      }

      for (i = 0; i < debris.length; i++) if (debris[i].on && debris[i].front) drawDebris(ctx, debris[i]);

      for (i = 0; i < rings.length; i++) {
        p = rings[i]; if (!p.on || p.age < 0) continue;
        k = p.age / p.life; a = D.easeOut(k);
        topPath(ctx, p.cx, p.cz, p.w, p.d, p.y, 1 + a * 0.85);
        ctx.globalAlpha = (1 - k) * 0.9; ctx.lineWidth = 3 - 2 * k; ctx.strokeStyle = '#FFFFFF'; ctx.stroke();
        if (k < 0.5) { ctx.globalAlpha = (0.5 - k) * 0.3; ctx.fillStyle = '#FFFFFF'; ctx.fill(); }
        ctx.globalAlpha = 1;
      }

      if (seaOn) { drawSea(ctx, 1, halfW, night); drawSea(ctx, 2, halfW, night); }

      for (i = 0; i < parts.length; i++) {
        p = parts[i]; if (!p.on) continue;
        k = p.age / p.life;
        if (p.kind === 1) {
          s = p.size * (0.4 + Math.sin(k * PI) * 0.9) * (0.75 + 0.25 * Math.sin(p.age * 30 + i));
          ctx.globalAlpha = Math.min(1, 2.2 * (1 - k)); ctx.fillStyle = '#FFFFFF';
          ctx.beginPath(); ctx.moveTo(p.x, p.y - s); ctx.quadraticCurveTo(p.x, p.y, p.x + s, p.y); ctx.quadraticCurveTo(p.x, p.y, p.x, p.y + s);
          ctx.quadraticCurveTo(p.x, p.y, p.x - s, p.y); ctx.quadraticCurveTo(p.x, p.y, p.x, p.y - s); ctx.fill();
        } else {
          ctx.globalAlpha = 1 - k; ctx.fillStyle = colT[p.ci];
          ctx.beginPath(); ctx.arc(p.x, p.y, p.size, 0, TAU); ctx.fill();
        }
      }
      ctx.globalAlpha = 1;

      for (i = 0; i < pops.length; i++) {
        p = pops[i]; if (!p.on) continue;
        k = p.age / p.life; s = k < 0.16 ? D.easeOutBack(k / 0.16) : 1; a = k > 0.68 ? 1 - (k - 0.68) / 0.32 : 1;
        ctx.save(); ctx.translate(p.x, p.y - 20 * S * D.easeOut(k)); ctx.scale(s, s);
        if ('letterSpacing' in ctx) ctx.letterSpacing = '1.5px';
        D.text(p.text, 0, 0, { size: p.size, color: p.color, stroke: 'rgba(54,22,118,0.55)', strokeWidth: 5, alpha: a });
        if ('letterSpacing' in ctx) ctx.letterSpacing = '0px';
        ctx.restore();
      }
      ctx.restore();

      if (flashA > 0) { ctx.globalAlpha = flashA; ctx.fillStyle = '#FFE6F0'; ctx.fillRect(0, 0, W, H); ctx.globalAlpha = 1; }

      // best marker
      if (D.best > 0 && !D.clip) {
        y = ay + (-(D.best + 1) * TH * S - camY) * zoom;
        if (y > D.safe.top + 150 && y < H - D.safe.bottom - 40) {
          a = score > D.best ? 0.4 : 0.85;
          ctx.globalAlpha = a; ctx.strokeStyle = '#FFFFFF'; ctx.lineWidth = 1.5;
          ctx.setLineDash([5, 4]); ctx.beginPath(); ctx.moveTo(W - 84, y); ctx.lineTo(W - 14, y); ctx.stroke(); ctx.setLineDash([]);
          ctx.fillStyle = '#FFFFFF'; ctx.beginPath(); ctx.moveTo(W - 96, y); ctx.lineTo(W - 91, y - 5); ctx.lineTo(W - 86, y); ctx.lineTo(W - 91, y + 5); ctx.closePath(); ctx.fill();
          D.text('BEST ' + D.best, W - 14, y + 15, { size: 12, align: 'right', alpha: a });
          ctx.globalAlpha = 1;
        }
      }

      // HUD
      k = scoreT < 0.28 ? 1 + 0.22 * (1 - D.easeOut(scoreT / 0.28)) : 1;
      y = D.safe.top + 122;
      ctx.save(); ctx.translate(W / 2, y - 28); ctx.scale(k, k);
      D.text(String(score), 0, 32, { size: 84, color: 'rgba(30,14,84,0.35)' });
      D.text(String(score), 0, 28, { size: 84 });
      ctx.restore();
      if (D.best > 0) {
        if ('letterSpacing' in ctx) ctx.letterSpacing = '1.5px';
        D.text('BEST ' + D.best, W / 2, y + 24, { size: 15, color: 'rgba(255,255,255,0.78)' });
        if ('letterSpacing' in ctx) ctx.letterSpacing = '0px';
      }
      if (!D.clip && hintA > 0.01 && state !== 'over') {
        a = hintA * (0.82 + 0.18 * Math.sin(tAnim * 3.2));
        y = H - D.safe.bottom - 96;
        ctx.globalAlpha = a;
        D.rr(W / 2 - 84, y - 20, 168, 40, 20);
        ctx.fillStyle = 'rgba(34,16,92,0.5)'; ctx.fill();
        ctx.lineWidth = 1; ctx.strokeStyle = 'rgba(255,255,255,0.28)'; ctx.stroke();
        if ('letterSpacing' in ctx) ctx.letterSpacing = '2px';
        D.text('TAP TO DROP', W / 2 + 1, y + 6.5, { size: 18 });
        if ('letterSpacing' in ctx) ctx.letterSpacing = '0px';
        ctx.globalAlpha = 1;
      }
    },

    pointerDown: function (x, y, id, first) {
      if (!mov.on || over) return;
      var top = tower[count - 1], far = Math.abs(mov.o) >= (mov.axis === 0 ? top.w : top.d) - MIN_OVERLAP;
      if (first) { if (far) { D.haptic('light'); return; } }
      else if (mov.age < 0.08 || (far && mov.age < 0.28)) return;
      drop();
    },
    key: function (k) { if (k === ' ' || k === 'Enter') this.pointerDown(0, 0, 0, false); },

    bot: function (dt) {
      if (!mov.on || over) return;
      if (bot.plan !== count) planBot();
      if (mov.dir > 0 && mov.o >= bot.target - mov.v * dt * 0.5) drop();
    },
  });
})();
