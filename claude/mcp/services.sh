# ccx 的依赖服务——被 ccx source,套餐 json 里 "ccx": {"needs": "<名字>"} 对应这里的 ensure_<名字>。
# 函数里 exit 非零 = 中止启动;可以 export 变量给片段里的 ${VAR} 展开用。输出一律走 stderr。

ccx_port_up() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }
ccx_wait_port() {
  local i
  for ((i = 0; i < ${2:-20}; i++)); do ccx_port_up "$1" && return 0; sleep 0.5; done
  return 1
}

# mitmweb-mcp 只连不起,mitmweb 不在它就是一堆报错的工具。没在跑就后台起一个,不带 Chrome:
# mitm-start 会顺带开自己的 Chrome,而 web 套餐同在时由 AI 的浏览器顶替,rev 同在时根本用不着。
# 想手动点页面就先自己 mitm-start,这里看到端口在就不动它。
# 参数与 mitm-start 对齐(同一个 env 文件、同一个日志),停用照旧 mitm-stop(按 UI 端口找进程)。
# 代理只听 127.0.0.1:自动拉起的东西不该对局域网开放;要抓手机流量请手动 mitm-start。
ensure_mitmweb() {
  . "$HOME/.config/mitmweb-mcp/env" 2>/dev/null || true
  local web="${MITMWEB_PORT:-8081}" proxy="${MITMPROXY_PORT:-8080}"
  ccx_port_up "$web" && return 0
  command -v mitmweb >/dev/null || { echo "ccx: 没装 mitmweb(pacman -S mitmproxy)" >&2; exit 1; }
  local log="${XDG_STATE_HOME:-$HOME/.local/state}/mitmweb-mcp/mitmweb.log"
  mkdir -p "${log%/*}"
  setsid mitmweb \
    --listen-host 127.0.0.1 --listen-port "$proxy" \
    --set "web_port=$web" \
    --set "web_password=$MITMWEB_TOKEN" \
    --set web_open_browser=false \
    >"$log" 2>&1 </dev/null &
  if ! ccx_wait_port "$web"; then
    echo "ccx: mitmweb 没起来,日志尾部($log):" >&2
    tail -n 10 "$log" >&2
    exit 1
  fi
  echo "ccx: 已后台启动 mitmweb(代理 :$proxy / 界面 :$web),用完 mitm-stop" >&2
}

# Burp 是 GUI 程序且要手动启用扩展,ccx 拉不起来;端口不在就直接拦下,别让会话开了才发现工具全挂。
ensure_burp() {
  ccx_port_up 9876 && return 0
  echo "ccx: Burp 的 MCP 端口 127.0.0.1:9876 没开——先启动 Burp 并启用 MCP Server 扩展(偏好 mitm 就用 cap)" >&2
  exit 1
}

# rev.json 里写的是 ${IDA_MCP_DIR}:取插件缓存下版本号最大的目录。插件已停用不自更新,
# 以后手动更新出新版本目录也不用再改片段。顺带确认 IDA 本体还在。
ensure_ida() {
  local d ida
  d=$(ls -d "$HOME"/.claude/plugins/cache/HexRaysSA/ida-mcp/*/ 2>/dev/null | sort -V | tail -n 1)
  if [ -z "$d" ]; then
    echo "ccx: 找不到 ida-mcp 插件缓存(~/.claude/plugins/cache/HexRaysSA/ida-mcp/)" >&2
    exit 1
  fi
  export IDA_MCP_DIR="${d%/}"
  ida=$(python3 -c "import json,os;print(json.load(open(os.path.expanduser('~/.idapro/ida-config.json')))['Paths']['ida-install-dir'])" 2>/dev/null || true)
  if [ -z "$ida" ] || [ ! -d "$ida" ]; then
    echo "ccx: ~/.idapro/ida-config.json 里的 IDA 安装目录不存在(${ida:-未配置}),ida-mcp 起不来" >&2
    exit 1
  fi
}
