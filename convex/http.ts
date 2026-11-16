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

export default http;
