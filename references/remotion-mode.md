# Remotion 模式（实验分支）

> 一句话：**Remotion 当时钟、音轨和预览器，画面仍然由 canvas 一帧一帧画。**
> `engine.js` / `character.js` / `shots/NN.js` 一行都不用改，换的只是"谁来喂 `t`、谁来听歌、谁来回拖"。

---

## 1. 什么时候用，什么时候别用

| 情况 | 用 Remotion 模式 | 用默认（puppeteer 逐帧） |
|---|---|---|
| 3–5 分钟长片、60–120 镜 | ✅ 分段渲染 + 拖时间轴预览更省事 | 也能做，改一版要等整片 |
| 要边听歌边拖时间轴对拍 | ✅ `rstudio` 直接拖 | ❌ 只能 `stills` / `sweep` 出图 |
| 想让歌直接进合成（不用最后封音） | ✅ `<Audio>` 同轨 | 需要 `deliver` 一步 |
| 30–60 秒短片、改两版就发 | 不必要（多一层 bundle） | ✅ 更少活动件 |
| 机器只有 8G 内存 | 不建议（并发标签页各要预烘） | ✅ 单页单进程 |

**它不提高画面上限。** 好看与否取决于引擎工艺、分镜、卡点，跟渲染器无关。

---

## 2. 三条命令

```bash
bash mv.sh remotion work/my-mv --song ~/Music/song.mp3   # 装配（每次改完镜头/CFG 都要重跑一次）
bash mv.sh rstudio                                        # 预览器：拖时间轴/听歌/逐帧看
bash mv.sh rrender out/mv.mp4                             # 出片（自带音轨）
bash mv.sh rmaster out/mv.mp4 ~/Music/song.mp3            # 响度归一到 -14 LUFS + 限峰（抖音参数）
```

- `remotion` = 把工程搬进 Remotion：生成 `<skill>/public/proj/` 与 `remotion/project.gen.json`。
- `rrender` 可加原生参数：`--frames=0-1799`（只渲前 60 秒）、`--concurrency=2`、`--log=error`。
- `rmaster` 只在你要发平台、要 −14 LUFS 时才需要；Remotion 自己混音**不做响度归一化**。

---

## 3. 它是怎么接上原来的管线的

```
work/my-mv/index.html ─┐
  engine.js            │  remotion/stage.mjs
  character.js         ├─► public/proj/{cfg.js,engine.js,character.js,lyrics.js,shots/NN.js,song.mp3}
  lyrics.js            │        + remotion/project.gen.json（宽高/帧率/时长/脚本顺序/歌）
  shots/NN.js ─────────┘
                                │
remotion/MV.tsx  ── 按顺序 <script> 注入 → await window.sceneReady
                └─ 每帧： useCurrentFrame() → t → window.drawFrame(t)   ← 复用 assemble.js
                   <Audio src={staticFile('proj/song.mp3')} />         ← 歌进合成
```

关键点：

- `MV.tsx` 里先渲染 `<canvas id="c" width={ow} height={oh}>`，`assemble.js` 会直接用它（它先找 `#c`，找不到才自己建）。
- 画完在 `useLayoutEffect` 里同步发生，Remotion 截图时画面已是最新 → 帧准。
- **像素风**：`ow/oh` 是输出尺寸（1920×1080），`w/h` 是世界里的小画布（新工程默认 640×360），别弄反。
- Studio 热更新会复用页面，`MV.tsx` 每次挂载前清 `window.SHOTS/ENGINE/...`，否则镜头会翻倍。

---

## 4. 速度实测（同一台机器，1920×1080，6 秒 = 180 帧）

| 画风 | Remotion 模式 | 默认 puppeteer 模式 |
|---|---|---|
| pixel | 9.8s（≈0.054 秒/帧） | 0.13 秒/帧 |
| collage | 13.3s（≈0.074 秒/帧） | 0.25 秒/帧 |
| crayon | 10.3s（≈0.057 秒/帧） | 0.14–0.16 秒/帧 |

折算：4 分钟（7200 帧）≈ **6–9 分钟**（Remotion 多标签页并发）；puppeteer 路线同样条件 16–30 分钟。
数字会变，**永远以你自己 `rrender` 的日志为准**。

---

## 5. 长片（3–5 分钟）的做法

1. **先分段**：按段落切 `--frames`，一段一段渲，改哪段只重跑哪段
   ```bash
   bash mv.sh rrender out/p1.mp4 --frames=0-1799        # 0:00–1:00
   bash mv.sh rrender out/p2.mp4 --frames=1800-3599     # 1:00–2:00
   printf "file 'p1.mp4'\nfile 'p2.mp4'\n" > out/list.txt && ffmpeg -f concat -safe 0 -i out/list.txt -c copy out/full.mp4
   ```
2. **对拍用 `rstudio`**，不要用出图对拍（拖一下就有画面，成本低）。
3. 副歌重复三次：同场景改 `variant` 参数（景别/机位/配色/雪量），别复制三遍同样的镜头。
4. 说唱段落时长参考 `references/storyboard.md`：主歌 1.2–2.2s/镜、副歌 0.8–1.5s/镜、hook 字卡 0.4–0.8s。

---

## 6. 踩坑（症状 → 原因 → 修法）

| 症状 | 原因 | 修法 |
|---|---|---|
| 画面里一行红字"脚本加载失败：/proj/cfg.js" | 静态文件没在 Remotion 的 publicDir 里 | 重跑 `mv.sh remotion`（它写到 `<skill>/public/proj/`），别手动往 `remotion/public` 放 |
| 日志里 `Failed to load resource: 404` | 同上 | 同上 |
| 画面全黑、无报错 | 当前帧没有任何镜头覆盖（`start/end` 对不上） | 先 `bash mv.sh check work/my-mv` |
| Studio 里镜头越改越多 | 热更新复用了页面，全局 `SHOTS` 没清 | `MV.tsx` 里那段清理别删 |
| 预览卡顿/爆内存 | 并发标签页各烘纸纹 | `rrender --concurrency=2` |
| 出片没声音 | 装配时没给 `--song` | `mv.sh remotion … --song 歌.mp3` |
| 声音偏小/忽大忽小 | Remotion 只直通混音，不做响度归一 | `mv.sh rmaster out/mv.mp4 歌.mp3` |
| `Cannot find module 'remotion'` | 依赖没装 | `cd <skill> && npm install` |
| 换了机器打不开浏览器 | 默认用系统 Chrome（`remotion.config.ts` 里写死了 macOS 路径） | 删掉那一行，让 Remotion 自己下载 headless shell |
| 想改分辨率/帧率 | 这两项来自工程 CFG，不是 Remotion | 改 `work/my-mv/index.html` 的 `CFG.W/H/FPS`，再重跑 `mv.sh remotion` |

---

## 7. 和主分支（`music-mv`）的差别

| | `music-mv`（主分支） | `music-mv-with-remotion`（本分支） |
|---|---|---|
| 渲染 | puppeteer 逐帧截图 → ffmpeg | Remotion 逐帧截图 → 自带编码 |
| 音轨 | 最后 `deliver` 封原曲 + 响度归一 | `<Audio>` 进合成；要归一得 `rmaster` |
| 预览 | `stills` / `sweep` 出图 | `rstudio` 拖时间轴 |
| 逐字歌词 | 像素风打字机 | 三种画风都能逐字（`CFG.LYRIC.stagger`）+ 像素风打字机 |
| 断点续渲 | ✅ `render` 自动续 | 用 `--frames` 分段 |
| 依赖 | puppeteer-core | puppeteer-core + remotion + react（`npm install`） |

主分支不受本分支影响：两条管线共用同一套 `engine.js` / `character.js` / `assemble.js` 契约，工程目录可以互相搬。

若接触表正常、播放时却有一帧花屏，在相邻几帧之间检查片名、纹理是否出现重复平铺。可用同一工程的逐帧管线输出作对照；本机模板等画布就绪并绘制首帧后才放行截图。
