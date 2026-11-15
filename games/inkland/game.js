/* Smallest possible game against the Dailies runtime. Not shipped (folders starting with _ are skipped). */
(function () {
  var D = window.Dailies;
  var ball, score, alive;

  D.game({
    reset: function () {
      ball = { x: D.W / 2, y: D.H / 2, vx: 120 + D.rand() * 120, vy: -200, r: 26 };
      score = 0;
      alive = true;
    },
    start: function () {},
    update: function (dt, state) {
      if (state !== 'playing') return;
      ball.vy += 900 * dt;
      ball.x += ball.vx * dt;
      ball.y += ball.vy * dt;
      if (ball.x < ball.r || ball.x > D.W - ball.r) ball.vx *= -1;
      if (ball.y > D.H - D.safe.bottom - ball.r && alive) {
        alive = false;
        D.haptic('error');
        D.end({ score: score, unit: 'taps', headline: 'Dropped it' });
      }
    },
    draw: function (ctx, W, H, state) {
      ctx.fillStyle = '#1B1B3A';
      ctx.fillRect(0, 0, W, H);
      ctx.fillStyle = '#FFC531';
      ctx.beginPath();
      ctx.arc(ball.x, ball.y, ball.r, 0, Math.PI * 2);
      ctx.fill();
      D.text(String(score), W / 2, D.safe.top + 110, { size: 72 });
      if (state === 'ready') D.text('TAP TO BOUNCE', W / 2, H - D.safe.bottom - 80, { size: 18, color: 'rgba(255,255,255,0.8)' });
    },
    pointerDown: function () {
      ball.vy = -520;
      score += 1;
      D.score(score);
      D.haptic('light');
    },
    bot: function () {
      if (ball.y > D.H * 0.6 && ball.vy > 0) this.pointerDown();
    },
  });
})();
