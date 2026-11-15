/* Inkland: drag to steer, loop out of your land and back to claim everything inside the trail. */
(function () {
  'use strict';
  var D = window.Dailies;
  var PI = Math.PI, TAU = PI * 2;
  var COLS = 60, ROWS = 90, N = 0, VW = 61;
  var DXS = [1, 0, -1, 0], DYS = [0, 1, 0, -1];
  var NAMES = ['You', 'kaz', 'devon.plays', 'noor.runs', 'tofu', 'juno'];
  var BASE = ['#FF4D79', '#34C5F3', '#A6E030', '#9B7CF6', '#FF9A38', '#2FCD8D'];
  var ORD = ['1st', '2nd', '3rd', '4th', '5th', '6th'];
  var REST = 0, EXIT = 1, LEG1 = 2, LEG2 = 3, LEG3 = 4, SEEK = 5, HUNT = 6;
  var BOTS = [
    { speed: 15, turn: 8.5, minL: 8, maxL: 12, restA: 0.2, restB: 0.45, aggr: 0.5, alert: 1, sight: 7, safety: 1.25, margin: 0.35, caution: 1.6 },
    { speed: 13.4, turn: 7, minL: 6, maxL: 11, restA: 0.8, restB: 2.3, aggr: 0.4, alert: 0.3, sight: 8, safety: 1, margin: 0.2, caution: 0.4 },
    { speed: 12.6, turn: 7, minL: 4, maxL: 8, restA: 1.2, restB: 3.0, aggr: 0.12, alert: 0.7, sight: 6, safety: 1.1, margin: 0.3, caution: 0.9 },
    { speed: 13.8, turn: 7.5, minL: 5, maxL: 9, restA: 0.9, restB: 2.6, aggr: 0.28, alert: 0.5, sight: 7, safety: 1, margin: 0.25, caution: 0.6 },
    { speed: 12.2, turn: 6.5, minL: 6, maxL: 11, restA: 1.4, restB: 3.2, aggr: 0.18, alert: 0.28, sight: 6, safety: 1, margin: 0.2, caution: 0.4 },
    { speed: 13.2, turn: 7, minL: 5, maxL: 9, restA: 1.0, restB: 2.8, aggr: 0.6, alert: 0.5, sight: 9, safety: 1, margin: 0.25, caution: 0.5 }
  ];
  var HERO_LOOPS = [[7, 8], [9, 10], [19, 20], [8, 9], [11, 11], [20, 18], [9, 10], [12, 12]];

  function hexRgb(h) { var n = parseInt(h.slice(1), 16); return [n >> 16, (n >> 8) & 255, n & 255]; }
  function mix(a, b, t) { return 'rgb(' + Math.round(a[0] + (b[0] - a[0]) * t) + ',' + Math.round(a[1] + (b[1] - a[1]) * t) + ',' + Math.round(a[2] + (b[2] - a[2]) * t) + ')'; }
  function rgba(a, al) { return 'rgba(' + a[0] + ',' + a[1] + ',' + a[2] + ',' + al + ')'; }
  var WHITE = [255, 255, 255], INK = [18, 10, 70];
  var PAL = BASE.map(function (h) {
    var c = hexRgb(h);
    return {
      base: h, rgb: c,
      top: mix(c, WHITE, 0.2), shade: mix(c, INK, 0.14), dark: mix(c, INK, 0.42), darkA: rgba(hexRgb('#1A0F5A'), 0.34),
      halo: rgba(c, 0.17), pale: mix(c, WHITE, 0.76), side: mix(c, WHITE, 0.4), soft: mix(c, WHITE, 0.5), trail: mix(c, WHITE, 0.1)
    };
  });

  var W = 0, H = 0, availW = 0, availH = 0, availY = 0, AX = 0, AY = 0, AW = 0, AH = 0, CELL = 6, AR = 12, LS = 1;
  var bg = null, LA = null, LB = null, la = null, lb = null;
  var owner = null, trail = null, mark = null, queue = null, vmask = null, sel = null, stamp = 0;
  var P = [], order = [], paths = [], dirty = [0, 0, 0, 0, 0, 0];
  var layerDirty = false, pend = { x: 0, y: 0, r: 0, on: false }, wave = { on: false, x: 0, y: 0, r: 0, max: 0, t: 0 };
  var fx = [], pops = [], parts = [];
  var joy = { active: false, id: -1, ax: 0, ay: 0, x: 0, y: 0 };
  var T = 0, timeLeft = 75, roundLen = 75, playing = false, over = false, overT = 0, shake = 0, flash = 0, hudPop = 0, dispShare = 0;
  var lastSec = -1, lastScore = -1, heroBias = 0.5, heroGrace = 6, polite = 0.6, finalRank = 0, ready = false;
  var G, commitWait = 0;

  function clamp(v, a, b) { return v < a ? a : v > b ? b : v; }
  function angDiff(a, b) { var d = (a - b) % TAU; if (d > PI) d -= TAU; else if (d < -PI) d += TAU; return d; }
  function mkCanvas(w, h) { var c = document.createElement('canvas'); c.width = Math.max(1, Math.round(w)); c.height = Math.max(1, Math.round(h)); return c; }
  function rrp(c, x, y, w, h, r) {
    c.beginPath();
    if (c.roundRect) c.roundRect(x, y, w, h, r);
    else { c.moveTo(x + r, y); c.arcTo(x + w, y, x + w, y + h, r); c.arcTo(x + w, y + h, x, y + h, r); c.arcTo(x, y + h, x, y, r); c.arcTo(x, y, x + w, y, r); c.closePath(); }
  }

  /* ---------- layout ---------- */
  function layout() {
    W = D.W || 390; H = D.H || 844;
    availY = D.safe.top + 166;
    availW = W - 16;
    availH = Math.max(120, H - D.safe.bottom - 16 - availY);
  }
  function fitArena() {
    CELL = Math.min(availW / COLS, availH / ROWS);
    AW = CELL * COLS; AH = CELL * ROWS;
    AX = (W - AW) / 2; AY = availY + (availH - AH) / 2;
    AR = Math.min(14, CELL * 2.2);
  }
  function buildBg() {
    var dpr = D.dpr || 1, c, g, x, y, i, j, sp = CELL * 2, x0, y0, pass;
    bg = mkCanvas(W * dpr, H * dpr);
    c = bg.getContext('2d'); c.setTransform(dpr, 0, 0, dpr, 0, 0);
    g = c.createLinearGradient(0, 0, 0, H); g.addColorStop(0, '#12154F'); g.addColorStop(0.5, '#0E1142'); g.addColorStop(1, '#0A0C34');
    c.fillStyle = g; c.fillRect(0, 0, W, H);
    x0 = AX - Math.ceil(AX / sp) * sp + sp; y0 = AY - Math.ceil(AY / sp) * sp + sp;
    for (pass = 0; pass < 2; pass++) {
      c.save();
      if (pass === 1) {
        c.fillStyle = 'rgba(96,112,255,0.10)'; rrp(c, AX - 5, AY - 5, AW + 10, AH + 10, AR + 5); c.fill();
        g = c.createLinearGradient(0, AY, 0, AY + AH); g.addColorStop(0, '#242D92'); g.addColorStop(1, '#1B2176');
        c.fillStyle = g; rrp(c, AX, AY, AW, AH, AR); c.fill();
        c.clip();
        g = c.createRadialGradient(AX + AW / 2, AY + AH * 0.45, 0, AX + AW / 2, AY + AH * 0.45, Math.max(AW, AH) * 0.62);
        g.addColorStop(0, 'rgba(84,104,240,0.30)'); g.addColorStop(1, 'rgba(84,104,240,0)');
        c.fillStyle = g; c.fillRect(AX, AY, AW, AH);
      }
      c.fillStyle = pass ? 'rgba(170,184,255,0.13)' : 'rgba(150,164,255,0.06)';
      for (y = y0, j = 0; y < H; y += sp, j++) for (x = x0, i = 0; x < W; x += sp, i++) c.fillRect(x - 0.6, y - 0.6, 1.2, 1.2);
      c.fillStyle = pass ? 'rgba(178,190,255,0.34)' : 'rgba(150,164,255,0.14)';
      for (y = y0 + sp * 2; y < H; y += sp * 6) for (x = x0 + sp * 2; x < W; x += sp * 6) { c.fillRect(x - 3.5, y - 0.6, 7, 1.2); c.fillRect(x - 0.6, y - 3.5, 1.2, 7); }
      c.restore();
    }
    c.lineWidth = 1.5; c.strokeStyle = 'rgba(150,164,255,0.62)'; rrp(c, AX, AY, AW, AH, AR); c.stroke();
    c.lineWidth = 1; c.strokeStyle = 'rgba(10,12,60,0.5)'; rrp(c, AX + 1.6, AY + 1.6, AW - 3.2, AH - 3.2, AR - 1.5); c.stroke();
  }
  function makeLayers() {
    LS = Math.min(D.dpr || 1, 2);
    LA = mkCanvas(AW * LS, AH * LS); LB = mkCanvas(AW * LS, AH * LS);
    la = LA.getContext('2d'); lb = LB.getContext('2d');
  }

  /* ---------- contours ---------- */
  function traceLoops(arr, val) {
    var x, y, i, v, d, nd, m, cur, pts, loops = [], nv = VW * (ROWS + 1);
    vmask.fill(0);
    for (y = 0; y < ROWS; y++) for (x = 0; x < COLS; x++) {
      i = y * COLS + x;
      if (arr[i] !== val) continue;
      if (y === 0 || arr[i - COLS] !== val) vmask[y * VW + x] |= 1;
      if (x === COLS - 1 || arr[i + 1] !== val) vmask[y * VW + x + 1] |= 2;
      if (y === ROWS - 1 || arr[i + COLS] !== val) vmask[(y + 1) * VW + x + 1] |= 4;
      if (x === 0 || arr[i - 1] !== val) vmask[(y + 1) * VW + x] |= 8;
    }
    for (v = 0; v < nv; v++) {
      while (vmask[v]) {
        m = vmask[v]; d = (m & 1) ? 0 : (m & 2) ? 1 : (m & 4) ? 2 : 3;
        pts = []; cur = v;
        for (;;) {
          vmask[cur] &= ~(1 << d);
          pts.push(cur % VW + DXS[d] * 0.5, ((cur / VW) | 0) + DYS[d] * 0.5);
          cur += DXS[d] + DYS[d] * VW;
          m = vmask[cur];
          if (!m) break;
          nd = (d + 1) & 3;
          if (!(m & (1 << nd))) { nd = d; if (!(m & (1 << nd))) { nd = (d + 3) & 3; if (!(m & (1 << nd))) break; } }
          d = nd;
        }
        if (pts.length >= 8) loops.push(pts);
      }
    }
    return loops;
  }
  function smooth(p, passes) {
    var n = p.length >> 1, k, i, x, y, px, py, nx, ny, fx0, fy0;
    for (k = 0; k < passes; k++) {
      fx0 = p[0]; fy0 = p[1]; px = p[2 * n - 2]; py = p[2 * n - 1];
      for (i = 0; i < n; i++) {
        x = p[2 * i]; y = p[2 * i + 1];
        if (i < n - 1) { nx = p[2 * i + 2]; ny = p[2 * i + 3]; } else { nx = fx0; ny = fy0; }
        if (x > 0.01 && x < COLS - 0.01) p[2 * i] = (px + 2 * x + nx) * 0.25;
        if (y > 0.01 && y < ROWS - 0.01) p[2 * i + 1] = (py + 2 * y + ny) * 0.25;
        px = x; py = y;
      }
    }
  }
  function loopsToPath(loops) {
    var path = new Path2D(), l, p, n, i, x, y, nx, ny, sc = CELL;
    for (l = 0; l < loops.length; l++) {
      p = loops[l]; n = p.length >> 1;
      smooth(p, 3);
      path.moveTo((p[2 * n - 2] + p[0]) * 0.5 * sc, (p[2 * n - 1] + p[1]) * 0.5 * sc);
      for (i = 0; i < n; i++) {
        x = p[2 * i]; y = p[2 * i + 1];
        if (i < n - 1) { nx = p[2 * i + 2]; ny = p[2 * i + 3]; } else { nx = p[0]; ny = p[1]; }
        path.quadraticCurveTo(x * sc, y * sc, (x + nx) * 0.5 * sc, (y + ny) * 0.5 * sc);
      }
      path.closePath();
    }
    return path;
  }
  function renderLayer(c) {
    var i, pal, path;
    c.setTransform(LS, 0, 0, LS, 0, 0);
    c.clearRect(0, 0, AW + 1, AH + 1);
    c.save();
    rrp(c, 0, 0, AW, AH, AR); c.clip();
    c.lineJoin = 'round';
    for (i = 0; i < 6; i++) { c.strokeStyle = PAL[i].halo; c.lineWidth = CELL * 2.8; c.stroke(paths[i]); }
    c.fillStyle = 'rgba(8,8,52,0.34)';
    for (i = 0; i < 6; i++) { c.save(); c.translate(CELL * 0.15, CELL * 0.6); c.fill(paths[i]); c.restore(); }
    for (i = 5; i >= 0; i--) {
      pal = PAL[i]; path = paths[i];
      c.fillStyle = pal.top; c.fill(path);
      c.save(); c.clip(path);
      c.strokeStyle = pal.base; c.lineWidth = CELL * 3.4; c.stroke(path);
      c.strokeStyle = pal.shade; c.lineWidth = CELL * 1.5; c.stroke(path);
      c.translate(-CELL * 0.3, -CELL * 0.5); c.strokeStyle = pal.darkA; c.lineWidth = CELL * 1.0; c.stroke(path);
      c.translate(CELL * 0.62, CELL * 1.04); c.strokeStyle = 'rgba(255,255,255,0.5)'; c.lineWidth = CELL * 0.42; c.stroke(path);
      c.restore();
    }
    c.restore();
  }
  function commitLayer(animate) {
    var i;
    lb.setTransform(1, 0, 0, 1, 0, 0);
    if (animate) { lb.clearRect(0, 0, LB.width, LB.height); lb.drawImage(LA, 0, 0); }
    for (i = 0; i < 6; i++) if (dirty[i] || !paths[i]) { paths[i] = loopsToPath(traceLoops(owner, i)); dirty[i] = 0; }
    renderLayer(la);
    if (animate) { wave.on = true; wave.t = 0; wave.r = 0; wave.x = pend.x; wave.y = pend.y; wave.max = pend.r; }
    pend.on = false; pend.r = 0; layerDirty = false;
  }
  function touchLayer(ox, oy, minx, miny, maxx, maxy, wantWave) {
    var r = 0, dx, dy, k;
    layerDirty = true;
    if (!wantWave) return;
    for (k = 0; k < 4; k++) {
      dx = ((k & 1) ? maxx + 1 : minx) - ox; dy = ((k & 2) ? maxy + 1 : miny) - oy;
      r = Math.max(r, Math.sqrt(dx * dx + dy * dy));
    }
    pend.x = ox * CELL; pend.y = oy * CELL; pend.r = (r + 3) * CELL; pend.on = true;
  }

  /* ---------- world ---------- */
  function stampBlob(id, cx, cy, r, organic) {
    var x, y, a, rr, dx, dy, i, p1 = D.rand() * TAU, p2 = D.rand() * TAU;
    for (y = Math.max(0, Math.floor(cy - r * 1.4)); y <= Math.min(ROWS - 1, Math.ceil(cy + r * 1.4)); y++) {
      for (x = Math.max(0, Math.floor(cx - r * 1.4)); x <= Math.min(COLS - 1, Math.ceil(cx + r * 1.4)); x++) {
        dx = x + 0.5 - cx; dy = y + 0.5 - cy; a = Math.atan2(dy, dx);
        rr = r * (1 + organic * (0.1 * Math.sin(2 * a + p1) + 0.06 * Math.sin(3 * a + p2)));
        if (dx * dx + dy * dy < rr * rr) { i = y * COLS + x; if (owner[i] >= 0) dirty[owner[i]] = 1; owner[i] = id; }
      }
    }
    dirty[id] = 1;
  }
  function recount() {
    var i, o, c, x, y, j, k, t;
    for (i = 0; i < 6; i++) { P[i].count = 0; P[i].sx = 0; P[i].sy = 0; }
    for (y = 0, i = 0; y < ROWS; y++) for (x = 0; x < COLS; x++, i++) { o = owner[i]; if (o >= 0) { c = P[o]; c.count++; c.sx += x; c.sy += y; } }
    for (i = 0; i < 6; i++) {
      c = P[i];
      if (c.count) { c.cx = c.sx / c.count + 0.5; c.cy = c.sy / c.count + 0.5; }
      c.share = c.count / N * 100;
      t = c.share.toFixed(1) + '%';
      if (t !== c.pct) c.pct = t;
    }
    for (j = 1; j < 6; j++) { k = j; while (k > 0 && P[order[k]].count > P[order[k - 1]].count) { t = order[k]; order[k] = order[k - 1]; order[k - 1] = t; k--; } }
  }
  function nearestOwn(c, fx0, fy0) {
    var x, y, i, best = -1, bd = 1e9, dx, dy, d, id = c.id;
    for (y = 0, i = 0; y < ROWS; y++) {
      dy = y + 0.5 - fy0; dy *= dy;
      if (dy >= bd) { i += COLS; continue; }
      for (x = 0; x < COLS; x++, i++) {
        if (owner[i] !== id) continue;
        dx = x + 0.5 - fx0; d = dx * dx + dy;
        if (d < bd) { bd = d; best = i; }
      }
    }
    return best;
  }
  function makeCreature(id, sx, sy) {
    var b = BOTS[id], a = Math.atan2(ROWS / 2 - sy, COLS / 2 - sx) + (D.rand() - 0.5) * 0.8;
    return {
      id: id, name: NAMES[id], pal: PAL[id], b: b, x: sx, y: sy, ang: a, want: a, aim: a, speed: b.speed, turn: b.turn,
      alive: true, dead: 0, homeless: false, tp: [], tc: [], odo: 0, count: 0, share: 0, pct: '0.0%', sx: 0, sy: 0, cx: sx, cy: sy,
      cell: (sy | 0) * COLS + (sx | 0), pop: 0, squash: 0, lean: 0, blink: D.rand() * 4, spawnT: 0,
      mode: REST, rest: id === 0 ? 0.25 : 0.2 + D.rand() * 1.6, modeT: 0, thinkT: D.rand() * 0.12, pdir: a, l1: 6, l2: 6, side: 1, legAt: 0,
      prey: null, huntCool: 2 + D.rand() * 3, loops: 0, planDone: false, hx: 0, hy: 0, polite: true, avoidT: 0, tagW: 0, rowY: -1
    };
  }
  function addPart(x, y, vx, vy, life, size, color, tick) {
    var p, i;
    for (i = 0; i < parts.length; i++) if (parts[i].life <= 0) { p = parts[i]; break; }
    if (!p) { if (parts.length >= 180) return; p = {}; parts.push(p); }
    p.x = x; p.y = y; p.vx = vx; p.vy = vy; p.life = life; p.max = life; p.size = size; p.color = color; p.tick = tick;
  }
  function burst(c, n, sp) {
    var i, a, v, px = c.x * CELL, py = c.y * CELL;
    for (i = 0; i < n; i++) {
      a = Math.random() * TAU; v = sp * (0.35 + Math.random() * 0.75);
      addPart(px, py, Math.cos(a) * v, Math.sin(a) * v, 0.45 + Math.random() * 0.35, 2 + Math.random() * 3.2, i % 3 ? c.pal.base : c.pal.pale, i % 4 === 0);
    }
  }
  function popup(txt, x, y, size, col, dur) { if (pops.length > 8) pops.shift(); pops.push({ txt: txt, x: x, y: y, t: 0, dur: dur || 1.2, size: size, col: col }); }

  function cut(v, by, wiped) {
    var i, ci, n = v.tc.length;
    if (!v.alive) return;
    for (i = 0; i < n; i++) {
      ci = v.tc[i];
      if (trail[ci] === v.id + 1) trail[ci] = 0;
      if (i % 3 === 0) addPart((ci % COLS + 0.5) * CELL, (((ci / COLS) | 0) + 0.5) * CELL, (Math.random() - 0.5) * 40, (Math.random() - 0.5) * 40 - 10, 0.35 + Math.random() * 0.4, 2.2 + Math.random() * 2, v.pal.base, false);
    }
    v.tc.length = 0; v.tp.length = 0; v.odo = 0;
    v.alive = false; v.dead = v.id === 0 ? 1.3 : 1.6; v.homeless = !!wiped || v.count === 0;
    burst(v, 16, 150);
    if (by) by.pop = 1;
    if (v.id === 0) {
      D.haptic('error'); shake = Math.max(shake, 11); flash = Math.max(flash, 0.25);
      popup(wiped ? 'WIPED OUT' : 'CUT', v.x * CELL, v.y * CELL - 18, 30, '#FF4D79', 1.3);
      D.tone({ freq: 300, slide: 70, dur: 0.3, type: 'sawtooth', vol: 0.1 });
    } else if (by && by.id === 0) {
      D.haptic('heavy'); shake = Math.max(shake, 7);
      popup('CUT ' + v.name.toUpperCase(), v.x * CELL, v.y * CELL - 18, 22, '#FFFFFF', 1.2);
      D.tone({ freq: 520, slide: 900, dur: 0.16, type: 'square', vol: 0.08 });
    }
  }

  function flood(id) {
    var qh = 0, qt = 0, x, y, i;
    mark.fill(0);
    for (x = 0; x < COLS; x++) {
      i = x; if (owner[i] !== id) { mark[i] = 1; queue[qt++] = i; }
      i = (ROWS - 1) * COLS + x; if (owner[i] !== id) { mark[i] = 1; queue[qt++] = i; }
    }
    for (y = 1; y < ROWS - 1; y++) {
      i = y * COLS; if (owner[i] !== id) { mark[i] = 1; queue[qt++] = i; }
      i = y * COLS + COLS - 1; if (owner[i] !== id) { mark[i] = 1; queue[qt++] = i; }
    }
    while (qh < qt) {
      i = queue[qh++]; x = i % COLS;
      if (x > 0 && !mark[i - 1] && owner[i - 1] !== id) { mark[i - 1] = 1; queue[qt++] = i - 1; }
      if (x < COLS - 1 && !mark[i + 1] && owner[i + 1] !== id) { mark[i + 1] = 1; queue[qt++] = i + 1; }
      if (i >= COLS && !mark[i - COLS] && owner[i - COLS] !== id) { mark[i - COLS] = 1; queue[qt++] = i - COLS; }
      if (i < N - COLS && !mark[i + COLS] && owner[i + COLS] !== id) { mark[i + COLS] = 1; queue[qt++] = i + COLS; }
    }
  }
  function claim(c) {
    var id = c.id, i, ci, o, n = c.tc.length, gained = 0, x, y, minx = COLS, miny = ROWS, maxx = 0, maxy = 0, sx = 0, sy = 0, pct, big, loops, f, l, p, k, step, m, dx, dy, d;
    stamp++; if (stamp > 250) { sel.fill(0); stamp = 1; }
    for (i = 0; i < n; i++) {
      ci = c.tc[i];
      if (trail[ci] === id + 1) trail[ci] = 0;
      if (owner[ci] !== id) { o = owner[ci]; if (o >= 0) dirty[o] = 1; owner[ci] = id; sel[ci] = stamp; }
    }
    c.tc.length = 0; c.tp.length = 0; c.odo = 0;
    c.mode = REST; c.rest = c.b.restA + D.rand() * (c.b.restB - c.b.restA); c.aim = c.ang;
    flood(id);
    for (y = 0, i = 0; y < ROWS; y++) for (x = 0; x < COLS; x++, i++) {
      if (!mark[i] && owner[i] !== id) { o = owner[i]; if (o >= 0) dirty[o] = 1; owner[i] = id; sel[i] = stamp; }
      if (sel[i] === stamp) { gained++; sx += x; sy += y; if (x < minx) minx = x; if (x > maxx) maxx = x; if (y < miny) miny = y; if (y > maxy) maxy = y; }
    }
    if (!gained) return;
    dirty[id] = 1;
    recount();
    pct = gained / N * 100; big = pct >= 5;
    touchLayer(c.x, c.y, minx, miny, maxx, maxy, id === 0 || gained > 90);
    c.pop = 1; c.squash = 1;
    if (fx.length < 6) {
      loops = traceLoops(sel, stamp);
      f = { path: loopsToPath(loops), t: 0, ox: c.x * CELL, oy: c.y * CELL, r: Math.max(maxx - minx, maxy - miny) * 1.3 * CELL + 20, ticks: [], col: c.pal, big: gained > 30, dur: big ? 0.8 : 0.6 };
      m = 0; for (l = 0; l < loops.length; l++) m += loops[l].length >> 1;
      step = Math.max(3, Math.ceil(m / 54));
      for (l = 0; l < loops.length; l++) {
        p = loops[l]; k = p.length >> 1;
        if (k < 10) continue;
        for (i = (step >> 1); i < k - 1; i += step) {
          dx = p[2 * i + 2] - p[2 * i]; dy = p[2 * i + 3] - p[2 * i + 1]; d = Math.sqrt(dx * dx + dy * dy) || 1;
          f.ticks.push(p[2 * i] * CELL, p[2 * i + 1] * CELL, dy / d, -dx / d);
        }
      }
      fx.push(f);
    }
    if (id === 0 && pct < 0.3) D.haptic('select');
    else if (id === 0) {
      popup('+' + pct.toFixed(1) + '%', (sx / gained + 0.5) * CELL, (sy / gained + 0.5) * CELL, clamp(20 + pct * 1.6, 22, 44), '#FFFFFF', big ? 1.6 : 1.2);
      if (big) D.haptic('heavy');
      D.haptic('success');
      shake = Math.max(shake, big ? 9 : 3 + pct); hudPop = 1;
      D.tone({ freq: big ? 440 : 520, slide: big ? 1320 : 1040, dur: big ? 0.3 : 0.18, type: 'triangle', vol: 0.12 });
    } else if (pct >= 3) shake = Math.max(shake, 2);
    for (i = 0; i < 6; i++) if (P[i].count === 0 && P[i].alive) cut(P[i], c, true);
  }
  function enter(c, ci, px, py) {
    var t = trail[ci];
    c.cell = ci;
    if (t && t - 1 !== c.id) cut(P[t - 1], c, false);
    if (owner[ci] === c.id) { if (c.tc.length) claim(c); return; }
    if (!c.tc.length) {
      c.tp.length = 0; c.tp.push(px, py); c.odo = 0;
      if (c.id === 0) { D.haptic('light'); D.tone({ freq: 660, dur: 0.06, type: 'sine', vol: 0.06 }); }
    }
    if (trail[ci] !== c.id + 1) { trail[ci] = c.id + 1; c.tc.push(ci); }
  }
  function moveCreature(c, dt) {
    var d = angDiff(c.want, c.ang), mt = c.turn * dt, step = d > mt ? mt : d < -mt ? -mt : d;
    var px = c.x, py = c.y, nx, ny, cxi, cyi, ci, ox, oy, n, dx, dy;
    c.ang += step;
    c.lean += (step / mt * 0.2 - c.lean) * Math.min(1, dt * 10);
    nx = clamp(px + Math.cos(c.ang) * c.speed * dt, 0.55, COLS - 0.55);
    ny = clamp(py + Math.sin(c.ang) * c.speed * dt, 0.55, ROWS - 0.55);
    c.x = nx; c.y = ny;
    cxi = nx | 0; cyi = ny | 0; ci = cyi * COLS + cxi;
    if (ci !== c.cell) {
      ox = c.cell % COLS; oy = (c.cell / COLS) | 0;
      if (ox !== cxi && oy !== cyi) { enter(c, oy * COLS + cxi, px, py); if (!c.alive) return; }
      enter(c, ci, px, py);
      if (!c.alive) return;
    }
    if (c.tc.length) {
      dx = nx - px; dy = ny - py; c.odo += Math.sqrt(dx * dx + dy * dy);
      n = c.tp.length; dx = nx - c.tp[n - 2]; dy = ny - c.tp[n - 1];
      if (dx * dx + dy * dy > 0.8) c.tp.push(nx, ny);
    }
  }
  function respawn(c) {
    var k, x, y, bx = COLS / 2, by = ROWS / 2, bs = -1e9, s, i, e, d, j;
    if (c.count === 0) {
      for (k = 0; k < 24; k++) {
        x = 6 + D.rand() * (COLS - 12); y = 6 + D.rand() * (ROWS - 12); s = 1e9;
        for (i = 0; i < 6; i++) { e = P[i]; if (e === c) continue; d = Math.sqrt((e.x - x) * (e.x - x) + (e.y - y) * (e.y - y)); if (d < s) s = d; }
        if (owner[(y | 0) * COLS + (x | 0)] < 0) s += 8;
        if (s > bs) { bs = s; bx = x; by = y; }
      }
      stampBlob(c.id, bx, by, 3.7, 1);
      recount();
      touchLayer(bx, by, bx - 5, by - 5, bx + 5, by + 5, false);
      c.x = bx; c.y = by;
    } else {
      j = nearestOwn(c, c.cx, c.cy);
      c.x = j % COLS + 0.5; c.y = ((j / COLS) | 0) + 0.5;
    }
    c.cell = (c.y | 0) * COLS + (c.x | 0);
    c.alive = true; c.homeless = false; c.spawnT = 0.45; c.pop = 1;
    c.ang = c.want = c.aim = Math.atan2(ROWS / 2 - c.y, COLS / 2 - c.x) + (D.rand() - 0.5);
    c.mode = REST; c.rest = c.b.restA + D.rand() * c.b.restB; c.huntCool = 1.5;
    if (c.id === 0) D.haptic('medium');
  }

  /* ---------- brains (the five rivals, and the clip bot for the player's creature) ---------- */
  function inb(x, y, m) { return x >= m && y >= m && x <= COLS - m && y <= ROWS - m; }
  function blocked(c, a) { return !inb(c.x + Math.cos(a) * 2.4, c.y + Math.sin(a) * 2.4, 1.1); }
  function ray(c, x, y, a, len) {
    var s = 0, d, px, py, o, i, e, dx, dy, ca = Math.cos(a), sa = Math.sin(a);
    for (d = 1.5; d <= len; d += 1.5) {
      px = x + ca * d; py = y + sa * d;
      if (!inb(px, py, 1.6)) { s -= 4; continue; }
      o = owner[(py | 0) * COLS + (px | 0)];
      s += o === c.id ? -0.6 : o >= 0 ? 1.2 : 1;
      for (i = 0; i < 6; i++) { e = P[i]; if (e === c || !e.alive) continue; dx = e.x - px; dy = e.y - py; if (dx * dx + dy * dy < 30) s -= c.b.caution; }
    }
    return s;
  }
  function plan(c) {
    var b = c.b, hero = c.id === 0, l1, l2, k, nd, a, s, sc, best = -1e9, ex, ey, d, L, ca, sa;
    if (hero) { if (c.planDone) c.loops++; c.planDone = false; L = HERO_LOOPS[c.loops % HERO_LOOPS.length]; l1 = L[0] + D.rand() * 2; l2 = L[1] + D.rand() * 2; }
    else { l1 = D.randRange(b.minL, b.maxL); l2 = D.randRange(b.minL, b.maxL); if (c.share > 12) { l1 *= 0.8; l2 *= 0.8; } }
    k = clamp(Math.sqrt(N / 5580), 0.6, 1.1); l1 *= k; l2 *= k;
    nd = hero ? 4 : 12;
    for (k = 0; k < nd; k++) {
      a = hero ? k * PI / 2 + (D.rand() - 0.5) * 0.1 : k * TAU / 12 + (D.rand() - 0.5) * 0.5;
      ca = Math.cos(a); sa = Math.sin(a);
      for (d = 0; d < 40; d += 1) { ex = c.x + ca * d; ey = c.y + sa * d; if (!inb(ex, ey, 0.6) || owner[(ey | 0) * COLS + (ex | 0)] !== c.id) break; }
      if (!inb(ex, ey, 1.5)) continue;
      for (s = -1; s <= 1; s += 2) {
        sc = ray(c, ex, ey, a, l1) + ray(c, ex + ca * l1, ey + sa * l1, a + s * PI / 2, l2) - d * 0.35 + D.rand() * (hero ? 1.5 : 3.5);
        if (sc > best) { best = sc; c.pdir = a; c.side = s; }
      }
    }
    c.l1 = l1; c.l2 = l2; c.polite = D.rand() < polite;
    if (best === -1e9) { c.pdir = Math.atan2(ROWS / 2 - c.y, COLS / 2 - c.x); c.side = D.rand() < 0.5 ? -1 : 1; }
  }
  function danger(c) {
    var j = nearestOwn(c, c.x, c.y), th, i, e, k, n = c.tc.length, ci, dx, dy, d, al, pe, ca, sa, lim, near;
    if (j < 0) return false;
    dx = j % COLS + 0.5 - c.x; dy = ((j / COLS) | 0) + 0.5 - c.y;
    th = Math.sqrt(dx * dx + dy * dy) / c.speed;
    lim = th * c.b.safety + c.b.margin;
    for (i = 0; i < 6; i++) {
      e = P[i]; if (e === c || !e.alive) continue;
      if (D.clip && c.id === 0 && !(e.mode === HUNT && e.prey === c)) continue;
      ca = Math.cos(e.ang); sa = Math.sin(e.ang); near = e.mode === HUNT && e.prey === c ? 9 : 4;
      for (k = -1; k < n; k += 2) {
        if (k < 0) { dx = c.x - e.x; dy = c.y - e.y; } else { ci = c.tc[k]; dx = ci % COLS + 0.5 - e.x; dy = ((ci / COLS) | 0) + 0.5 - e.y; }
        d = dx * dx + dy * dy;
        if (d < near * near) { if (Math.sqrt(d) / e.speed < lim + 0.25) return true; continue; }
        al = dx * ca + dy * sa; if (al <= 0) continue;
        pe = dx * sa - dy * ca; if (pe < 0) pe = -pe;
        if (pe < 2 + al * 0.3 && al / e.speed < lim) return true;
      }
    }
    return false;
  }
  function findPrey(c) {
    var i, e, k, n, ci, dx, dy, d, best = null, bd = c.b.sight * c.b.sight;
    for (i = 0; i < 6; i++) {
      e = P[i]; if (e === c || !e.alive) continue;
      n = e.tc.length; if (n < 4) continue;
      for (k = 0; k < n; k += 2) { ci = e.tc[k]; dx = ci % COLS + 0.5 - c.x; dy = ((ci / COLS) | 0) + 0.5 - c.y; d = dx * dx + dy * dy; if (d < bd) { bd = d; best = e; c.hx = c.x + dx; c.hy = c.y + dy; } }
    }
    return best;
  }
  function brain(c, dt) {
    var out = c.tc.length > 0, onLand = owner[c.cell] === c.id, tick, e, j, lx = 0, ly = 0, k, n, ci, dx, dy, d, bd, h;
    c.modeT += dt; c.huntCool -= dt; c.thinkT -= dt;
    tick = c.thinkT <= 0;
    if (tick) c.thinkT = 0.1 + c.id * 0.008;
    h = P[0];
    if (c.id > 0 && c.polite && c.mode !== HUNT && h.alive && h.tc.length) {
      n = h.tc.length; bd = 14;
      dx = h.x + Math.cos(h.ang) * 1.5 - c.x; dy = h.y + Math.sin(h.ang) * 1.5 - c.y; d = (dx * dx + dy * dy) * 0.5;
      if (d < bd) { bd = d; lx = dx; ly = dy; }
      for (k = 0; k < n; k++) { ci = h.tc[k]; dx = ci % COLS + 0.5 - c.x; dy = ((ci / COLS) | 0) + 0.5 - c.y; d = dx * dx + dy * dy; if (d < bd) { bd = d; lx = dx; ly = dy; } }
      if (bd < 14) {
        c.aim = Math.atan2(-ly, -lx);
        if (out) c.mode = SEEK; else if (c.mode !== REST) { c.mode = REST; c.rest = 0.6 + D.rand(); }
        return;
      }
    }
    if (tick && out && c.mode !== SEEK && c.odo > 2.5 && danger(c) && D.rand() < c.b.alert) c.mode = SEEK;
    if (tick && c.huntCool <= 0 && T > 4 && (c.mode === REST || c.mode === EXIT || (c.mode === LEG1 && c.odo < 6))) {
      e = findPrey(c);
      if (e) {
        if (D.rand() < c.b.aggr * (e.id === 0 ? (T > heroGrace ? heroBias : 0) : 1)) { c.mode = HUNT; c.prey = e; c.modeT = 0; }
        else c.huntCool = 1.2;
      }
    }
    switch (c.mode) {
      case REST:
        c.rest -= dt;
        if (out) { c.mode = SEEK; break; }
        if (tick) {
          lx = c.x + Math.cos(c.aim) * 2.6; ly = c.y + Math.sin(c.aim) * 2.6;
          if (!inb(lx, ly, 1) || owner[(ly | 0) * COLS + (lx | 0)] !== c.id) c.aim = Math.atan2(c.cy - c.y, c.cx - c.x) + (D.rand() - 0.5) * 1.4;
        }
        if (c.rest <= 0) { plan(c); c.mode = EXIT; c.modeT = 0; }
        break;
      case EXIT:
        c.aim = c.pdir;
        if (out) c.mode = LEG1;
        else if (c.modeT > 3) { plan(c); c.modeT = 0; }
        break;
      case LEG1:
        c.aim = c.pdir;
        if (c.odo >= c.l1 || blocked(c, c.aim)) { c.mode = LEG2; c.legAt = c.odo; }
        break;
      case LEG2:
        c.aim = c.pdir + c.side * PI / 2;
        if (c.odo - c.legAt >= c.l2 || blocked(c, c.aim)) { c.mode = LEG3; c.legAt = c.odo; c.planDone = true; }
        break;
      case LEG3:
        c.aim = c.pdir + PI;
        if (c.odo - c.legAt >= c.l1 + 3 || blocked(c, c.aim)) c.mode = SEEK;
        break;
      case SEEK:
        if (!out && onLand) { c.mode = REST; c.rest = 0.3; break; }
        if (tick) { j = nearestOwn(c, c.x, c.y); if (j >= 0) c.aim = Math.atan2(((j / COLS) | 0) + 0.5 - c.y, j % COLS + 0.5 - c.x); }
        break;
      case HUNT:
        e = c.prey;
        if (!e || !e.alive || !e.tc.length || c.modeT > 3.2 || c.odo > 15) { c.mode = out ? SEEK : REST; c.rest = 0.3; c.huntCool = 1.6; c.prey = null; break; }
        if (tick) {
          n = e.tc.length; bd = 1e9;
          for (k = 0; k < n; k++) { ci = e.tc[k]; dx = ci % COLS + 0.5 - c.x; dy = ((ci / COLS) | 0) + 0.5 - c.y; d = dx * dx + dy * dy; if (d < bd) { bd = d; c.hx = c.x + dx; c.hy = c.y + dy; } }
          c.aim = Math.atan2(c.hy - c.y, c.hx - c.x);
        }
        break;
    }
  }

  function finish() {
    var i, me = P[0], sc = Math.round(me.share * 10) / 10;
    over = true; overT = 0; playing = false; joy.active = false;
    for (i = 0; i < 6; i++) if (order[i] === 0) finalRank = i;
    flash = 0.5; shake = Math.max(shake, 5);
    if (finalRank === 0) { D.haptic('success'); burst(me, 22, 190); }
    else D.haptic('medium');
    D.tone({ freq: 880, slide: 440, dur: 0.4, type: 'triangle', vol: 0.12 });
    D.end({ score: sc, unit: '%', headline: ORD[finalRank] + ' of 6' });
  }

  /* ---------- drawing ---------- */
  function trailPath(ctx, c) {
    var p = c.tp, n = p.length, i;
    ctx.beginPath(); ctx.moveTo(p[0] * CELL, p[1] * CELL);
    for (i = 2; i < n - 2; i += 2) ctx.quadraticCurveTo(p[i] * CELL, p[i + 1] * CELL, (p[i] + p[i + 2]) * 0.5 * CELL, (p[i + 1] + p[i + 3]) * 0.5 * CELL);
    if (n > 2) ctx.quadraticCurveTo(p[n - 2] * CELL, p[n - 1] * CELL, c.x * CELL, c.y * CELL); else ctx.lineTo(c.x * CELL, c.y * CELL);
  }
  function crown(ctx, x, y, s) {
    ctx.beginPath(); ctx.moveTo(x - s, y + s * 0.62); ctx.lineTo(x - s, y - s * 0.55); ctx.lineTo(x - s * 0.45, y + s * 0.02); ctx.lineTo(x, y - s * 0.8);
    ctx.lineTo(x + s * 0.45, y + s * 0.02); ctx.lineTo(x + s, y - s * 0.55); ctx.lineTo(x + s, y + s * 0.62); ctx.closePath();
    ctx.fillStyle = '#FFC531'; ctx.fill();
  }
  function drawCreature(ctx, c, state) {
    var s = CELL * 3.5, px = c.x * CELL, py = c.y * CELL, sc = 1 + c.pop * 0.22, k, moving = state === 'playing';
    var bob, tilt, ex, ey, bl, hero = c.id === 0, sq;
    if (c.spawnT > 0) sc *= D.easeOutBack(1 - c.spawnT / 0.45);
    if (state === 'over' && c.id === order[0]) py -= Math.abs(Math.sin(overT * 6)) * CELL * 1.6 * Math.max(0.25, 1 - overT * 0.25);
    bob = Math.sin(T * (moving ? 11 : 3) + c.id * 1.7) * s * (moving ? 0.035 : 0.045);
    tilt = c.lean + Math.sin(T * (moving ? 7 : 2.2) + c.id * 2.1) * 0.06;
    sq = c.squash * 0.2 + (moving ? 0 : Math.sin(T * 3 + c.id) * 0.03);
    ctx.fillStyle = 'rgba(6,6,44,0.36)';
    ctx.beginPath(); ctx.ellipse(px, py + s * 0.46, s * 0.5 * sc, s * 0.2 * sc, 0, 0, TAU); ctx.fill();
    if (hero) {
      ctx.save(); ctx.strokeStyle = 'rgba(255,255,255,0.75)'; ctx.lineWidth = 1.6; ctx.setLineDash([4, 4]); ctx.lineDashOffset = -T * 14;
      ctx.beginPath(); ctx.arc(px, py - s * 0.05, s * 0.92, 0, TAU); ctx.stroke(); ctx.restore();
      if (state === 'ready') {
        k = (T * 0.9) % 1;
        ctx.strokeStyle = 'rgba(255,255,255,' + (0.55 * (1 - k)).toFixed(3) + ')'; ctx.lineWidth = 2;
        ctx.beginPath(); ctx.arc(px, py - s * 0.05, s * (0.95 + k * 1.3), 0, TAU); ctx.stroke();
      }
    }
    ctx.save();
    ctx.translate(px, py - s * 0.1 + bob); ctx.rotate(tilt); ctx.scale(sc * (1 + sq), sc * (1 - sq));
    ctx.fillStyle = c.pal.side; rrp(ctx, -s / 2, -s / 2 + s * 0.14, s, s, s * 0.3); ctx.fill();
    ctx.fillStyle = c.pal.pale; rrp(ctx, -s / 2, -s / 2, s, s * 0.9, s * 0.3); ctx.fill();
    ctx.fillStyle = 'rgba(255,255,255,0.6)'; rrp(ctx, -s * 0.34, -s * 0.4, s * 0.42, s * 0.13, s * 0.065); ctx.fill();
    ex = Math.cos(c.ang) * s * 0.13; ey = Math.sin(c.ang) * s * 0.1 - s * 0.03;
    bl = ((T + c.blink) % 3.4) < 0.12 ? 0.15 : 1;
    ctx.fillStyle = '#1D1447';
    ctx.beginPath(); ctx.ellipse(ex - s * 0.17, ey, s * 0.085, s * 0.115 * bl, 0, 0, TAU); ctx.ellipse(ex + s * 0.17, ey, s * 0.085, s * 0.115 * bl, 0, 0, TAU); ctx.fill();
    if (bl === 1) {
      ctx.fillStyle = '#FFFFFF';
      ctx.beginPath(); ctx.arc(ex - s * 0.19, ey - s * 0.04, s * 0.03, 0, TAU); ctx.arc(ex + s * 0.15, ey - s * 0.04, s * 0.03, 0, TAU); ctx.fill();
    }
    ctx.restore();
  }
  function drawTag(ctx, c, state) {
    var s = CELL * 3.5, hero = c.id === 0, label = hero ? 'YOU' : c.name, lead = order[0] === c.id, w, h = hero ? 15 : 14, x, y, tx;
    ctx.font = D.textFont(hero ? 10 : 9.5, 800);
    if (!c.tagW) c.tagW = ctx.measureText(label).width;
    w = c.tagW + 12 + (lead ? 12 : 0);
    x = clamp(c.x * CELL - w / 2, 3 - AX, W - 3 - AX - w);
    y = c.y * CELL - s * 0.72 - h - 4 - (hero ? Math.abs(Math.sin(T * 3)) * (state === 'ready' ? 4 : 0) : 0);
    ctx.fillStyle = 'rgba(6,6,44,0.3)'; rrp(ctx, x, y + 1.5, w, h, h / 2); ctx.fill();
    ctx.fillStyle = hero ? '#FFFFFF' : 'rgba(13,15,60,0.9)'; rrp(ctx, x, y, w, h, h / 2); ctx.fill();
    if (!hero) { ctx.strokeStyle = 'rgba(190,200,255,0.3)'; ctx.lineWidth = 1; ctx.stroke(); }
    tx = x + 6;
    if (lead) { crown(ctx, tx + 4.5, y + h / 2, 4.4); tx += 12; }
    ctx.fillStyle = hero ? '#F0356A' : '#FFFFFF'; ctx.textAlign = 'left'; ctx.textBaseline = 'middle';
    ctx.fillText(label, tx, y + h / 2 + 0.5);
  }
  function drawFx(ctx, f) {
    var k = f.t / f.dur, e = D.easeOut(Math.min(1, k * 1.3)), a = 1 - k, i, n = f.ticks.length, x, y, nx, ny, d0, d1, pass;
    ctx.globalAlpha = 0.6 * a * a; ctx.fillStyle = '#FFFFFF'; ctx.fill(f.path);
    if (f.big) {
      ctx.save(); ctx.clip(f.path);
      ctx.strokeStyle = '#FFFFFF'; ctx.lineWidth = CELL * 1.6; ctx.globalAlpha = 0.3 * a;
      ctx.beginPath(); ctx.arc(f.ox, f.oy, f.r * e, 0, TAU); ctx.moveTo(f.ox + f.r * e * 0.62, f.oy); ctx.arc(f.ox, f.oy, f.r * e * 0.62, 0, TAU); ctx.stroke();
      ctx.restore();
    }
    ctx.globalAlpha = Math.min(1, a * 1.6); ctx.lineCap = 'round'; ctx.lineWidth = 3.2;
    d0 = 5 + e * 13; d1 = d0 + 8 * (1 - k * 0.7);
    for (pass = 0; pass < 2; pass++) {
      ctx.strokeStyle = pass ? '#FFFFFF' : f.col.soft; ctx.beginPath();
      for (i = pass * 4; i < n; i += 8) { x = f.ticks[i]; y = f.ticks[i + 1]; nx = f.ticks[i + 2]; ny = f.ticks[i + 3]; ctx.moveTo(x + nx * d0, y + ny * d0); ctx.lineTo(x + nx * d1, y + ny * d1); }
      ctx.stroke();
    }
    ctx.globalAlpha = 1; ctx.lineCap = 'butt';
  }
  function drawHud(ctx, state) {
    var st = D.safe.top, cx = W / 2, me = P[0], s, w, pw, x, y, i, c, sc, secs, t, px, py, PW, low, row, acc, bw;
    // your ink
    ctx.font = D.textFont(9.5, 800); ctx.textBaseline = 'middle'; ctx.textAlign = 'left';
    w = ctx.measureText('YOUR INK').width + 12;
    ctx.fillStyle = BASE[0]; rrp(ctx, cx - w / 2, st + 2, 8, 8, 2.5); ctx.fill();
    ctx.fillStyle = 'rgba(214,220,255,0.82)'; ctx.fillText('YOUR INK', cx - w / 2 + 12, st + 6.5);
    s = dispShare.toFixed(1); sc = 1 + hudPop * 0.22;
    ctx.save(); ctx.translate(cx, st + 36); ctx.scale(sc, sc);
    ctx.font = D.font(42); ctx.textBaseline = 'middle'; w = ctx.measureText(s).width;
    ctx.font = D.font(22); pw = ctx.measureText('%').width;
    x = -(w + pw + 3) / 2;
    ctx.font = D.font(42); ctx.fillStyle = 'rgba(6,6,44,0.45)'; ctx.fillText(s, x, 3);
    ctx.fillStyle = '#FFFFFF'; ctx.fillText(s, x, 1);
    ctx.font = D.font(22); ctx.fillStyle = BASE[0]; ctx.fillText('%', x + w + 3, 7);
    ctx.restore();
    // share bar
    bw = Math.min(104, W - 72 - 120 - 16); x = cx - bw / 2; y = st + 62;
    ctx.fillStyle = 'rgba(8,10,50,0.75)'; rrp(ctx, x, y, bw, 6, 3); ctx.fill();
    acc = 0;
    w = dispShare / 100 * bw; ctx.fillStyle = BASE[0]; ctx.fillRect(x, y, w + 0.4, 6); acc = w;
    for (i = 0; i < 6; i++) { c = P[order[i]]; if (c === me) continue; w = c.share / 100 * bw; ctx.fillStyle = c.pal.base; ctx.fillRect(x + acc, y, w + 0.4, 6); acc += w; }
    // clock
    secs = Math.max(0, Math.ceil(timeLeft)); low = playing && timeLeft <= 10;
    t = ((secs / 60) | 0) + ':' + (secs % 60 < 10 ? '0' : '') + (secs % 60);
    px = 22; py = st + 76; sc = low ? 1 + 0.12 * Math.max(0, 1 - (secs - timeLeft) * 3) : 1;
    ctx.save(); ctx.translate(px, py); ctx.scale(sc, sc);
    ctx.strokeStyle = low ? '#FF6D92' : 'rgba(226,230,255,0.9)'; ctx.lineWidth = 1.8; ctx.lineCap = 'round';
    ctx.beginPath(); ctx.arc(0, 0, 6.2, 0, TAU); ctx.moveTo(0, -3.2); ctx.lineTo(0, 0); ctx.lineTo(2.4, 1.4); ctx.stroke(); ctx.lineCap = 'butt';
    ctx.font = D.font(19); ctx.textAlign = 'left'; ctx.textBaseline = 'middle'; ctx.fillStyle = low ? '#FF6D92' : '#FFFFFF';
    ctx.fillText(t, 12, 1);
    ctx.restore();
    // ranking
    PW = 136; x = W - 8 - PW; y = st + 64; row = 14.6;
    ctx.fillStyle = 'rgba(9,11,52,0.72)'; rrp(ctx, x, y, PW, row * 6 + 8, 10); ctx.fill();
    ctx.strokeStyle = 'rgba(150,164,255,0.22)'; ctx.lineWidth = 1; ctx.stroke();
    ctx.font = D.textFont(10.5, 700); ctx.textBaseline = 'middle';
    for (i = 0; i < 6; i++) {
      c = P[order[i]]; py = y + 4 + row * i + row / 2;
      if (c.rowY < 0) c.rowY = py; else c.rowY += (py - c.rowY) * 0.22;
    }
    for (i = 5; i >= 0; i--) {
      c = P[order[i]]; if (c.id === 0) continue;
      drawRow(ctx, c, x, c.rowY, PW, row, i === 0);
    }
    drawRow(ctx, me, x, me.rowY, PW, row, order[0] === 0);
  }
  function drawRow(ctx, c, x, y, PW, row, lead) {
    var hero = c.id === 0, label = hero ? 'You' : c.name, w;
    if (hero) { ctx.fillStyle = BASE[0]; rrp(ctx, x + 3, y - row / 2 + 0.6, PW - 6, row - 1.2, 4.5); ctx.fill(); }
    ctx.fillStyle = hero ? '#FFFFFF' : c.pal.base; rrp(ctx, x + 9, y - 3.5, 7, 7, 2.2); ctx.fill();
    ctx.textAlign = 'left'; ctx.fillStyle = hero ? '#FFFFFF' : 'rgba(232,236,255,0.94)';
    ctx.fillText(label, x + 22, y + 0.5);
    if (lead) { if (!c.rowW) c.rowW = ctx.measureText(label).width; crown(ctx, x + 22 + c.rowW + 8, y, 4.2); ctx.fillStyle = hero ? '#FFFFFF' : 'rgba(232,236,255,0.94)'; }
    ctx.textAlign = 'right'; ctx.fillText(c.pct, x + PW - 9, y + 0.5);
  }
  function drawHint(ctx) {
    var txt = 'DRAG TO STEER', y = AY + AH - 46 + Math.sin(T * 2.4) * 2.5, w, x, k;
    ctx.font = D.textFont(13, 800); w = ctx.measureText(txt).width + 58; x = W / 2 - w / 2;
    ctx.fillStyle = 'rgba(6,6,44,0.35)'; rrp(ctx, x, y - 15, w, 36, 18); ctx.fill();
    ctx.fillStyle = 'rgba(12,14,58,0.94)'; rrp(ctx, x, y - 18, w, 36, 18); ctx.fill();
    ctx.strokeStyle = 'rgba(170,182,255,0.4)'; ctx.lineWidth = 1.2; ctx.stroke();
    k = Math.sin(T * 2.6);
    ctx.strokeStyle = 'rgba(255,255,255,0.4)'; ctx.lineWidth = 1.5; ctx.beginPath(); ctx.arc(x + 22, y, 9.5, 0, TAU); ctx.stroke();
    ctx.fillStyle = '#FF4D79'; ctx.beginPath(); ctx.arc(x + 22 + k * 5, y - Math.cos(T * 2.6) * 2, 4.6, 0, TAU); ctx.fill();
    ctx.fillStyle = '#FFFFFF'; ctx.textAlign = 'left'; ctx.textBaseline = 'middle'; ctx.fillText(txt, x + 40, y + 0.5);
  }

  function steer(a) { P[0].want = a; }

  G = {
    reset: function () {
      var i, slots = [], cols, rows, cx, cy, t, j, r0, n;
      layout();
      ROWS = clamp(Math.round(availH / (availW / COLS)), 36, 110);
      n = COLS * ROWS;
      if (n !== N || !owner) {
        N = n; VW = COLS + 1;
        owner = new Int8Array(N); trail = new Uint8Array(N); mark = new Uint8Array(N); sel = new Uint8Array(N);
        queue = new Int32Array(N); vmask = new Uint8Array(VW * (ROWS + 1));
      }
      owner.fill(-1); trail.fill(0); sel.fill(0); stamp = 0;
      fitArena(); buildBg(); makeLayers();
      roundLen = D.clip ? 35 : 75; timeLeft = roundLen; T = 0;
      playing = false; over = false; overT = 0; shake = 0; flash = 0; hudPop = 0; lastSec = -1; lastScore = -1; finalRank = 0;
      heroBias = D.clip ? 0.1 : 0.5; heroGrace = D.clip ? 14 : 6; polite = D.clip ? 1 : 0.55;
      fx.length = 0; pops.length = 0; for (i = 0; i < parts.length; i++) parts[i].life = 0;
      joy.active = false; joy.id = -1; wave.on = false; pend.on = false; pend.r = 0;
      if (ROWS >= COLS) { cols = 2; rows = 3; } else { cols = 3; rows = 2; }
      for (j = 0; j < rows; j++) for (i = 0; i < cols; i++) {
        cx = (cols === 2 ? (i ? 0.72 : 0.28) : 0.2 + i * 0.3) * COLS + (D.rand() - 0.5) * COLS * 0.1;
        cy = (rows === 3 ? 0.17 + j * 0.33 : (j ? 0.73 : 0.27)) * ROWS + (D.rand() - 0.5) * ROWS * 0.07;
        slots.push([cx, cy, j]);
      }
      for (i = slots.length - 1; i > 0; i--) { j = Math.floor(D.rand() * (i + 1)); t = slots[i]; slots[i] = slots[j]; slots[j] = t; }
      if (D.clip) for (i = 0; i < 6; i++) if (slots[i][2] === 0) { t = slots[0]; slots[0] = slots[i]; slots[i] = t; break; }
      P.length = 0; order.length = 0;
      r0 = Math.sqrt(0.0135 * N / PI);
      for (i = 0; i < 6; i++) {
        P.push(makeCreature(i, slots[i][0], slots[i][1])); order.push(i);
        stampBlob(i, slots[i][0], slots[i][1], r0, 1);
        paths[i] = null;
      }
      for (i = 5; i > 0; i--) { j = Math.floor(D.rand() * (i + 1)); t = order[i]; order[i] = order[j]; order[j] = t; }
      recount();
      dispShare = P[0].share;
      wave.on = false; commitLayer(false);
      ready = true;
    },
    start: function () { playing = true; },
    resize: function () {
      if (!ready) return;
      layout(); fitArena(); buildBg(); makeLayers();
      for (var i = 0; i < 6; i++) dirty[i] = 1;
      fx.length = 0;
      wave.on = false; commitLayer(false);
    },
    update: function (dt, state) {
      var i, c, p, f, sc, s;
      T += dt; commitWait -= dt;
      shake *= Math.exp(-dt * 9); if (shake < 0.2) shake = 0;
      flash = Math.max(0, flash - dt * 1.6); hudPop = Math.max(0, hudPop - dt * 3.5);
      dispShare += (P[0].share - dispShare) * Math.min(1, dt * 9);
      for (i = 0; i < 6; i++) { c = P[i]; c.pop = Math.max(0, c.pop - dt * 4); c.squash = Math.max(0, c.squash - dt * 5); if (c.spawnT > 0) c.spawnT = Math.max(0, c.spawnT - dt); }
      for (i = 0; i < parts.length; i++) { p = parts[i]; if (p.life > 0) { p.life -= dt; p.x += p.vx * dt; p.y += p.vy * dt; p.vx *= 1 - dt * 3.2; p.vy *= 1 - dt * 3.2; } }
      for (i = fx.length - 1; i >= 0; i--) { f = fx[i]; f.t += dt; if (f.t >= f.dur) fx.splice(i, 1); }
      for (i = pops.length - 1; i >= 0; i--) { p = pops[i]; p.t += dt; if (p.t >= p.dur) pops.splice(i, 1); }
      if (wave.on) { wave.t += dt / 0.4; wave.r = wave.max * D.easeOut(Math.min(1, wave.t)); if (wave.t >= 1) wave.on = false; }
      if (state === 'over') { overT += dt; return; }
      if (state !== 'playing') return;
      timeLeft -= dt;
      for (i = 0; i < 6; i++) {
        c = P[i];
        if (!c.alive) { c.dead -= dt; if (c.dead <= 0) respawn(c); continue; }
        if (i > 0) { brain(c, dt); c.want = c.aim; }
        moveCreature(c, dt);
      }
      sc = Math.round(P[0].share * 10) / 10;
      if (sc !== lastScore) { lastScore = sc; D.score(sc); }
      s = Math.ceil(timeLeft);
      if (s !== lastSec) { lastSec = s; if (s <= 5 && s > 0) { D.haptic('light'); D.tone({ freq: 740, dur: 0.05, vol: 0.05 }); } }
      if (timeLeft <= 0) { timeLeft = 0; finish(); }
    },
    draw: function (ctx, w, h, state) {
      var i, c, p, k, a, sx = 0, sy = 0, s, jx, jy, d;
      if (!ready) return;
      if (layerDirty && (pend.on || commitWait <= 0)) { commitLayer(pend.on); commitWait = 0.22; }
      if (shake > 0) { sx = (Math.random() - 0.5) * shake; sy = (Math.random() - 0.5) * shake; }
      if (shake > 0) { ctx.fillStyle = '#0C0E3A'; ctx.fillRect(0, 0, W, H); }
      ctx.drawImage(bg, sx * 0.5, sy * 0.5, W, H);
      ctx.save(); ctx.translate(AX + sx, AY + sy);
      if (wave.on) {
        ctx.save(); ctx.beginPath(); ctx.rect(0, 0, AW, AH); ctx.moveTo(wave.x + wave.r, wave.y); ctx.arc(wave.x, wave.y, wave.r, 0, TAU); ctx.clip('evenodd');
        ctx.drawImage(LB, 0, 0, AW, AH); ctx.restore();
        ctx.save(); ctx.beginPath(); ctx.arc(wave.x, wave.y, wave.r, 0, TAU); ctx.clip(); ctx.drawImage(LA, 0, 0, AW, AH); ctx.restore();
      } else ctx.drawImage(LA, 0, 0, AW, AH);
      for (i = 0; i < fx.length; i++) drawFx(ctx, fx[i]);
      // trails
      ctx.lineJoin = 'round'; ctx.lineCap = 'round';
      for (i = 5; i >= 0; i--) {
        c = P[i]; if (c.tp.length < 2 || !c.alive) continue;
        trailPath(ctx, c);
        ctx.strokeStyle = 'rgba(8,8,52,0.3)'; ctx.lineWidth = CELL * 1.75; ctx.stroke();
        ctx.strokeStyle = c.pal.trail; ctx.lineWidth = CELL * 1.2; ctx.stroke();
        ctx.fillStyle = c.pal.pale; ctx.globalAlpha = 0.85; k = CELL * 0.36;
        for (a = 2, p = c.tp; a < p.length - 2; a += 2) ctx.fillRect((p[a] + p[a + 2]) * 0.5 * CELL - k / 2, (p[a + 1] + p[a + 3]) * 0.5 * CELL - k / 2, k, k);
        ctx.globalAlpha = 1;
      }
      ctx.lineCap = 'butt';
      // heading cue for the player
      c = P[0];
      if (state === 'playing' && c.alive && joy.active) {
        a = c.want; s = CELL * 3.5;
        ctx.save(); ctx.translate(c.x * CELL + Math.cos(a) * s * 1.25, c.y * CELL - s * 0.05 + Math.sin(a) * s * 1.25); ctx.rotate(a);
        ctx.fillStyle = 'rgba(255,255,255,0.8)'; ctx.beginPath(); ctx.moveTo(5, 0); ctx.lineTo(-3, -4.5); ctx.lineTo(-1, 0); ctx.lineTo(-3, 4.5); ctx.closePath(); ctx.fill(); ctx.restore();
      }
      // respawn markers
      for (i = 0; i < 6; i++) {
        c = P[i]; if (c.alive || c.homeless || state !== 'playing') continue;
        k = clamp(c.dead / 1.6, 0, 1);
        ctx.strokeStyle = c.pal.pale; ctx.lineWidth = 2; ctx.globalAlpha = 0.7;
        ctx.beginPath(); ctx.arc(c.cx * CELL, c.cy * CELL, CELL * (1.2 + k * 2.4), 0, TAU); ctx.stroke(); ctx.globalAlpha = 1;
      }
      for (i = 5; i >= 0; i--) if (P[i].alive) drawCreature(ctx, P[i], state);
      // particles
      for (i = 0; i < parts.length; i++) {
        p = parts[i]; if (p.life <= 0) continue;
        k = p.life / p.max; ctx.globalAlpha = Math.min(1, k * 1.8); ctx.fillStyle = p.color;
        if (p.tick) { ctx.save(); ctx.translate(p.x, p.y); ctx.rotate(Math.atan2(p.vy, p.vx)); rrp(ctx, -p.size * 1.6, -p.size * 0.45, p.size * 3.2, p.size * 0.9, p.size * 0.45); ctx.fill(); ctx.restore(); }
        else { ctx.beginPath(); ctx.arc(p.x, p.y, p.size * (0.4 + k * 0.6), 0, TAU); ctx.fill(); }
      }
      ctx.globalAlpha = 1;
      for (i = 5; i >= 0; i--) if (P[i].alive) drawTag(ctx, P[i], state);
      // popups
      for (i = 0; i < pops.length; i++) {
        p = pops[i]; k = p.t / p.dur; s = k < 0.18 ? D.easeOutBack(k / 0.18) : 1; a = k > 0.75 ? 1 - (k - 0.75) / 0.25 : 1;
        ctx.save(); ctx.translate(clamp(p.x, 40, AW - 40), clamp(p.y - k * 16, 16, AH - 12)); ctx.scale(s, s); ctx.globalAlpha = a;
        ctx.font = D.font(p.size); ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.lineJoin = 'round';
        ctx.lineWidth = p.size * 0.22; ctx.strokeStyle = 'rgba(20,10,70,0.85)'; ctx.strokeText(p.txt, 0, 0);
        ctx.fillStyle = p.col; ctx.fillText(p.txt, 0, 0);
        ctx.restore();
      }
      ctx.globalAlpha = 1;
      ctx.restore();
      if (flash > 0) { ctx.fillStyle = 'rgba(255,255,255,' + (flash * 0.5).toFixed(3) + ')'; ctx.fillRect(0, 0, W, H); }
      drawHud(ctx, state);
      if (state === 'ready' && !D.clip) drawHint(ctx);
      if (joy.active && state === 'playing') {
        jx = joy.x - joy.ax; jy = joy.y - joy.ay; d = Math.sqrt(jx * jx + jy * jy); if (d > 30) { jx *= 30 / d; jy *= 30 / d; }
        ctx.globalAlpha = D.clip ? 0.4 : 1;
        ctx.fillStyle = 'rgba(255,255,255,0.05)'; ctx.strokeStyle = 'rgba(255,255,255,0.2)'; ctx.lineWidth = 2;
        ctx.beginPath(); ctx.arc(joy.ax, joy.ay, 44, 0, TAU); ctx.fill(); ctx.stroke();
        ctx.fillStyle = 'rgba(255,255,255,0.2)'; ctx.beginPath(); ctx.arc(joy.ax + jx, joy.ay + jy, 17, 0, TAU); ctx.fill(); ctx.globalAlpha = 1;
      }
      if (state === 'over') {
        k = Math.min(1, overT / 0.3); a = overT > 1.25 ? Math.max(0, 1 - (overT - 1.25) / 0.4) : 1;
        if (a > 0) {
          s = D.easeOutBack(k);
          ctx.save(); ctx.translate(W / 2, AY + AH * 0.4); ctx.scale(s, s); ctx.globalAlpha = a;
          ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.lineJoin = 'round';
          ctx.font = D.font(64); ctx.lineWidth = 12; ctx.strokeStyle = 'rgba(14,10,64,0.9)'; ctx.strokeText('TIME', 0, 0);
          ctx.fillStyle = '#FFFFFF'; ctx.fillText('TIME', 0, 0);
          ctx.font = D.font(26); ctx.lineWidth = 7; ctx.strokeText(ORD[finalRank].toUpperCase() + ' OF 6', 0, 46);
          ctx.fillStyle = finalRank === 0 ? '#FFC531' : '#FFD9E2'; ctx.fillText(ORD[finalRank].toUpperCase() + ' OF 6', 0, 46);
          ctx.restore(); ctx.globalAlpha = 1;
        }
      }
    },
    pointerDown: function (x, y, id) {
      joy.active = true; joy.id = id; joy.ax = x; joy.ay = y; joy.x = x; joy.y = y;
      if (!D.clip) D.haptic('select');
    },
    pointerMove: function (x, y, id, down) {
      var dx, dy, d;
      if (!down || !joy.active || id !== joy.id) return;
      joy.x = x; joy.y = y; dx = x - joy.ax; dy = y - joy.ay; d = Math.sqrt(dx * dx + dy * dy);
      if (d < 7) return;
      steer(Math.atan2(dy, dx));
      if (d > 52) { joy.ax = x - dx / d * 52; joy.ay = y - dy / d * 52; }
    },
    pointerUp: function (x, y, id) { if (id === joy.id) joy.active = false; },
    key: function (k) {
      var a = k === 'ArrowRight' || k === 'd' ? 0 : k === 'ArrowDown' || k === 's' ? PI / 2 : k === 'ArrowLeft' || k === 'a' ? PI : k === 'ArrowUp' || k === 'w' ? -PI / 2 : null;
      if (a !== null) steer(a);
    },
    bot: function (dt) {
      var h = P[0], a, jx = W / 2, jy = Math.min(H - 290, AY + AH - 70);
      if (!playing || !h.alive) return;
      if (!joy.active) { G.pointerDown(jx, jy, 77, false); joy.ax = jx; joy.ay = jy; }
      brain(h, dt);
      a = h.aim + Math.sin(T * 2.3) * 0.05;
      G.pointerMove(joy.ax + Math.cos(a) * 30, joy.ay + Math.sin(a) * 30, 77, true);
    }
  };
  D.game(G);
})();
