// stage.mjs —— 把一个 music-mv 工程搬进 Remotion：
//   node remotion/stage.mjs --proj <项目目录> [--song <歌.mp3>] [--skill <skill根>]
// 产出：remotion/public/proj/{cfg.js,engine.js,character.js,lyrics.js,shots/NN.js,song.mp3}
//       remotion/project.gen.json（Root.tsx 直接 import）
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const get = (k, d) => { const i = args.indexOf('--' + k); return i >= 0 ? args[i + 1] : d; };
const proj = get('proj');
const song = get('song', '');
if (!proj) { console.error('用法：node remotion/stage.mjs --proj <项目目录> [--song <歌>]'); process.exit(2); }

const html = fs.readFileSync(path.join(proj, 'index.html'), 'utf8');
const clean = html.replace(/<!--[\s\S]*?-->/g, '');

// 1) CFG：模板里是字面量对象（可能带 /regex/.test(location.search)），用括号配对抠出来再求值
const at = clean.indexOf('window.CFG');
if (at < 0) { console.error('index.html 里找不到 window.CFG = {...};'); process.exit(1); }
const b0 = clean.indexOf('{', at);
let depth = 0, b1 = -1;
for (let i = b0; i < clean.length; i++) {
  const ch = clean[i];
  if (ch === '{') depth++;
  else if (ch === '}') { depth--; if (depth === 0) { b1 = i; break; } }
}
if (b1 < 0) { console.error('window.CFG 的大括号没闭合'); process.exit(1); }
let CFG;
try { CFG = new Function('location', 'return (' + clean.slice(b0, b1 + 1) + ')')({search: ''}); }
catch (e) { console.error('CFG 求值失败：' + e.message); process.exit(1); }
for (const k of ['W', 'H', 'FPS', 'DURATION', 'BPM']) {
  if (typeof CFG[k] !== 'number') { console.error('CFG.' + k + ' 不是数字'); process.exit(1); }
}
const OW = CFG.OUT ? CFG.OUT.w : CFG.W, OH = CFG.OUT ? CFG.OUT.h : CFG.H;

// 2) 脚本：按 index.html 里的顺序，规范化到 proj/ 下
const srcs = [...clean.matchAll(/<script\b[^>]*?\bsrc="([^"]+)"/g)].map(x => x[1])
  .filter(s => !/^https?:/.test(s));
const staged = [];
const outDir = path.join(here, '..', 'public', 'proj');   // <skill>/public/proj —— Remotion 的 publicDir 默认就是它
fs.rmSync(outDir, {recursive: true, force: true});
fs.mkdirSync(path.join(outDir, 'shots'), {recursive: true});
for (const s of srcs) {
  const abs = path.resolve(proj, s);
  if (!fs.existsSync(abs)) { console.error(`index.html 列的脚本不存在：${s}`); process.exit(1); }
  const base = path.basename(abs);
  const rel = /shots[\\/]/.test(s) || /^\d/.test(base) ? 'shots/' + base : base;
  fs.mkdirSync(path.dirname(path.join(outDir, rel)), {recursive: true});
  fs.copyFileSync(abs, path.join(outDir, rel));
  staged.push(rel);
}
fs.writeFileSync(path.join(outDir, 'cfg.js'), 'window.CFG = ' + JSON.stringify(CFG, null, 2) + ';\n');

// 3) 音频
let stagedSong = '';
if (song) {
  if (!fs.existsSync(song)) { console.error('歌不存在：' + song); process.exit(1); }
  fs.copyFileSync(song, path.join(outDir, 'song' + path.extname(song).toLowerCase()));
  stagedSong = 'proj/song' + path.extname(song).toLowerCase();
}

// 4) 给 Root.tsx 的清单
const gen = {
  name: path.basename(path.resolve(proj)),
  ow: OW, oh: OH, w: CFG.W, h: CFG.H,
  fps: CFG.FPS, duration: CFG.DURATION, bpm: CFG.BPM,
  scripts: ['cfg.js', ...staged],
  song: stagedSong,
};
fs.writeFileSync(path.join(here, 'project.gen.json'), JSON.stringify(gen, null, 2));
console.log(`STAGE OK  ${gen.name}  ${OW}x${OH}  ${gen.fps}fps  ${gen.duration}s  ${gen.scripts.length} 个脚本  ${stagedSong || '(无声)'}`);
