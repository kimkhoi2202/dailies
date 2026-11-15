/* Gulp City. You are a hole in a pastel toy city: drag to move, swallow what fits, grow, swallow more. */
(function () {
  'use strict';
  var D = window.Dailies;
  var TAU = Math.PI * 2;

  // Projection: the ground plane is rotated, squashed vertically, and height goes straight up the screen.
  var ANG = -0.44, CS = Math.cos(ANG), SN = Math.sin(ANG), TK = 0.72, HK = 0.82;

  var N = 6, B = 220, RW = 64, CELL = B + RW, CITY = N * CELL + RW, NC = N + 1;
  var MAXL = 8;
  var RAD = [0, 27, 34, 43, 55, 71, 91, 115, 142];
  var ZOOM = [0, 1.6, 1.48, 1.34, 1.18, 1.03, 0.89, 0.77, 0.68];
  var FRAC_PLAY = [0, 0.01, 0.03, 0.07, 0.14, 0.25, 0.4, 0.6, 9];
  var FRAC_CLIP = [0, 0.006, 0.015, 0.032, 0.06, 0.1, 0.17, 0.3, 9];
  var JMAX = 56;
  var INK = '#2B2452';
  var SEA = '#A9DEF3', ROAD = '#BDBBEC', PAD = '#FFEEC4', CURB = '#E2CB9E', LAWN = '#BDEBC4', CREAM = '#FFF0C8';

  var T = {
    flower: { lvl: 1, rad: 6, pts: 1, h: 10, hap: 0, shr: 5 },
    cone: { lvl: 1, rad: 6, pts: 1, h: 13, hap: 0, shr: 5 },
    bush: { lvl: 1, rad: 9, pts: 1, h: 12, hap: 0, shr: 8 },
    person: { lvl: 1, rad: 6, pts: 2, h: 20, hap: 0, shr: 4.5 },
    bench: { lvl: 1, rad: 13, pts: 2, h: 12, hap: 0, bx: 13, by: 5 },
    tree: { lvl: 2, rad: 15, pts: 4, h: 40, hap: 1, shr: 11 },
    parasol: { lvl: 2, rad: 17, pts: 4, h: 36, hap: 1, shr: 13 },
    bigtree: { lvl: 3, rad: 20, pts: 6, h: 56, hap: 1, shr: 15 },
    kiosk: { lvl: 3, rad: 21, pts: 6, h: 30, hap: 1, bx: 15, by: 12 },
    car: { lvl: 3, rad: 23, pts: 8, h: 20, hap: 2, bx: 22, by: 11.5 },
    fountain: { lvl: 4, rad: 28, pts: 10, h: 24, hap: 2, shr: 27 },
    bus: { lvl: 4, rad: 34, pts: 14, h: 27, hap: 2, bx: 38, by: 13 },
    house: { lvl: 5, rad: 38, pts: 20, h: 50, hap: 2, bx: 30, by: 26 },
    building: { lvl: 6, rad: 50, pts: 30, h: 112, hap: 3, bx: 40, by: 40, tall: 1 },
    tower: { lvl: 7, rad: 58, pts: 44, h: 232, hap: 3, bx: 46, by: 46, tall: 1 }
  };

  // ------------------------------------------------------------------ colour helpers
  function hex(c) { return [parseInt(c.substr(1, 2), 16), parseInt(c.substr(3, 2), 16), parseInt(c.substr(5, 2), 16)]; }
  function h2(n) { var s = Math.round(n).toString(16); return s.length < 2 ? '0' + s : s; }
  function mix(a, b, t) {
    var A = hex(a), C = hex(b);
    return '#' + h2(A[0] + (C[0] - A[0]) * t) + h2(A[1] + (C[1] - A[1]) * t) + h2(A[2] + (C[2] - A[2]) * t);
  }
  function tri(col) { return { t: mix(col, '#FFFFFF', 0.4), s: mix(col, '#FFFFFF', 0.1), f: mix(col, '#6E5AC8', 0.2), d: mix(col, '#5A46B4', 0.36) }; }

  // ------------------------------------------------------------------ sprite drawing primitives
  var g = null, SS = 0, SPR = null;
  function X(x, y) { return CS * x - SN * y; }
  function Y(x, y, z) { return (SN * x + CS * y) * TK - z * HK; }
  function quad(col, ax, ay, bx, by, cx, cy, dx, dy, r) {
    g.beginPath(); g.moveTo(ax, ay); g.lineTo(bx, by); g.lineTo(cx, cy); g.lineTo(dx, dy); g.closePath();
    g.fillStyle = col; g.fill();
    if (r) { g.strokeStyle = col; g.lineWidth = r; g.lineJoin = 'round'; g.stroke(); }
  }
  function top(col, x0, y0, x1, y1, z, r) { quad(col, X(x0, y0), Y(x0, y0, z), X(x1, y0), Y(x1, y0, z), X(x1, y1), Y(x1, y1, z), X(x0, y1), Y(x0, y1, z), r); }
  function front(col, x0, x1, y, z0, z1, r) { quad(col, X(x0, y), Y(x0, y, z0), X(x1, y), Y(x1, y, z0), X(x1, y), Y(x1, y, z1), X(x0, y), Y(x0, y, z1), r); }
  function side(col, x, y0, y1, z0, z1, r) { quad(col, X(x, y0), Y(x, y0, z0), X(x, y1), Y(x, y1, z0), X(x, y1), Y(x, y1, z1), X(x, y0), Y(x, y0, z1), r); }
  function box(x0, y0, x1, y1, z0, z1, c, r) {
    side(c.s, x0, y0, y1, z0, z1, r); front(c.f, x0, x1, y1, z0, z1, r); top(c.t, x0, y0, x1, y1, z1, r);
  }
  function blob(sx, sy, r, c1, c2) {
    var gr = g.createRadialGradient(sx - r * 0.35, sy - r * 0.42, r * 0.08, sx, sy, r);
    gr.addColorStop(0, c1); gr.addColorStop(1, c2);
    g.fillStyle = gr; g.beginPath(); g.arc(sx, sy, r, 0, TAU); g.fill();
  }
  function cyl(x, y, r, z0, z1, ct, cs) {
    var cx = X(x, y), y0 = Y(x, y, z0), y1 = Y(x, y, z1);
    var gr = g.createLinearGradient(cx - r, 0, cx + r, 0);
    gr.addColorStop(0, mix(cs, '#FFFFFF', 0.25)); gr.addColorStop(1, mix(cs, '#6E5AC8', 0.22));
    g.fillStyle = gr; g.beginPath(); g.ellipse(cx, y0, r, r * TK, 0, 0, TAU); g.fill();
    g.fillRect(cx - r, y1, r * 2, y0 - y1);
    g.fillStyle = ct; g.beginPath(); g.ellipse(cx, y1, r, r * TK, 0, 0, TAU); g.fill();
  }
  function mk(hx, hy, h, fn) {
    var ex = Math.abs(CS) * hx + Math.abs(SN) * hy, ey = (Math.abs(SN) * hx + Math.abs(CS) * hy) * TK, pad = 4;
    var cv = document.createElement('canvas');
    cv.width = Math.ceil((ex * 2 + pad * 2) * SS); cv.height = Math.ceil((ey * 2 + h * HK + pad * 2) * SS);
    g = cv.getContext('2d');
    g.setTransform(SS, 0, 0, SS, (ex + pad) * SS, (ey + h * HK + pad) * SS);
    fn();
    return { cv: cv, ax: ex + pad, ay: ey + h * HK + pad, w: cv.width / SS, h: cv.height / SS };
  }

  // ------------------------------------------------------------------ the toys
  function sFlower(col) {
    return mk(7, 7, 12, function () {
      var p = [-3.6, -5.5, 3.4, -7, 0, -10], i;
      g.fillStyle = '#7FD08E'; g.beginPath(); g.ellipse(0, 0.5, 6, 3.4, 0, 0, TAU); g.fill();
      g.strokeStyle = '#58B877'; g.lineWidth = 1.3; g.lineCap = 'round';
      for (i = 0; i < 6; i += 2) { g.beginPath(); g.moveTo(p[i] * 0.4, 0); g.lineTo(p[i], p[i + 1]); g.stroke(); }
      for (i = 0; i < 6; i += 2) {
        blob(p[i], p[i + 1], 3, mix(col, '#FFFFFF', 0.55), col);
        g.fillStyle = '#FFE27A'; g.beginPath(); g.arc(p[i], p[i + 1], 1, 0, TAU); g.fill();
      }
    });
  }
  function sCone() {
    return mk(6, 6, 14, function () {
      top('#E77F4C', -4.6, -4.6, 4.6, 4.6, 0.6, 1.6);
      quad('#FF9D5C', -3.7, -1, 3.7, -1, 1.1, -12.5, -1.1, -12.5, 1.6);
      quad('#FFFFFF', -2.8, -4.6, 2.8, -4.6, 2.05, -7.6, -2.05, -7.6, 0.4);
    });
  }
  function sBush(c1, c2) {
    return mk(9, 9, 13, function () { blob(-4.2, -3.6, 5.6, c1, c2); blob(4.4, -4, 5.4, c1, c2); blob(0, -8, 6, c1, c2); });
  }
  function sPerson(shirt, skin, hair) {
    return mk(5, 5, 22, function () {
      cyl(0, 0, 3.9, 0, 10.5, mix(shirt, '#FFFFFF', 0.3), shirt);
      blob(0, -12.6, 4.1, mix(skin, '#FFFFFF', 0.35), skin);
      g.fillStyle = hair; g.beginPath(); g.arc(0, -13.2, 4.15, Math.PI * 1.02, Math.PI * 1.98); g.closePath(); g.fill();
    });
  }
  function sBench(oy) {
    var hx = oy ? 5 : 13, hy = oy ? 13 : 5, w = tri('#E9B27C'), d = tri('#B98458');
    return mk(hx, hy, 13, function () {
      if (oy) {
        box(-hx + 1, -hy + 1, hx - 1, -hy + 3, 0, 4, d, 0); box(-hx + 1, hy - 3, hx - 1, hy - 1, 0, 4, d, 0);
        box(hx - 2, -hy, hx, hy, 6, 12, w, 1); box(-hx, -hy, hx - 1, hy, 4, 6.4, w, 1.2);
      } else {
        box(-hx + 1, -hy + 1, -hx + 3, hy - 1, 0, 4, d, 0); box(hx - 3, -hy + 1, hx - 1, hy - 1, 0, 4, d, 0);
        box(-hx, -hy, hx, -hy + 2, 6, 12, w, 1); box(-hx, -hy + 1, hx, hy, 4, 6.4, w, 1.2);
      }
    });
  }
  function sTree(c, s) {
    return mk(13 * s, 13 * s, 42 * s, function () {
      cyl(0, 0, 2.7 * s, 0, 15 * s, '#C99676', '#A9785C');
      blob(-6.6 * s, -17 * s, 9.2 * s, c[0], c[1]);
      blob(6.8 * s, -18.5 * s, 9.4 * s, c[0], c[1]);
      blob(0.5 * s, -14 * s, 8 * s, c[0], c[1]);
      blob(-0.5 * s, -26 * s, 10.4 * s, mix(c[0], '#FFFFFF', 0.18), mix(c[1], c[0], 0.25));
    });
  }
  function sParasol(c1, c2) {
    return mk(18, 18, 38, function () {
      var i, n = 10, cy = -24 * HK, ay = -34 * HK, rx = 17, ry = 17 * TK;
      cyl(0, 0, 6.5, 0, 7.5, '#FFFFFF', '#DCD2F2');
      g.strokeStyle = '#F4EEFF'; g.lineWidth = 1.8; g.beginPath(); g.moveTo(0, -6); g.lineTo(0, ay); g.stroke();
      g.fillStyle = mix(c1, '#5A46B4', 0.4); g.beginPath(); g.ellipse(0, cy + 1.2, rx, ry, 0, 0, TAU); g.fill();
      for (i = 0; i < n; i++) {
        var a0 = i * TAU / n + 0.2, a1 = (i + 1) * TAU / n + 0.2, col = i % 2 ? c2 : c1;
        col = mix(col, '#6E5AC8', 0.1 + 0.12 * Math.max(0, Math.sin((a0 + a1) / 2 - 0.5)));
        g.fillStyle = col; g.strokeStyle = col; g.lineWidth = 0.5;
        g.beginPath(); g.moveTo(0, ay); g.lineTo(Math.cos(a0) * rx, cy + Math.sin(a0) * ry); g.lineTo(Math.cos(a1) * rx, cy + Math.sin(a1) * ry); g.closePath(); g.fill(); g.stroke();
      }
      g.fillStyle = '#FFFFFF'; g.beginPath(); g.arc(0, ay, 1.6, 0, TAU); g.fill();
    });
  }
  function sKiosk(c1, c2) {
    return mk(19, 16, 30, function () {
      var b = tri('#FFE9C9'), i, n = 6, w = 34 / n;
      box(-14, -10, 14, 10, 0, 19, b, 1.5);
      front('#7B62B8', -10, 10, 10.4, 8, 17, 0); front('#FFFFFF', -11.5, 11.5, 10.6, 6.5, 8.6, 0.6);
      side(mix(c1, '#6E5AC8', 0.1), -17, -13, 14, 19, 23, 0.8);
      for (i = 0; i < n; i++) {
        var col = i % 2 ? c2 : c1, x0 = -17 + i * w;
        front(mix(col, '#6E5AC8', 0.18), x0, x0 + w, 14, 19, 23, 0.3);
        top(col, x0, -13, x0 + w, 14, 23, 0.3);
      }
    });
  }
  function wheel(x, y) {
    g.fillStyle = '#453D6E'; g.beginPath(); g.arc(X(x, y), Y(x, y, 3.2), 3.6, 0, TAU); g.fill();
  }
  function sCar(col, oy) {
    var L = 22, Wd = 11.5, hx = oy ? Wd : L, hy = oy ? L : Wd, c = tri(col);
    return mk(hx, hy, 22, function () {
      if (oy) { wheel(-hx, -hy * 0.58); wheel(-hx, hy * 0.58); } else { wheel(-hx * 0.58, hy); wheel(hx * 0.58, hy); }
      box(-hx, -hy, hx, hy, 3, 11, c, 3);
      if (oy) { front('#FFF6C4', -7.5, -3.5, hy + 1.4, 6, 9, 0.5); front('#FFF6C4', 3.5, 7.5, hy + 1.4, 6, 9, 0.5); }
      else { side('#FFF6C4', -hx - 1.4, -7.5, -3.5, 6, 9, 0.5); side('#FFF6C4', -hx - 1.4, 3.5, 7.5, 6, 9, 0.5); }
      var kx = oy ? hx * 0.8 : hx * 0.52, ky = oy ? hy * 0.52 : hy * 0.8;
      box(-kx, -ky, kx, ky, 11, 18, { t: mix(col, '#FFFFFF', 0.55), s: '#D6F1FF', f: '#A9D6F5' }, 2.4);
      top(mix(col, '#FFFFFF', 0.7), -kx * 0.55, -ky * 0.55, kx * 0.55, ky * 0.55, 18.1, 1);
    });
  }
  function sBus(col, oy) {
    var L = 38, Wd = 13, hx = oy ? Wd : L, hy = oy ? L : Wd, c = tri(col), i;
    return mk(hx, hy, 30, function () {
      if (oy) { wheel(-hx, -hy * 0.62); wheel(-hx, hy * 0.62); } else { wheel(-hx * 0.62, hy); wheel(hx * 0.62, hy); }
      box(-hx, -hy, hx, hy, 3, 25, c, 3);
      for (i = 0; i < 5; i++) {
        var a = -L + 5 + i * 14;
        if (oy) side('#D6F1FF', -hx - 1.5, a, a + 10.5, 13, 21, 0.8); else front('#A9D6F5', a, a + 10.5, hy + 1.5, 13, 21, 0.8);
      }
      if (oy) { front('#A9D6F5', -hx + 3, hx - 3, hy + 1.5, 13, 21, 0.8); front('#FFF6C4', -9, -5, hy + 1.6, 6, 9, 0.5); front('#FFF6C4', 5, 9, hy + 1.6, 6, 9, 0.5); }
      else { side('#D6F1FF', -hx - 1.5, -hy + 3, hy - 3, 13, 21, 0.8); side('#FFF6C4', -hx - 1.6, -9, -5, 6, 9, 0.5); side('#FFF6C4', -hx - 1.6, 5, 9, 6, 9, 0.5); }
      top(mix(col, '#FFFFFF', 0.72), -hx + 5, -hy + 5, hx - 5, hy - 5, 25.2, 2);
      var q = oy ? 0 : 1, r = oy ? 1 : 0;
      top(c.s, -5 - q * 14, -5 - r * 14, 5 - q * 14, 5 - r * 14, 25.4, 1.5); top(c.s, -5 + q * 14, -5 + r * 14, 5 + q * 14, 5 + r * 14, 25.4, 1.5);
    });
  }
  function sFountain() {
    return mk(28, 28, 28, function () {
      cyl(0, 0, 27, 0, 7, '#FFF4E6', '#F2D2C4');
      g.fillStyle = '#8FD2EE'; g.beginPath(); g.ellipse(0, -7 * HK, 22.5, 22.5 * TK, 0, 0, TAU); g.fill();
      g.fillStyle = '#B9E8FA'; g.beginPath(); g.ellipse(0, -7 * HK + 1.4, 20, 19 * TK, 0, 0, TAU); g.fill();
      g.strokeStyle = 'rgba(255,255,255,0.8)'; g.lineWidth = 1.2; g.beginPath(); g.ellipse(0, -7 * HK + 1, 13, 13 * TK, 0, 0.4, 2.6); g.stroke();
      cyl(0, 0, 4.5, 6, 17, '#FFF4E6', '#F2D2C4');
      cyl(0, 0, 10.5, 17, 19.5, '#B9E8FA', '#FFE9DC');
      blob(0, -23 * HK, 3.6, '#FFFFFF', '#CDEFFC');
      g.fillStyle = 'rgba(255,255,255,0.9)';
      g.beginPath(); g.arc(-7, -20, 1.5, 0, TAU); g.arc(7, -19, 1.3, 0, TAU); g.arc(3, -25, 1.2, 0, TAU); g.fill();
    });
  }
  function sHouse(wall, roof) {
    var hx = 30, hy = 26, wz = 26, rz = 47, e = 3.5, c = tri(wall), r = tri(roof);
    return mk(hx + e, hy + e, 54, function () {
      box(-hx, -hy, hx, hy, 0, wz, c, 2);
      g.beginPath(); g.moveTo(X(-hx, -hy), Y(-hx, -hy, wz)); g.lineTo(X(-hx, hy), Y(-hx, hy, wz)); g.lineTo(X(-hx, 0), Y(-hx, 0, rz)); g.closePath();
      g.fillStyle = c.s; g.fill(); g.strokeStyle = c.s; g.lineWidth = 2; g.stroke();
      front('#B88668', -5.5, 5.5, hy + 1.1, 0, 15, 0.8); front('#FFE9A8', 2.2, 3.6, hy + 1.3, 7, 8.4, 0);
      front('#BFE6FA', -23, -12, hy + 1.1, 9, 19, 1); front('#BFE6FA', 12, 23, hy + 1.1, 9, 19, 1);
      side('#DDF3FD', -hx - 1.1, -9, 9, 9, 19, 1);
      box(12, -15, 19, -8, 32, 50, tri('#F7C9B4'), 1);
      quad(r.s, X(-hx - e, hy + e), Y(-hx - e, hy + e, wz - 3), X(hx + e, hy + e), Y(hx + e, hy + e, wz - 3), X(hx + e, 0), Y(hx + e, 0, rz), X(-hx - e, 0), Y(-hx - e, 0, rz), 2.5);
      g.strokeStyle = r.t; g.lineWidth = 2.2; g.lineCap = 'round';
      g.beginPath(); g.moveTo(X(-hx - e, 0), Y(-hx - e, 0, rz)); g.lineTo(X(hx + e, 0), Y(hx + e, 0, rz)); g.stroke();
      g.strokeStyle = r.f; g.lineWidth = 1;
      for (var i = 1; i < 4; i++) {
        var yy = (hy + e) * i / 4, zz = rz - (rz - wz + 3) * i / 4;
        g.beginPath(); g.moveTo(X(-hx - e, yy), Y(-hx - e, yy, zz)); g.lineTo(X(hx + e, yy), Y(hx + e, yy, zz)); g.stroke();
      }
    });
  }
  function sBuilding(col, hz, style) {
    var hx = 40, c = tri(col), i, j;
    return mk(hx, hx, hz + 12, function () {
      box(-hx, -hx, hx, hx, 0, hz, c, 2.5);
      var rows = Math.floor((hz - 22) / 17);
      for (j = 0; j < rows; j++) {
        var z = 20 + j * 17;
        for (i = 0; i < 4; i++) {
          var a = -34 + i * 18.2;
          front(style ? '#FFF3C2' : '#A9D6F5', a, a + 13.5, hx + 1.4, z, z + 10.5, 1);
          side('#D6F1FF', -hx - 1.4, a, a + 13.5, z, z + 10.5, 1);
        }
      }
      front(c.d, -9, 9, hx + 1.4, 0, 14, 1); front('#FFF6D8', -6, 6, hx + 1.6, 0, 11, 0.5);
      front(mix(col, '#FFFFFF', 0.6), -hx, hx, hx + 1.6, hz - 5, hz, 2); side(mix(col, '#FFFFFF', 0.72), -hx - 1.6, -hx, hx, hz - 5, hz, 2);
      top(mix(col, '#6E5AC8', 0.1), -hx + 6, -hx + 6, hx - 6, hx - 6, hz + 0.2, 1.5);
      if (style) { top('#A9E8B4', -26, -26, 4, 4, hz + 0.4, 2); blob(X(-11, -11), Y(-11, -11, hz + 4), 5, '#A9ECA6', '#52BF88'); }
      else box(-26, -24, -6, -6, hz, hz + 8, tri('#FFFFFF'), 1.5);
      box(8, 6, 26, 22, hz, hz + 7, tri('#E9E4FA'), 1.5);
    });
  }
  function sTower(col, glass) {
    var hx = 46, c = tri(col), i;
    return mk(hx, hx, 236, function () {
      box(-hx, -hx, hx, hx, 0, 168, c, 2.5);
      for (i = 0; i < 4; i++) {
        var a = -38 + i * 20.5;
        front(glass, a, a + 14, hx + 1.4, 20, 158, 1.2); side(mix(glass, '#FFFFFF', 0.4), -hx - 1.4, a, a + 14, 20, 158, 1.2);
      }
      for (i = 0; i < 7; i++) { front(c.f, -hx, hx, hx + 1.6, 36 + i * 20, 39 + i * 20, 0); side(c.s, -hx - 1.6, -hx, hx, 36 + i * 20, 39 + i * 20, 0); }
      front(c.d, -11, 11, hx + 1.5, 0, 15, 1); front('#FFF6D8', -8, 8, hx + 1.7, 0, 12, 0.5);
      top(mix(col, '#6E5AC8', 0.08), -hx + 5, -hx + 5, hx - 5, hx - 5, 168.2, 1.5);
      box(-32, -32, 32, 32, 168, 206, c, 2.5);
      for (i = 0; i < 3; i++) { a = -26 + i * 19; front(glass, a, a + 13, 33.4, 176, 198, 1); side(mix(glass, '#FFFFFF', 0.4), -33.4, a, a + 13, 176, 198, 1); }
      box(-17, -17, 17, 17, 206, 220, tri(mix(col, '#FFFFFF', 0.35)), 2);
      g.strokeStyle = '#8F86C4'; g.lineWidth = 1.6; g.beginPath(); g.moveTo(0, -220 * HK); g.lineTo(0, -234 * HK); g.stroke();
      g.fillStyle = '#FF7F8E'; g.beginPath(); g.arc(0, -234 * HK, 2, 0, TAU); g.fill();
    });
  }

  function buildSprites() {
    var S = {}, greens = [['#B4F0AC', '#4FBF88'], ['#9BE8CF', '#35A398'], ['#C6F29A', '#6FC56E'], ['#FFD3E4', '#F285B3']];
    S.flower = ['#FF8FB3', '#FFD35C', '#FFFFFF', '#B79CF0', '#FF9E7A'].map(sFlower);
    S.cone = [sCone()];
    S.bush = [sBush('#B4F0AC', '#4FBF88'), sBush('#9BE8CF', '#35A398')];
    S.person = [sPerson('#FF8FA3', '#FFD9B8', '#4A3558'), sPerson('#7FB8F5', '#E8B48A', '#2F2A45'), sPerson('#FFC65C', '#B98060', '#2F2A45'),
      sPerson('#8ED9B5', '#FFD9B8', '#C98A4A'), sPerson('#B79CF0', '#8A5A44', '#2F2A45'), sPerson('#FF9E7A', '#E8B48A', '#7A4A3A'), sPerson('#FFFFFF', '#B98060', '#4A3558')];
    S.bench = [sBench(0), sBench(1)];
    S.tree = greens.map(function (c) { return sTree(c, 1); });
    S.bigtree = greens.map(function (c) { return sTree(c, 1.38); });
    S.parasol = [sParasol('#FF8FA3', '#FFFFFF'), sParasol('#B79CF0', '#FFFFFF'), sParasol('#FFC65C', '#FFF6DA'), sParasol('#7FD3C0', '#FFFFFF')];
    S.kiosk = [sKiosk('#FF7F8E', '#FFFFFF'), sKiosk('#8FA8F5', '#FFFFFF'), sKiosk('#FFB65C', '#FFF7E0'), sKiosk('#B79CF0', '#FFFFFF')];
    S.car = ['#FF9FB8', '#FF9E8A', '#8FDCC2', '#B5A5F2', '#FFFFFF', '#8DB8F5', '#FFD36B'].map(function (c) { return [sCar(c, 0), sCar(c, 1)]; });
    S.bus = ['#FFD36B', '#FF9FB8', '#FFFFFF', '#8FDCC2'].map(function (c) { return [sBus(c, 0), sBus(c, 1)]; });
    S.fountain = [sFountain()];
    S.house = [sHouse('#FFE9C9', '#FF8E7A'), sHouse('#FFD5DE', '#8F9CF0'), sHouse('#D9F2E0', '#FF9FB8'), sHouse('#FFF4E0', '#5FC2B4'), sHouse('#DDE6FF', '#FFB65C')];
    S.building = [sBuilding('#FFB3C7', 112, 0), sBuilding('#FFCBA6', 96, 1), sBuilding('#C9B8F5', 112, 1), sBuilding('#A9CDF7', 100, 0), sBuilding('#A8E4CF', 108, 0), sBuilding('#FFE3A3', 92, 1)];
    S.tower = [sTower('#FFC2A6', '#8DB8F5'), sTower('#FFB3C7', '#9CC8F7'), sTower('#C9B8F5', '#FFE9A8'), sTower('#A9D4F7', '#F4FBFF'), sTower('#A8E4CF', '#8DB8F5')];
    SPR = S;
  }

  // ------------------------------------------------------------------ round state
  var objs, cells, veh, blocks, marks, cityPaths, padPath;
  var hole, cam, lvl, pts, total, thr, pct, tLeft, roundLen, ended, endT, TT = 0;
  var zs = 1, zoomNow = 1, zBump = 0, shake = 0, shx = 0, shy = 0, gulp = 0, pctPop = 0, lvlPop = 0;
  var falls = [], wobs = [], vis = [];
  var jid = null, jx0 = 0, jy0 = 0, jx = 0, jy = 0, sdx = 0, sdy = 0, sstr = 0;
  var pend = 0, pendT = 0, selT = 0, lightT = 0, wordT = 0, combo = 0, comboT = 0;
  var pops = [], parts = [], rings = [], i0;
  for (i0 = 0; i0 < 16; i0++) pops.push({ on: 0, str: '', u: 0, v: 0, t: 0, life: 1, word: 0, ox: 0 });
  for (i0 = 0; i0 < 96; i0++) parts.push({ on: 0, u: 0, v: 0, du: 0, dv: 0, t: 0, life: 1, r: 1, col: 0 });
  for (i0 = 0; i0 < 4; i0++) rings.push({ on: 0, t: 0 });
  var gWall = null, gVoid = null, gBar = null, fBig = '', fNum = '', fWord = '', fSmall = '', fHint = '';
  var BN = 26, BS = CITY / BN, binW = null;
  var bot = { bin: -1, tgt: null, t: 0, dx: 0, dy: 0, held: 0, down: false, ph: 0 };

  function rs(arr) { return arr[Math.floor(D.rand() * arr.length)]; }
  function add(kind, x, y, sp, oy) {
    var k = T[kind];
    var o = { k: k, sp: sp, x: x, y: y, u: CS * x - SN * y, v: (SN * x + CS * y) * TK, st: 0, wob: 0, ph: (x * 7 + y * 13) % 6.28, ft: 0, fd: 0, fu: 0, fv: 0, fr: 0, oy: oy | 0, al: 1, skip: 0, lp: null };
    objs.push(o); total += k.pts;
    return o;
  }
  function prr(p, x, y, w, h, r) {
    p.moveTo(x + r, y); p.arcTo(x + w, y, x + w, y + h, r); p.arcTo(x + w, y + h, x, y + h, r); p.arcTo(x, y + h, x, y, r); p.arcTo(x, y, x + w, y, r); p.closePath();
  }
  function pel(p, x, y, rx, ry) { p.moveTo(x + rx, y); p.ellipse(x, y, rx, ry, 0, 0, TAU); }
  function arrow(p, x, y, dx, dy) {
    var nx = -dy, ny = dx;
    p.moveTo(x - dx * 10 + nx * 1.7, y - dy * 10 + ny * 1.7);
    p.lineTo(x + dx + nx * 1.7, y + dy + ny * 1.7); p.lineTo(x + dx + nx * 5.5, y + dy + ny * 5.5);
    p.lineTo(x + dx * 10, y + dy * 10);
    p.lineTo(x + dx - nx * 5.5, y + dy - ny * 5.5); p.lineTo(x + dx - nx * 1.7, y + dy - ny * 1.7);
    p.lineTo(x - dx * 10 - nx * 1.7, y - dy * 10 - ny * 1.7); p.closePath();
  }

  function genMarks(i, j) {
    var p = new Path2D(), xc = RW / 2 + i * CELL, yc = RW / 2 + j * CELL, a, t;
    if (i < N) {
      var xa = i * CELL + RW, xb = xa + B;
      for (t = -RW / 2 + 6; t < RW / 2 - 8; t += 9.5) { p.rect(xa + 5, yc + t, 15, 5); p.rect(xb - 20, yc + t, 15, 5); }
      for (a = xa + 34; a < xb - 44; a += 26) p.rect(a, yc - 1.2, 13, 2.4);
      arrow(p, xa + B * 0.36, yc + RW / 4, 1, 0); arrow(p, xa + B * 0.64, yc - RW / 4, -1, 0);
    }
    if (j < N) {
      var ya = j * CELL + RW, yb = ya + B;
      for (t = -RW / 2 + 6; t < RW / 2 - 8; t += 9.5) { p.rect(xc + t, ya + 5, 5, 15); p.rect(xc + t, yb - 20, 5, 15); }
      for (a = ya + 34; a < yb - 44; a += 26) p.rect(xc - 1.2, a, 2.4, 13);
      arrow(p, xc - RW / 4, ya + B * 0.36, 0, 1); arrow(p, xc + RW / 4, ya + B * 0.64, 0, -1);
    }
    return p;
  }

  function genBlock(bi, bj, type, rich) {
    var x0 = RW + bi * CELL, y0 = RW + bj * CELL, layers = [], placed = [], i, k, p, q;
    function L(col) { var path = new Path2D(); layers.push({ c: col, p: path }); return path; }
    function blk(x, y, r) { placed.push(x, y, r); }
    function free(x, y, r) {
      if (x < r + 6 || y < r + 6 || x > B - r - 6 || y > B - r - 6) return false;
      for (var n = 0; n < placed.length; n += 3) { var dx = placed[n] - x, dy = placed[n + 1] - y, rr = placed[n + 2] + r; if (dx * dx + dy * dy < rr * rr) return false; }
      return true;
    }
    function put(kind, x, y, sp, oy, br) { blk(x, y, br || T[kind].rad * 0.85); return add(kind, x0 + x, y0 + y, sp || rs(SPR[kind]), oy); }
    function scatter(kind, n, xa, ya, xb, yb, nc) {
      var r = T[kind].rad * 0.85;
      for (var a = 0; a < n; a++) for (var t = 0; t < 18; t++) {
        var x = D.randRange(xa, xb), y = D.randRange(ya, yb);
        if (nc && (Math.abs(x - 110) < r + 9 || Math.abs(y - 110) < r + 9)) continue;
        if (free(x, y, r)) { put(kind, x, y); break; }
      }
    }
    function bench(x, y, oy) { if (free(x, y, 9)) put('bench', x, y, SPR.bench[oy], oy); }
    var Q = [[58, 56], [162, 56], [58, 164], [162, 164]];

    if (type === 0) { // park
      prr(L(LAWN), x0 + 9, y0 + 9, B - 18, B - 18, 26);
      p = L('#CDF3CF');
      for (i = 0; i < 4; i++) pel(p, x0 + D.randRange(45, 175), y0 + D.randRange(45, 175), D.randRange(18, 34), D.randRange(14, 24));
      p = L(CREAM); p.rect(x0 + B / 2 - 8, y0 + 9, 16, B - 18); p.rect(x0 + 9, y0 + B / 2 - 8, B - 18, 16); pel(p, x0 + 110, y0 + 110, 27, 27);
      q = Q[D.randInt(0, 3)];
      pel(L('#88CCE8'), x0 + q[0], y0 + q[1], 33, 27); pel(L('#B4E6F8'), x0 + q[0], y0 + q[1] + 1.5, 29.5, 23.5); pel(L('#E2F7FE'), x0 + q[0] - 9, y0 + q[1] - 6, 9, 4.5);
      blk(q[0], q[1], 37); blk(110, 110, rich ? 34 : 24);
      bench(110 - 16, D.rand() < 0.5 ? 48 : 172, 1); bench(110 + 16, D.rand() < 0.5 ? 60 : 160, 1); bench(D.rand() < 0.5 ? 50 : 170, 110 - 16, 0);
      scatter('tree', rich ? 6 : 8, 14, 14, 206, 206, 1); scatter('bigtree', rich ? 2 : 3, 20, 20, 200, 200, 1);
      scatter('flower', rich ? 16 : 12, 14, 14, 206, 206, 1); scatter('person', rich ? 6 : 3, 30, 30, 190, 190); scatter('bush', rich ? 5 : 3, 14, 14, 206, 206, 1);
      if (rich) scatter('cone', 3, 60, 60, 160, 160);
    } else if (type === 1) { // plaza
      pel(L('#FFDDB6'), x0 + 110, y0 + 110, 58, 58); pel(L(CREAM), x0 + 110, y0 + 110, 46, 46); pel(L('#FFDDB6'), x0 + 110, y0 + 110, 30, 30);
      p = L(LAWN); k = D.randInt(0, 3);
      for (i = 0; i < 2; i++) {
        q = [[12, 12], [146, 12], [146, 146], [12, 146]][(k + i * 2) % 4];
        prr(p, x0 + q[0], y0 + q[1], 62, 62, 18);
        put(D.rand() < 0.4 ? 'bigtree' : 'tree', q[0] + 22, q[1] + 24); put('tree', q[0] + 44, q[1] + 40);
        scatter('flower', 3, q[0] + 4, q[1] + 4, q[0] + 58, q[1] + 58);
      }
      if (D.rand() < 0.62) put('fountain', 110, 110); else { blk(110, 110, 10); scatter('person', 2, 90, 90, 130, 130); }
      q = [[110, 28], [110, 192], [28, 110], [192, 110]][D.randInt(0, 3)];
      put('kiosk', q[0], q[1]);
      bench(110 - 70, 110, 1); bench(110 + 70, 110, 1); bench(110, 110 - 70, 0); bench(110, 110 + 70, 0);
      scatter('parasol', D.randInt(2, 3), 28, 28, 192, 192); scatter('person', 6, 20, 20, 200, 200);
      scatter('cone', 2, 20, 20, 200, 200); scatter('flower', 4, 16, 16, 204, 204); scatter('bush', 3, 16, 16, 204, 204); scatter('tree', 2, 16, 16, 204, 204);
    } else if (type === 2) { // car park
      prr(L('#B3B0E4'), x0 + 10, y0 + 10, B - 20, B - 20, 16);
      p = L('rgba(255,255,255,0.78)');
      for (k = 0; k <= 6; k++) { p.rect(x0 + 25 + k * 28.3, y0 + 18, 2, 50); p.rect(x0 + 25 + k * 28.3, y0 + 152, 2, 50); }
      arrow(p, x0 + 64, y0 + 110, 1, 0); arrow(p, x0 + 156, y0 + 110, 1, 0);
      for (k = 0; k < 6; k++) {
        if (D.rand() < 0.76) put('car', 40 + k * 28.3, 43, rs(SPR.car)[1], 1, 12);
        if (D.rand() < 0.76) put('car', 40 + k * 28.3, 177, rs(SPR.car)[1], 1, 12);
      }
      p = L(LAWN); pel(p, x0 + 24, y0 + 110, 13, 13); pel(p, x0 + 196, y0 + 110, 13, 13);
      put('tree', 24, 110); put('tree', 196, 110);
      if (D.rand() < 0.4) put('bus', 110, 110, rs(SPR.bus)[0], 0, 40);
      scatter('cone', 4, 40, 84, 180, 136); scatter('person', 3, 40, 84, 180, 136);
    } else if (type === 3) { // houses
      prr(L('#C6EFCA'), x0 + 8, y0 + 8, B - 16, B - 16, 24);
      p = L(CREAM); p.rect(x0 + 8, y0 + 104, B - 16, 12);
      for (i = 0; i < 4; i++) {
        q = Q[i];
        if (D.rand() < 0.88) {
          put('house', q[0], q[1], null, 0, 40);
          if (i < 2) p.rect(x0 + q[0] - 6, y0 + q[1] + 24, 12, 104 - q[1] - 24); else p.rect(x0 + q[0] - 6, y0 + q[1] + 24, 12, B - 8 - q[1] - 24);
        } else { put('bigtree', q[0] - 8, q[1] - 6); put('tree', q[0] + 18, q[1] + 10); bench(q[0] + 4, q[1] + 30, 0); }
      }
      blk(58, 92, 8); blk(162, 92, 8); blk(58, 200, 8); blk(162, 200, 8);
      scatter('tree', 4, 12, 12, 208, 208); scatter('flower', 8, 12, 12, 208, 208); scatter('bush', 3, 12, 12, 208, 208);
      scatter('person', 3, 20, 98, 200, 122); scatter('cone', 1, 20, 98, 200, 122);
    } else { // towers
      prr(L('#FFE4D2'), x0 + 8, y0 + 8, B - 16, B - 16, 18);
      p = L('#F9D6C3');
      for (k = 1; k < 8; k++) { p.rect(x0 + 8 + k * 25.5, y0 + 12, 1.5, B - 24); p.rect(x0 + 12, y0 + 8 + k * 25.5, B - 24, 1.5); }
      if (D.rand() < 0.45) {
        put('tower', 110, 110, null, 0, 68);
        q = [[26, 26], [194, 26], [26, 194], [194, 194]];
        for (i = 0; i < 4; i++) put(D.rand() < 0.5 ? 'bigtree' : 'tree', q[i][0], q[i][1]);
        bench(110, 196, 0); bench(24, 110, 1);
        scatter('person', 3, 12, 12, 208, 208); scatter('flower', 4, 12, 12, 208, 208); scatter('bush', 2, 12, 12, 208, 208); scatter('cone', 2, 12, 12, 208, 208);
      } else {
        k = D.randInt(0, 3); var nb = D.rand() < 0.55 ? 2 : 3, lp = L(LAWN);
        for (i = 0; i < 4; i++) {
          q = [[58, 58], [162, 58], [162, 162], [58, 162]][(k + i) % 4];
          if (i === 0 || i === 2 || (i === 1 && nb === 3)) put('building', q[0], q[1], null, 0, 54);
          else {
            pel(lp, x0 + q[0], y0 + q[1], 38, 38);
            put(D.rand() < 0.5 ? 'bigtree' : 'tree', q[0] - 12, q[1] - 10); put('tree', q[0] + 16, q[1] + 6);
            if (D.rand() < 0.6) put('parasol', q[0] - 6, q[1] + 22);
            scatter('flower', 4, q[0] - 34, q[1] - 34, q[0] + 34, q[1] + 34); scatter('person', 2, q[0] - 34, q[1] - 34, q[0] + 34, q[1] + 34);
            bench(q[0] + 22, q[1] - 26, 0);
          }
        }
        scatter('person', 2, 12, 12, 208, 208); scatter('cone', 2, 12, 12, 208, 208); scatter('bush', 2, 12, 12, 208, 208);
      }
    }
    return { x: x0, y: y0, u: CS * (x0 + B / 2) - SN * (y0 + B / 2), v: (SN * (x0 + B / 2) + CS * (y0 + B / 2)) * TK, layers: layers };
  }

  function vehPos(o) {
    var lp = o.lp, w = lp.r - lp.l, h = lp.b - lp.t, s = lp.s, oy;
    if (s < w) { o.x = lp.l + s; o.y = lp.t; o.dx = 1; o.dy = 0; oy = 0; }
    else if (s < w + h) { o.x = lp.r; o.y = lp.t + s - w; o.dx = 0; o.dy = 1; oy = 1; }
    else if (s < w * 2 + h) { o.x = lp.r - (s - w - h); o.y = lp.b; o.dx = -1; o.dy = 0; oy = 0; }
    else { o.x = lp.l; o.y = lp.b - (s - w * 2 - h); o.dx = 0; o.dy = -1; oy = 1; }
    o.oy = oy; o.sp = lp.sps[oy];
    o.u = CS * o.x - SN * o.y; o.v = (SN * o.x + CS * o.y) * TK;
  }

  function buildCity() {
    var i, j, k, types = [], o;
    objs = []; veh = []; blocks = []; marks = []; cells = []; total = 0;
    for (i = 0; i < 8; i++) types.push(0);
    for (i = 0; i < 8; i++) types.push(1);
    for (i = 0; i < 5; i++) types.push(2);
    for (i = 0; i < 8; i++) types.push(3);
    for (i = 0; i < 7; i++) types.push(4);
    for (i = types.length - 1; i > 0; i--) { j = Math.floor(D.rand() * (i + 1)); k = types[i]; types[i] = types[j]; types[j] = k; }
    // The start block is always a busy park with a plaza next door, so there is plenty of small stuff at once.
    function force(idx, t) { if (types[idx] === t) return; for (var n = 0; n < types.length; n++) if (types[n] === t && n !== 14 && n !== 15 && n !== 20) { types[n] = types[idx]; types[idx] = t; return; } }
    force(14, 0); force(15, 1); force(20, 1);
    for (j = 0; j < N; j++) for (i = 0; i < N; i++) blocks.push(genBlock(i, j, types[j * N + i], j * N + i === 14));
    for (j = 0; j < NC; j++) for (i = 0; i < NC; i++) { marks.push(genMarks(i, j)); cells.push([]); }
    for (i = 0; i < objs.length; i++) { o = objs[i]; cells[Math.floor(o.x / CELL) + Math.floor(o.y / CELL) * NC].push(o); }
    for (k = 0; k < 24; k++) {
      var i1 = D.randInt(0, N - 1), i2 = Math.min(N, i1 + D.randInt(1, 3)), j1 = D.randInt(0, N - 1), j2 = Math.min(N, j1 + D.randInt(1, 3));
      var kind = k % 4 === 3 ? 'bus' : 'car';
      o = add(kind, 0, 0, null, 0); objs.pop(); veh.push(o);
      o.lp = { l: RW / 2 + i1 * CELL + RW / 4, r: RW / 2 + i2 * CELL - RW / 4, t: RW / 2 + j1 * CELL + RW / 4, b: RW / 2 + j2 * CELL - RW / 4, s: 0, per: 0, sps: rs(SPR[kind]), max: D.randRange(42, 68), spd: 0 };
      o.lp.per = 2 * (o.lp.r - o.lp.l + o.lp.b - o.lp.t); o.lp.s = D.rand() * o.lp.per; o.lp.spd = o.lp.max;
      o.dx = 1; o.dy = 0; vehPos(o);
    }
    cityPaths = [new Path2D(), new Path2D(), new Path2D()];
    prr(cityPaths[0], -36, -36, CITY + 72, CITY + 72, 64); prr(cityPaths[1], -27, -27, CITY + 54, CITY + 54, 56); prr(cityPaths[2], 0, 0, CITY, CITY, 30);
    padPath = new Path2D(); prr(padPath, 0, 0, B, B, 20);
  }

  // ------------------------------------------------------------------ feedback
  function pop(str, u, v, word) {
    var p = null, i, best = -1;
    for (i = 0; i < pops.length; i++) { if (!pops[i].on) { p = pops[i]; break; } if (!pops[i].word && pops[i].t > best) { best = pops[i].t; p = pops[i]; } }
    if (!p) return;
    p.on = 1; p.str = str; p.u = u; p.v = v; p.t = 0; p.word = word; p.life = word ? 0.95 : 0.7; p.ox = 0;
  }
  function puff(u, v, du, dv, r, life, col) {
    for (var i = 0; i < parts.length; i++) {
      var p = parts[i];
      if (!p.on) { p.on = 1; p.u = u; p.v = v; p.du = du; p.dv = dv; p.t = 0; p.life = life; p.r = r; p.col = col; return; }
    }
  }
  function ring() { for (var i = 0; i < rings.length; i++) if (!rings[i].on) { rings[i].on = 1; rings[i].t = 0; return; } }

  function swallow(o) {
    var k = o.k, R = hole.R, a, n, i;
    o.st = 1; o.ft = 0; o.fd = 0.3 + k.rad * 0.0065 + k.h * 0.0012;
    o.fu = o.u - hole.u; o.fv = o.v - hole.v;
    o.fr = (o.fu > 0 ? -1 : 1) * Math.min(1.1, 14 / (k.h + 6)) * (0.6 + Math.random() * 0.5);
    o.wob = 0;
    falls.push(o);
    pts += k.pts; gulp = Math.min(1, gulp + 0.35 + k.hap * 0.25);
    combo = comboT > 0 ? combo + 1 : 1; comboT = 0.6;
    a = Math.atan2(o.fv, o.fu); n = 2 + k.hap * 2;
    for (i = 0; i < n; i++) {
      var b = a + (Math.random() - 0.5) * (0.9 + k.hap * 0.5);
      puff(hole.u + Math.cos(b) * R * 0.98, hole.v + Math.sin(b) * R * TK * 0.98, Math.cos(b) * (16 + Math.random() * 26), Math.sin(b) * (10 + Math.random() * 16) - 8, (2.6 + Math.random() * 2.6) * (1 + k.hap * 0.35), 0.4 + Math.random() * 0.25, 0);
    }
    if (k.pts >= 8) pop('+' + k.pts, hole.u + (Math.random() - 0.5) * R, hole.v - R * TK * 0.9, 0);
    else pend += k.pts;
    if (k.hap === 0) { if (selT <= 0) { D.haptic('select'); selT = 0.075; } }
    else if (k.hap === 1) { if (lightT <= 0) { D.haptic('light'); lightT = 0.05; } }
    else D.haptic(k.hap === 2 ? 'medium' : 'heavy');
    if (k.hap >= 2) shake = Math.max(shake, k.hap === 3 ? 7 : k.lvl >= 4 ? 4 : 2.5);
    if (wordT <= 0 && k.pts >= 4) {
      if (k.lvl >= 5) { pop('MEGA GULP', hole.u, hole.v - R * TK, 3); wordT = 0.7; }
      else if (k.hap === 2) { pop('CRUNCH', hole.u, hole.v - R * TK, 2); wordT = 0.8; }
      else if (k.pts >= 6 || combo >= 4) { pop('NOM', hole.u, hole.v - R * TK, 1); wordT = 1.1; }
    }
    D.tone({ freq: 300 + Math.min(combo, 14) * 34 + k.hap * 20, dur: 0.07 + k.hap * 0.03, type: k.hap >= 2 ? 'square' : 'triangle', vol: 0.06 + k.hap * 0.02, slide: k.hap >= 2 ? 120 : 0 });
    while (lvl < MAXL && pts >= thr[lvl]) levelUp();
    var np = Math.floor(pts / total * 100);
    if (np !== pct) { pct = np; pctPop = 1; }
  }
  function levelUp() {
    lvl += 1; hole.Rt = RAD[lvl]; zBump = 0.085; lvlPop = 1; gulp = 1; shake = Math.max(shake, 4);
    ring(); D.haptic('success');
    D.tone({ freq: 520, dur: 0.12, type: 'triangle', vol: 0.1, slide: 1040 });
    for (var i = 0; i < 14; i++) {
      var a = i / 14 * TAU;
      puff(hole.u + Math.cos(a) * hole.R, hole.v + Math.sin(a) * hole.R * TK, Math.cos(a) * 70, Math.sin(a) * 50, 3.5 + Math.random() * 2, 0.55, 1 + (i % 3));
    }
  }
  function tryEat(o) {
    var k = o.k, R = hole.R, dx = o.x - hole.x, dy = o.y - hole.y, reach = R + k.rad;
    if (dx > reach || dx < -reach || dy > reach || dy < -reach) return;
    var d2 = dx * dx + dy * dy, e;
    if (k.lvl <= lvl) { e = R - k.rad * 0.5; if (e < 8) e = 8; if (d2 < e * e) swallow(o); }
    else { e = R + k.rad * 0.72; if (d2 < e * e) { if (o.wob <= 0) wobs.push(o); o.wob = 1; } }
  }
  function finish() {
    if (ended) return;
    ended = true; endT = 0; jid = null; sstr = 0;
    ring(); shake = 5;
    D.haptic('success');
    D.tone({ freq: 660, dur: 0.3, type: 'triangle', vol: 0.12, slide: 990 });
    D.end({ score: pct, unit: '%', headline: 'Hole level ' + lvl });
  }

  // ------------------------------------------------------------------ bot
  function botEdible(o) { return o.st === 0 && o.k.lvl <= lvl && o.skip < TT; }
  function botBinOf(o) { return Math.min(BN - 1, Math.floor(o.x / BS)) + Math.min(BN - 1, Math.floor(o.y / BS)) * BN; }
  function botPickBin() {
    var i, o, b, x, y, best = -1, bs = 0, R = hole.R;
    if (!binW) binW = new Float32Array(BN * BN);
    for (i = 0; i < binW.length; i++) binW[i] = 0;
    for (i = 0; i < objs.length; i++) { o = objs[i]; if (botEdible(o)) binW[botBinOf(o)] += o.k.pts * (o.k.lvl >= lvl - 1 ? 1.5 : 1); }
    for (i = 0; i < veh.length; i++) { o = veh[i]; if (botEdible(o)) binW[botBinOf(o)] += o.k.pts; }
    for (y = 0; y < BN; y++) for (x = 0; x < BN; x++) {
      b = x + y * BN;
      var w = binW[b];
      if (w <= 0) continue;
      if (x > 0) w += binW[b - 1] * 0.6; if (x < BN - 1) w += binW[b + 1] * 0.6;
      if (y > 0) w += binW[b - BN] * 0.6; if (y < BN - 1) w += binW[b + BN] * 0.6;
      var dx = (x + 0.5) * BS - hole.x, dy = (y + 0.5) * BS - hole.y;
      var sc = w / Math.pow(Math.sqrt(dx * dx + dy * dy) + 70 + R, 1.35);
      if (b === bot.bin) sc *= 1.3;
      if (sc > bs) { bs = sc; best = b; }
    }
    bot.bin = best;
  }
  function botNearest() {
    if (bot.bin < 0) return null;
    var bx = bot.bin % BN, by = Math.floor(bot.bin / BN), best = null, bd = 1e12, i, o, n = objs.length + veh.length;
    for (i = 0; i < n; i++) {
      o = i < objs.length ? objs[i] : veh[i - objs.length];
      if (!botEdible(o)) continue;
      var ox = Math.min(BN - 1, Math.floor(o.x / BS)) - bx, oy = Math.min(BN - 1, Math.floor(o.y / BS)) - by;
      if (ox < -1 || ox > 1 || oy < -1 || oy > 1) continue;
      var dx = o.x - hole.x, dy = o.y - hole.y, d = dx * dx + dy * dy - o.k.pts * 60;
      if (d < bd) { bd = d; best = o; }
    }
    return best;
  }

  // ------------------------------------------------------------------ drawing helpers
  function otext(ctx, str, x, y, font, fill, stroke, sw, scale) {
    var d = D.dpr * (scale || 1);
    ctx.setTransform(d, 0, 0, d, D.dpr * x, D.dpr * y);
    ctx.font = font; ctx.textAlign = 'center'; ctx.textBaseline = 'alphabetic'; ctx.lineJoin = 'round';
    if (stroke) { ctx.lineWidth = sw; ctx.strokeStyle = stroke; ctx.strokeText(str, 0, 0); }
    ctx.fillStyle = fill; ctx.fillText(str, 0, 0);
    ctx.setTransform(D.dpr, 0, 0, D.dpr, 0, 0);
  }
  function byDepth(a, b) { return a.v - b.v; }
  var PCOL = ['#FFFFFF', '#FFE27A', '#FF9FB8', '#B79CF0'];

  function drawHole(ctx, hx, hy, rx, ry) {
    ctx.fillStyle = 'rgba(74,54,140,0.3)';
    ctx.beginPath(); ctx.ellipse(hx, hy + ry * 0.03, rx * 1.09, ry * 1.1, 0, 0, TAU); ctx.fill();
    ctx.save(); ctx.translate(hx, hy); ctx.scale(rx, ry);
    ctx.fillStyle = gWall; ctx.beginPath(); ctx.arc(0, 0, 1, 0, TAU); ctx.fill();
    ctx.fillStyle = 'rgba(24,10,60,0.34)';
    ctx.beginPath(); ctx.ellipse(0, 0.1, 0.93, 0.87, 0, 0, TAU); ctx.fill();
    ctx.beginPath(); ctx.ellipse(0, 0.2, 0.85, 0.76, 0, 0, TAU); ctx.fill();
    ctx.fillStyle = gVoid; ctx.beginPath(); ctx.ellipse(0, 0.3, 0.76, 0.64, 0, 0, TAU); ctx.fill();
    ctx.restore();
    ctx.lineCap = 'round';
    ctx.strokeStyle = 'rgba(196,172,255,0.95)'; ctx.lineWidth = Math.max(1.6, rx * 0.04);
    ctx.beginPath(); ctx.ellipse(hx, hy, rx * 0.975, ry * 0.975, 0, Math.PI * 1.1, Math.PI * 1.9); ctx.stroke();
    ctx.strokeStyle = 'rgba(255,255,255,0.6)'; ctx.lineWidth = 1.5;
    ctx.beginPath(); ctx.ellipse(hx, hy, rx * 1.035, ry * 1.045, 0, Math.PI * 0.18, Math.PI * 0.82); ctx.stroke();
  }

  function drawHud(ctx, W, H, state) {
    var top = D.safe.top, dpr = D.dpr, i;
    // percentage
    otext(ctx, pct + '%', W / 2, top + 108 + 3, fBig, INK, INK, 9, 1 + pctPop * 0.16);
    otext(ctx, pct + '%', W / 2, top + 108, fBig, '#FFFFFF', INK, 9, 1 + pctPop * 0.16);
    // growth bar
    var bw = Math.min(150, W * 0.38), bx = W / 2 - bw / 2, by = top + 122, bh = 11;
    var lo = thr[lvl - 1] || 0, f = lvl >= MAXL ? 1 : D.clamp((pts - lo) / (thr[lvl] - lo), 0, 1);
    ctx.fillStyle = INK; D.rr(bx - 3, by - 3, bw + 6, bh + 6, 9); ctx.fill();
    ctx.fillStyle = '#FFFFFF'; D.rr(bx, by, bw, bh, 6); ctx.fill();
    if (f > 0.01) { ctx.fillStyle = gBar; D.rr(bx, by, Math.max(bh, bw * f), bh, 6); ctx.fill(); }
    if (lvlPop > 0.01) { ctx.fillStyle = 'rgba(255,255,255,' + (lvlPop * 0.8) + ')'; D.rr(bx, by, bw, bh, 6); ctx.fill(); }
    var cy = by + bh / 2, r1 = 12.5 * (1 + lvlPop * 0.35);
    ctx.fillStyle = '#FFFFFF'; ctx.beginPath(); ctx.arc(bx - 5, cy, r1 + 2, 0, TAU); ctx.fill();
    ctx.fillStyle = INK; ctx.beginPath(); ctx.arc(bx - 5, cy, r1, 0, TAU); ctx.fill();
    otext(ctx, String(lvl), bx - 5, cy + 5.5, fSmall, '#FFFFFF', null, 0, 1 + lvlPop * 0.35);
    ctx.fillStyle = INK; ctx.beginPath(); ctx.arc(bx + bw + 5, cy, 12.5, 0, TAU); ctx.fill();
    ctx.fillStyle = '#FFFFFF'; ctx.beginPath(); ctx.arc(bx + bw + 5, cy, 10, 0, TAU); ctx.fill();
    if (lvl >= MAXL) {
      ctx.fillStyle = INK; ctx.beginPath();
      for (i = 0; i < 10; i++) { var sa = -Math.PI / 2 + i * Math.PI / 5, sr = i & 1 ? 3 : 7; ctx.lineTo(bx + bw + 5 + Math.cos(sa) * sr, cy + Math.sin(sa) * sr); }
      ctx.closePath(); ctx.fill();
    } else otext(ctx, String(lvl + 1), bx + bw + 5, cy + 5.5, fSmall, INK, null, 0, 1);
    // timer pill
    var sec = Math.max(0, Math.ceil(tLeft)), hot = state === 'playing' && tLeft <= 10, pw = 80, ph = 30;
    var ps = hot ? 1 + 0.09 * Math.pow(1 - (tLeft - Math.floor(tLeft)), 4) : 1;
    ctx.setTransform(dpr * ps, 0, 0, dpr * ps, dpr * (14 + pw / 2), dpr * (top + 64 + ph / 2));
    ctx.fillStyle = INK; D.rr(-pw / 2 - 2.5, -ph / 2 - 2.5, pw + 5, ph + 5, 18); ctx.fill();
    ctx.fillStyle = hot ? '#FF4F6E' : '#FFFFFF'; D.rr(-pw / 2, -ph / 2, pw, ph, 15); ctx.fill();
    ctx.strokeStyle = hot ? '#FFFFFF' : '#FF4F6E'; ctx.lineWidth = 2.2; ctx.lineCap = 'round';
    ctx.beginPath(); ctx.arc(-pw / 2 + 17, 0, 7, 0, TAU); ctx.moveTo(-pw / 2 + 17, -3.6); ctx.lineTo(-pw / 2 + 17, 0); ctx.lineTo(-pw / 2 + 20, 1.6); ctx.stroke();
    ctx.font = fNum; ctx.textAlign = 'center'; ctx.textBaseline = 'alphabetic';
    ctx.fillStyle = hot ? '#FFFFFF' : INK;
    ctx.fillText(Math.floor(sec / 60) + ':' + (sec % 60 < 10 ? '0' : '') + (sec % 60), 11, 7);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }

  // ------------------------------------------------------------------ the game
  var G = {
    reset: function () {
      var want = Math.min(4.2, D.dpr * ZOOM[1] * D.clamp(D.W / 390, 0.85, 1.3));
      if (!SPR || Math.abs(want - SS) > 0.05) { SS = want; buildSprites(); }
      G.resize(D.W, D.H);
      buildCity();
      roundLen = D.clip ? 35 : 75; tLeft = roundLen;
      var fr = D.clip ? FRAC_CLIP : FRAC_PLAY, i;
      thr = [];
      for (i = 0; i <= MAXL; i++) thr.push(Math.round(fr[i] * total));
      lvl = 1; pts = 0; pct = 0; ended = false; endT = 0;
      var sx = RW + 2 * CELL + 110, sy = RW + 2 * CELL + 110;
      hole = { x: sx, y: sy, vx: 0, vy: 0, R: RAD[1], Rt: RAD[1], u: CS * sx - SN * sy, v: (SN * sx + CS * sy) * TK };
      cam = { x: sx, y: sy };
      zoomNow = ZOOM[1] * zs; zBump = 0; shake = 0; gulp = 0; pctPop = 0; lvlPop = 0;
      falls.length = 0; wobs.length = 0; jid = null; sdx = sdy = sstr = 0;
      pend = 0; pendT = 0; selT = 0; lightT = 0; wordT = 0; combo = 0; comboT = 0;
      for (i = 0; i < pops.length; i++) pops[i].on = 0;
      for (i = 0; i < parts.length; i++) parts[i].on = 0;
      for (i = 0; i < rings.length; i++) rings[i].on = 0;
      bot.bin = -1; bot.tgt = null; bot.t = 0; bot.dx = 0; bot.dy = 0; bot.held = 0; bot.down = false; bot.ph = D.rand() * 6;
    },
    resize: function (W) {
      var ctx = D.ctx;
      zs = D.clamp(W / 390, 0.85, 1.3);
      gWall = ctx.createLinearGradient(0, -1, 0, 1);
      gWall.addColorStop(0, '#9274E0'); gWall.addColorStop(0.5, '#5433A0'); gWall.addColorStop(1, '#22114A');
      gVoid = ctx.createRadialGradient(0, 0.36, 0.05, 0, 0.3, 0.8);
      gVoid.addColorStop(0, '#04020C'); gVoid.addColorStop(0.65, '#120828'); gVoid.addColorStop(1, '#2A1560');
      gBar = ctx.createLinearGradient(W / 2 - 80, 0, W / 2 + 80, 0);
      gBar.addColorStop(0, '#7B5CE0'); gBar.addColorStop(1, '#FF7FB0');
      fBig = D.font(56); fNum = D.font(20); fWord = D.font(30); fSmall = D.font(16); fHint = D.font(17);
    },
    start: function () {},

    update: function (dt, state) {
      var i, o, k, playing = state === 'playing' && !ended;
      TT += dt;
      if (playing) {
        tLeft -= dt;
        if (tLeft <= 0) { tLeft = 0; finish(); playing = false; }
      }
      if (ended) endT += dt;

      // hole movement: floating joystick, eased velocity
      var maxS = 215 / Math.pow(ZOOM[lvl], 0.9), tvx = 0, tvy = 0;
      if (playing && sstr > 0.02) {
        var a = sdx, b = sdy / TK, wx = CS * a + SN * b, wy = -SN * a + CS * b, m = Math.sqrt(wx * wx + wy * wy) || 1;
        tvx = wx / m * maxS * sstr; tvy = wy / m * maxS * sstr;
      }
      k = 1 - Math.exp(-dt * (tvx || tvy ? 13 : 9));
      hole.vx += (tvx - hole.vx) * k; hole.vy += (tvy - hole.vy) * k;
      hole.x = D.clamp(hole.x + hole.vx * dt, 12, CITY - 12); hole.y = D.clamp(hole.y + hole.vy * dt, 12, CITY - 12);
      hole.u = CS * hole.x - SN * hole.y; hole.v = (SN * hole.x + CS * hole.y) * TK;
      hole.R += (hole.Rt - hole.R) * (1 - Math.exp(-dt * 7));

      // traffic: clockwise loops, later vehicles give way to earlier ones
      for (i = 0; i < veh.length; i++) {
        o = veh[i];
        if (o.st !== 0) continue;
        var lp = o.lp, blocked = false, j;
        for (j = 0; j < i; j++) {
          var w = veh[j];
          if (w.st !== 0) continue;
          var rx = w.x - o.x, ry = w.y - o.y, ah = rx * o.dx + ry * o.dy;
          if (ah > 0 && ah < 78 && Math.abs(rx * o.dy - ry * o.dx) < 26) { blocked = true; break; }
        }
        lp.spd += ((blocked ? 0 : lp.max) - lp.spd) * Math.min(1, dt * 5);
        lp.s = (lp.s + lp.spd * dt) % lp.per;
        vehPos(o);
      }

      if (playing) {
        var R = hole.R, mrg = R + 62;
        var c0 = Math.max(0, Math.floor((hole.x - mrg) / CELL)), c1 = Math.min(N, Math.floor((hole.x + mrg) / CELL));
        var r0 = Math.max(0, Math.floor((hole.y - mrg) / CELL)), r1 = Math.min(N, Math.floor((hole.y + mrg) / CELL)), cx, cy, arr;
        for (cy = r0; cy <= r1; cy++) for (cx = c0; cx <= c1; cx++) {
          arr = cells[cx + cy * NC];
          for (i = 0; i < arr.length; i++) if (arr[i].st === 0) tryEat(arr[i]);
        }
        for (i = 0; i < veh.length; i++) if (veh[i].st === 0) tryEat(veh[i]);
        D.score(pct);
      }

      for (i = falls.length - 1; i >= 0; i--) {
        o = falls[i]; o.ft += dt;
        var ft = Math.min(1, o.ft / o.fd), e = 1 - (1 - ft) * (1 - ft);
        o.v = hole.v + o.fv * (1 - 0.75 * e);
        if (o.ft >= o.fd) { o.st = 2; falls[i] = falls[falls.length - 1]; falls.pop(); }
      }
      for (i = wobs.length - 1; i >= 0; i--) {
        o = wobs[i]; o.wob -= dt * 2.6;
        if (o.wob <= 0 || o.st !== 0) { o.wob = 0; wobs[i] = wobs[wobs.length - 1]; wobs.pop(); }
      }

      pendT -= dt; selT -= dt; lightT -= dt; wordT -= dt; comboT -= dt;
      if (pend > 0 && pendT <= 0) {
        var pa = Math.random() * TAU;
        pop('+' + pend, hole.u + Math.cos(pa) * hole.R * 0.9, hole.v - hole.R * TK * 0.5 + Math.sin(pa) * hole.R * TK * 0.5, 0);
        pend = 0; pendT = 0.13;
      }
      for (i = 0; i < pops.length; i++) { o = pops[i]; if (o.on) { o.t += dt; if (o.t >= o.life) o.on = 0; } }
      for (i = 0; i < parts.length; i++) {
        o = parts[i];
        if (o.on) { o.t += dt; o.u += o.du * dt; o.v += o.dv * dt; o.du *= 1 - dt * 3; o.dv *= 1 - dt * 3; if (o.t >= o.life) o.on = 0; }
      }
      for (i = 0; i < rings.length; i++) { o = rings[i]; if (o.on) { o.t += dt; if (o.t >= 0.7) o.on = 0; } }
      gulp *= Math.exp(-dt * 7); pctPop *= Math.exp(-dt * 8); lvlPop *= Math.exp(-dt * 4); zBump *= Math.exp(-dt * 4.5);
      shake *= Math.exp(-dt * 9);
      shx = (Math.random() - 0.5) * shake * 2; shy = (Math.random() - 0.5) * shake * 2;

      // camera
      k = 1 - Math.exp(-dt * 6);
      cam.x += (hole.x + hole.vx * 0.16 - cam.x) * k; cam.y += (hole.y + hole.vy * 0.16 - cam.y) * k;
      var zt = ZOOM[lvl] * zs * (ended ? 0.9 : 1);
      zoomNow += (zt - zoomNow) * (1 - Math.exp(-dt * (ended ? 1.2 : 2.6)));
    },

    draw: function (ctx, W, H, state) {
      var dpr = D.dpr, z = zoomNow * (1 + zBump), i, j, o, sp, sx, sy;
      var fy = D.clip ? H * 0.42 : H * 0.47;
      var ox = W / 2 - (CS * cam.x - SN * cam.y) * z + shx, oy = fy - (SN * cam.x + CS * cam.y) * TK * z + shy;


      // visible range of city cells
      var x0 = 1e9, x1 = -1e9, y0 = 1e9, y1 = -1e9;
      for (i = 0; i < 4; i++) {
        var a = ((i & 1 ? W + 20 : -20) - ox) / z, b = ((i & 2 ? H + 250 * z : -20) - oy) / (z * TK);
        var wx = CS * a + SN * b, wy = -SN * a + CS * b;
        if (wx < x0) x0 = wx; if (wx > x1) x1 = wx; if (wy < y0) y0 = wy; if (wy > y1) y1 = wy;
      }
      var c0 = Math.max(0, Math.floor(x0 / CELL)), c1 = Math.min(N, Math.floor(x1 / CELL));
      var r0 = Math.max(0, Math.floor(y0 / CELL)), r1 = Math.min(N, Math.floor(y1 / CELL));

      // ground
      ctx.setTransform(dpr * z * CS, dpr * z * SN * TK, -dpr * z * SN, dpr * z * CS * TK, dpr * ox, dpr * oy);
      if (x0 > 2 && y0 > 2 && x1 < CITY - 2 && y1 < CITY - 2) {
        ctx.fillStyle = ROAD; ctx.fillRect(x0 - 40, y0 - 40, x1 - x0 + 80, y1 - y0 + 80);
      } else {
        ctx.fillStyle = SEA; ctx.fillRect(x0 - 40, y0 - 40, x1 - x0 + 80, y1 - y0 + 80);
        ctx.fillStyle = 'rgba(255,255,255,0.55)'; ctx.fill(cityPaths[0]);
        ctx.fillStyle = '#FFF2CC'; ctx.fill(cityPaths[1]);
        ctx.fillStyle = ROAD; ctx.fill(cityPaths[2]);
      }
      ctx.fillStyle = 'rgba(255,255,255,0.82)';
      for (j = r0; j <= r1; j++) for (i = c0; i <= c1; i++) ctx.fill(marks[i + j * NC]);
      var cvx = SN * 1.6 / TK, cvy = CS * 1.6 / TK;
      ctx.strokeStyle = CURB; ctx.lineWidth = 3.4;
      for (j = r0; j <= r1 && j < N; j++) for (i = c0; i <= c1 && i < N; i++) {
        var bl = blocks[i + j * N];
        sx = bl.u * z + ox; sy = bl.v * z + oy;
        var ext = B * 0.98 * z;
        if (sx < -ext || sx > W + ext || sy < -ext || sy > H + ext) continue;
        ctx.translate(bl.x + cvx, bl.y + cvy); ctx.stroke(padPath);
        ctx.translate(-cvx, -cvy); ctx.fillStyle = PAD; ctx.fill(padPath);
        ctx.translate(-bl.x, -bl.y);
        for (var n = 0; n < bl.layers.length; n++) { ctx.fillStyle = bl.layers[n].c; ctx.fill(bl.layers[n].p); }
      }

      // visible objects
      vis.length = 0;
      for (j = r0; j <= r1; j++) for (i = c0; i <= c1; i++) {
        var arr = cells[i + j * NC];
        for (var m = 0; m < arr.length; m++) {
          o = arr[m];
          if (o.st !== 0) continue;
          sp = o.sp; sx = o.u * z + ox; sy = o.v * z + oy;
          if (sx + (sp.w - sp.ax) * z < 0 || sx - sp.ax * z > W || sy - sp.ay * z > H || sy + (sp.h - sp.ay) * z < 0) continue;
          vis.push(o);
        }
      }
      for (i = 0; i < veh.length; i++) {
        o = veh[i];
        if (o.st !== 0) continue;
        sp = o.sp; sx = o.u * z + ox; sy = o.v * z + oy;
        if (sx + (sp.w - sp.ax) * z < 0 || sx - sp.ax * z > W || sy - sp.ay * z > H || sy + (sp.h - sp.ay) * z < 0) continue;
        vis.push(o);
      }

      // one merged shadow layer, still in ground space
      ctx.beginPath();
      for (i = 0; i < vis.length; i++) {
        o = vis[i];
        var kk = o.k, r = kk.shr, d;
        if (r) { d = r * 0.38; ctx.moveTo(o.x + d + r, o.y + d); ctx.arc(o.x + d, o.y + d, r, 0, TAU); }
        else {
          var hx = o.oy ? kk.by : kk.bx, hy = o.oy ? kk.bx : kk.by;
          d = 3 + kk.h * 0.2;
          ctx.moveTo(o.x - hx, o.y - hy); ctx.lineTo(o.x + hx, o.y - hy); ctx.lineTo(o.x + hx + d, o.y - hy + d);
          ctx.lineTo(o.x + hx + d, o.y + hy + d); ctx.lineTo(o.x - hx + d, o.y + hy + d); ctx.lineTo(o.x - hx, o.y + hy); ctx.closePath();
        }
      }
      ctx.fillStyle = 'rgba(92,80,172,0.24)'; ctx.fill();
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

      // the hole and its level-up rings
      var hsx = hole.u * z + ox, hsy = hole.v * z + oy;
      var hr = hole.R * (1 + gulp * 0.07 + Math.sin(TT * 3) * 0.012), rx = hr * z, ry = hr * z * TK;
      for (i = 0; i < rings.length; i++) {
        o = rings[i];
        if (!o.on) continue;
        var rt = o.t / 0.7, re = 1 - (1 - rt) * (1 - rt);
        ctx.strokeStyle = 'rgba(255,255,255,' + (0.9 * (1 - rt)) + ')'; ctx.lineWidth = 7 * (1 - rt) + 1.5;
        ctx.beginPath(); ctx.ellipse(hsx, hsy, rx * (1.1 + re * 1.3), ry * (1.1 + re * 1.3), 0, 0, TAU); ctx.stroke();
      }
      drawHole(ctx, hsx, hsy, rx, ry);

      // objects, far to near
      for (i = 0; i < falls.length; i++) vis.push(falls[i]);
      vis.sort(byDepth);
      for (i = 0; i < vis.length; i++) {
        o = vis[i]; sp = o.sp;
        if (o.st === 1) {
          var ft = Math.min(1, o.ft / o.fd), e = 1 - (1 - ft) * (1 - ft), sc = (1 - 0.42 * ft * ft) * z;
          sx = hsx + o.fu * (1 - 0.75 * e) * z; sy = hsy + o.fv * (1 - 0.75 * e) * z + ft * ft * (sp.ay * 0.85 + hole.R * TK * 0.5) * z;
          ctx.save();
          ctx.beginPath(); ctx.rect(0, 0, W, hsy); ctx.ellipse(hsx, hsy, rx * 0.97, ry * 0.97, 0, 0, TAU); ctx.clip();
          ctx.translate(sx, sy); ctx.rotate(o.fr * e);
          ctx.drawImage(sp.cv, -sp.ax * sc, -sp.ay * sc, sp.w * sc, sp.h * sc);
          ctx.restore();
          continue;
        }
        sx = o.u * z + ox; sy = o.v * z + oy;
        if (o.k.tall) {
          var hide = o.v > hole.v && hsx > sx - sp.ax * z && hsx < sx + (sp.w - sp.ax) * z && hsy > sy - sp.ay * z && hsy < sy;
          o.al += ((hide ? 0.3 : 1) - o.al) * 0.2;
          if (o.al < 0.99) ctx.globalAlpha = o.al;
        } else if (o.k === T.person) sy -= Math.abs(Math.sin(TT * 5 + o.ph)) * 1.6 * z;
        if (o.wob > 0.01) {
          var ang = Math.sin(TT * 30 + o.ph) * Math.min(0.13, 3.4 / (o.k.h + 8)) * o.wob, ca = Math.cos(ang) * dpr, sa = Math.sin(ang) * dpr;
          ctx.setTransform(ca, sa, -sa, ca, dpr * sx, dpr * sy);
          ctx.drawImage(sp.cv, -sp.ax * z, -sp.ay * z, sp.w * z, sp.h * z);
          ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
        } else ctx.drawImage(sp.cv, sx - sp.ax * z, sy - sp.ay * z, sp.w * z, sp.h * z);
        if (o.k.tall) ctx.globalAlpha = 1;
      }

      // puffs
      for (i = 0; i < parts.length; i++) {
        o = parts[i];
        if (!o.on) continue;
        var pt = o.t / o.life;
        ctx.globalAlpha = 1 - pt * pt; ctx.fillStyle = PCOL[o.col];
        ctx.beginPath(); ctx.arc(o.u * z + ox, o.v * z + oy, o.r * (0.6 + pt * 0.8) * Math.max(0.8, z), 0, TAU); ctx.fill();
      }
      ctx.globalAlpha = 1;

      // popups
      for (i = 0; i < pops.length; i++) {
        o = pops[i];
        if (!o.on) continue;
        var t = o.t / o.life, s = D.easeOutBack(Math.min(1, o.t / 0.16));
        ctx.globalAlpha = t > 0.65 ? 1 - (t - 0.65) / 0.35 : 1;
        sx = D.clamp(o.u * z + ox, 50, W - 50); sy = o.v * z + oy - (o.word ? 16 + 26 * D.easeOut(t) : 34 * D.easeOut(t));
        if (sy < D.safe.top + (o.word ? 182 : 162)) sy = D.safe.top + (o.word ? 182 : 162);
        if (o.word) otext(ctx, o.str, sx, sy, fWord, o.word === 3 ? '#FFE27A' : '#FFFFFF', o.word === 3 ? '#E0447F' : '#6B4FD8', 7, s * (o.word === 3 ? 1.12 : 0.92));
        else otext(ctx, o.str, sx, sy, fNum, '#FFFFFF', INK, 5, s);
      }
      ctx.globalAlpha = 1;

      // joystick
      if (jid !== null && state === 'playing' && !D.clip) {
        ctx.strokeStyle = 'rgba(255,255,255,0.4)'; ctx.lineWidth = 3;
        ctx.beginPath(); ctx.arc(jx0, jy0, JMAX, 0, TAU); ctx.stroke();
        ctx.fillStyle = 'rgba(43,36,82,0.2)'; ctx.fill();
        ctx.fillStyle = 'rgba(255,255,255,0.75)';
        ctx.beginPath(); ctx.arc(jx0 + sdx * sstr * JMAX, jy0 + sdy * sstr * JMAX, 20, 0, TAU); ctx.fill();
      }

      drawHud(ctx, W, H, state);

      if (state === 'ready' && !D.clip) {
        var hy2 = H - D.safe.bottom - 104 + Math.sin(TT * 3) * 3, hw = 190;
        ctx.fillStyle = 'rgba(43,36,82,0.88)'; D.rr(W / 2 - hw / 2, hy2, hw, 42, 21); ctx.fill();
        var fx = W / 2 - hw / 2 + 28 + Math.sin(TT * 2.4) * 7;
        ctx.strokeStyle = 'rgba(255,255,255,0.45)'; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(W / 2 - hw / 2 + 28, hy2 + 21, 11, 0, TAU); ctx.stroke();
        ctx.fillStyle = '#FFFFFF'; ctx.beginPath(); ctx.arc(fx, hy2 + 21, 6, 0, TAU); ctx.fill();
        otext(ctx, 'DRAG TO MOVE', W / 2 + 16, hy2 + 27.5, fHint, '#FFFFFF', null, 0, 1);
      }
      if (ended && endT < 1.5) {
        ctx.globalAlpha = endT > 1.1 ? 1 - (endT - 1.1) / 0.4 : 1;
        otext(ctx, 'TIME UP', W / 2, H * (D.clip ? 0.26 : 0.3), fBig, '#FFFFFF', INK, 10, D.easeOutBack(Math.min(1, endT / 0.25)));
        ctx.globalAlpha = 1;
      }
    },

    pointerDown: function (x, y, id) {
      if (ended) return;
      if (jid === null) { jid = id; jx0 = x; jy0 = y; jx = x; jy = y; sstr = 0; D.haptic('light'); }
    },
    pointerMove: function (x, y, id, down) {
      if (id !== jid || !down) return;
      var dx = x - jx0, dy = y - jy0, d = Math.sqrt(dx * dx + dy * dy);
      if (d > JMAX) { jx0 += dx / d * (d - JMAX); jy0 += dy / d * (d - JMAX); dx = x - jx0; dy = y - jy0; d = JMAX; }
      if (d < 5) { sstr = 0; return; }
      sdx = dx / d; sdy = dy / d; sstr = Math.min(1, (d - 3) / (JMAX * 0.72));
    },
    pointerUp: function (x, y, id) { if (id === jid) { jid = null; sstr = 0; } },
    key: function (k) {
      var m = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1], a: [-1, 0], d: [1, 0], w: [0, -1], s: [0, 1] }[k];
      if (m) { sdx = m[0]; sdy = m[1]; sstr = 1; } else if (k === ' ') sstr = 0;
    },

    bot: function (dt) {
      if (ended) return;
      var bx = D.W / 2, by = D.H * 0.62, o = bot.tgt;
      if (!bot.down) { G.pointerDown(bx, by, 99, false); bot.down = true; }
      bot.t -= dt; bot.held += dt;
      if (!o || o.st !== 0 || bot.t <= 0 || bot.held > 3.2) {
        if (o && o.st === 0 && bot.held > 3.2) o.skip = TT + 5;
        if (bot.t <= 0 || bot.bin < 0 || !o) { botPickBin(); bot.t = 0.55 + D.rand() * 0.35; }
        var nt = botNearest();
        if (!nt) { botPickBin(); nt = botNearest(); }
        if (nt !== o) bot.held = 0;
        bot.tgt = o = nt;
      }
      var tx = o ? o.x : CITY / 2, ty = o ? o.y : CITY / 2;
      var dx = tx - hole.x, dy = ty - hole.y, sx = CS * dx - SN * dy, sy = (SN * dx + CS * dy) * TK, d = Math.sqrt(sx * sx + sy * sy) || 1;
      var an = Math.atan2(sy, sx) + Math.sin(TT * 1.9 + bot.ph) * 0.16 + Math.sin(TT * 4.3 + bot.ph * 2) * 0.07;
      var k = 1 - Math.exp(-dt * 9);
      bot.dx += (Math.cos(an) - bot.dx) * k; bot.dy += (Math.sin(an) - bot.dy) * k;
      G.pointerMove(bx + bot.dx * JMAX * 0.95, by + bot.dy * JMAX * 0.95, 99, true);
    }
  };

  D.game(G);
})();
