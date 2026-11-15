/* Lane Dash: an endless three-lane synthwave runner for Dailies. */
(function () {
  'use strict';
  var D = window.Dailies;
  var PI = Math.PI, TAU = PI * 2;
  var clamp = D.clamp, lerp = D.lerp;

  var LW = 3, ROAD = 4.5, KERB = 5.3, WALK = 6.9, LAMPX = 7.25, DK = 14;
  var V0 = 21, V1 = 44, VK = 2600, CAR_V = 6;
  var AIR_T = 0.9, GRAV = 31.6, JUMP_V = GRAV * AIR_T / 2, BOOST = 1.3;
  var BARRIER = 0, CONES = 1, CAR = 2, RAMP = 3, GEM = 4;
  var CLEAR_H = [1.0, 0.8, 2.4];
  var PPM = 72, PAD = 16;
  var FLAGS = ['#FF4D6D', '#FFC531', '#4FC3FF'];

  var W = 0, H = 0, cx = 0, HY = 0, kartY = 0, SK = 0, F = 0, camH = 0, builtDpr = 0;
  var bg = null, roadGrad = null, hazeGrad = null, walkGrad = null, noseGrad = null, bodyGrad = null;
  var spBarrier, spCones, spCars, spGem, spGlow, spritesReady = false;

  var items = [], genZ = 0, lastFree = 7, lastPat = -1;
  var kart = { lane: 1, x: 0, z: 0, y: 0, vy: 0, vx: 0, air: false, lean: 0, sqT: 9, sqA: 0, spin: 0, spinV: 0, bump: 0, roll: 0 };
  var camZ = 0, camX = 0, kartV = 0, hitCar = null, carPush = 0;
  var speed = 0, score = 0, gems = 0, nears = 0, mult = 1, multHold = 0, multPulse = 0, gemPulse = 0;
  var tPlay = 0, time = 0, boostT = 0, over = false, crashT = 0, errAt = -1, shake = 0, flash = 0, lastGemHaptic = 0, gemChain = 0, gemChainT = 0;
  var trail = [], trailHead = 0, trailZ = 0, TRAIL_N = 26;
  var parts = [], PART_N = 150, partI = 0;
  var pops = [], POP_N = 10, popI = 0;
  var lines = [];
  var ptr = { id: -1, x0: 0, y0: 0, moved: false, first: false };
  var botRng = null, botCool = 0, botQueue = 0, botQT = 0, failAt = 0;
  var clr = [0, 0, 0], hz = [null, null, null], gemD = [0, 0, 0], rampD = [0, 0, 0];
  var ksx = 0, ksy = 0, ks = 1;
  var i0;

  for (i0 = 0; i0 < TRAIL_N; i0++) trail.push({ x: 0, z: 0, on: false, hw: 0.26 });
  for (i0 = 0; i0 < PART_N; i0++) parts.push({ x: 0, y: 0, vx: 0, vy: 0, life: 0, max: 1, size: 1, col: '#fff', g: 0, kind: 0, rot: 0, vr: 0 });
  for (i0 = 0; i0 < POP_N; i0++) pops.push({ txt: '', x: 0, y: 0, t: 9, life: 1, col: '#fff', size: 20 });
  for (i0 = 0; i0 < 18; i0++) lines.push({ a: 0, p: Math.random(), sp: 0.9 + Math.random() * 0.9, side: i0 % 2 ? 1 : -1 });

  function mk(w, h) { var c = document.createElement('canvas'); c.width = Math.ceil(w); c.height = Math.ceil(h); return c; }
  function rrp(c, x, y, w, h, r) { c.beginPath(); if (c.roundRect) c.roundRect(x, y, w, h, r); else c.rect(x, y, w, h); }
  function ell(c, x, y, rx, ry) { c.beginPath(); c.ellipse(x, y, rx, ry, 0, 0, TAU); }
  function speedAt(z) { return V0 + (V1 - V0) * (1 - Math.exp(-z / VK)); }

  function sprite(wm, hm, base, fn) {
    var img = mk(wm * PPM, hm * PPM), c = img.getContext('2d');
    c.translate(wm * PPM / 2, (hm - base) * PPM);
    c.scale(PPM, -PPM);
    fn(c);
    return { img: img, w: wm, h: hm, base: base };
  }

  function coneShape(c, x, y, k) {
    var g;
    c.fillStyle = 'rgba(12,6,48,0.32)'; ell(c, x, y, 0.52 * k, 0.13 * k); c.fill();
    c.fillStyle = '#D9461A'; rrp(c, x - 0.44 * k, y - 0.02 * k, 0.88 * k, 0.16 * k, 0.05 * k); c.fill();
    g = c.createLinearGradient(x - 0.3 * k, 0, x + 0.3 * k, 0);
    g.addColorStop(0, '#FFA347'); g.addColorStop(0.55, '#FF7426'); g.addColorStop(1, '#D8481C');
    c.fillStyle = g;
    c.beginPath(); c.moveTo(x - 0.33 * k, y + 0.12 * k); c.lineTo(x - 0.08 * k, y + 1.04 * k);
    c.quadraticCurveTo(x, y + 1.12 * k, x + 0.08 * k, y + 1.04 * k); c.lineTo(x + 0.33 * k, y + 0.12 * k); c.closePath(); c.fill();
    c.fillStyle = '#FFF4EC';
    c.beginPath(); c.moveTo(x - 0.235 * k, y + 0.48 * k); c.lineTo(x - 0.175 * k, y + 0.7 * k); c.lineTo(x + 0.175 * k, y + 0.7 * k); c.lineTo(x + 0.235 * k, y + 0.48 * k); c.closePath(); c.fill();
    c.fillStyle = 'rgba(255,255,255,0.35)';
    c.beginPath(); c.moveTo(x - 0.2 * k, y + 0.16 * k); c.lineTo(x - 0.04 * k, y + 0.98 * k); c.lineTo(x - 0.1 * k, y + 0.98 * k); c.lineTo(x - 0.29 * k, y + 0.16 * k); c.closePath(); c.fill();
  }

  function carSprite(main, light, dark) {
    return sprite(3, 2.9, 0.25, function (c) {
      var g;
      c.fillStyle = 'rgba(12,6,48,0.38)'; ell(c, 0, 0.02, 1.4, 0.22); c.fill();
      c.fillStyle = '#17103F'; rrp(c, -1.2, 0, 0.5, 0.6, 0.12); c.fill(); rrp(c, 0.7, 0, 0.5, 0.6, 0.12); c.fill();
      c.fillStyle = light;
      c.beginPath(); c.moveTo(-0.86, 1.95); c.lineTo(-0.74, 2.45); c.quadraticCurveTo(0, 2.56, 0.74, 2.45); c.lineTo(0.86, 1.95); c.closePath(); c.fill();
      c.fillStyle = main;
      c.beginPath(); c.moveTo(-1.02, 1.2); c.lineTo(-0.88, 2.0); c.quadraticCurveTo(0, 2.1, 0.88, 2.0); c.lineTo(1.02, 1.2); c.closePath(); c.fill();
      c.fillStyle = '#231A5C';
      c.beginPath(); c.moveTo(-0.84, 1.3); c.lineTo(-0.74, 1.88); c.quadraticCurveTo(0, 1.96, 0.74, 1.88); c.lineTo(0.84, 1.3); c.closePath(); c.fill();
      c.fillStyle = 'rgba(255,255,255,0.22)';
      c.beginPath(); c.moveTo(-0.6, 1.36); c.lineTo(-0.3, 1.36); c.lineTo(-0.12, 1.86); c.lineTo(-0.42, 1.86); c.closePath(); c.fill();
      g = c.createLinearGradient(0, 1.3, 0, 0.25);
      g.addColorStop(0, main); g.addColorStop(1, dark);
      c.fillStyle = g; rrp(c, -1.18, 0.28, 2.36, 1.0, 0.24); c.fill();
      c.fillStyle = 'rgba(255,255,255,0.25)'; rrp(c, -1.1, 1.14, 2.2, 0.09, 0.04); c.fill();
      c.fillStyle = '#231A5C'; rrp(c, -1.22, 0.2, 2.44, 0.26, 0.1); c.fill();
      c.fillStyle = '#FF3355'; rrp(c, -1.08, 0.78, 0.5, 0.24, 0.08); c.fill(); rrp(c, 0.58, 0.78, 0.5, 0.24, 0.08); c.fill();
      c.fillStyle = '#FFD0D8'; rrp(c, -1.02, 0.86, 0.2, 0.1, 0.04); c.fill(); rrp(c, 0.82, 0.86, 0.2, 0.1, 0.04); c.fill();
      c.fillStyle = '#FFF4F7'; rrp(c, -0.3, 0.58, 0.6, 0.24, 0.05); c.fill();
      c.fillStyle = 'rgba(40,20,110,0.5)'; c.fillRect(-0.2, 0.67, 0.4, 0.06);
    });
  }

  function buildSprites() {
    spritesReady = true;
    spBarrier = sprite(3, 1.95, 0.25, function (c) {
      var i, x;
      c.fillStyle = 'rgba(12,6,48,0.36)'; ell(c, 0, 0, 1.4, 0.2); c.fill();
      c.fillStyle = '#2B1C63';
      c.fillRect(-1.02, 0, 0.17, 0.7); c.fillRect(0.85, 0, 0.17, 0.7);
      rrp(c, -1.26, -0.03, 0.62, 0.13, 0.05); c.fill(); rrp(c, 0.64, -0.03, 0.62, 0.13, 0.05); c.fill();
      c.save(); rrp(c, -1.32, 0.52, 2.64, 0.84, 0.15); c.clip();
      c.fillStyle = '#FFF4F7'; c.fillRect(-1.4, 0.5, 2.8, 0.9);
      c.fillStyle = '#F2385A';
      for (i = -4; i < 5; i++) {
        x = i * 0.66;
        c.beginPath(); c.moveTo(x, 0.5); c.lineTo(x + 0.33, 0.5); c.lineTo(x + 0.75, 1.4); c.lineTo(x + 0.42, 1.4); c.closePath(); c.fill();
      }
      c.fillStyle = 'rgba(50,10,100,0.16)'; c.fillRect(-1.4, 0.5, 2.8, 0.22);
      c.fillStyle = 'rgba(255,255,255,0.35)'; c.fillRect(-1.4, 1.25, 2.8, 0.08);
      c.restore();
      c.lineWidth = 0.06; c.strokeStyle = '#3A1672'; rrp(c, -1.32, 0.52, 2.64, 0.84, 0.15); c.stroke();
      c.fillStyle = 'rgba(255,197,49,0.35)'; ell(c, -0.94, 1.5, 0.24, 0.24); c.fill(); ell(c, 0.94, 1.5, 0.24, 0.24); c.fill();
      c.fillStyle = '#FFD45E'; ell(c, -0.94, 1.48, 0.13, 0.13); c.fill(); ell(c, 0.94, 1.48, 0.13, 0.13); c.fill();
    });
    spCones = sprite(3, 1.7, 0.25, function (c) {
      coneShape(c, 0.05, 0.42, 0.92);
      coneShape(c, -0.72, 0.06, 1.05);
      coneShape(c, 0.7, 0, 1.1);
    });
    spCars = [carSprite('#2FD6C8', '#7DF0E4', '#1C9AA8'), carSprite('#FF6FAE', '#FFA9CF', '#D2408A'), carSprite('#8E7BFF', '#B9ACFF', '#5E49D8')];
    spGem = sprite(1.6, 1.6, 0.8, function (c) {
      var g = c.createRadialGradient(0, 0, 0.1, 0, 0, 0.8);
      g.addColorStop(0, 'rgba(120,230,255,0.55)'); g.addColorStop(1, 'rgba(120,230,255,0)');
      c.fillStyle = g; c.fillRect(-0.8, -0.8, 1.6, 1.6);
      c.fillStyle = '#1D7BFF'; c.beginPath(); c.moveTo(-0.5, 0.12); c.lineTo(0, -0.52); c.lineTo(0.5, 0.12); c.closePath(); c.fill();
      c.fillStyle = '#35B8FF'; c.beginPath(); c.moveTo(-0.2, 0.12); c.lineTo(0, -0.52); c.lineTo(0.2, 0.12); c.closePath(); c.fill();
      c.fillStyle = '#5FD9FF'; c.beginPath(); c.moveTo(-0.5, 0.12); c.lineTo(-0.28, 0.42); c.lineTo(0.28, 0.42); c.lineTo(0.5, 0.12); c.closePath(); c.fill();
      c.fillStyle = '#B5F4FF'; c.beginPath(); c.moveTo(-0.2, 0.12); c.lineTo(-0.1, 0.42); c.lineTo(0.1, 0.42); c.lineTo(0.2, 0.12); c.closePath(); c.fill();
      c.fillStyle = 'rgba(255,255,255,0.85)'; c.beginPath(); c.moveTo(-0.5, 0.12); c.lineTo(-0.28, 0.42); c.lineTo(-0.1, 0.42); c.lineTo(-0.2, 0.12); c.closePath(); c.fill();
      c.lineWidth = 0.045; c.strokeStyle = '#1647B8'; c.lineJoin = 'round';
      c.beginPath(); c.moveTo(-0.5, 0.12); c.lineTo(-0.28, 0.42); c.lineTo(0.28, 0.42); c.lineTo(0.5, 0.12); c.lineTo(0, -0.52); c.closePath(); c.stroke();
    });
    spGlow = mk(96, 96);
    var c = spGlow.getContext('2d'), g = c.createRadialGradient(48, 48, 2, 48, 48, 48);
    g.addColorStop(0, 'rgba(255,244,200,0.95)'); g.addColorStop(0.25, 'rgba(255,214,150,0.45)'); g.addColorStop(1, 'rgba(255,190,150,0)');
    c.fillStyle = g; c.fillRect(0, 0, 96, 96);
  }

  function buildBg() {
    var dpr = D.dpr || 1, i, g, x, y, r = D.makeRng(4242), k = W / 390;
    bg = mk((W + PAD * 2) * dpr, (H + PAD * 2) * dpr);
    var c = bg.getContext('2d');
    c.scale(dpr, dpr); c.translate(PAD, PAD);

    g = c.createLinearGradient(0, 0, 0, HY);
    g.addColorStop(0, '#1A1160'); g.addColorStop(0.26, '#3C1B93'); g.addColorStop(0.52, '#8A2EC0'); g.addColorStop(0.78, '#E0489D'); g.addColorStop(1, '#FF8E7E');
    c.fillStyle = g; c.fillRect(-PAD, -PAD, W + PAD * 2, HY + PAD + 1);

    c.fillStyle = '#fff';
    for (i = 0; i < 90; i++) {
      x = r() * W; y = r() * HY * 0.66;
      c.globalAlpha = (0.3 + r() * 0.65) * (1 - y / (HY * 0.72));
      c.beginPath(); c.arc(x, y, 0.4 + r() * 0.9, 0, TAU); c.fill();
    }
    for (i = 0; i < 7; i++) {
      x = r() * W; y = r() * HY * 0.45; var q = 2.5 + r() * 2.5;
      c.globalAlpha = 0.7;
      c.beginPath(); c.moveTo(x, y - q); c.quadraticCurveTo(x, y, x + q, y); c.quadraticCurveTo(x, y, x, y + q); c.quadraticCurveTo(x, y, x - q, y); c.quadraticCurveTo(x, y, x, y - q); c.fill();
    }
    c.globalAlpha = 1;

    for (i = 0; i < 12; i++) {
      var side = i % 2 ? 1 : -1, cw = (26 + r() * 60) * k;
      x = cx + side * (W * 0.2 + r() * W * 0.3) - cw / 2; y = HY * (0.3 + r() * 0.52);
      c.fillStyle = 'rgba(255,160,205,' + (0.18 + r() * 0.22).toFixed(2) + ')';
      rrp(c, x, y, cw, 2.6 * k, 1.3 * k); c.fill();
      rrp(c, x + cw * 0.25, y + 5 * k, cw * 0.6, 2 * k, 1 * k); c.fill();
    }

    var R = W * 0.2, sx0 = cx, sy0 = HY - R * 0.3;
    g = c.createRadialGradient(sx0, sy0, R * 0.7, sx0, sy0, R * 2.6);
    g.addColorStop(0, 'rgba(255,190,140,0.6)'); g.addColorStop(0.4, 'rgba(255,130,160,0.25)'); g.addColorStop(1, 'rgba(255,120,160,0)');
    c.fillStyle = g; c.fillRect(-PAD, 0, W + PAD * 2, HY);
    c.strokeStyle = 'rgba(255,150,180,0.3)'; c.lineWidth = R * 0.09;
    c.beginPath(); c.arc(sx0, sy0, R * 1.36, PI * 0.95, TAU + PI * 0.05); c.stroke();
    c.strokeStyle = 'rgba(255,170,200,0.16)'; c.lineWidth = R * 0.05;
    c.beginPath(); c.arc(sx0, sy0, R * 1.62, PI * 0.95, TAU + PI * 0.05); c.stroke();
    c.save(); c.beginPath(); c.arc(sx0, sy0, R, 0, TAU); c.clip();
    g = c.createLinearGradient(0, sy0 - R, 0, sy0 + R * 0.35);
    g.addColorStop(0, '#FFF67E'); g.addColorStop(0.5, '#FFCC5C'); g.addColorStop(1, '#FF6FA8');
    c.fillStyle = g; c.fillRect(sx0 - R, sy0 - R, R * 2, R * 2);
    c.fillStyle = 'rgba(232,80,160,0.9)';
    for (i = 0; i < 6; i++) c.fillRect(sx0 - R, sy0 - R * 0.42 + i * R * 0.135, R * 2, (1.2 + i * 1.15) * k);
    c.restore();

    var back = [], front = [], bx, bw, bh, cen;
    for (bx = -4; bx < W + 4;) {
      bw = (10 + r() * 16) * k; cen = Math.abs(bx + bw / 2 - cx) < W * 0.11 ? 0.55 : 1;
      back.push(bx, bw, (16 + r() * 26) * k * cen); bx += bw + r() * 2 * k;
    }
    for (bx = -6; bx < W + 4;) {
      bw = (11 + r() * 15) * k; cen = Math.abs(bx + bw / 2 - cx) < W * 0.1 ? 0.5 : 1;
      bh = (9 + r() * 26) * k * cen;
      front.push(bx, bw, bh, r()); bx += bw + (r() < 0.25 ? 3 * k : 0.5);
    }
    function city(reflect) {
      var j, wx, wy, rr2 = D.makeRng(99);
      c.fillStyle = reflect ? '#7A3BC8' : '#9A4AD6';
      for (j = 0; j < back.length; j += 3) c.fillRect(back[j], HY - back[j + 2], back[j + 1], back[j + 2] + 1);
      var fx = W * 0.19, fr = W * 0.062, fy = HY - W * 0.088;
      c.strokeStyle = '#4A1FA0'; c.lineWidth = 1.5 * k;
      c.beginPath(); c.arc(fx, fy, fr, 0, TAU); c.stroke();
      c.lineWidth = 0.9 * k; c.beginPath(); c.arc(fx, fy, fr * 0.72, 0, TAU);
      for (j = 0; j < 10; j++) { c.moveTo(fx, fy); c.lineTo(fx + Math.cos(j * TAU / 10) * fr, fy + Math.sin(j * TAU / 10) * fr); }
      c.moveTo(fx, fy); c.lineTo(fx - fr * 0.55, HY); c.moveTo(fx, fy); c.lineTo(fx + fr * 0.55, HY); c.stroke();
      for (j = 0; j < 10; j++) {
        c.fillStyle = ['#FFD36B', '#FF8FD0', '#7DE8FF'][j % 3];
        c.beginPath(); c.arc(fx + Math.cos(j * TAU / 10) * fr, fy + Math.sin(j * TAU / 10) * fr, 1.7 * k, 0, TAU); c.fill();
      }
      var tx = W * 0.795, th = W * 0.19;
      c.fillStyle = '#4A1FA0';
      c.beginPath(); c.moveTo(tx - 3.2 * k, HY); c.lineTo(tx - 1 * k, HY - th * 0.7); c.lineTo(tx + 1 * k, HY - th * 0.7); c.lineTo(tx + 3.2 * k, HY); c.closePath(); c.fill();
      c.fillRect(tx - 0.6 * k, HY - th, 1.2 * k, th * 0.35);
      ell(c, tx, HY - th * 0.7, 8 * k, 2.6 * k); c.fill();
      c.fillRect(tx - 4.5 * k, HY - th * 0.78, 9 * k, 3 * k);
      c.fillStyle = '#FFD36B'; c.fillRect(tx - 6 * k, HY - th * 0.71, 12 * k, 1 * k);
      c.fillStyle = '#FF5577'; c.beginPath(); c.arc(tx, HY - th, 1.5 * k, 0, TAU); c.fill();
      for (j = 0; j < front.length; j += 4) {
        c.fillStyle = front[j + 3] < 0.5 ? '#5A29B8' : '#4F22AC';
        c.fillRect(front[j], HY - front[j + 2], front[j + 1], front[j + 2] + 1);
        if (front[j + 3] < 0.3) c.fillRect(front[j] + front[j + 1] * 0.3, HY - front[j + 2] - 3 * k, front[j + 1] * 0.4, 3 * k);
        for (wy = HY - front[j + 2] + 3 * k; wy < HY - 3 * k; wy += 4.2 * k) {
          for (wx = front[j] + 2 * k; wx < front[j] + front[j + 1] - 2.5 * k; wx += 3.6 * k) {
            if (rr2() < 0.52) { c.fillStyle = rr2() < 0.7 ? '#FFD36B' : '#FF9AD4'; c.fillRect(wx, wy, 1.7 * k, 2 * k); }
          }
        }
      }
    }
    city(false);

    g = c.createLinearGradient(0, HY, 0, H);
    g.addColorStop(0, '#F28FCB'); g.addColorStop(0.05, '#C56FDB'); g.addColorStop(0.22, '#7C5FE6'); g.addColorStop(0.6, '#4A76EA'); g.addColorStop(1, '#2F9AE8');
    c.fillStyle = g; c.fillRect(-PAD, HY, W + PAD * 2, H - HY + PAD);
    c.save(); c.beginPath(); c.rect(-PAD, HY, W + PAD * 2, H); c.clip();
    c.translate(0, HY); c.scale(1, -0.8); c.translate(0, -HY);
    c.globalAlpha = 0.3; city(true);
    c.restore(); c.globalAlpha = 1;
    c.save(); c.translate(cx, HY); c.scale(1, 0.3);
    g = c.createRadialGradient(0, 0, 0, 0, 0, W * 0.62);
    g.addColorStop(0, 'rgba(255,226,150,0.75)'); g.addColorStop(0.4, 'rgba(255,150,180,0.35)'); g.addColorStop(1, 'rgba(255,150,180,0)');
    c.fillStyle = g; c.fillRect(-W, 0, W * 2, W * 0.62);
    c.restore();
    for (i = 0; i < 70; i++) {
      var f = r() * r(); y = HY + 6 + f * (H - HY) * 0.9; x = r() * W; bw = (6 + r() * 20) * (0.5 + f * 2) * k;
      c.fillStyle = 'rgba(255,255,255,' + (0.05 + r() * 0.13).toFixed(2) + ')';
      rrp(c, x - bw / 2, y, bw, 1 + f * 1.6, 1); c.fill();
    }
    g = c.createLinearGradient(0, HY - 12 * k, 0, HY + 30 * k);
    g.addColorStop(0, 'rgba(255,200,225,0)'); g.addColorStop(0.3, 'rgba(255,200,225,0.5)'); g.addColorStop(1, 'rgba(255,200,225,0)');
    c.fillStyle = g; c.fillRect(-PAD, HY - 12 * k, W + PAD * 2, 42 * k);
  }

  function layout() {
    if (D.W === W && D.H === H && D.dpr === builtDpr) return;
    builtDpr = D.dpr;
    W = D.W; H = D.H; cx = W / 2;
    HY = Math.round(H * 0.345);
    kartY = HY + H * 0.262;
    SK = W * 0.48 / 3 / LW;
    F = SK * DK;
    camH = (kartY - HY) / SK;
    var ctx = D.ctx;
    roadGrad = ctx.createLinearGradient(0, HY, 0, H);
    roadGrad.addColorStop(0, '#7A55D6'); roadGrad.addColorStop(0.1, '#5136B4'); roadGrad.addColorStop(0.35, '#38249A'); roadGrad.addColorStop(0.7, '#2C1E80'); roadGrad.addColorStop(1, '#231A6C');
    walkGrad = ctx.createLinearGradient(0, HY, 0, H);
    walkGrad.addColorStop(0, '#C79BF0'); walkGrad.addColorStop(0.3, '#8C6CEA'); walkGrad.addColorStop(1, '#6A55D8');
    hazeGrad = ctx.createLinearGradient(0, HY, 0, HY + H * 0.09);
    hazeGrad.addColorStop(0, 'rgba(255,196,224,0.75)'); hazeGrad.addColorStop(1, 'rgba(255,196,224,0)');
    noseGrad = ctx.createLinearGradient(0, -92, 0, -36);
    noseGrad.addColorStop(0, '#FFE873'); noseGrad.addColorStop(1, '#FFB52E');
    bodyGrad = ctx.createLinearGradient(0, -44, 0, -6);
    bodyGrad.addColorStop(0, '#FF5C7C'); bodyGrad.addColorStop(1, '#D42658');
    if (!spritesReady) buildSprites();
    buildBg();
  }

  function put(o) {
    var i = items.length;
    items.push(o);
    while (i > 0 && items[i - 1].z > o.z) { items[i] = items[i - 1]; i--; }
    items[i] = o;
    return o;
  }
  function add(t, lane, z, y) {
    return put({ t: t, lane: lane, x: (lane - 1) * LW, z: z, y: y || 0, done: false, armed: false, gone: false, react: -1, v: t === CAR ? D.randInt(0, 2) : 0, ph: 0 });
  }
  function gemLine(lane, z, n, step) { for (var i = 0; i < n; i++) add(GEM, lane, z + i * step, 0); }
  function lowType() { return D.rand() < 0.55 ? BARRIER : CONES; }
  function hazType(diff, car) { var r = D.rand(); return r < 0.4 ? BARRIER : r < 0.72 || !car || diff < 0.04 ? CONES : CAR; }
  function carExtra(v) { return 80 * CAR_V / (v - CAR_V) + 3; }
  function far(f) { return (f === 0 && (lastFree & 4)) || (f === 2 && (lastFree & 1)); }

  function gen() {
    var z = genZ, v = speedAt(z), diff = clamp(z / 4200, 0, 1);
    var gap = v * lerp(1.3, 0.64, diff);
    var w0 = 3, w1 = 0.5 + 2.4 * diff, w2 = lastPat === 2 ? 0 : 1.35, w3 = 0.3 + 1.3 * diff, w4 = lastPat === 4 ? 0 : 0.9 - 0.5 * diff, w5 = diff > 0.06 ? 0.8 : 0;
    var r = D.rand() * (w0 + w1 + w2 + w3 + w4 + w5), pat, i, a, b, f, t, extra = 0;
    pat = r < w0 ? 0 : (r -= w0) < w1 ? 1 : (r -= w1) < w2 ? 2 : (r -= w2) < w3 ? 3 : (r -= w3) < w4 ? 4 : 5;
    lastPat = pat;
    if (pat === 0) {
      b = D.randInt(0, 2); t = hazType(diff, true);
      add(t, b, z);
      if (D.rand() < 0.65) gemLine((b + 1 + D.randInt(0, 1)) % 3, z - 6, 4 + D.randInt(0, 2), 3.6);
      genZ = z + gap + (t === CAR ? carExtra(v) : 0);
      lastFree = 7 & ~(1 << b);
    } else if (pat === 1) {
      f = D.randInt(0, 2);
      if (far(f) && diff < 0.75) z += gap * 0.35;
      for (i = 0; i < 3; i++) {
        if (i === f) continue;
        t = hazType(diff, !extra);
        if (t === CAR) extra = carExtra(v);
        add(t, i, z);
      }
      if (D.rand() < 0.55) gemLine(f, z - 4, 4, 3.6);
      genZ = z + gap * 1.05 + extra;
      lastFree = 1 << f;
    } else if (pat === 2) {
      a = D.randInt(0, 2);
      var vb = v * BOOST, jl = vb * AIR_T;
      add(RAMP, a, z);
      for (i = 0; i < 5; i++) { t = 0.14 + i * 0.155; add(GEM, a, z - 0.4 + vb * t, JUMP_V * t - GRAV * t * t / 2); }
      if (D.rand() < 0.85) add(lowType(), a, z + jl * 0.5);
      if (diff > 0.2 && D.rand() < 0.5) add(lowType(), (a + 1 + D.randInt(0, 1)) % 3, z + jl * (0.38 + D.rand() * 0.24));
      if (D.rand() < 0.6) gemLine(a, z - 15, 3, 3.6);
      genZ = z + jl * 1.12 + gap * 0.85;
      lastFree = 7;
    } else if (pat === 3) {
      var n = 3 + (diff > 0.5 ? 1 : 0), p = D.randInt(0, 2), sp = gap * 0.82, both = diff > 0.3, prev = -1;
      if (far(p)) z += gap * 0.3;
      for (i = 0; i < n; i++) {
        var zz = z + i * sp;
        if (both) { for (b = 0; b < 3; b++) if (b !== p) add(lowType(), b, zz); }
        else add(lowType(), prev >= 0 ? prev : (p + 1 + D.randInt(0, 1)) % 3, zz);
        add(GEM, p, zz - 2, 0); add(GEM, p, zz + 2, 0);
        prev = p;
        if (i < n - 1) p = p === 1 ? D.randInt(0, 1) * 2 : 1;
      }
      genZ = z + (n - 1) * sp + gap;
      lastFree = both ? 1 << p : 7 & ~(1 << (n > 1 ? (p === prev ? 3 : prev) : 3));
      if (!both) lastFree = 7;
    } else if (pat === 4) {
      a = D.randInt(0, 2); b = a === 1 ? D.randInt(0, 1) * 2 : 1;
      for (i = 0; i < 6; i++) add(GEM, i < 3 ? a : b, z + i * 4, 0);
      genZ = z + 24 + gap * 0.5;
    } else {
      a = D.randInt(0, 2); b = (a + 1 + D.randInt(0, 1)) % 3; f = 3 - a - b;
      if (far(f) && diff < 0.75) z += gap * 0.35;
      add(CAR, a, z); add(CAR, b, z + gap * 0.55);
      gemLine(f, z - 2, 5, 4);
      genZ = z + gap * 1.55 + carExtra(v);
      lastFree = 1 << f;
    }
  }

  function spawn(x, y, vx, vy, life, size, col, g, kind) {
    var p = parts[partI]; partI = (partI + 1) % PART_N;
    p.x = x; p.y = y; p.vx = vx; p.vy = vy; p.life = life; p.max = life; p.size = size; p.col = col; p.g = g; p.kind = kind || 0;
    p.rot = Math.random() * TAU; p.vr = (Math.random() - 0.5) * 16;
  }
  function pop(txt, x, y, col, size) {
    var p = pops[popI]; popI = (popI + 1) % POP_N;
    p.txt = txt; p.x = x; p.y = y; p.t = 0; p.life = size > 20 ? 1.1 : 0.7; p.col = col; p.size = size;
  }

  function steer(dir) {
    if (over) return;
    var nl = kart.lane + dir, i, o, dz;
    if (nl < 0 || nl > 2) { kart.bump = dir; return; }
    if (!kart.air) {
      var win = Math.max(7, speed * 0.38);
      for (i = 0; i < items.length; i++) {
        o = items[i];
        if (o.t > CAR || o.done || o.lane !== kart.lane) continue;
        dz = o.z - kart.z;
        if (dz > 0.5 && dz < win) o.armed = true;
      }
      for (i = 0; i < 4; i++) spawn(ksx - dir * ks * 1.2 + (Math.random() - 0.5) * ks, ksy - ks * 0.2, -dir * (30 + Math.random() * 50), -10 - Math.random() * 30, 0.35, 3 + Math.random() * 3, 'rgba(210,190,255,0.5)', 0, 0);
    }
    kart.lane = nl; kart.sqT = 0; kart.sqA = 0.28;
    D.haptic('light');
    D.tone({ freq: 480, slide: 720, dur: 0.07, type: 'triangle', vol: 0.05 });
  }

  function collect(o) {
    o.done = true;
    gems += 1; gemPulse = 1;
    gemChain = gemChainT > 0 ? Math.min(gemChain + 1, 8) : 0; gemChainT = 0.6;
    if (time - lastGemHaptic > 0.09) { lastGemHaptic = time; D.haptic('select'); }
    D.tone({ freq: 880 * Math.pow(1.06, gemChain), dur: 0.09, type: 'sine', vol: 0.07 });
    var gy = ksy - (o.y + 0.9) * ks, i;
    pop('+1', ksx + ks * 1.4, gy - 6, '#9BEAFF', 17);
    for (i = 0; i < 5; i++) spawn(ksx + (Math.random() - 0.5) * ks, gy, (Math.random() - 0.5) * 160, -40 - Math.random() * 120, 0.4, 2 + Math.random() * 2.5, i % 2 ? '#BDF4FF' : '#4FC3FF', 300, 0);
  }

  function nearMiss(o) {
    var bonus = Math.round(50 * mult), i, side = o.x > kart.x ? 1 : -1;
    score += bonus; nears += 1;
    mult = Math.min(5, mult + 0.5); multHold = 3; multPulse = 1;
    D.haptic('success');
    D.tone({ freq: 660, slide: 1320, dur: 0.16, type: 'square', vol: 0.05 });
    pop('NEAR MISS +' + bonus, clamp(ksx, 110, W - 110), ksy - ks * 5.2, '#FFE45C', 24);
    for (i = 0; i < 14; i++) spawn(ksx + side * ks * 1.7, ksy - ks * (0.2 + Math.random() * 1.4), side * (10 + Math.random() * 150), -40 - Math.random() * 240, 0.35 + Math.random() * 0.25, 2 + Math.random() * 2, i % 3 ? '#FFE45C' : '#FFFFFF', 500, 2);
    shake = Math.max(shake, 4);
  }

  function crash(o) {
    var i, cols = o.t === BARRIER ? ['#F2385A', '#FFF4F7', '#2B1C63'] : o.t === CONES ? ['#FF7426', '#FFF4EC', '#FFA347'] : ['#FFD84A', '#F2385A', '#DDE6FF'];
    over = true; crashT = 0; errAt = 0.22;
    kart.spinV = (kart.x >= o.x ? 1 : -1) * (12 + Math.random() * 4);
    kart.vy = 10; kart.air = true; kart.y = Math.max(kart.y, 0.01);
    kartV = speed * (o.t === CAR ? 0.3 : 0.9);
    if (o.t === CAR) { hitCar = o; carPush = speed * 0.5; } else o.gone = true;
    shake = 18; flash = 1; boostT = 0;
    for (i = 0; i < 26; i++) spawn(ksx + (Math.random() - 0.5) * ks * 2.4, ksy - ks * (0.4 + Math.random() * 1.6), (Math.random() - 0.5) * 520, -120 - Math.random() * 420, 0.7 + Math.random() * 0.6, 4 + Math.random() * 7, cols[i % 3], 900, 1);
    for (i = 0; i < 12; i++) spawn(ksx, ksy - ks, (Math.random() - 0.5) * 420, -80 - Math.random() * 300, 0.4 + Math.random() * 0.3, 2 + Math.random() * 2, i % 2 ? '#FFE45C' : '#FFFFFF', 500, 2);
    for (i = 0; i < 8; i++) spawn(ksx + (Math.random() - 0.5) * ks * 2, ksy - ks * Math.random(), (Math.random() - 0.5) * 120, -30 - Math.random() * 60, 0.9, 10 + Math.random() * 10, 'rgba(220,200,255,0.35)', -40, 0);
    D.haptic('heavy');
    D.tone({ freq: 180, slide: 50, dur: 0.4, type: 'sawtooth', vol: 0.12 });
    var s = Math.floor(score), head = o.t === BARRIER ? 'Stopped by a barrier' : o.t === CONES ? 'Clipped the cones' : 'Rear-ended traffic';
    if (D.best > 0 && s > D.best) head = 'New personal best';
    else if (nears >= 6) head = nears + ' near misses';
    D.end({ score: s, unit: 'm', headline: head });
  }

  function resetRound(seed) {
    layout();
    var i;
    items.length = 0; lastFree = 7; lastPat = -1;
    kart.lane = 1; kart.x = 0; kart.z = 0; kart.y = 0; kart.vy = 0; kart.vx = 0; kart.air = false; kart.lean = 0;
    kart.sqT = 9; kart.sqA = 0; kart.spin = 0; kart.spinV = 0; kart.bump = 0; kart.roll = 0;
    camZ = -DK; camX = 0; kartV = 0; hitCar = null; carPush = 0;
    speed = 0; score = 0; gems = 0; nears = 0; mult = 1; multHold = 0; multPulse = 0; gemPulse = 0;
    tPlay = 0; boostT = 0; over = false; crashT = 0; errAt = -1; shake = 0; flash = 0; gemChain = 0; gemChainT = 0;
    for (i = 0; i < TRAIL_N; i++) { trail[i].x = 0; trail[i].z = -(TRAIL_N - 1 - i); trail[i].on = true; trail[i].hw = 0.26; }
    trailHead = 0; trailZ = 0;
    for (i = 0; i < PART_N; i++) parts[i].life = 0;
    for (i = 0; i < POP_N; i++) pops[i].t = 9;
    ptr.id = -1;
    gemLine(1, 22, 5, 4);
    gemLine(D.randInt(0, 1) * 2, 52, 5, 4);
    genZ = 118;
    while (genZ < 300) gen();
    botRng = D.makeRng((seed | 0) * 31 + 17);
    botCool = 0.6; botQueue = 0; botQT = 0;
    failAt = 26 + botRng() * 7;
  }

  function land() {
    kart.y = 0; kart.vy = 0; kart.air = false; kart.sqT = 0; kart.sqA = 1;
    shake = Math.max(shake, 5);
    D.haptic('medium');
    D.tone({ freq: 140, slide: 70, dur: 0.14, type: 'triangle', vol: 0.1 });
    for (var i = 0; i < 10; i++) spawn(ksx + (Math.random() - 0.5) * ks * 3, ksy, (Math.random() - 0.5) * 240, -20 - Math.random() * 70, 0.45, 5 + Math.random() * 6, 'rgba(215,195,255,0.45)', 0, 0);
  }

  function update(dt, state) {
    var i, o, p, dz, dx;
    time += dt;
    shake *= Math.exp(-dt * 9); flash = Math.max(0, flash - dt * 5);
    multPulse = Math.max(0, multPulse - dt * 3); gemPulse = Math.max(0, gemPulse - dt * 5);
    gemChainT -= dt;
    kart.sqT += dt; kart.bump *= Math.exp(-dt * 12);

    for (i = 0; i < PART_N; i++) {
      p = parts[i];
      if (p.life <= 0) continue;
      p.life -= dt; p.vy += p.g * dt; p.x += p.vx * dt; p.y += p.vy * dt; p.rot += p.vr * dt;
      if (p.kind === 0) { p.vx *= 1 - dt * 2.5; p.vy *= 1 - dt * 2.5; }
    }
    for (i = 0; i < POP_N; i++) if (pops[i].t < pops[i].life) pops[i].t += dt;
    for (i = 0; i < lines.length; i++) {
      p = lines[i]; p.p += dt * p.sp * 1.6;
      if (p.p > 1) { p.p = 0; p.a = (0.04 + Math.random() * 0.24) * PI; p.sp = 0.9 + Math.random() * 0.9; }
    }

    if (state === 'playing' && !over) {
      tPlay += dt;
      boostT = Math.max(0, boostT - dt);
      speed = speedAt(kart.z) * (0.3 + 0.7 * D.easeOut(Math.min(1, tPlay / 0.9))) * (1 + (BOOST - 1) * clamp(boostT / 0.7, 0, 1));
      kart.z += speed * dt;
      camZ = kart.z - DK;
      if (multHold > 0) multHold -= dt; else mult = Math.max(1, mult - dt * 0.4);
      score += speed * dt * mult;
      D.score(Math.floor(score));

      if (kart.air) {
        kart.vy -= GRAV * dt; kart.y += kart.vy * dt;
        if (kart.y <= 0) land();
      } else if (Math.random() < dt * 14) {
        spawn(ksx + (Math.random() < 0.5 ? -1 : 1) * ks * 1.3, ksy, (Math.random() - 0.5) * 20, 40 + Math.random() * 40, 0.3, 2 + Math.random() * 3, 'rgba(210,190,255,0.3)', 0, 0);
      }

      while (genZ < kart.z + 300) gen();
      while (items.length && items[0].z < camZ + 3) items.shift();

      for (i = 0; i < items.length; i++) {
        o = items[i];
        dz = o.z - kart.z;
        if (o.t === CAR && dz < 80) {
          o.z += CAR_V * dt; dz = o.z - kart.z;
          if (i + 1 < items.length && items[i + 1].z < o.z) { items[i] = items[i + 1]; items[i + 1] = o; continue; }
        }
        if (o.done || dz > 4) continue;
        dx = o.x - kart.x; if (dx < 0) dx = -dx;
        if (o.t === GEM) {
          if (dz < -2.5) o.done = true;
          else if (dz < 1.7 && dx < 1.8 && Math.abs(o.y - kart.y) < 1.9) collect(o);
        } else if (o.t === RAMP) {
          if (dz < -2.2) o.done = true;
          else if (!kart.air && dz < 1.2 && dx < 1.7) {
            o.done = true; kart.air = true; kart.vy = JUMP_V; kart.y = 0.01; boostT = AIR_T + 0.7; kart.sqT = 0; kart.sqA = -0.6;
            D.haptic('light');
            D.tone({ freq: 300, slide: 900, dur: 0.25, type: 'sawtooth', vol: 0.06 });
            pop('BOOST', clamp(ksx, 60, W - 60), ksy - ks * 4.5, '#7DF3FF', 22);
          }
        } else if (dz < -1.5) {
          o.done = true;
          if (o.armed && !kart.air) nearMiss(o);
        } else if (dz < (o.t === CAR ? 1.7 : 1.3) && dx < 1.72 && kart.y < CLEAR_H[o.t]) {
          crash(o);
          break;
        }
      }
    } else if (over) {
      crashT += dt;
      if (errAt >= 0 && crashT >= errAt) { errAt = -1; D.haptic('error'); }
      kartV *= Math.exp(-dt * 2.6); carPush *= Math.exp(-dt * 2.2);
      kart.z += kartV * dt;
      p = camZ; camZ += (kart.z - 10.5 - camZ) * (1 - Math.exp(-dt * 2.5));
      speed = (camZ - p) / dt;
      for (i = 0; i < items.length; i++) {
        o = items[i];
        if (o.t === CAR && o.z - kart.z < 80) o.z += (CAR_V + (o === hitCar ? carPush : 0)) * dt;
      }
      kart.vy -= GRAV * dt; kart.y += kart.vy * dt;
      if (kart.y <= 0) {
        kart.y = 0;
        if (kart.vy < -4) { kart.vy *= -0.45; kart.spinV *= 0.55; shake = Math.max(shake, 6); for (i = 0; i < 6; i++) spawn(ksx + (Math.random() - 0.5) * ks * 3, ksy, (Math.random() - 0.5) * 200, -20 - Math.random() * 60, 0.5, 5 + Math.random() * 6, 'rgba(215,195,255,0.45)', 0, 0); }
        else { kart.vy = 0; kart.spinV *= Math.exp(-dt * 6); }
      }
      kart.spin += kart.spinV * dt;
      if (crashT > 0.5 && Math.random() < dt * 9) spawn(ksx + (Math.random() - 0.5) * ks, ksy - ks * 1.5, (Math.random() - 0.5) * 20, -30 - Math.random() * 30, 1.2, 6 + Math.random() * 8, 'rgba(200,185,240,0.3)', -20, 0);
    } else {
      speed = 0;
    }

    var tx = (kart.lane - 1) * LW, px = kart.x;
    if (!over) kart.x += (tx - kart.x) * (1 - Math.exp(-dt * 16));
    kart.vx = (kart.x - px) / dt;
    kart.lean += (clamp(kart.vx * 0.014, -0.34, 0.34) - kart.lean) * (1 - Math.exp(-dt * 20));
    kart.roll += speed * dt;
    camX += (kart.x * 0.22 - camX) * (1 - Math.exp(-dt * 8));

    if (!over && state !== 'ready' && kart.z - trailZ >= 1) {
      trailZ = kart.z;
      p = trail[trailHead]; trailHead = (trailHead + 1) % TRAIL_N;
      p.x = kart.x; p.z = kart.z; p.on = !kart.air; p.hw = trailHw();
    }

    ks = F / (kart.z - camZ);
    ksx = cx + (kart.x - camX) * ks; ksy = HY + camH * ks;
  }

  function botStep(dir) { steer(dir); botCool = 0.3; }

  function bot(dt) {
    if (over) return;
    botCool -= dt;
    if (botQueue) { botQT -= dt; if (botQT <= 0) { steer(botQueue); botQueue = 0; } return; }
    var v = Math.max(speed, 8), kz = kart.z, i, o, dz, l, flyTo = kz - 9;
    if (kart.air) flyTo = kz + v * (kart.vy + Math.sqrt(kart.vy * kart.vy + 2 * GRAV * kart.y)) / GRAV - 3;
    for (l = 0; l < 3; l++) { clr[l] = 999; hz[l] = null; gemD[l] = 999; rampD[l] = 999; }
    for (i = 0; i < items.length; i++) {
      o = items[i];
      if (o.t === RAMP && !o.done && o.z > kz && o.z - kz < rampD[o.lane]) rampD[o.lane] = o.z - kz;
    }
    var jl = v * BOOST * AIR_T * 0.9;
    for (i = 0; i < items.length; i++) {
      o = items[i]; dz = o.z - kz;
      if (o.done || dz < -1.4 || dz > 150 || o.t === RAMP) continue;
      l = o.lane;
      if (o.t === GEM) { if (o.y < 0.5 && dz > 4 && dz < gemD[l]) gemD[l] = dz; continue; }
      if (o.t !== CAR && o.z < flyTo) continue;
      if (o.t !== CAR && rampD[l] < dz && dz < rampD[l] + jl) continue;
      if (dz < clr[l]) { clr[l] = dz; hz[l] = o; }
    }
    var cur = kart.lane, h = hz[cur], failing = tPlay > failAt, margin = v * 0.45, c, best = -1, bestV = -1;
    if (h && clr[cur] < v * 1.5) {
      if (h.react < 0) h.react = botRng() < 0.55 ? 0.17 + botRng() * 0.1 : 0.5 + botRng() * 0.4;
      var react = failing ? 0.03 : h.react, two = 0;
      for (c = cur - 1; c <= cur + 1; c += 2) {
        if (c < 0 || c > 2) continue;
        if (clr[c] > clr[cur] + margin && clr[c] > bestV + (gemD[c] < 40 ? -6 : 0)) { best = c; bestV = clr[c]; }
      }
      if (best < 0 && cur !== 1 && clr[2 - cur] > clr[cur] + margin) {
        if (clr[1] < v * 0.24 + 3.5) return;
        best = 1; two = cur === 0 ? 1 : -1; react = failing ? react : Math.max(react, 0.85);
      }
      if (best < 0) {
        for (c = cur - 1; c <= cur + 1; c += 2) if (c >= 0 && c <= 2 && clr[c] > clr[cur] + 4 && clr[c] > v * 0.2 + 4 && clr[c] > bestV) { best = c; bestV = clr[c]; }
        react = failing ? react : Math.max(react, 0.5);
      }
      if (best >= 0 && clr[cur] < v * react) {
        botStep(best - cur);
        if (two) { botQueue = two; botQT = 0.1; }
      }
      return;
    }
    if (botCool > 0) return;
    if (failing && tPlay > failAt + 2) {
      for (c = cur - 1; c <= cur + 1; c += 2) if (c >= 0 && c <= 2 && clr[c] < 70 && clr[c] > 18) { botStep(c - cur); botCool = 2; return; }
    }
    if (Math.min(gemD[cur], rampD[cur]) < 50) return;
    for (c = cur - 1; c <= cur + 1; c += 2) {
      if (c < 0 || c > 2) continue;
      var want = Math.min(gemD[c], rampD[c]);
      if (want < 55 && want > 5 && clr[c] > Math.max(v * 0.9, want + v * 0.35) && (best < 0 || want < bestV)) { best = c; bestV = want; }
    }
    if (best >= 0) { botStep(best - cur); botCool = 0.4 + botRng() * 0.4; return; }
    if (failing || kart.air) return;
    for (c = cur - 1; c <= cur + 1; c += 2) {
      if (c < 0 || c > 2) continue;
      h = hz[c];
      if (!h || h.ph || clr[c] > v * 2.2) continue;
      h.ph = 1;
      if (clr[c] > v * 0.9 && clr[cur] > clr[c] + margin * 1.5 && botRng() < 0.6) {
        h.react = 0.17 + botRng() * 0.1;
        botStep(c - cur);
        return;
      }
    }
  }

  function drawRoad(ctx) {
    var s0 = F / (DK * 0.36), y0 = HY + camH * s0, i, z, za, zb, sa, sb, ya, yb, sg, x, k;
    var c0 = cx - camX * s0;
    ctx.fillStyle = walkGrad;
    ctx.beginPath(); ctx.moveTo(cx, HY); ctx.lineTo(c0 - WALK * s0, y0); ctx.lineTo(c0 + WALK * s0, y0); ctx.closePath(); ctx.fill();
    ctx.fillStyle = '#F6EEFF';
    ctx.beginPath(); ctx.moveTo(cx, HY); ctx.lineTo(c0 - KERB * s0, y0); ctx.lineTo(c0 + KERB * s0, y0); ctx.closePath(); ctx.fill();
    ctx.fillStyle = roadGrad;
    ctx.beginPath(); ctx.moveTo(cx, HY); ctx.lineTo(c0 - ROAD * s0, y0); ctx.lineTo(c0 + ROAD * s0, y0); ctx.closePath(); ctx.fill();

    ctx.fillStyle = '#F2385A';
    ctx.beginPath();
    k = Math.floor((camZ + 4) / 10);
    for (i = 0; i < 17; i++) {
      za = (k + i) * 10 - camZ; zb = za + 5; if (za < 4.2) za = 4.2; if (zb <= za) continue;
      sa = F / za; sb = F / zb; ya = HY + camH * sa; yb = HY + camH * sb;
      for (sg = -1; sg <= 1; sg += 2) {
        ctx.moveTo(cx + (sg * ROAD - camX) * sa, ya); ctx.lineTo(cx + (sg * KERB - camX) * sa, ya);
        ctx.lineTo(cx + (sg * KERB - camX) * sb, yb); ctx.lineTo(cx + (sg * ROAD - camX) * sb, yb); ctx.closePath();
      }
    }
    ctx.fill();
    ctx.fillStyle = 'rgba(242,120,160,0.55)';
    sa = F / ((k + 17) * 10 - camZ); ya = HY + camH * sa;
    for (sg = -1; sg <= 1; sg += 2) {
      ctx.beginPath(); ctx.moveTo(cx, HY); ctx.lineTo(cx + (sg * ROAD - camX) * sa, ya); ctx.lineTo(cx + (sg * KERB - camX) * sa, ya); ctx.closePath(); ctx.fill();
    }

    ctx.fillStyle = 'rgba(255,255,255,0.92)';
    ctx.beginPath();
    k = Math.floor((camZ + 4) / 11);
    for (i = 0; i < 17; i++) {
      za = (k + i) * 11 - camZ; zb = za + 4.6; if (za < 4.2) za = 4.2; if (zb <= za) continue;
      sa = F / za; sb = F / zb; ya = HY + camH * sa; yb = HY + camH * sb;
      for (sg = -1; sg <= 1; sg += 2) {
        x = sg * 1.5 - camX;
        var wa = Math.max(0.1 * sa, 0.5), wb = Math.max(0.1 * sb, 0.5);
        ctx.moveTo(cx + x * sa - wa, ya); ctx.lineTo(cx + x * sa + wa, ya); ctx.lineTo(cx + x * sb + wb, yb); ctx.lineTo(cx + x * sb - wb, yb); ctx.closePath();
      }
    }
    ctx.fill();

    ctx.fillStyle = 'rgba(215,190,255,0.85)';
    ctx.beginPath();
    for (sg = -1; sg <= 1; sg += 2) {
      x = cx + (sg * WALK - camX) * s0;
      ctx.moveTo(cx, HY); ctx.lineTo(x, HY + (camH - 1.05) * s0); ctx.lineTo(x, HY + (camH - 0.93) * s0); ctx.closePath();
      ctx.moveTo(cx, HY); ctx.lineTo(x, HY + (camH - 0.56) * s0); ctx.lineTo(x, HY + (camH - 0.47) * s0); ctx.closePath();
    }
    k = Math.floor((camZ + 4) / 4);
    for (i = 0; i < 20; i++) {
      za = (k + i) * 4 - camZ; if (za < 4.4) continue;
      sa = F / za; ya = HY + camH * sa;
      for (sg = -1; sg <= 1; sg += 2) {
        x = cx + (sg * WALK - camX) * sa;
        ctx.rect(x - 0.06 * sa, ya - 1.05 * sa, 0.12 * sa, 1.05 * sa);
      }
    }
    ctx.fill();

    ctx.fillStyle = hazeGrad;
    ctx.beginPath(); ctx.moveTo(cx, HY); ctx.lineTo(cx - W * 0.14, HY + H * 0.09); ctx.lineTo(cx + W * 0.14, HY + H * 0.09); ctx.closePath(); ctx.fill();
  }

  function trailHw() {
    var s = kart.vx / Math.max(speed, 6);
    return 0.26 * Math.min(2.4, Math.sqrt(1 + s * s));
  }

  function drawTrail(ctx) {
    var i, a, b, sa, sb, ya, yb, sg, hw, hb, n = 0;
    ctx.fillStyle = 'rgba(255,62,104,0.5)';
    ctx.beginPath();
    for (i = 0; i < TRAIL_N; i++) {
      a = trail[(trailHead + i) % TRAIL_N];
      b = i === TRAIL_N - 1 ? kart : trail[(trailHead + i + 1) % TRAIL_N];
      if (!a.on || (b !== kart && !b.on) || (b === kart && kart.y > 0.05)) continue;
      if (a.z - camZ < 4 || b.z <= a.z) continue;
      sa = F / (a.z - camZ); sb = F / (b.z - camZ); ya = HY + camH * sa; yb = HY + camH * sb;
      hw = a.hw; hb = b === kart ? trailHw() : b.hw;
      for (sg = -1; sg <= 1; sg += 2) {
        ctx.moveTo(cx + (a.x + sg * 1.12 - hw - camX) * sa, ya); ctx.lineTo(cx + (a.x + sg * 1.12 + hw - camX) * sa, ya);
        ctx.lineTo(cx + (b.x + sg * 1.12 + hb - camX) * sb, yb); ctx.lineTo(cx + (b.x + sg * 1.12 - hb - camX) * sb, yb); ctx.closePath();
      }
      n++;
    }
    if (n) ctx.fill();
  }

  function drawLamps(ctx) {
    var k = Math.ceil((camZ + 6) / 36), i, d, s, x, by, top, sg, w;
    for (i = 6; i >= 0; i--) {
      d = (k + i) * 36 - camZ; s = F / d; by = HY + camH * s; top = HY + (camH - 7.4) * s;
      for (sg = -1; sg <= 1; sg += 2) {
        x = cx + (sg * LAMPX - camX) * s;
        if (x < -40 || x > W + 40) continue;
        w = Math.max(1, 0.17 * s);
        ctx.fillStyle = '#35218A'; ctx.fillRect(x - w / 2, top, w, by - top);
        ctx.fillRect(x - w * 1.4, by - 0.5 * s, w * 2.8, 0.5 * s);
        ctx.fillStyle = FLAGS[(k + i + (sg > 0 ? 1 : 0)) % 3];
        ctx.beginPath(); ctx.moveTo(x, top + 2.1 * s); ctx.lineTo(x - sg * 1.5 * s, top + 2.5 * s); ctx.lineTo(x, top + 2.95 * s); ctx.closePath(); ctx.fill();
        ctx.drawImage(spGlow, x - 2.6 * s, top - 2.6 * s, 5.2 * s, 5.2 * s);
        ctx.fillStyle = '#FFF7DA'; ctx.beginPath(); ctx.arc(x, top, Math.max(1.2, 0.5 * s), 0, TAU); ctx.fill();
      }
    }
  }

  function drawItem(ctx, o) {
    var d = o.z - camZ;
    if (d < 3 || d > 255 || o.gone || (o.t === GEM && o.done)) return;
    var s = F / d, sx = cx + (o.x - camX) * s, gy = HY + camH * s, sp, fade = d > 205;
    if (fade) ctx.globalAlpha = (255 - d) / 50;
    if (o.t === GEM) {
      var bob = Math.sin(time * 4 + o.z * 0.4) * 0.12, yy = gy - (o.y + 0.95 + bob) * s;
      if (o.y < 0.5) { ctx.fillStyle = 'rgba(14,6,56,0.3)'; ell(ctx, sx, gy, 0.42 * s, 0.11 * s); ctx.fill(); }
      ctx.drawImage(spGem.img, sx - 0.8 * s, yy - 0.8 * s, 1.6 * s, 1.6 * s);
    } else if (o.t === RAMP) {
      var s2 = F / (d + 4.4), sn = F / Math.max(1.5, d - 2.2), sf = s2;
      sn = F / Math.max(1.5, d - 2.2); sf = F / (d + 2.2);
      var nx = cx + (o.x - camX) * sn, ny = HY + camH * sn, fx = cx + (o.x - camX) * sf, fyg = HY + camH * sf, fy = HY + (camH - 1.6) * sf;
      ctx.fillStyle = 'rgba(14,6,56,0.35)';
      ctx.beginPath(); ctx.moveTo(nx - 1.4 * sn, ny); ctx.lineTo(fx - 1.5 * sf, fyg - 0.3 * sf); ctx.lineTo(fx + 1.5 * sf, fyg - 0.3 * sf); ctx.lineTo(nx + 1.4 * sn, ny); ctx.closePath(); ctx.fill();
      ctx.fillStyle = '#B81F6A';
      ctx.beginPath(); ctx.moveTo(fx - 1.3 * sf, fy); ctx.lineTo(fx + 1.3 * sf, fy); ctx.lineTo(fx + 1.3 * sf, fyg); ctx.lineTo(fx - 1.3 * sf, fyg); ctx.closePath(); ctx.fill();
      ctx.fillStyle = '#FFC531';
      ctx.beginPath(); ctx.moveTo(nx - 1.3 * sn, ny); ctx.lineTo(fx - 1.3 * sf, fy); ctx.lineTo(fx + 1.3 * sf, fy); ctx.lineTo(nx + 1.3 * sn, ny); ctx.closePath(); ctx.fill();
      ctx.fillStyle = '#FF4D8D';
      var j, v0, v1, v2, sA, sB, sC, ph = (time * 1.4) % 0.5;
      for (j = 0; j < 2; j++) {
        v0 = 0.08 + j * 0.42 + ph * 0.2; v1 = v0 + 0.24; v2 = v0 + 0.2;
        sA = F / (d - 2.2 + 4.4 * v0); sB = F / (d - 2.2 + 4.4 * v1); sC = F / (d - 2.2 + 4.4 * Math.min(1, v1 + v2 - v0));
        var sD = F / (d - 2.2 + 4.4 * v2);
        var xo = cx + (o.x - camX) * sA, xb = cx + (o.x - camX) * sB, xc = cx + (o.x - camX) * sC, xd = cx + (o.x - camX) * sD;
        var yA = HY + (camH - 1.6 * v0) * sA, yB = HY + (camH - 1.6 * v1) * sB, yC = HY + (camH - 1.6 * Math.min(1, v1 + v2 - v0)) * sC, yD = HY + (camH - 1.6 * v2) * sD;
        ctx.beginPath(); ctx.moveTo(xo - 0.95 * sA, yA); ctx.lineTo(xb, yB); ctx.lineTo(xo + 0.95 * sA, yA); ctx.lineTo(xd + 0.95 * sD, yD); ctx.lineTo(xc, yC); ctx.lineTo(xd - 0.95 * sD, yD); ctx.closePath(); ctx.fill();
      }
      ctx.fillStyle = '#FFF4C2';
      ctx.fillRect(fx - 1.3 * sf, fy - 0.06 * sf, 2.6 * sf, Math.max(1, 0.14 * sf));
    } else {
      sp = o.t === BARRIER ? spBarrier : o.t === CONES ? spCones : spCars[o.v];
      ctx.drawImage(sp.img, sx - sp.w * s / 2, gy - (sp.h - sp.base) * s, sp.w * s, sp.h * s);
    }
    if (fade) ctx.globalAlpha = 1;
  }

  function drawKart(ctx, state) {
    var d = kart.z - camZ;
    if (d < 2) return;
    var s = F / d, gx = cx + (kart.x - camX) * s, gy = HY + camH * s, u = 3.1 * s / 100;
    var sh = 1 / (1 + kart.y * 0.3), sq = kart.sqT < 0.8 ? kart.sqA * Math.exp(-kart.sqT * 9) * Math.cos(kart.sqT * 24) : 0;
    var idle = state === 'ready' ? Math.sin(time * 34) * 0.5 : speed > 1 ? Math.sin(time * 22) * 0.35 : 0;
    var i, y;
    ctx.globalAlpha = 0.42 * sh; ctx.fillStyle = '#0E0638';
    ell(ctx, gx, gy + 1.5 * u, 56 * u * sh, 13 * u * sh); ctx.fill();
    ctx.globalAlpha = 1;
    ctx.save();
    ctx.translate(gx + kart.bump * 5 * u, gy - kart.y * s + idle * u);
    ctx.rotate(kart.lean * 0.55);
    if (kart.spin) { ctx.translate(0, -42 * u); ctx.rotate(kart.spin); ctx.translate(0, 42 * u); }
    ctx.scale(u * (1 + sq * 0.2), u * (1 - sq * 0.28));
    ctx.transform(1, 0, -kart.lean * 0.5, 1, 0, 0);

    if (boostT > 0 && !over) {
      var fl = 14 + Math.random() * 12;
      ctx.fillStyle = '#7DF3FF';
      ctx.beginPath(); ctx.moveTo(-17, -4); ctx.lineTo(-11, 4 + fl); ctx.lineTo(-5, -4); ctx.closePath(); ctx.fill();
      ctx.beginPath(); ctx.moveTo(5, -4); ctx.lineTo(11, 4 + fl); ctx.lineTo(17, -4); ctx.closePath(); ctx.fill();
      ctx.fillStyle = '#FFFFFF';
      ctx.beginPath(); ctx.moveTo(-14, -4); ctx.lineTo(-11, fl * 0.5); ctx.lineTo(-8, -4); ctx.closePath(); ctx.fill();
      ctx.beginPath(); ctx.moveTo(8, -4); ctx.lineTo(11, fl * 0.5); ctx.lineTo(14, -4); ctx.closePath(); ctx.fill();
    }

    ctx.fillStyle = '#1A1244';
    rrp(ctx, -48, -80, 16, 26, 5); ctx.fill(); rrp(ctx, 32, -80, 16, 26, 5); ctx.fill();
    ctx.fillStyle = '#3A2D85'; ctx.fillRect(-34, -70, 68, 5);
    ctx.fillStyle = noseGrad;
    ctx.beginPath(); ctx.moveTo(-17, -92); ctx.quadraticCurveTo(0, -97, 17, -92); ctx.lineTo(31, -38); ctx.lineTo(-31, -38); ctx.closePath(); ctx.fill();
    ctx.fillStyle = '#F2385A'; ctx.beginPath(); ctx.moveTo(-5, -95); ctx.lineTo(5, -95); ctx.lineTo(7, -60); ctx.lineTo(-7, -60); ctx.closePath(); ctx.fill();
    ctx.fillStyle = '#FFC531'; rrp(ctx, -38, -60, 76, 30, 9); ctx.fill();
    ctx.fillStyle = 'rgba(255,255,255,0.35)'; rrp(ctx, -34, -58, 68, 5, 2.5); ctx.fill();

    ctx.fillStyle = '#1A1244';
    rrp(ctx, -54, -36, 23, 36, 7); ctx.fill(); rrp(ctx, 31, -36, 23, 36, 7); ctx.fill();
    ctx.fillStyle = '#3A2D85';
    for (i = 0; i < 3; i++) {
      y = -32 + ((kart.roll * 22 + i * 10) % 30);
      ctx.fillRect(-51, y, 17, 2.4); ctx.fillRect(34, y, 17, 2.4);
    }
    ctx.fillStyle = 'rgba(255,255,255,0.12)'; rrp(ctx, -53, -35, 5, 34, 2.5); ctx.fill(); rrp(ctx, 32, -35, 5, 34, 2.5); ctx.fill();

    ctx.fillStyle = '#3A1672'; rrp(ctx, -16, -70, 32, 24, 7); ctx.fill();
    ctx.fillStyle = '#F4EEFF'; rrp(ctx, -14, -78, 28, 26, 10); ctx.fill();
    var fw = Math.sin(time * 15), fw2 = Math.cos(time * 11);
    ctx.fillStyle = '#F2385A';
    ctx.beginPath(); ctx.moveTo(8, -72); ctx.quadraticCurveTo(22, -80 + fw * 3, 36 + fw2 * 2, -76 + fw * 5); ctx.lineTo(34 + fw2 * 2, -66 + fw * 5); ctx.quadraticCurveTo(20, -66 + fw * 2, 8, -66); ctx.closePath(); ctx.fill();
    rrp(ctx, -12, -73, 24, 7, 3.5); ctx.fill();
    ctx.fillStyle = '#FFFFFF';
    ctx.save(); ctx.translate(-8, -101); ctx.rotate(-0.22); rrp(ctx, -4, -10, 8, 20, 4); ctx.fill(); ctx.fillStyle = '#FFB3CC'; rrp(ctx, -1.6, -7, 3.2, 12, 1.6); ctx.fill(); ctx.restore();
    ctx.fillStyle = '#FFFFFF';
    ctx.save(); ctx.translate(8, -101); ctx.rotate(0.22); rrp(ctx, -4, -10, 8, 20, 4); ctx.fill(); ctx.fillStyle = '#FFB3CC'; rrp(ctx, -1.6, -7, 3.2, 12, 1.6); ctx.fill(); ctx.restore();
    ctx.fillStyle = '#FFFFFF'; ctx.beginPath(); ctx.arc(0, -86, 14.5, 0, TAU); ctx.fill();
    ctx.fillStyle = 'rgba(120,80,210,0.22)'; ctx.beginPath(); ctx.arc(0, -86, 14.5, 0.15 * PI, 0.85 * PI); ctx.closePath(); ctx.fill();
    ctx.fillStyle = '#F2385A'; rrp(ctx, -3.6, -100.5, 7.2, 22, 3.6); ctx.fill();

    ctx.fillStyle = bodyGrad; rrp(ctx, -33, -42, 66, 36, 10); ctx.fill();
    ctx.fillStyle = 'rgba(255,255,255,0.28)'; rrp(ctx, -28, -40, 56, 4.5, 2.2); ctx.fill();
    ctx.fillStyle = '#2B1C63'; rrp(ctx, -29, -14, 58, 10, 5); ctx.fill();
    ctx.fillStyle = 'rgba(125,243,255,0.35)'; ctx.beginPath(); ctx.arc(-18, -9, 6.5, 0, TAU); ctx.arc(18, -9, 6.5, 0, TAU); ctx.fill();
    ctx.fillStyle = '#9FF6FF'; ctx.beginPath(); ctx.arc(-18, -9, 3.6, 0, TAU); ctx.arc(18, -9, 3.6, 0, TAU); ctx.fill();
    ctx.fillStyle = '#FFD84A'; ctx.beginPath(); ctx.arc(0, -27, 10, 0, TAU); ctx.fill();
    ctx.fillStyle = '#F2385A';
    ctx.beginPath(); ctx.moveTo(2.5, -35); ctx.lineTo(-5, -25.5); ctx.lineTo(-0.5, -25.5); ctx.lineTo(-2.5, -19); ctx.lineTo(5, -28.5); ctx.lineTo(0.5, -28.5); ctx.closePath(); ctx.fill();

    ctx.fillStyle = '#3A1672'; ctx.fillRect(-22, -54, 5, 13); ctx.fillRect(17, -54, 5, 13);
    ctx.fillStyle = '#F2385A'; rrp(ctx, -44, -61, 88, 11, 4.5); ctx.fill();
    ctx.fillStyle = '#FF8CA3'; rrp(ctx, -42, -60, 84, 3.6, 1.8); ctx.fill();
    ctx.fillStyle = '#FFF4F7'; rrp(ctx, -48, -64, 8, 18, 3); ctx.fill(); rrp(ctx, 40, -64, 8, 18, 3); ctx.fill();
    ctx.restore();
  }

  function drawFx(ctx) {
    var i, p, a, t, k, sc;
    for (i = 0; i < PART_N; i++) {
      p = parts[i];
      if (p.life <= 0) continue;
      a = p.life / p.max;
      ctx.globalAlpha = a < 0.5 ? a * 2 : 1;
      ctx.fillStyle = p.col;
      if (p.kind === 1) {
        ctx.save(); ctx.translate(p.x, p.y); ctx.rotate(p.rot); ctx.fillRect(-p.size / 2, -p.size * 0.35, p.size, p.size * 0.7); ctx.restore();
      } else if (p.kind === 2) {
        ctx.save(); ctx.translate(p.x, p.y); ctx.rotate(Math.atan2(p.vy, p.vx)); ctx.fillRect(-p.size * 2.5, -p.size * 0.4, p.size * 5, p.size * 0.8); ctx.restore();
      } else {
        k = p.size * (1.6 - a * 0.6);
        ctx.beginPath(); ctx.arc(p.x, p.y, k, 0, TAU); ctx.fill();
      }
    }
    ctx.globalAlpha = 1;
    for (i = 0; i < POP_N; i++) {
      p = pops[i];
      if (p.t >= p.life) continue;
      t = p.t / p.life; sc = t < 0.2 ? D.easeOutBack(t / 0.2) : 1;
      D.text(p.txt, p.x, p.y - t * 46, { size: p.size * sc, color: p.col, stroke: '#2A1466', strokeWidth: p.size * 0.26, alpha: t > 0.7 ? (1 - t) / 0.3 : 1 });
    }
  }

  function drawSpeedLines(ctx) {
    var amt = clamp((speed - 27) / 16, 0, 0.6) + clamp(boostT / 0.7, 0, 1) * 0.7, i, p, r0, r1, ca, sa;
    if (amt < 0.03 || over) return;
    ctx.strokeStyle = '#FFFFFF'; ctx.lineCap = 'round';
    for (i = 0; i < lines.length; i++) {
      p = lines[i];
      ca = Math.cos(p.a) * p.side; sa = Math.sin(p.a);
      r0 = (0.18 + p.p * 0.75) * H * 0.62; r1 = r0 + (26 + p.p * 80) * (0.6 + amt);
      ctx.globalAlpha = Math.min(1, amt) * Math.sin(p.p * PI) * 0.8;
      ctx.lineWidth = 1.2 + p.p * 2.6;
      ctx.beginPath(); ctx.moveTo(cx + ca * r0, HY + sa * r0); ctx.lineTo(cx + ca * r1, HY + sa * r1); ctx.stroke();
    }
    ctx.globalAlpha = 1;
  }

  function drawHud(ctx, state) {
    var y0 = D.safe.top + 60, str = String(Math.floor(score)), w, mw, x, pw, gw, tw, k;
    ctx.font = D.font(50); w = ctx.measureText(str).width;
    ctx.font = D.font(22); mw = ctx.measureText('m').width;
    x = cx - (w + mw + 3) / 2;
    D.text(str, x, y0 + 40, { size: 50, align: 'left', stroke: '#2A1466', strokeWidth: 7 });
    D.text('m', x + w + 3, y0 + 40, { size: 22, align: 'left', stroke: '#2A1466', strokeWidth: 5, color: '#E9DCFF' });

    var gs = String(gems), ms = 'x' + mult.toFixed(1), py = y0 + 52, ph = 25;
    ctx.font = D.font(17); gw = ctx.measureText(gs).width + 38; tw = ctx.measureText(ms).width + 24;
    pw = gw + tw + 6; x = cx - pw / 2;
    ctx.fillStyle = 'rgba(32,18,96,0.85)'; D.rr(x, py, gw, ph, ph / 2); ctx.fill();
    k = 1 + gemPulse * 0.35;
    ctx.drawImage(spGem.img, x + 14 - 13 * k, py + ph / 2 - 13 * k, 26 * k, 26 * k);
    D.text(gs, x + 27, py + 18.5, { size: 17, align: 'left' });
    x += gw + 6;
    k = multPulse * 3;
    ctx.fillStyle = mult > 1.01 ? '#FF3F8E' : 'rgba(255,79,154,0.75)';
    D.rr(x - k, py - k * 0.5, tw + k * 2, ph + k, (ph + k) / 2); ctx.fill();
    if (mult > 1.01 && multHold <= 0) { ctx.fillStyle = 'rgba(255,255,255,0.28)'; D.rr(x + 4, py + ph - 5, (tw - 8) * clamp((mult - 1) % 0.5 / 0.5 || 1, 0, 1), 2.5, 1.2); ctx.fill(); }
    D.text(ms, x + tw / 2, py + 18.5, { size: 17 });

    if (state === 'ready' && !D.clip) {
      var hy = H - D.safe.bottom - 112, hs = 'SWIPE TO CHANGE LANE', a = 0.5 + 0.5 * Math.sin(time * 4), hw;
      ctx.font = D.font(17); hw = ctx.measureText(hs).width + 84;
      ctx.fillStyle = 'rgba(26,14,84,0.72)'; D.rr(cx - hw / 2, hy, hw, 40, 20); ctx.fill();
      ctx.strokeStyle = 'rgba(255,255,255,0.22)'; ctx.lineWidth = 1; ctx.stroke();
      D.text(hs, cx, hy + 26, { size: 17, color: '#F3ECFF' });
      ctx.strokeStyle = '#FF7FB2'; ctx.lineWidth = 2.6; ctx.lineCap = 'round'; ctx.lineJoin = 'round';
      x = cx - hw / 2 + 22 - a * 4;
      ctx.beginPath(); ctx.moveTo(x + 5, hy + 13); ctx.lineTo(x - 2, hy + 20); ctx.lineTo(x + 5, hy + 27); ctx.stroke();
      x = cx + hw / 2 - 22 + a * 4;
      ctx.beginPath(); ctx.moveTo(x - 5, hy + 13); ctx.lineTo(x + 2, hy + 20); ctx.lineTo(x - 5, hy + 27); ctx.stroke();
    }
  }

  function draw(ctx, w, h, state) {
    layout();
    var i, o, drawn = false, sx = 0, sy = 0;
    if (shake > 0.3) { sx = (Math.random() - 0.5) * shake; sy = (Math.random() - 0.5) * shake; }
    ctx.save();
    ctx.translate(sx, sy);
    ctx.drawImage(bg, -PAD, -PAD, W + PAD * 2, H + PAD * 2);
    ctx.fillStyle = '#FFFFFF';
    for (i = 0; i < 6; i++) {
      ctx.globalAlpha = 0.25 + 0.75 * Math.abs(Math.sin(time * (0.9 + i * 0.23) + i * 1.7));
      ctx.beginPath(); ctx.arc(W * ((i * 0.173 + 0.09) % 1), HY * (0.07 + ((i * 0.37) % 1) * 0.36), 1.3, 0, TAU); ctx.fill();
    }
    ctx.globalAlpha = 1;
    drawRoad(ctx);
    drawTrail(ctx);
    drawLamps(ctx);
    for (i = items.length - 1; i >= 0; i--) {
      o = items[i];
      if (!drawn && o.z < kart.z) { drawKart(ctx, state); drawn = true; }
      drawItem(ctx, o);
    }
    if (!drawn) drawKart(ctx, state);
    drawFx(ctx);
    drawSpeedLines(ctx);
    ctx.restore();
    if (flash > 0) { ctx.fillStyle = 'rgba(255,255,255,' + (flash * 0.55).toFixed(2) + ')'; ctx.fillRect(0, 0, W, H); }
    drawHud(ctx, state);
  }

  D.game({
    reset: resetRound,
    start: function () {
      D.haptic('light');
      D.tone({ freq: 220, slide: 440, dur: 0.2, type: 'sawtooth', vol: 0.05 });
    },
    update: update,
    draw: draw,
    resize: function () { layout(); },
    pointerDown: function (x, y, id, first) {
      ptr.id = id; ptr.x0 = x; ptr.y0 = y; ptr.moved = false; ptr.first = !!first;
    },
    pointerMove: function (x, y, id, down) {
      if (!down || id !== ptr.id) return;
      var dx = x - ptr.x0, thr = Math.max(16, W * 0.05) * (ptr.moved ? 1.7 : 1);
      if (Math.abs(dx) > thr && Math.abs(dx) > Math.abs(y - ptr.y0) * 0.7) {
        steer(dx > 0 ? 1 : -1);
        ptr.x0 = x; ptr.y0 = y; ptr.moved = true;
      }
    },
    pointerUp: function (x, y, id) {
      if (id !== ptr.id) return;
      ptr.id = -1;
      if (ptr.moved || ptr.first) return;
      if (x < W / 3) steer(-1); else if (x > W * 2 / 3) steer(1);
    },
    key: function (k) {
      if (k === 'ArrowLeft' || k === 'a') steer(-1);
      else if (k === 'ArrowRight' || k === 'd') steer(1);
    },
    bot: bot,
  });
})();
