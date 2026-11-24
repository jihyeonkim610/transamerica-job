// A tiny local web server for previewing the page on this computer.
// Run:  node scripts/serve.mjs     then open http://localhost:8124
// It only serves files from this project folder and never sends out the .env file.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const PORT = Number(process.env.PORT) || 8124;
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.mjs': 'text/javascript', '.css': 'text/css',
                '.jpg': 'image/jpeg', '.png': 'image/png', '.webp': 'image/webp', '.json': 'application/json', '.csv': 'text/csv',
                '.mp4': 'video/mp4' };

// Run logs saved from the page on this computer land in data/demo-runs/ (demo runs, no AI).
// Real AI runs from claude.ai go in data/runs/ (update-trust.ps1 moves them there from Downloads).
function saveRun(req, res) {
  const name = String(req.headers['x-filename'] || '');
  if (!/^transamerica-job-[\w-]{1,40}\.csv$/.test(name)) { res.writeHead(400); return res.end('Bad file name'); }
  const chunks = []; let size = 0;
  req.on('data', c => { size += c.length; if (size > 5e6) req.destroy(); else chunks.push(c); });
  req.on('end', () => {
    const dir = path.join(ROOT, 'data', 'demo-runs');
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, name), Buffer.concat(chunks));
    res.writeHead(200, { 'Content-Type': 'text/plain' }); res.end('saved');
  });
}

http.createServer((req, res) => {
  const urlPath = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  if (req.method === 'POST' && urlPath === '/api/save-run') return saveRun(req, res);
  const file = path.join(ROOT, urlPath === '/' ? 'index.html' : urlPath);
  const name = path.basename(file);
  if (!file.startsWith(ROOT + path.sep) || name.startsWith('.') || !TYPES[path.extname(file)]) { res.writeHead(404); return res.end('Not found'); }
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404); return res.end('Not found'); }
    res.writeHead(200, { 'Content-Type': TYPES[path.extname(file)] });
    res.end(data);
  });
}).listen(PORT, '127.0.0.1', () => console.log(`Preview: http://localhost:${PORT}`));
