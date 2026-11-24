// Turns each cutscene still into a 10-second story video with Runware (image-to-video).
// Run from the project folder:   node scripts/generate-videos.mjs
//   --test         make only the heist video (check the key and the cost first)
//   --only=<name>  make one video, e.g. --only=arrest_sky
//   --redo         make videos again even if the file already exists
// Videos land in video/<name>.mp4. The key is read from .env and never goes into the page.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const API = 'https://api.runware.ai/v1';
const MODEL = process.env.RUNWARE_VIDEO_MODEL || 'lightricks:ltx@2.3-fast';
const STILLS = path.join(ROOT, 'img', 'cutscenes');
const OUT = path.join(ROOT, 'video');
const PARALLEL = 4;

function readKey() {
  for (const raw of fs.readFileSync(path.join(ROOT, '.env'), 'utf8').split(/\r?\n/)) {
    const m = raw.match(/^\s*RUNWARE_API_KEY\s*=\s*(.*)\s*$/);
    if (m) return m[1].replace(/^["']|["']$/g, '').trim();
  }
  return '';
}
const KEY = readKey();
if (!KEY) { console.error('RUNWARE_API_KEY in .env is empty.'); process.exit(1); }

// What should move in each clip (the still already fixes the look of the characters)
const BASE = 'Anime film shot, 1990s cel animation look, smooth natural motion, slow cinematic camera push-in, '
           + 'hair and coats moving in the night wind, city lights flickering. Keep exactly the same characters for the whole shot: '
           + 'same faces, hair, outfits and colors, no new people appear, nobody turns into someone else, no text';
function motionFor(name) {
  if (name.startsWith('escape_') && name.endsWith('_marin')) return 'racing across the Golden Gate Bridge through drifting fog, bridge cables rushing past, escape';
  if (name.startsWith('escape_') && name.endsWith('_oakland')) return 'driving fast across the Bay Bridge, lights streaking past, escape';
  if (name.startsWith('escape_') && name.endsWith('_openBay')) return 'speedboat bouncing over the waves, sea spray, the Alcatraz lighthouse beam sweeping, escape';
  if (name.startsWith('arrest_')) return 'police officers step closer, red and blue lights pulse, the character slowly raises both hands';
  if (name.startsWith('place_')) return 'establishing shot with a slow camera pan, fog drifting, lights flickering, water and traffic moving gently, no people appear';
  return {
    heist: 'the crew runs out of the bank carrying duffel bags, alarm light flashing red',
    betrayal_tip: 'nervous thumbs typing a message on the glowing phone, glancing over the shoulder, lanterns swaying',
    betrayal_exposed: 'the crew turns toward Mint in shock, Mint steps back holding the phone',
    arc_planning: 'fingers trace routes on the map, the lamp flickers, the crew exchanges looks',
    arc_scouting: 'they watch the bank, a security guard walks past, cars drive by',
    arc_prep: 'code scrolls on the laptop, the driver drums on the wheel, headlights pass',
    arc_chase: 'the getaway car swerves down the hill, police cars follow with sirens flashing',
    arc_split: 'the crew turns and runs in different directions into the fog',
    arc_distrust: 'rain falls, the leader steps forward accusing, the others back away',
  }[name] || 'subtle movement, tension';
}

async function call(tasks) {
  const res = await fetch(API, { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${KEY}` }, body: JSON.stringify(tasks) });
  const json = await res.json().catch(() => ({}));
  if (json.errors?.length) { const e = json.errors[0]; throw new Error(`${e.code}: ${e.message}${e.parameter ? ` (${e.parameter})` : ''}`); }
  return json.data || [];
}
const sleep = ms => new Promise(r => setTimeout(r, ms));

async function makeVideo(name) {
  // 1. upload the still so Runware can use it as the first frame
  const dataUri = 'data:image/jpeg;base64,' + fs.readFileSync(path.join(STILLS, `${name}.jpg`)).toString('base64');
  const [up] = await call([{ taskType: 'mediaStorage', taskUUID: crypto.randomUUID(), operation: 'upload', media: dataUri }]);
  if (!up?.mediaUUID) throw new Error('upload returned no mediaUUID');
  // 2. start the video (it runs in the background on Runware)
  const taskUUID = crypto.randomUUID();
  await call([{ taskType: 'videoInference', taskUUID, model: MODEL, positivePrompt: `${BASE}. ${motionFor(name)}`,
                width: 1024, height: 576, duration: 10, fps: 24,
                // The still is both the first and the last frame, so the characters can't drift away from their designs
                inputs: { frameImages: [{ image: up.mediaUUID, frame: 'first' }, { image: up.mediaUUID, frame: 'last' }] },
                deliveryMethod: 'async', outputFormat: 'MP4', includeCost: true }]);
  // 3. check every few seconds until it is ready (up to 8 minutes)
  for (let i = 0; i < 96; i++) {
    await sleep(i < 2 ? 15000 : 5000);
    const [r] = await call([{ taskType: 'getResponse', taskUUID }]);
    if (r?.status === 'success' && r.videoURL) {
      const v = await fetch(r.videoURL);
      if (!v.ok) throw new Error(`download failed (HTTP ${v.status})`);
      // keep the full-size original in video/raw, and put a web-friendly copy in video/ (needs ffmpeg)
      const raw = path.join(OUT, 'raw', `${name}.mp4`);
      fs.mkdirSync(path.dirname(raw), { recursive: true });
      fs.writeFileSync(raw, Buffer.from(await v.arrayBuffer()));
      const { execFileSync } = await import('node:child_process');
      execFileSync('ffmpeg', ['-v', 'error', '-y', '-i', raw, '-c:v', 'libx264', '-crf', '20', '-preset', 'slow', '-tune', 'animation',
                              '-pix_fmt', 'yuv420p', '-an', '-movflags', '+faststart', path.join(OUT, `${name}.mp4`)]);
      return r.cost ?? 0;
    }
    if (r?.status === 'error') throw new Error('Runware reported an error for this video');
  }
  throw new Error('timed out after 8 minutes');
}

const args = process.argv.slice(2);
const only = args.find(a => a.startsWith('--only='))?.slice(7);
const redo = args.includes('--redo');
let names = fs.readdirSync(STILLS).filter(f => f.endsWith('.jpg')).map(f => f.slice(0, -4)).sort();
if (args.includes('--test')) names = ['heist'];
else if (only) names = names.filter(n => n === only);
if (!redo) names = names.filter(n => !fs.existsSync(path.join(OUT, `${n}.mp4`)));
console.log(`Making ${names.length} video(s) with ${MODEL}, ${PARALLEL} at a time...`);

let total = 0, made = 0, failed = 0;
const queue = [...names];
await Promise.all(Array.from({ length: PARALLEL }, async () => {
  while (queue.length) {
    const name = queue.shift();
    const t0 = Date.now();
    try {
      const cost = await makeVideo(name);
      total += cost; made++;
      const mb = (fs.statSync(path.join(OUT, `${name}.mp4`)).size / 1e6).toFixed(1);
      console.log(`made   ${name}.mp4  (${mb} MB, ${Math.round((Date.now() - t0) / 1000)}s${cost ? `, $${cost.toFixed(3)}` : ''})`);
    } catch (e) {
      failed++;
      console.log(`FAILED ${name}: ${e.message}`);
    }
  }
}));
console.log(`\nDone: ${made} made, ${failed} failed. Runware cost this run: $${total.toFixed(3)}`);
if (failed) process.exitCode = 1;
