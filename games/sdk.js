/* Dailies game runtime. Loaded before every game. Exposes window.Dailies (alias D). */
(function () {
  'use strict';

  var query = {};
  try {
    new URLSearchParams(location.search).forEach(function (v, k) { query[k] = v; });
  } catch (e) {}

  var cfg = Object.assign(
    { mode: 'play', seed: 1, safeTop: 47, safeBottom: 34, best: 0, sound: false, autostart: false, maxDpr: 2 },
    window.DAILIES_CONFIG || {}
  );
  if (query.mode) cfg.mode = query.mode;
  if (query.seed) cfg.seed = Number(query.seed);
  if (query.best) cfg.best = Number(query.best);
  if (query.autostart) cfg.autostart = query.autostart === '1';
  if (query.sound) cfg.sound = query.sound === '1';

  var canvas = document.getElementById('c');
  var ctx = canvas.getContext('2d');
  var game = null;
  var state = 'loading';
  var paused = false;
  var lastTime = 0;
  var elapsed = 0;
  var overAt = 0;
  var clipRound = 0;
  var lastScore = null;
  var lastScoreSent = 0;
  var lastInputSent = 0;
  var audio = null;

  function post(type, data) {
    var msg = JSON.stringify(Object.assign({ type: type }, data || {}));
    if (window.ReactNativeWebView) window.ReactNativeWebView.postMessage(msg);
    else if (window.parent && window.parent !== window) window.parent.postMessage(msg, '*');
    else if (type !== 'input' && type !== 'score') console.log('[dailies] ' + msg);
  }

  function mulberry32(a) {
    return function () {
      a |= 0; a = (a + 0x6d2b79f5) | 0;
      var t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }
  var rng = mulberry32(cfg.seed);

  var D = {
    config: cfg,
    canvas: canvas,
    ctx: ctx,
    W: 0,
    H: 0,
    dpr: 1,
    clip: cfg.mode === 'clip',
    safe: { top: cfg.safeTop, bottom: cfg.safeBottom },
    best: cfg.best,
    state: function () { return state; },
    time: function () { return elapsed; },

    rand: function () { return rng(); },
    randRange: function (a, b) { return a + rng() * (b - a); },
    randInt: function (a, b) { return a + Math.floor(rng() * (b - a + 1)); },
    pick: function (arr) { return arr[Math.floor(rng() * arr.length)]; },
    makeRng: mulberry32,

    clamp: function (v, a, b) { return v < a ? a : v > b ? b : v; },
    lerp: function (a, b, t) { return a + (b - a) * t; },
    easeOut: function (t) { return 1 - Math.pow(1 - t, 3); },
    easeInOut: function (t) { return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2; },
    easeOutBack: function (t) { var c = 1.70158; return 1 + (c + 1) * Math.pow(t - 1, 3) + c * Math.pow(t - 1, 2); },

    font: function (size, weight) { return (weight || 900) + ' ' + size + 'px "Big Shoulders", "Arial Narrow", system-ui, sans-serif'; },
    textFont: function (size, weight) { return (weight || 600) + ' ' + size + 'px -apple-system, system-ui, "Helvetica Neue", sans-serif'; },
    text: function (str, x, y, o) {
      o = o || {};
      ctx.font = o.font || D.font(o.size || 24, o.weight);
      ctx.textAlign = o.align || 'center';
      ctx.textBaseline = o.baseline || 'alphabetic';
      if (o.alpha != null) ctx.globalAlpha = o.alpha;
      if (o.stroke) { ctx.lineJoin = 'round'; ctx.lineWidth = o.strokeWidth || 4; ctx.strokeStyle = o.stroke; ctx.strokeText(str, x, y); }
      ctx.fillStyle = o.color || '#fff';
      ctx.fillText(str, x, y);
      if (o.alpha != null) ctx.globalAlpha = 1;
    },
    rr: function (x, y, w, h, r) {
      ctx.beginPath();
      if (ctx.roundRect) ctx.roundRect(x, y, w, h, r);
      else { ctx.moveTo(x + r, y); ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r); ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath(); }
    },

    haptic: function (kind) { if (!D.clip) post('haptic', { kind: kind || 'light' }); },
    tone: function (o) {
      if (!cfg.sound || D.clip) return;
      try {
        audio = audio || new (window.AudioContext || window.webkitAudioContext)();
        var t = audio.currentTime, osc = audio.createOscillator(), g = audio.createGain();
        osc.type = o.type || 'sine';
        osc.frequency.setValueAtTime(o.freq || 440, t);
        if (o.slide) osc.frequency.exponentialRampToValueAtTime(Math.max(30, o.slide), t + (o.dur || 0.12));
        g.gain.setValueAtTime(o.vol || 0.12, t);
        g.gain.exponentialRampToValueAtTime(0.0001, t + (o.dur || 0.12));
        osc.connect(g); g.connect(audio.destination);
        osc.start(t); osc.stop(t + (o.dur || 0.12) + 0.02);
      } catch (e) {}
    },

    score: function (value, label) {
      if (D.clip || state !== 'playing') return;
      if (value === lastScore) return;
      var now = performance.now();
      if (now - lastScoreSent < 250) return;
      lastScore = value; lastScoreSent = now;
      post('score', { score: value, label: label });
    },
    end: function (result) {
      if (state !== 'playing') return;
      state = 'over';
      overAt = elapsed;
      if (!D.clip) post('end', result || {});
    },

    game: function (impl) {
      game = impl;
      resize();
      beginRound(cfg.seed);
      requestAnimationFrame(frame);
      post('ready', { title: document.title });
    },

    host: function (type, data) {
      data = data || {};
      if (type === 'pause') paused = true;
      else if (type === 'resume') { paused = false; lastTime = 0; }
      else if (type === 'restart') {
        if (data.best != null) { cfg.best = data.best; D.best = data.best; }
        paused = false;
        beginRound(data.seed != null ? data.seed : cfg.seed + 1);
        if (data.autostart) startRound();
      } else if (type === 'config') {
        Object.assign(cfg, data);
        D.safe.top = cfg.safeTop; D.safe.bottom = cfg.safeBottom; D.best = cfg.best;
      }
    }
  };

  function beginRound(seed) {
    cfg.seed = seed;
    rng = mulberry32(seed);
    state = 'ready';
    lastScore = null;
    lastTime = 0;
    game.reset(seed);
    if (D.clip || cfg.autostart) startRound();
  }

  function startRound() {
    if (state !== 'ready') return;
    state = 'playing';
    if (game.start) game.start();
    if (!D.clip) post('start', { seed: cfg.seed });
  }

  function resize() {
    var w = window.innerWidth, h = window.innerHeight;
    if (!w || !h) return;
    var dpr = Math.min(window.devicePixelRatio || 1, cfg.maxDpr);
    D.W = w; D.H = h; D.dpr = dpr;
    canvas.width = Math.round(w * dpr);
    canvas.height = Math.round(h * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    if (game && game.resize) game.resize(w, h);
  }
  window.addEventListener('resize', resize);

  function frame(now) {
    requestAnimationFrame(frame);
    if (!D.W) { resize(); return; }
    if (paused) { lastTime = 0; if (D.clip) return; }
    var dt = lastTime ? Math.min((now - lastTime) / 1000, 1 / 30) : 1 / 60;
    lastTime = now;
    if (!paused) {
      elapsed += dt;
      if (D.clip && state === 'playing' && game.bot) game.bot(dt);
      game.update(dt, state);
      if (D.clip && state === 'over' && elapsed - overAt > 1.8) {
        clipRound += 1;
        beginRound(cfg.seed + 7919);
      }
    }
    ctx.setTransform(D.dpr, 0, 0, D.dpr, 0, 0);
    game.draw(ctx, D.W, D.H, state);
  }

  function pointerPos(e) {
    var r = canvas.getBoundingClientRect();
    return { x: e.clientX - r.left, y: e.clientY - r.top };
  }
  function noteInput() {
    var now = performance.now();
    if (now - lastInputSent > 1000) { lastInputSent = now; post('input'); }
  }
  if (!D.clip) {
    canvas.addEventListener('pointerdown', function (e) {
      e.preventDefault();
      if (paused || !game) return;
      var p = pointerPos(e), first = false;
      if (state === 'ready') { startRound(); first = true; }
      if (state !== 'playing') return;
      noteInput();
      try { canvas.setPointerCapture(e.pointerId); } catch (err) {}
      if (game.pointerDown) game.pointerDown(p.x, p.y, e.pointerId, first);
    });
    canvas.addEventListener('pointermove', function (e) {
      e.preventDefault();
      if (paused || state !== 'playing' || !game) return;
      var p = pointerPos(e);
      if (e.buttons || e.pointerType === 'touch') noteInput();
      if (game.pointerMove) game.pointerMove(p.x, p.y, e.pointerId, e.buttons > 0 || e.pointerType === 'touch');
    });
    var up = function (e) {
      e.preventDefault();
      if (!game || state !== 'playing') return;
      var p = pointerPos(e);
      if (game.pointerUp) game.pointerUp(p.x, p.y, e.pointerId);
    };
    canvas.addEventListener('pointerup', up);
    canvas.addEventListener('pointercancel', up);
    window.addEventListener('keydown', function (e) {
      if (game && game.key && state !== 'over') {
        if (state === 'ready') startRound();
        noteInput();
        game.key(e.key);
      }
    });
  }
  document.addEventListener('gesturestart', function (e) { e.preventDefault(); });
  document.addEventListener('touchmove', function (e) { e.preventDefault(); }, { passive: false });
  document.addEventListener('contextmenu', function (e) { e.preventDefault(); });

  window.Dailies = D;
  window.D = D;
})();
