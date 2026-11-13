import {Config} from '@remotion/cli/config';

// 本机用系统 Chrome（省掉下载 chrome-headless-shell）；换机器可删掉这一行让 Remotion 自己下载
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
try { Config.setBrowserExecutable(CHROME); } catch (e) { /* 旧版本没有这个 API 时忽略 */ }
Config.setEntryPoint('remotion/index.ts');
Config.setVideoImageFormat('jpeg');
Config.setJpegQuality(95);
Config.setOverwriteOutput(true);
Config.setConcurrency(2);          // 16G 机器：每个标签页都要预烘纸纹/调色板，2 个够
Config.setChromiumOpenGlRenderer('angle');
// 关掉 webpack 缓存：单次渲染只快 0–2 秒，却会在 node_modules/.cache 里堆 200–350MB
if ('setWebpackCaching' in Config && typeof Config.setWebpackCaching === 'function') {
  Config.setWebpackCaching(false);
}
