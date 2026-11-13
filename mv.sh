#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
#  mv.sh —— 一条命令一个动作。你只需要记这 18 个动词，不要自己拼 node/ffmpeg 命令。
#
#  ── Remotion 模式（实验性：Remotion 当时钟/音轨/预览器，画面仍由 canvas 逐帧画）──
#   ./mv.sh remotion <工程目录> [--song 歌.mp3]   把工程装进 Remotion（会生成 public/proj/ 与 project.gen.json）
#   ./mv.sh rrender  [输出.mp4] [--concurrency=2] Remotion 渲染整片（自带音轨，不用再 deliver）
#   ./mv.sh rstudio                              Remotion 预览器：拖时间轴/听歌/逐帧看，改完热更新
#   ./mv.sh clean                                清掉打包缓存/装配产物（node_modules 里的 .cache 会占 300MB+）
#   ./mv.sh rmaster <视频> <歌.mp3>               把 Remotion 成片响度归一（-14 LUFS / 真峰 -1 dBTP）
#
#   ./mv.sh env                       环境自检（python/ffmpeg/chrome/puppeteer 缺什么）
#   ./mv.sh init  <工程目录> --style=pixel|collage|crayon [--w=1920 --h=1080 --world=640x360 --analysis=分析.json --bpm=120 --dur=6 --title=歌名 --no-intro]
#   ./mv.sh ncm   <歌.ncm|目录>        网易云 .ncm → mp3/flac（调 ncm2mp3，零损失、不重编码）
#   ./mv.sh analyze <歌.mp3>          测 BPM / 拍位 / 情绪段落 → 工程目录下的 song-analysis.json
#   ./mv.sh lyric <歌.lrc|字幕.srt>    歌词 → lyrics.js（+ 歌词网格 md）
#   ./mv.sh storyboard <工程目录>       依据歌词和节奏轨写 STORYBOARD.md 草稿
#   ./mv.sh check <工程目录>           静态自检（镜头接线/首尾相接/黑名单/歌词时间轴）退出码 0/1
#   ./mv.sh stills <工程目录> 0.4,1.6  出几张关键帧图 + 拼一张接触表（每镜审图用这个）
#   ./mv.sh sheet <工程目录>           角色设定图（三视图/表情/动作），存 character-sheet.png
#   ./mv.sh sweep <工程目录> 2.0 3.0   区间内每一帧拼一条（看运动、找穿帮）
#   ./mv.sh speed <工程目录>           渲 1 秒测速，报"秒/帧"，超过 0.15 就要优化
#   ./mv.sh render <工程目录>          渲整片（断点续渲：中断了重跑会接着渲）
#   ./mv.sh encode <工程目录>          帧 → 无声 mp4
#   ./mv.sh deliver <工程目录> <歌.mp3> 封原曲 + 抖音参数转码 + ffprobe 自检，最后一行 PASS/FAIL
#
# 出图/出片都在 <工程目录>/out/ 下。渲染 >1 分钟，用 run_in_background 跑 render。
# ═══════════════════════════════════════════════════════════════════════════
set -uo pipefail
SRC="${BASH_SOURCE[0]}"; case "$SRC" in /*) ;; *) SRC="$PWD/$SRC";; esac
SKILL="$(cd "$(dirname "$SRC")" && pwd)"   # mv.sh 就在 skill 根目录
S="$SKILL/scripts"
# 本机私有配置（不进仓库）：可在这里设 MV_PYTHON / MV_WORKERS
[ -f "$SKILL/mv.local.sh" ] && . "$SKILL/mv.local.sh"
say() { printf '\033[1m%s\033[0m\n' "$*"; }
die() { printf '\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }
warn() { printf '\033[33m! %s\033[0m\n' "$*" >&2; }

# 找得到 librosa 的 python（顺序：$MV_PYTHON → python3 → 技能目录下的 .venv）
pick_py() {
  local mod="${1:-}" c
  for c in "${MV_PYTHON:-}" "$(command -v python3 || true)" \
           "$SKILL/.venv/bin/python" "$SKILL/.venv3/bin/python"; do
    [ -n "$c" ] && [ -x "$c" ] || continue
    if [ -z "$mod" ] || "$c" -c "import $mod" >/dev/null 2>&1; then echo "$c"; return 0; fi
  done
  return 1
}

# 取画面某一点的颜色（16×16 采样成 1 像素）→ "R G B"
corner_rgb() {  # $1=视频 $2=秒 $3=x表达式 $4=y表达式
  ffmpeg -hide_banner -v error -ss "$2" -i "$1" -vframes 1 \
    -vf "crop=16:16:$3:$4,scale=1:1" -f rawvideo -pix_fmt rgb24 - 2>/dev/null | od -An -tu1 | tr -s ' ' | sed 's/^ //'
}

# 判断成片是不是 MV.tsx 的"加载失败"页：该页底色是暗红（R>G≥B、R-B≥8、R<80），四角都一样
looks_error() {
  local f="$1" ts r g b hits=0 tot=0 pos
  [ -f "$f" ] || return 1
  for ts in 0.6 1.6; do
    for pos in "4:4" "iw-20:4" "4:ih-20" "iw-20:ih-20"; do
      read -r r g b <<EOF2
$(corner_rgb "$f" "$ts" "${pos%:*}" "${pos#*:}")
EOF2
      [ -z "$r" ] && continue
      tot=$((tot+1))
      if [ "$r" -gt "$g" ] && [ "$g" -ge "$b" ] && [ $((r-b)) -ge 8 ] && [ "$r" -lt 80 ]; then
        hits=$((hits+1))
      fi
    done
  done
  [ "$tot" -gt 0 ] && [ "$hits" -ge "$tot" ]
}

# 从 index.html 里读 CFG 的一个数（键名固定，见 templates/_shared/index.html）
cfg() {   # 从 index.html 读 CFG 里的一个数（macOS 的 grep 不支持 \b，所以用 awk）
  local proj="$1" k="$2" d="${3:-0}" v=""
  if [ -f "$proj/index.html" ]; then
    v=$(awk -v k="$k" 'match($0, k"[ \t]*:[ \t]*[0-9]+([.][0-9]+)?") { s=substr($0,RSTART,RLENGTH); sub(/^[^:]*:[ \t]*/,"",s); print s; exit }' "$proj/index.html")
  fi
  echo "${v:-$d}"
}
out_w() { local p="$1"; local w; w=$(grep -oE "OUT:[[:space:]]*\{[[:space:]]*w:[[:space:]]*[0-9]+" "$p/index.html" | grep -oE '[0-9]+$'); echo "${w:-$(cfg "$p" W 1920)}"; }
out_h() { local p="$1"; local h; h=$(grep -oE "OUT:[[:space:]]*\{[^}]*h:[[:space:]]*[0-9]+" "$p/index.html" | grep -oE '[0-9]+$'); echo "${h:-$(cfg "$p" H 1080)}"; }
# 拼一张接触表。没有 Pillow 就明确跳过，不要假装成功
sheet() {  # $1=图片目录  $2=输出 jpg
  local py; if py=$(pick_py PIL); then
    "$py" "$S/contact_sheet.py" --images "$1" -o "$2" >/dev/null 2>&1 \
      && return 0 || { warn "拼图失败：$1 → $2（看 contact_sheet.py 的报错）"; return 1; }
  else
    warn "拼图跳过：没有装 Pillow（pip install Pillow）；单帧图在 $1"; return 1
  fi
}
shot_line() {  # $1=图片目录 $2=拼图路径 → 拼图没出来就不提它
  if [ -f "$2" ]; then echo "$1（拼图 $2）"; else echo "$1"; fi
}
need_proj() { [ -n "${1:-}" ] || die "要给工程目录，例如 work/my-mv"; [ -f "$1/index.html" ] || die "$1 里没有 index.html（用 ./mv.sh init 建）"; }

cmd="${1:-help}"; shift || true

case "$cmd" in
# ───────────────────────────────────────────────────────────────────────
env)
  say "── 环境自检 ──"
  local_ok=0
  printf 'node      '; node -v || { echo 缺; local_ok=1; }
  printf 'ffmpeg    '; ffmpeg -version 2>/dev/null | head -1 || { echo "缺（brew install ffmpeg）"; local_ok=1; }
  printf 'chrome    '; ls -d "/Applications/Google Chrome.app" 2>/dev/null || echo "没找到 Chrome（puppeteer 要用）"
  printf 'puppeteer '; (cd "$SKILL" && node -e "console.log('ok  '+require.resolve('puppeteer-core'))" 2>/dev/null) \
      || echo "缺 → 在有 node_modules 的目录里跑，或 cd $SKILL && npm i puppeteer-core"
  printf 'remotion  '; (cd "$SKILL" && node -p "'ok  ' + require('remotion/package.json').version" 2>/dev/null) \
      || echo "缺 → cd $SKILL && npm install（Remotion 模式要用；只走默认管线可以不装）"
  printf 'librosa   '; p=$(pick_py librosa) && echo "$p" || echo "没有 → 设 MV_PYTHON 指向有 librosa 的 python，或退到 beat_grid.py（只需 numpy）"
  printf 'numpy     '; p=$(pick_py numpy) && echo "$p" || echo "没有 → 只能手填 BPM"
  printf 'Pillow    '; p=$(pick_py PIL) && echo "$p" || echo "没有 → 接触表/拼图出不来（read_image 看图不受影响）"
  [ $local_ok = 0 ] && echo "ENV PASS" || { echo "ENV FAIL"; exit 1; }
  ;;

# ───────────────────────────────────────────────────────────────────────
init)
  "$(pick_py)" "$S/init_project.py" "$@"
  ;;

# ───────────────────────────────────────────────────────────────────────
ncm)
  # 网易云 .ncm 是加密壳，librosa / 剪辑软件都读不了。先撬开再进流程。
  [ $# -ge 1 ] || die "要给 .ncm 文件或目录：./mv.sh ncm 歌.ncm"
  ncm_sh="$SKILL/../ncm2mp3/ncm.sh"
  [ -x "$ncm_sh" ] || ncm_sh="$HOME/.agents/skills/ncm2mp3/ncm.sh"
  [ -x "$ncm_sh" ] || die "找不到 ncm2mp3 技能（git clone https://github.com/EmingChao/ncm2mp3.git ~/.agents/skills/ncm2mp3）"
  say "── .ncm → 音频（原样还原，不重新编码）──"
  "$ncm_sh" "$@"
  ;;

# ───────────────────────────────────────────────────────────────────────
analyze)
  song="${1:?用法: ./mv.sh analyze <歌.mp3>}"; shift || true
  [ -f "$song" ] || die "找不到 $song"
  case "$song" in
    *.ncm|*.NCM) die "这是网易云加密壳，先转：./mv.sh ncm \"$song\"" ;;
  esac
  if p=$(pick_py librosa); then
    "$p" "$S/analyze_song.py" "$song" "$@"
  else
    for arg in "$@"; do case "$arg" in --rhythm|--rhythm=*|-o|--out|--out=*) die "导出分析或节奏文件需要 librosa，请设置 MV_PYTHON";; esac; done
    warn "没有 librosa，退到 beat_grid.py（只给 BPM 和拍位，没有情绪段）"
    pick_py numpy >/dev/null || die "numpy 也没有。直接问用户 BPM，写进 index.html 的 BPM:"
    "$(pick_py numpy)" "$S/beat_grid.py" "$song" "$@"
  fi
  ;;

# ───────────────────────────────────────────────────────────────────────
storyboard)
  need_proj "${1:-}"; proj="$1"; shift || true
  node "$S/storyboard_draft.mjs" "$proj" "$@"
  ;;

# ───────────────────────────────────────────────────────────────────────
lyric)
  src="${1:?用法: ./mv.sh lyric <歌.lrc|字幕.srt> [--offset=-0.3] [-o 输出] [--out 网格.md]}"; shift || true
  [ -f "$src" ] || die "找不到 $src"
  case "$src" in
    *.srt) out=""; for a in "$@"; do case "$a" in -o|--out) ;; esac; done
           has_o=0; for a in "$@"; do [ "$a" = "-o" ] && has_o=1; done
           if [ $has_o = 1 ]; then "$(pick_py)" "$S/srt2js.py" "$src" "$@"; else "$(pick_py)" "$S/srt2js.py" "$src" -o "${src%.*}.lyrics.js" "$@"; say "歌词 → ${src%.*}.lyrics.js（拷进工程目录时改名 lyrics.js）"; fi ;;
    *)     "$(pick_py)" "$S/lyric_grid.py" "$src" "$@" ;;
  esac
  ;;

# ───────────────────────────────────────────────────────────────────────
check)
  need_proj "${1:-}"; proj="$1"; shift || true
  for f in "$proj"/engine.js "$proj"/character.js "$proj"/assemble.js "$proj"/shots/*.js "$proj"/lyrics.js; do
    [ -f "$f" ] || continue
    node --check "$f" || die "语法错：$f（照上面报的行号改）"
  done
  node "$S/check_shots.mjs" "$proj"
  ;;

# ───────────────────────────────────────────────────────────────────────
stills|sheet|sweep)
  need_proj "${1:-}"; proj="$1"; shift || true
  W=$(out_w "$proj"); H=$(out_h "$proj")
  mkdir -p "$proj/out/stills"
  if [ "$cmd" = "sheet" ]; then
    [ -f "$proj/stills.html" ] || die "$proj 里没有 stills.html（从 templates/_shared/stills.html 拷一份）"
    node "$S/render_frames.mjs" --page "$proj/stills.html" --times 0 --out "$proj/out" --name character-sheet --width 1920 --height 1080 \
      || die "出图失败"
    say "设定图：$proj/out/character-sheet.png"
  elif [ "$cmd" = "sweep" ]; then
    t0="${1:?用法: ./mv.sh sweep <工程> 2.0 3.0}"; t1="${2:?要到几秒}"
    times=$(node -e "const a=+process.argv[1],b=+process.argv[2],o=[];for(let t=a;t<=b+1e-9;t+=1/15)o.push(t.toFixed(3));console.log(o.join(','))" "$t0" "$t1")
    node "$S/render_frames.mjs" --page "$proj/index.html" --times "$times" --out "$proj/out/sweep" --width "$W" --height "$H" --format jpg || die "出图失败"
    sheet "$proj/out/sweep" "$proj/out/sweep.jpg" || true
    say "区间图：$(shot_line "$proj/out/sweep/" "$proj/out/sweep.jpg")"
  else
    times="${1:-}"; [ -n "$times" ] || die "用法: ./mv.sh stills <工程> 0.4,1.6,2.9（逗号分隔的秒数）"
    node "$S/render_frames.mjs" --page "$proj/index.html" --times "$times" --out "$proj/out/stills" --width "$W" --height "$H" --format jpg || die "出图失败"
    sheet "$proj/out/stills" "$proj/out/stills.jpg" || true
    say "关键帧：$(shot_line "$proj/out/stills/" "$proj/out/stills.jpg")"
  fi
  ;;

# ───────────────────────────────────────────────────────────────────────
speed)
  need_proj "${1:-}"; proj="$1"; shift || true
  W=$(out_w "$proj"); H=$(out_h "$proj")
  rm -rf "$proj/out/speed"
  say "渲 1 秒（$(cfg "$proj" FPS 30) 帧）测速度…"
  node "$S/render_frames.mjs" --page "$proj/index.html" --duration 1 --fps "$(cfg "$proj" FPS 30)" \
    --out "$proj/out/speed" --width "$W" --height "$H" --workers 2 --force 2>&1 | tail -3
  ;;

# ───────────────────────────────────────────────────────────────────────
render)
  need_proj "${1:-}"; proj="$1"; shift || true
  W=$(out_w "$proj"); H=$(out_h "$proj"); FPS=$(cfg "$proj" FPS 30); DUR=$(cfg "$proj" DURATION 0)
  [ "$(echo "$DUR > 0" | bc -l 2>/dev/null)" = "1" ] || die "index.html 里 DURATION 不对：$DUR"
  node "$S/check_shots.mjs" "$proj" || die "静态自检没过，先跑 ./mv.sh check 修完再渲"
  say "渲整片：${DUR}s × ${FPS}fps = $(node -e "console.log(Math.round($DUR*$FPS))") 帧，$W×$H"
  node "$S/render_frames.mjs" --page "$proj/index.html" --fps "$FPS" --duration "$DUR" \
    --out "$proj/out/frames" --width "$W" --height "$H" --workers "${MV_WORKERS:-2}" "$@" || die "渲帧失败"
  say "帧好了：$proj/out/frames/（接着 ./mv.sh encode $proj）"
  ;;

# ───────────────────────────────────────────────────────────────────────
encode)
  need_proj "${1:-}"; proj="$1"; shift || true
  FPS=$(cfg "$proj" FPS 30); DUR=$(cfg "$proj" DURATION 6)
  node "$S/render_frames.mjs" --page "$proj/index.html" --fps "$FPS" --duration "$DUR" \
    --out "$proj/out/frames" --encode "$proj/out/raw.mp4" || die "编码失败"
  say "无声成片：$proj/out/raw.mp4"
  ;;

# ───────────────────────────────────────────────────────────────────────
deliver)
  need_proj "${1:-}"; proj="$1"; song="${2:?用法: ./mv.sh deliver <工程> <歌.mp3>}"
  W=$(out_w "$proj"); H=$(out_h "$proj"); shift 2 || true
  [ -f "$proj/out/raw.mp4" ] || die "先 ./mv.sh encode $proj"
  # 1) 把原曲封回去（渲染出的音轨会被编码器压 2–4dB，必须换回原曲并统一响度）
  "$(pick_py)" "$S/finalize_audio.py" "$proj/out/raw.mp4" "$song" -o "$proj/out/deliver.mp4" --target-lufs -14 "$@" \
    || die "封音失败"
  # 2) 抖音交付参数（bt709 三件套 + 高码率，不用 crf：暗场会被压得很低）
  tmp="$proj/out/_d.mp4"
  ffmpeg -v error -y -i "$proj/out/deliver.mp4" -c:v libx264 -preset slow -b:v 8M -maxrate 12M -bufsize 16M \
    -pix_fmt yuv420p -color_range tv -color_primaries bt709 -color_trc bt709 -colorspace bt709 \
    -c:a copy -movflags +faststart "$tmp" || die "转码失败"
  mv "$tmp" "$proj/out/deliver.mp4"
  # 3) 自检：分辨率/帧率/编码/音轨/响度/黑场
  echo "──── 交付自检 ────"
  ffprobe -v error -select_streams v:0 -show_entries stream=width,height,r_frame_rate,codec_name,pix_fmt,bit_rate \
    -of default=nw=1 "$proj/out/deliver.mp4"
  ffprobe -v error -select_streams a:0 -show_entries stream=codec_name,sample_rate,channels -of default=nw=1 "$proj/out/deliver.mp4"
  ffmpeg -hide_banner -nostats -i "$proj/out/deliver.mp4" -af loudnorm=print_format=summary -f null - 2>&1 | grep -E "Input Integrated|Input True Peak" || true
  ffmpeg -hide_banner -nostats -i "$proj/out/deliver.mp4" -vf blackdetect=d=0.1:pix_th=0.08 -an -f null - 2>&1 | grep -c black_start | xargs -I{} sh -c 'echo "黑场段数：{}（前 3 秒不能有）"'
  # 4) 硬判据
  fail=0
  vw=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=nw=1:nk=1 "$proj/out/deliver.mp4" | tr -dc 0-9)
  vh=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 "$proj/out/deliver.mp4" | tr -dc 0-9)
  [ "$vw" = "$W" ] || { warn "宽不是 $W（实际 $vw）"; fail=1; }
  [ "$vh" = "$H" ] || { warn "高不是 $H（实际 $vh）"; fail=1; }
  [ "$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_type -of csv=p=0 "$proj/out/deliver.mp4")" = "audio" ] || { warn "没有音轨"; fail=1; }
  [ -s "$proj/out/deliver.mp4" ] || fail=1
  echo "成片：$proj/out/deliver.mp4"
  [ $fail = 0 ] && echo "DELIVER PASS" || { echo "DELIVER FAIL"; exit 1; }
  ;;

# ── Remotion 模式（实验性）───────────────────────────────────────────────
clean)
  # 清缓存与临时物（不动 templates/ scripts/ 与 preview/）
  rm -rf "$SKILL/node_modules/.cache" "$SKILL/node_modules/.remotion" "$SKILL/public/proj" "$SKILL/work" "$SKILL/out"
  rm -f "$SKILL/remotion/project.gen.json"
  say "── 已清理 ──"
  du -sh "$SKILL" "$SKILL/node_modules" 2>/dev/null
  echo "CLEAN PASS"
  ;;

remotion)
  proj="${1:-}"; shift || true; song=""
  while [ $# -gt 0 ]; do case "$1" in
    --song) song="${2:-}"; shift 2;;
    --song=*) song="${1#--song=}"; shift;;
    *) die "不认识的参数：$1（只支持 --song）";;
  esac; done
  need_proj "$proj"
  if [ -n "$song" ] && [ ! -f "$song" ]; then die "歌不存在：$song"; fi
  say "── 装进 Remotion ──"
  node "$SKILL/remotion/stage.mjs" --proj "$proj" ${song:+--song "$song"} || die "装配失败"
  echo "下一步： ./mv.sh rstudio          预览、拖时间轴"
  echo "        ./mv.sh rrender  out/mv.mp4   直接出片"
  ;;

rrender)
  out="${1:-out/mv.mp4}"; shift || true
  [ -f "$SKILL/remotion/project.gen.json" ] || die "还没装配：先跑 ./mv.sh remotion <工程目录> --song <歌>"
  # 装配产物校验（被 clean 掉过 / 手工删过都会在这里拦下，否则会渲出一整片"加载失败"）
  [ -f "$SKILL/public/proj/cfg.js" ] || die "装配产物不在（public/proj/cfg.js 缺失）：重跑 ./mv.sh remotion <工程目录>"
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    [ -f "$SKILL/public/proj/$f" ] || die "装配产物缺文件：public/proj/$f（重跑 ./mv.sh remotion <工程目录>）"
  done < <(node -e "const p=require('$SKILL/remotion/project.gen.json');p.scripts.forEach(s=>console.log(s.replace(/^proj\\//,'')))" 2>/dev/null)
  case "$out" in /*) ;; *) out="$SKILL/$out";; esac
  mkdir -p "$(dirname "$out")"
  say "── Remotion 渲染 → $out ──"
  cd "$SKILL" && npx remotion render MV "$out" "$@"
  rc=$?
  # 打包缓存单次只省 0–2 秒，却会堆 200–350MB；除非 MV_KEEP_CACHE=1，渲完就删
  [ "${MV_KEEP_CACHE:-0}" = "1" ] || rm -rf "$SKILL/node_modules/.cache"
  if [ $rc = 0 ] && [ "${MV_SKIP_FRAME_CHECK:-0}" != "1" ]; then
    if looks_error "$out"; then
      echo "REMOTION FAIL：画面是"加载失败"页（四角全是暗红底），成片不能交"
      echo "  排查：① ./mv.sh remotion <工程目录> 重装 ② ./mv.sh rstudio 看红字 ③ 确认 work 里的工程没被删"
      exit 1
    fi
  fi
  [ $rc = 0 ] && { echo "成片：$out"; ffprobe -v error -show_entries stream=codec_type,codec_name,width,height,r_frame_rate -of default=nw=1 "$out"; echo "REMOTION PASS"; } \
              || { echo "REMOTION FAIL"; exit 1; }
  ;;

rstudio)
  say "── Remotion 预览器（Ctrl-C 退出）──"
  cd "$SKILL" && npx remotion studio remotion/index.ts "$@"
  ;;

rmaster)
  vid="${1:-}"; song="${2:-}"
  [ -f "$vid" ] || die "找不到视频：$vid"
  [ -f "$song" ] || die "找不到歌：$song"
  out="$(dirname "$vid")/$(basename "${vid%.*}")-master.mp4"
  py=$(pick_py) || die "找不到 python3"
  say "── 响度归一（目标 -14 LUFS / 真峰 ≤ -1 dBTP）──"
  "$py" "$S/finalize_audio.py" "$vid" "$song" -o "$out" --target-lufs -14 || die "归一失败"
  ffmpeg -hide_banner -nostats -i "$out" -af loudnorm=print_format=summary -f null - 2>&1 | grep -E "Input Integrated|Input True Peak" || true
  echo "成片：$out"
  echo "RMASTER PASS"
  ;;

# ───────────────────────────────────────────────────────────────────────
*) awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "${BASH_SOURCE[0]}" ;;
esac
