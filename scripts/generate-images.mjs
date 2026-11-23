// Makes the character portraits and cutscene images with Runware.
// Run from the project folder:   node scripts/generate-images.mjs
//   --test         make only Ruby's portrait (a cheap check that the key works)
//   --only=<id>    make just one image, e.g. --only=arrest_sky
//   --redo         make images again even if the file already exists
// The key is read from the .env file. It never goes into the web page.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const OUT = path.join(ROOT, 'img');
const API = 'https://api.runware.ai/v1';
const MODEL = process.env.RUNWARE_MODEL || 'runware:101@1';   // FLUX.1 [dev]: follows style prompts closely

// ---------- 1. Read the key from .env ----------
function readKey() {
  const file = path.join(ROOT, '.env');
  if (!fs.existsSync(file)) throw new Error('No .env file in the project folder.');
  for (const raw of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    const m = raw.match(/^\s*RUNWARE_API_KEY\s*=\s*(.*)\s*$/);
    if (m) return m[1].replace(/^["']|["']$/g, '').trim();
  }
  return '';
}
const KEY = readKey();
if (!KEY) { console.error('RUNWARE_API_KEY in .env is empty. Paste your key after the = sign and save the file.'); process.exit(1); }

// ---------- 2. One shared art style + a fixed look for each character ----------
const STYLE = 'anime key visual, 1990s anime film style, clean cel shading, crisp line art, rich cinematic night lighting, '
            + 'detailed background, consistent character design, no text, no watermark, no logo';
const NEGATIVE = 'photo, photorealistic, 3d render, text, letters, watermark, logo, signature, extra fingers, deformed hands, blurry, gore, blood, gun, weapon';

const CREW = {
  ruby:  { name: 'Ruby',  seed: 1101, look: 'a calm woman in her thirties with a short black bob haircut, steady dark eyes, a thin scar through her left eyebrow, wearing a long dark red coat over a black turtleneck' },
  sky:   { name: 'Sky',   seed: 2202, look: 'a nervous young man in his twenties with messy light brown hair, wide worried eyes, wearing a blue racing jacket and fingerless black driving gloves' },
  sunny: { name: 'Sunny', seed: 3303, look: 'a smug young woman with long blond hair in a high ponytail, round glasses, wearing an oversized mustard yellow hoodie with headphones around her neck' },
  mint:  { name: 'Mint',  seed: 4404, look: 'a charming man in his thirties with neat dark green hair and an easy friendly smile, wearing a green suit jacket with an open collar white shirt' },
};
const crewLine = 'a four-person crew: ' + Object.values(CREW).map(c => `${c.name}, ${c.look}`).join('; ');

// ---------- 3. Everything we want to make ----------
const JOBS = [];
for (const [id, c] of Object.entries(CREW)) {
  JOBS.push({ id: `portrait_${id}`, dir: 'portraits', file: `${id}.jpg`, w: 512, h: 512, seed: c.seed,
    prompt: `${STYLE}. Head-and-shoulders character portrait of ${c.look}, looking at the viewer, plain deep teal background with soft rim light` });
}
const EXITS = {
  marin:   'racing across the Golden Gate Bridge at night in thick fog, huge international-orange bridge towers and cables overhead, glancing back over the shoulder',
  oakland: 'driving fast across the Bay Bridge at night, silver suspension cables and towers, Oakland city lights ahead, San Francisco skyline behind',
  openBay: 'steering a small speedboat across San Francisco Bay at night, sea spray, Alcatraz island with its lighthouse in the background',
};
for (const [id, c] of Object.entries(CREW)) {
  for (const [exit, scene] of Object.entries(EXITS)) {
    JOBS.push({ id: `escape_${id}_${exit}`, dir: 'cutscenes', file: `escape_${id}_${exit}.jpg`, w: 1024, h: 576, seed: c.seed + 10,
      prompt: `${STYLE}. Cinematic wide shot: ${c.look}, ${scene}, triumphant escape` });
  }
  JOBS.push({ id: `arrest_${id}`, dir: 'cutscenes', file: `arrest_${id}.jpg`, w: 1024, h: 576, seed: c.seed + 20,
    prompt: `${STYLE}. Cinematic wide shot: ${c.look}, caught by police on a San Francisco street at night, hands raised, `
          + 'police officers and a police car with flashing red and blue lights, the white Transamerica Pyramid towering in the background, dramatic' });
}
JOBS.push({ id: 'betrayal_tip', dir: 'cutscenes', file: 'betrayal_tip.jpg', w: 1024, h: 576, seed: 4430,
  prompt: `${STYLE}. Cinematic shot: ${CREW.mint.look}, secretly texting on a glowing phone in a narrow Chinatown alley at night, red paper lanterns, glancing over the shoulder, suspicious mood` });
JOBS.push({ id: 'betrayal_exposed', dir: 'cutscenes', file: 'betrayal_exposed.jpg', w: 1024, h: 576, seed: 4440,
  prompt: `${STYLE}. Cinematic dramatic shot on a pier at Fisherman's Wharf at night: ${CREW.mint.name}, ${CREW.mint.look}, holding a phone showing a message to the police, `
        + `cornered and caught, while ${CREW.ruby.name} in the dark red coat, ${CREW.sky.name} in the blue racing jacket and ${CREW.sunny.name} in the yellow hoodie stare in shock, betrayal` });
JOBS.push({ id: 'heist', dir: 'cutscenes', file: 'heist.jpg', w: 1024, h: 576, seed: 5550,
  prompt: `${STYLE}. Cinematic wide shot: ${crewLine}, rushing out of a classical stone bank with columns at night carrying duffel bags, `
        + 'the white Transamerica Pyramid right next to it, alarm light glowing red, exciting caper movie moment' });

// ---------- 4. Ask Runware for one image and save it ----------
async function generate(job) {
  const body = [{
    taskType: 'imageInference', taskUUID: crypto.randomUUID(), model: MODEL,
    positivePrompt: job.prompt, negativePrompt: NEGATIVE,
    width: job.w, height: job.h, seed: job.seed, numberResults: 1, includeCost: true,
  }];
  const res = await fetch(API, { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${KEY}` }, body: JSON.stringify(body) });
  const json = await res.json().catch(() => ({}));
  if (json.errors?.length || !json.data?.[0]?.imageURL) {
    const e = json.errors?.[0];
    throw new Error(e ? `${e.code}: ${e.message}${e.parameter ? ` (parameter: ${e.parameter})` : ''}` : `HTTP ${res.status}, no image returned`);
  }
  const { imageURL, cost } = json.data[0];
  const img = await fetch(imageURL);
  if (!img.ok) throw new Error(`Could not download the image (HTTP ${img.status})`);
  const dir = path.join(OUT, job.dir);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, job.file), Buffer.from(await img.arrayBuffer()));
  return cost ?? 0;
}

const args = process.argv.slice(2);
const only = args.find(a => a.startsWith('--only='))?.slice(7);
const redo = args.includes('--redo');
let todo = args.includes('--test') ? JOBS.slice(0, 1) : only ? JOBS.filter(j => j.id === only) : JOBS;
if (!todo.length) { console.error(`No image called "${only}". Names: ${JOBS.map(j => j.id).join(', ')}`); process.exit(1); }

let total = 0, made = 0, failed = 0;
for (const job of todo) {
  const file = path.join(OUT, job.dir, job.file);
  if (!redo && fs.existsSync(file)) { console.log(`skip   ${job.id} (already exists)`); continue; }
  try {
    const cost = await generate(job);
    total += cost; made++;
    console.log(`made   ${job.id}  -> img/${job.dir}/${job.file}${cost ? `  ($${cost.toFixed(4)})` : ''}`);
  } catch (e) {
    failed++;
    console.log(`FAILED ${job.id}: ${e.message}`);
    if (/apikey|auth/i.test(e.message)) break;   // a bad key fails every image: stop early
  }
}
console.log(`\nDone: ${made} made, ${failed} failed. Runware cost this run: $${total.toFixed(4)}`);
if (failed) process.exitCode = 1;
