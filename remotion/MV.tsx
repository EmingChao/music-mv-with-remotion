import React, {useEffect, useLayoutEffect, useState} from 'react';
import {AbsoluteFill, Audio, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import proj from './project.gen.json';

// ── 脚本加载：每个 src 只加载一次，顺序即依赖顺序（cfg → engine → character → lyrics → shots → assemble）
const cache: Record<string, Promise<void>> = {};
function loadScript(src: string) {
  if (!cache[src]) {
    cache[src] = new Promise<void>((res, rej) => {
      const s = document.createElement('script');
      s.src = src;
      s.async = false;
      s.onload = () => res();
      s.onerror = () => rej(new Error('脚本加载失败：' + src));
      document.head.appendChild(s);
    });
  }
  return cache[src];
}

/**
 * Remotion 只当"时钟 + 音轨 + 预览器"：每帧把 t 递给 assemble.js 的 drawFrame(t)，
 * 画面仍然由 canvas 逐帧画出来。引擎/镜头脚本一行都不用改。
 */
export const MV: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const t = frame / fps;
  const [ready, setReady] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    let dead = false;
    (async () => {
      const w = window as any;
      // Studio 里热重载会复用页面：清掉上一次的全局状态，避免镜头表翻倍
      w.SHOTS = [];
      delete w.ENGINE; delete w.CHARACTER; delete w.sceneReady; delete w.drawFrame;
      for (const s of (proj as any).scripts as string[]) {
        await loadScript(staticFile('proj/' + s));
      }
      if (typeof w.sceneReady === 'undefined') throw new Error('assemble.js 没有产出 window.sceneReady');
      await w.sceneReady;
      if (typeof w.drawFrame !== 'function') throw new Error('assemble.js 没有产出 window.drawFrame');
      if (!dead) setReady(true);
    })().catch((e) => { if (!dead) setErr(String(e && e.message ? e.message : e)); });
    return () => { dead = true; };
  }, []);

  // 每帧画一帧：布局阶段同步画完，Remotion 截图时画面已经是最新的
  useLayoutEffect(() => {
    if (!ready) return;
    (window as any).drawFrame(t);
  }, [ready, frame, t]);

  if (err) {
    return (
      <AbsoluteFill style={{background: '#160b0b', color: '#ff9b9b', fontFamily: 'monospace', fontSize: 26, padding: 40, whiteSpace: 'pre-wrap'}}>
        {'画面加载失败\n\n' + err + '\n\n先跑：bash mv.sh remotion <项目目录> --song <歌>'}
      </AbsoluteFill>
    );
  }

  return (
    <AbsoluteFill style={{background: '#000'}}>
      <canvas id="c" width={(proj as any).ow} height={(proj as any).oh} style={{width: '100%', height: '100%', display: 'block'}} />
      {(proj as any).song ? <Audio src={staticFile((proj as any).song)} /> : null}
    </AbsoluteFill>
  );
};
