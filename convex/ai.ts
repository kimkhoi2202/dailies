import { v } from "convex/values";
import OpenAI from "openai";
import { internal } from "./_generated/api";
import { internalAction } from "./_generated/server";

// The studio's voice: an OpenAI model that designs a game with a maker, one short exchange at a
// time. It asks the questions that matter, offers ideas when the maker has none, and fills in the
// design sheet a little more with every reply. The key lives in the Convex environment as
// OPENAI_API_KEY. Nothing is built from the sheet.

const MODEL = "gpt-6-luna";

const INSTRUCTIONS = `You are the studio inside DEGEN, a phone app where people play small games for a minute or two at a time. A maker is talking to you to design a game of their own. Your job is to turn whatever they bring, from a single word to a full idea, into a clear, detailed design for a small phone game, and to keep a design sheet that fills in as you go.

The sheet has these parts: title, pitch (one line), genre, setting (where and when, the mood), player (who or what the player controls), goal (what a round is trying to do and how it ends), controls (what a finger does on a phone, one hand, portrait), rules (three to six short lines about how it plays: what happens, what hurts, what helps), scoring (what the score counts and what makes it go up), progression (how it gets harder or changes over a round, and what brings players back), look (colours, shapes, style, in a few words), sound (a line or two), tint (six hex digits for the game's main colour, no leading #).

How to talk:
- Short plain sentences. Warm, never gushing. No exclamation marks, no emoji, no long dashes.
- Never use the words win, prize, reward, cash, payout, bonus, bet, wager, jackpot, spin, lucky, token or mint.
- One question per reply, about the part of the sheet that matters most next. Give three or four tappable answers for it, and make them concrete and different from each other. Each answer at most 32 characters.
- When the maker asks to be surprised, or brings nothing concrete, ask one question about the feel they want (with answers), and after that offer three ideas: a title and a one line pitch each, all different in kind.
- Build on what they said. Reflect their words back in the sheet. Never replace a part they settled unless they ask.
- Do not ask about a part that is already settled. Once title, player, goal, controls, rules and scoring are all settled, say the sheet looks complete and ask whether to finish or keep tuning (answers: "Finish the sheet", "Make it harder", "Change the look", "Add a twist"). Do not finish on your own.
- If a wish is violent, cruel or about real people, keep the playful part and drop the rest, and say what you changed in a few words.
- When the maker asks for different ideas or other answers, give fresh ones.
- When asked to finish ("That is the game. Write the full sheet."), fill every part of the sheet, with rules of five or six lines, and set done to true. The reply then is one line that sums the game up.

Answer with JSON only, in this shape:
{"reply": string, "options": string[], "ideas": [{"title": string, "pitch": string}], "design": {"title": string, "pitch": string, "genre": string, "setting": string, "player": string, "goal": string, "controls": string, "rules": string[], "scoring": string, "progression": string, "look": string, "sound": string, "tint": string}, "progress": number, "done": boolean}

- reply: what you say to the maker, one to three short sentences, ending with the question when there is one.
- options: the tappable answers to the question, else an empty list. Never options and ideas in the same answer.
- ideas: up to three ideas, else an empty list. Title at most 24 characters, pitch at most 60.
- design: the whole sheet as you now understand it. Every string is a short plain sentence or phrase; leave a part as an empty string (or an empty list for rules) until it is settled. Title at most 24 characters, pitch at most 60, every other string at most 160, each rule at most 90.
- progress: 0 to 1, how much of the sheet is settled.
- done: true only when asked to finish.`;

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
    design: {
      type: "object",
      additionalProperties: false,
      properties: {
        title: { type: "string" },
        pitch: { type: "string" },
        genre: { type: "string" },
        setting: { type: "string" },
        player: { type: "string" },
        goal: { type: "string" },
        controls: { type: "string" },
        rules: { type: "array", items: { type: "string" } },
        scoring: { type: "string" },
        progression: { type: "string" },
        look: { type: "string" },
        sound: { type: "string" },
        tint: { type: "string" },
      },
      required: ["title", "pitch", "genre", "setting", "player", "goal", "controls", "rules", "scoring", "progression", "look", "sound", "tint"],
    },
    progress: { type: "number" },
    done: { type: "boolean" },
  },
  required: ["reply", "options", "ideas", "design", "progress", "done"],
} as const;

type Sheet = {
  title: string; pitch: string; genre: string; setting: string; player: string; goal: string; controls: string;
  rules: string[]; scoring: string; progression: string; look: string; sound: string; tint: string;
};

type StudioAnswer = {
  reply: string;
  options: string[];
  ideas: { title: string; pitch: string }[];
  design: Sheet;
  progress: number;
  done: boolean;
};

const cut = (text: string, max: number) => text.trim().replace(/\s+/g, " ").slice(0, max);

export const replyToCreation = internalAction({
  args: { creationId: v.id("creations"), finish: v.boolean() },
  handler: async (ctx, args) => {
    const context = await ctx.runQuery(internal.creations.context, { creationId: args.creationId });
    if (context === null) return null;
    try {
      const openai = new OpenAI();
      const sheet = context.creation.design ? JSON.stringify(context.creation.design) : "nothing settled yet";
      const input = context.messages.map((message) => ({
        role: message.role === "maker" ? ("user" as const) : ("assistant" as const),
        content:
          message.role === "studio"
            ? JSON.stringify({ reply: message.text, options: message.options, ideas: message.ideas })
            : message.text,
      }));
      const response = await openai.responses.create({
        model: MODEL,
        instructions:
          INSTRUCTIONS +
          `\n\nThe maker's name is ${context.handle}. The sheet so far: ${sheet}.` +
          (args.finish ? " The maker has asked to finish: fill every part of the sheet and set done to true." : ""),
        input,
        text: { format: { type: "json_schema", name: "studio_answer", schema: SHAPE, strict: true } },
      });
      const answer = JSON.parse(response.output_text) as StudioAnswer;
      const options = answer.options.map((o) => cut(o, 32)).filter((o) => o.length > 0).slice(0, 4);
      const ideas = answer.ideas
        .map((idea) => ({ title: cut(idea.title, 24), pitch: cut(idea.pitch, 60) }))
        .filter((idea) => idea.title.length > 0)
        .slice(0, 3);
      const d = answer.design;
      const tint = d.tint.replace("#", "").toUpperCase();
      await ctx.runMutation(internal.creations.reply, {
        creationId: args.creationId,
        text: cut(answer.reply, 400) || "Tell me more.",
        options: options.length > 0 && ideas.length === 0 ? options : undefined,
        ideas: ideas.length > 0 ? ideas : undefined,
        design: {
          title: cut(d.title, 24),
          pitch: cut(d.pitch, 60),
          genre: cut(d.genre, 40),
          setting: cut(d.setting, 160),
          player: cut(d.player, 160),
          goal: cut(d.goal, 160),
          controls: cut(d.controls, 160),
          rules: d.rules.map((rule) => cut(rule, 90)).filter((rule) => rule.length > 0).slice(0, 6),
          scoring: cut(d.scoring, 160),
          progression: cut(d.progression, 160),
          look: cut(d.look, 160),
          sound: cut(d.sound, 160),
          tint: /^[0-9A-F]{6}$/.test(tint) ? tint : undefined,
        },
        progress: typeof answer.progress === "number" ? answer.progress : 0,
        done: args.finish && answer.done,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      console.error("studio reply failed", message);
      await ctx.runMutation(internal.creations.fail, { creationId: args.creationId, error: message });
    }
    return null;
  },
});
