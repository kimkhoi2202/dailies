#!/usr/bin/env node
// Takes the recording controls out of clips that were filmed with them in the picture: the gold stop key
// with its ring, and the clock with its red dot. The pixels behind them were never recorded, so each spot
// is filled in from the picture around it.
//
//   node scripts/clean-clips.mjs            cleans every clip into the work folder and changes nothing
//   node scripts/clean-clips.mjs --apply    also uploads each cleaned file and points its clip at it
//
// A clip without the stop key in it is left alone, so the script can be run again at any time.
// Needs ffmpeg, and the Convex CLI signed in to the deployment (CONVEX_DEPLOY_KEY or .env.local).

import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const apply = process.argv.includes("--apply");
const work = join(process.env.CLEAN_CLIPS_DIR ?? tmpdir(), "clean-clips");
mkdirSync(work, { recursive: true });

const run = (command, args, options = {}) => execFileSync(command, args, { maxBuffer: 1 << 28, ...options });
const convex = (name, args = {}) => JSON.parse(run("npx", ["convex", "run", name, JSON.stringify(args)], { encoding: "utf8" }));

function probe(file) {
  const out = run("ffprobe", ["-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height:format=duration",
                              "-of", "json", file], { encoding: "utf8" });
  const { streams, format } = JSON.parse(out);
  return { w: streams[0].width, h: streams[0].height, seconds: Number(format.duration) };
}

/** Eight frames from across the clip, as RGB bytes. */
function frames(file, { w, h, seconds }) {
  const out = [];
  for (let i = 0; i < 8; i++) {
    const at = seconds * (0.15 + (0.8 * i) / 7);
    const frame = run("ffmpeg", ["-v", "error", "-ss", at.toFixed(3), "-i", file, "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"]);
    if (frame.length === w * h * 3) out.push(frame);
  }
  return out;
}

/** The blobs of pixels that pass `test` in most of the frames, inside a part of the picture. */
function blobs(shots, w, { x0, x1, y0, y1 }, test) {
  const need = Math.ceil(shots.length * 0.75);
  const on = new Uint8Array(w * y1);
  for (let y = y0; y < y1; y++) {
    for (let x = x0; x < x1; x++) {
      let hits = 0;
      for (const shot of shots) {
        const i = (y * w + x) * 3;
        if (test(shot[i], shot[i + 1], shot[i + 2])) hits++;
      }
      if (hits >= need) on[y * w + x] = 1;
    }
  }
  const found = [];
  for (let start = y0 * w; start < y1 * w; start++) {
    if (on[start] !== 1) continue;
    const blob = { minX: w, maxX: 0, minY: y1, maxY: 0, count: 0 };
    const stack = [start];
    on[start] = 2;
    while (stack.length > 0) {
      const at = stack.pop();
      const x = at % w, y = (at - x) / w;
      blob.count++;
      blob.minX = Math.min(blob.minX, x); blob.maxX = Math.max(blob.maxX, x);
      blob.minY = Math.min(blob.minY, y); blob.maxY = Math.max(blob.maxY, y);
      for (const next of [at - 1, at + 1, at - w, at + w]) {
        if (next >= 0 && next < on.length && on[next] === 1) { on[next] = 2; stack.push(next); }
      }
    }
    blob.w = blob.maxX - blob.minX + 1;
    blob.h = blob.maxY - blob.minY + 1;
    blob.fill = blob.count / (blob.w * blob.h);
    found.push(blob);
  }
  return found;
}

/** The gold stop square: a filled square, centred, in the lower part of the picture. nil when the clip has none. */
function findStop(shots, w, h) {
  const gold = (r, g, b) => r > 225 && g > 150 && g < 220 && b < 95;
  const squares = blobs(shots, w, { x0: Math.round(w * 0.3), x1: Math.round(w * 0.7), y0: Math.round(h * 0.55), y1: h }, gold)
    .filter((b) => b.w > w * 0.03 && b.w < w * 0.12 && b.w / b.h > 0.85 && b.w / b.h < 1.18 && b.fill > 0.85
      && Math.abs((b.minX + b.maxX + 1) / 2 - w / 2) < w * 0.03);
  return squares.length === 1 ? squares[0] : null;
}

/** The clock's red dot: a filled circle left of centre near the top. nil when the clip shows no clock. */
function findDot(shots, w, h) {
  const red = (r, g, b) => r > 215 && g > 60 && g < 150 && b > 40 && b < 130 && r - g > 90;
  const dots = blobs(shots, w, { x0: Math.round(w * 0.3), x1: Math.round(w * 0.5), y0: 0, y1: Math.round(h * 0.2) }, red)
    .filter((b) => b.w > w * 0.012 && b.w < w * 0.04 && b.w / b.h > 0.8 && b.w / b.h < 1.25 && b.fill > 0.62 && b.fill < 0.9);
  return dots.length === 1 ? dots[0] : null;
}

/** A picture the size of the video, white where the controls are. The ring is 92 points across for a 34 point square. */
function mask(file, w, h, stop, dot) {
  // A few pixels past each shape, for its soft edge. The ring's edge is softer and its place is less exact.
  const edge = 3, rim = 7;
  const cx = (stop.minX + stop.maxX + 1) / 2, cy = (stop.minY + stop.maxY + 1) / 2;
  const half = stop.w / 2 + edge;
  const outer = (stop.w * 46) / 34 + rim, inner = (stop.w * 41) / 34 - rim;
  let pill = null;
  if (dot !== null) {
    const y = (dot.minY + dot.maxY + 1) / 2, r = dot.w * 1.7 + edge;
    pill = { y, r, reach: w / 2 - dot.minX + dot.w * 1.35 + edge - r };
  }
  const bytes = Buffer.alloc(w * h);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const far = Math.hypot(x + 0.5 - cx, y + 0.5 - cy);
      let on = (far <= outer && far >= inner) || (Math.abs(x + 0.5 - cx) <= half && Math.abs(y + 0.5 - cy) <= half);
      if (!on && pill !== null) {
        const along = Math.max(0, Math.abs(x + 0.5 - w / 2) - pill.reach);
        on = Math.hypot(along, y + 0.5 - pill.y) <= pill.r;
      }
      if (on) bytes[y * w + x] = 255;
    }
  }
  writeFileSync(file, Buffer.concat([Buffer.from(`P5\n${w} ${h}\n255\n`), bytes]));
}

function clean(source, target, maskFile) {
  run("ffmpeg", ["-v", "error", "-y", "-i", source, "-map", "0:v:0", "-map", "0:a?", "-vf", `removelogo=${maskFile}`,
                 "-fps_mode", "passthrough", "-c:v", "libx264", "-crf", "18", "-preset", "medium", "-pix_fmt", "yuv420p",
                 "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709",
                 "-c:a", "copy", "-movflags", "+faststart", target]);
}

const clips = [];
for (let cursor = null, done = false; !done;) {
  const result = convex("clipRepair:videos", { paginationOpts: { numItems: 50, cursor } });
  clips.push(...result.page);
  cursor = result.continueCursor;
  done = result.isDone;
}
console.log(`${clips.length} clips hold a video`);

for (const clip of clips) {
  const source = join(work, `${clip.clipId}.mp4`), target = join(work, `${clip.clipId}-clean.mp4`);
  writeFileSync(source, Buffer.from(await (await fetch(clip.url)).arrayBuffer()));
  const size = probe(source);
  const shots = frames(source, size);
  const stop = shots.length > 0 ? findStop(shots, size.w, size.h) : null;
  if (stop === null) {
    console.log(`${clip.clipId}  no stop key in it, left alone`);
    continue;
  }
  const dot = findDot(shots, size.w, size.h);
  const maskFile = join(work, `${clip.clipId}-mask.pgm`);
  mask(maskFile, size.w, size.h, stop, dot);
  clean(source, target, maskFile);

  const after = probe(target);
  const still = findStop(frames(target, after), after.w, after.h);
  if (still !== null || Math.abs(after.seconds - size.seconds) > 0.1) {
    console.log(`${clip.clipId}  the cleaned file did not check out, left alone`);
    continue;
  }
  const what = dot === null ? "stop key" : "stop key and clock";
  if (!apply) {
    console.log(`${clip.clipId}  ${what} filled in, written to ${target}`);
    continue;
  }
  const sent = await fetch(convex("clipRepair:uploadUrl"), { method: "POST", headers: { "Content-Type": "video/mp4" }, body: readFileSync(target) });
  if (!sent.ok) throw new Error(`Upload failed for ${clip.clipId}: ${sent.status}`);
  const { storageId } = await sent.json();
  const swapped = convex("clipRepair:swap", { clipId: clip.clipId, from: clip.storageId, to: storageId });
  console.log(`${clip.clipId}  ${what} filled in, ${swapped ? "clip updated" : "clip changed meanwhile, left alone"}`);
}
