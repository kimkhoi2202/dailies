import { unwrapWebhook } from "@whop/sdk/helpers";
import { httpRouter } from "convex/server";
import { internal } from "./_generated/api";
import { env, httpAction } from "./_generated/server";

const http = httpRouter();

// Whop calls this when a payment goes through. The signature is checked before anything is read.
http.route({
  path: "/whop",
  method: "POST",
  handler: httpAction(async (ctx, req) => {
    const payload = await req.text();
    let event: Record<string, unknown>;
    try {
      event = unwrapWebhook(payload, { headers: Object.fromEntries(req.headers), key: env.WHOP_WEBHOOK_SECRET });
    } catch {
      return new Response("Bad signature", { status: 400 });
    }
    if (event.type !== "payment.succeeded") return new Response("OK", { status: 200 });

    const data = event.data;
    if (typeof data !== "object" || data === null) return new Response("Bad payment", { status: 400 });
    const payment = data as Record<string, unknown>;
    const metadata = payment.metadata;
    const order = typeof metadata === "object" && metadata !== null ? (metadata as Record<string, unknown>).order : undefined;
    // A payment that did not start in the app has no order and is none of our business.
    if (typeof payment.id !== "string" || typeof order !== "string") return new Response("OK", { status: 200 });
    await ctx.runMutation(internal.whop.settle, { order, paymentId: payment.id });
    return new Response("OK", { status: 200 });
  }),
});

// Where Whop sends the browser after a payment.
http.route({
  path: "/whop/done",
  method: "GET",
  handler: httpAction(async () => {
    const page = `<!doctype html><meta name="viewport" content="width=device-width, initial-scale=1"><title>DEGEN</title>
<body style="margin:0;height:100vh;display:grid;place-items:center;background:#111;color:#fff;font:600 20px -apple-system,system-ui,sans-serif;text-align:center">
<div>Payment received.<br><span style="font-weight:400;opacity:.7;font-size:16px">Close this page to go back to DEGEN.</span></div></body>`;
    return new Response(page, { status: 200, headers: { "content-type": "text/html; charset=utf-8" } });
  }),
});

// Where signing in with Apple or Google ends. The app is waiting on a degen:// address, so the answer is passed on to it.
http.route({
  path: "/auth/done",
  method: "GET",
  handler: httpAction(async (_ctx, req) => {
    return new Response(null, { status: 302, headers: { location: "degen://auth" + new URL(req.url).search } });
  }),
});

// The page Safari adds to the Home Screen as a game's own icon. In Safari it says how to add it.
// Opened from the Home Screen it hands over to the app, which opens the game.
http.route({
  path: "/shortcut",
  method: "GET",
  handler: httpAction(async (ctx, req) => {
    const shortcut = await ctx.runQuery(internal.shortcuts.page, { id: new URL(req.url).searchParams.get("id") ?? "" });
    if (shortcut === null) return new Response("Not found", { status: 404 });
    const text = (value: string) =>
      value.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c] ?? c);
    const title = text(shortcut.title);
    const icon = text(shortcut.icon);
    const game = "degen://play/" + encodeURIComponent(shortcut.slug);
    const page = `<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-title" content="${title}">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="theme-color" content="#111111">
<link rel="apple-touch-icon" href="${icon}">
<title>${title}</title>
<style>
  html, body { margin: 0; min-height: 100%; background: #111; color: #fff; font: 400 17px/1.4 -apple-system, system-ui, sans-serif; -webkit-text-size-adjust: 100%; }
  body { min-height: 100vh; min-height: 100dvh; box-sizing: border-box; padding: 32px 28px; display: flex; flex-direction: column; align-items: center; justify-content: center; text-align: center; }
  img { width: 120px; height: 120px; border-radius: 27px; box-shadow: 0 12px 40px rgba(0, 0, 0, .5); }
  h1 { margin: 20px 0 6px; font-size: 28px; font-weight: 700; }
  p { margin: 0; opacity: .7; }
  ol { margin: 26px 0 0; padding: 0; list-style: none; text-align: left; counter-reset: step; }
  li { counter-increment: step; display: flex; align-items: center; gap: 14px; padding: 9px 0; }
  li::before { content: counter(step); flex: none; width: 30px; height: 30px; border-radius: 15px; background: #fff; color: #111; font-weight: 700; display: grid; place-items: center; }
  li small { display: block; font-size: 14px; opacity: .6; }
  svg { vertical-align: -4px; }
  a { margin-top: 28px; color: #fff; font-weight: 600; }
  .launch #add { display: none; }
  .launch a { text-decoration: none; background: #ffc83d; color: #111; font-size: 20px; font-weight: 700; padding: 15px 56px; border-radius: 20px; }
</style>
<body>
<img src="${icon}" alt="">
<h1>${title}</h1>
<div id="add">
  <p>Add it to your Home Screen.</p>
  <ol>
    <li><div>Tap Share <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v12M8 7l4-4 4 4M6 11H5a1 1 0 0 0-1 1v8a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-8a1 1 0 0 0-1-1h-1"/></svg><small>If you do not see it, open the menu by the address bar.</small></div></li>
    <li><div>Tap Add to Home Screen<small>It can be under View More.</small></div></li>
    <li><div>Tap Add</div></li>
  </ol>
</div>
<a href="${game}">Open the game</a>
<script>
  // navigator.standalone is true only when the page was opened from its Home Screen icon.
  if (navigator.standalone) {
    document.body.className = "launch";
    document.querySelector("a").textContent = "Play";
    var open = function () { if (!document.hidden) location.href = "${game}"; };
    // The page stays alive behind the app, so the next tap on the icon shows it again without loading it.
    document.addEventListener("visibilitychange", open);
    open();
  }
</script>
</body>
</html>`;
    return new Response(page, { status: 200, headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" } });
  }),
});

export default http;
