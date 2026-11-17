# music-mv-with-remotion（实验分支）

把一首歌做成可拖时间轴、可带声预览和可分段渲染的代码 MV。像素、纸艺拼贴和蜡笔绘本共用同一套工程契约，Remotion 负责时间、音轨、预览和最终编码，画面由 Canvas 逐帧绘制。

- 两条技能共用 `engine.js`、`character.js`、`assemble.js` 的工程契约，工程可以在两条渲染入口之间复用
- 每首歌可重新设计角色、场景、镜头、色阶和字幕。模板里的排练镜头只用于验证接口

默认像素工程是 640×360 世界画布到 1920×1080 输出。也可以选择 320×180、1280×720 或 1920×1080 原生世界画布。`init` 会生成带 `rehearsal: true` 的排练镜头，正式制作要按本曲分镜替换，并检查工程中没有 `rehearsal: true`。

| 世界画布 | 画面特点 | 适用镜头 |
|---|---|---|
| `320×180` | 颗粒最大，轮廓强 | 剪影、远景、强图形 |
| `640×360` | 细节与渲染成本平衡 | 人物、道具、分层建筑 |
| `1280×720` | 小动作和材质更清楚 | 复杂服装、密集前后景 |
| `1920×1080` | 原生 1080p 像素绘制 | 需要细节的特写和复杂场景 |


```bash
git clone https://github.com/EmingChao/music-mv-with-remotion.git ~/.agents/skills/music-mv-with-remotion
cd music-mv-with-remotion && npm install     # 只走默认管线的话，装 puppeteer-core 就够
./mv.sh env
```

## 一条命令一个动作

```bash
cd music-mv-with-remotion

bash mv.sh env                                   # 环境自检（含 remotion 版本）
bash mv.sh init work/my-mv --style=pixel --w=1920 --h=1080 --bpm=92 --dur=180
bash mv.sh ncm ~/Music/song.ncm                  # 网易云加密壳先还原（转调 ncm2mp3）
bash mv.sh analyze ~/Music/song.mp3              # BPM / 拍位 / 段落
bash mv.sh lyric ~/Music/song.lrc                # 歌词 → lyrics.js
bash mv.sh storyboard work/my-mv                # 生成可编辑的全曲分镜草稿
bash mv.sh check work/my-mv                      # 静态自检（接线/首尾相接/CFG 语法/歌词轴）

# —— 默认管线（Puppeteer 逐帧）——
bash mv.sh stills work/my-mv 1.2,3.4             # 出关键帧审图
bash mv.sh render work/my-mv                     # 渲整片（断点续渲）
bash mv.sh deliver work/my-mv ~/Music/song.mp3   # 封原曲 + 抖音参数 + 自检

# —— Remotion 模式（长片/要拖时间轴/要逐字歌词）——
bash mv.sh remotion work/my-mv --song ~/Music/song.mp3
bash mv.sh rstudio                               # 拖时间轴预览
bash mv.sh rrender out/mv.mp4                     # 出片（自带音轨）
bash mv.sh rmaster out/mv.mp4 ~/Music/song.mp3    # -14 LUFS / 真峰 -1 dBTP
bash mv.sh clean                                  # 清缓存/装配产物（能省 200–300MB）
```

## 逐字歌词

改工程 `index.html` 的 CFG 一行：

```js
LYRIC: { stagger: true, bottom: 0.90, size: 68, color: '#FFF8E7', ink: '#1B1B29', align: 'center' },
```

三种画风表现不同（像素=打字机、拼贴=逐字贴上、蜡笔=逐字跳到位）。细节见 `references/lyrics-and-beats.md` §5b。

## 依赖

```bash
cd ~/.agents/skills/music-mv-with-remotion && npm install
```

- 只走默认管线：装 `puppeteer-core` 就够
- 用 Remotion 模式：需要 `remotion@4.0.539` + `@remotion/cli` + `react@19`（`package.json` 已钉住）
- `remotion.config.ts` 里写死了 macOS 的 Chrome 路径（省下载 headless shell），换机器删掉那一行

## 性能参考（不同机器会有差异）

| 画风 | Remotion 模式 | 默认 puppeteer 模式 |
|---|---|---|
| pixel | 9.8s（0.054 秒/帧） | 0.13 秒/帧 |
| collage | 13.3s（0.074 秒/帧） | 0.25 秒/帧 |
| crayon | 10.3s（0.057 秒/帧） | 0.14–0.16 秒/帧 |

4 分钟（7200 帧）折算 ≈ 6–9 分钟（Remotion，多标签页并发）；同样条件 puppeteer 路线 16–30 分钟。
成片响度（`rmaster` 之后）：−14.2 LUFS / 真峰 −1.0 dBTP。

## 体积与依赖（为什么 1.2G → 305M）

刚装完时这个目录是 1.2G，拆开看是三块：

| 块 | 大小 | 是什么 | 能不能省 |
|---|---|---|---|
| `node_modules`（真依赖） | 282M | remotion / @remotion/cli / react / bundler / rspack / webpack 等 169 个包 | 不建议省：`flash` 自己装依赖容易失败，装好最省心 |
| `node_modules/.remotion` | 574M | Remotion 自动下载的 **chrome-headless-shell** | **能省，已省**：把 `remotion.config.ts` 放回 skill 根目录后，`Config.setBrowserExecutable` 才生效，直接用系统 Chrome |
| `node_modules/.cache` | 200–350M | webpack 打包缓存 | **已处理**：`rrender` 渲完自动删（想留就 `MV_KEEP_CACHE=1`） |

> 关键坑：`remotion.config.ts` 和 `tsconfig.json` **必须放在 skill 根目录**。原先放在 `remotion/` 子目录里，Remotion CLI 只读当前工作目录的配置，等于配置全没生效——于是它自己去下了 574MB 的 headless Chrome，用的还是默认并发/jpeg 质量。挪到根目录后：系统 Chrome 直接复用、配置生效、目录从 1.2G 降到 305M。

想再瘦：`node_modules` 可以移到仓库外再软链回来（本项目明确不做软链，所以不推荐）；或者干脆不装依赖，第一次用前 `npm install`（约 4 分钟，278 包）。

## 出片前的两道保险（已内建）

- **前置校验**：`rrender` 会先确认 `public/proj/cfg.js` 和 `project.gen.json` 里列的每个脚本都在，缺一个直接报 `装配产物缺文件`——否则会渲出一整条"加载失败"的视频还报成功。
- **成片校验**：`rrender` 渲完会取四角颜色判断是不是"加载失败页"（该页是暗红底），命中就 `REMOTION FAIL` 并给出三条排查建议；确实要跳过用 `MV_SKIP_FRAME_CHECK=1`。

## 已知限制

- Remotion 只直通混音，**不做响度归一**，发平台前要跑 `rmaster`
- 没有 whisper 时，普通 LRC 的词级时间戳靠句内字数估算（`charsOf`）。增强型逐字 LRC 当前也需要在工程中补充人工确认的字级时间，说唱咬字极密时应手动修正
- 并发标签页各自预烘纸纹/调色板，内存 ×N；16G 机器建议 `rrender --concurrency=2`
- 断点续渲靠 `--frames=a-b` 手工分段（默认管线的 `render` 是自动续的）
- Remotion 许可是 Remotion License（非 MIT），商用前自行确认

## 文档

- `SKILL.md` —— 总控（阶段、命令、闸门、排错）
- `references/remotion-mode.md` —— Remotion 模式：命令、原理、速度、长片分段、10 条踩坑
- `references/` 其余 7 篇 —— 测拍与歌词、分镜、镜头脚本 API、画风、坑表、审图、原视频提示词卡
- `templates/<style>/STYLE.md` —— 三种画风各自的引擎 API 与工艺红线

## 发布版压缩

完成带声成片后，`deliver` 会生成 `out/deliver-small.mp4`。Remotion 的 `rmaster` 也会生成对应的 `-small.mp4`。压缩前的成片保留在原路径，发布版单独保存。默认目标为 50 MB（十进制），可通过 `MV_TARGET_MB=30` 修改。

也可对已有成片执行 `./mv.sh compress 成片.mp4 -o 发布版.mp4 --target-mb 50`。发布版使用 H.264 双遍编码，保留分辨率和帧率，AAC 音轨直接复制。建议听看发布版并检查暗部、像素边缘与快速动作。

也可以选择 `./mv.sh compress 成片.mp4 -o 发布版.mp4 --preset 1600k`，或设置 `MV_COMPRESS_PRESET=1600k` 后执行交付命令。该预设以 1600 kbps 为视频平均码率，使用 H.264 slow 双遍编码，并直接复制输入音轨。文件大小随片长变化，原视频码率很低时可能变大，音轨需与 MP4 容器兼容。
