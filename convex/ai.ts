import { v } from "convex/values";
import OpenAI from "openai";
import { internal } from "./_generated/api";
import { internalAction } from "./_generated/server";

// The studio's voice: an OpenAI model that turns a maker's wish into a game. It asks until it has
// enough, offers ideas when asked to inspire, and then hands back a design the app assembles on
// one of the built-in engines. The key lives in the Convex environment as OPENAI_API_KEY.

const MODEL = "gpt-6-luna";

const ENGINES = `
- tippyTower: a stacking game. Tap to drop a sliding slab on the tower; overhang is cut off. Score counts floors. Good for: stacking, building, timing, towers, pancakes, boxes.
- spiralDrop: a ball falls through a spinning tower of ringed platforms with gaps. Drag to spin. Avoid red. Score counts points. Good for: falling, helix, descending, bouncing.
- laneDash: a three lane runner. Swipe between lanes to dodge things and pick things up. Score counts metres. Good for: running, racing, dodging, chasing, driving, dashing, slashing through a crowd.
- gulpCity: a hole eats a city. Drag to move the hole; it grows as it eats. Score counts percent eaten. Good for: eating, growing, swallowing, collecting, cleaning up, absorbing.
- inkland: claim land by drawing loops on a shared field against other players. Score counts percent owned. Good for: territory, painting, drawing, area control, multiplayer.
- fiveUp: guess a five letter word in six tries with coloured hints. Score counts points. Good for: words, spelling, trivia, quiz, guessing.`;

const INSTRUCTIONS = `You are the studio in Dailies, a feed of small phone games played for a minute or two at a time. A maker talks to you to create a game. Every game you design plays on one of six built-in engines, so your job is to shape the maker's wish into a theme, a title and a short design that fits one engine.

Engines:${ENGINES}

How to talk:
- Short plain sentences. Friendly, never gushing. No exclamation marks, no emoji, no long dashes.
- Never use the words win, prize, reward, cash, payout, bonus, bet, wager, jackpot, spin, lucky, token or mint.
- If the maker asks to be inspired or gives nothing concrete, ask one question with three or four short options (a mood, a setting, a kind of play). After at most one such question, offer three ideas with a title and a one line pitch each.
- If the maker picks an idea or describes a game clearly enough to place on an engine, build it at once. Do not ask more than two questions in a whole conversation. A maker who repeats themselves or says "just make it" gets a build.
- If a wish is violent, cruel or about real people, keep the playful part and drop the rest. A game about stabbing characters becomes dodging or bopping them. Never refuse outright; reshape.
- When the maker asks for more options or more ideas, give fresh ones.

Answer with JSON only, in this shape:
{"reply": string, "options": string[], "ideas": [{"title": string, "pitch": string}], "build": null | {"title": string, "pitch": string, "how": string, "category": string, "kind": string, "tint": string, "unit": string}}

- reply: what you say to the maker, one to three short sentences. When building, say which engine idea it became in a few words, as in "Building Pancake Pile. It stacks like Tippy Tower, with pancakes."
- options: up to four short choices the maker can tap, else an empty list. Never give options and ideas in the same answer.
- ideas: up to three ideas with a title (at most 24 characters) and a pitch (at most 60 characters), else an empty list.
- build: null until the game is settled. Then: title at most 24 characters, pitch at most 60 characters, how at most 240 characters of plain instructions in the voice of the app ("Tap to drop. Line it up for a perfect."), category one of Arcade, Puzzle, Word, Runner, Casual, Multiplayer, Sport, kind one of tippyTower, spiralDrop, laneDash, gulpCity, inkland, fiveUp, tint six hex digits for the game's main colour without a leading #, unit the word the score counts in lower case (floors, points, m, %, tries).`;

const SHAPE = {
  type: "object",
  additionalProperties: false,
  properties: {
    reply: { type: "string" },
    options: { type: "array", items: { type: "string" } },
    ideas: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        properties: { title: { type: "string" }, pitch: { type: "string" } },
        required: ["title", "pitch"],
      },
    },
    build: {
      anyOf: [
        { type: "null" },
        {
          type: "object",
          additionalProperties: false,
          properties: {
            title: { type: "string" },
            pitch: { type: "string" },
            how: { type: "string" },
            category: { type: "string" },
            kind: { type: "string" },
            tint: { type: "string" },
            unit: { type: "string" },
          },
          required: ["title", "pitch", "how", "category", "kind", "tint", "unit"],
        },
      ],
    },
  },
  required: ["reply", "options", "ideas", "build"],
} as const;

type StudioAnswer = {
  reply: string;
  options: string[];
  ideas: { title: string; pitch: string }[];
  build: null | { title: string; pitch: string; how: string; category: string; kind: string; tint: string; unit: string };
};

export const replyToCreation = internalAction({
  args: { creationId: v.id("creations") },
  handler: async (ctx, args) => {
    const context = await ctx.runQuery(internal.creations.context, { creationId: args.creationId });
    if (context === null) return null;
    try {
      // The client reads OPENAI_API_KEY itself and throws a clear error when it is missing.
      const openai = new OpenAI();
      const input = context.messages.map((message) => ({
        role: message.role === "maker" ? ("user" as const) : ("assistant" as const),
        content:
          message.role === "studio"
            ? JSON.stringify({ reply: message.text, options: message.options, ideas: message.ideas, build: null })
            : message.text,
      }));
      const response = await openai.responses.create({
        model: MODEL,
        instructions: INSTRUCTIONS + `\n\nThe maker's name is ${context.handle}.`,
        input,
        text: { format: { type: "json_schema", name: "studio_answer", schema: SHAPE, strict: true } },
      });
      const answer = JSON.parse(response.output_text) as StudioAnswer;
      const options = answer.options.map((o) => o.trim()).filter((o) => o.length > 0).slice(0, 4);
      const ideas = answer.ideas
        .map((idea) => ({ title: idea.title.trim().slice(0, 24), pitch: idea.pitch.trim().slice(0, 60) }))
        .filter((idea) => idea.title.length > 0)
        .slice(0, 3);
      await ctx.runMutation(internal.creations.reply, {
        creationId: args.creationId,
        text: answer.reply.trim() || "Tell me more.",
        options: options.length > 0 && ideas.length === 0 ? options : undefined,
        ideas: ideas.length > 0 ? ideas : undefined,
        build: answer.build ?? undefined,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      console.error("studio reply failed", message);
      await ctx.runMutation(internal.creations.fail, { creationId: args.creationId, error: message });
    }
    return null;
  },
});
