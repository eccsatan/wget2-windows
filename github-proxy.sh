#!/bin/bash
# ============================================================
# github-proxy.sh —— GitHub 前缀代理「测速 + 选择 + 设置」独立工具
# ------------------------------------------------------------
# 说明：本脚本把「测试候选代理 → 选最快 → 用 git config insteadOf 设置」从
#       build-msys64.sh 中独立出来。不改任何脚本内的下载地址，只通过
#       git config --global url."https://代理/https://github.com/".insteadOf 生效。
# 用法（在 WSL 中执行）：
#   bash /mnt/d/wget2/github-proxy.sh            测试全部候选 → 选最快 → 设置 git 代理
#   bash /mnt/d/wget2/github-proxy.sh --test     仅测速并输出排名（不设置）
#   bash /mnt/d/wget2/github-proxy.sh --set      跳过测速，直接用当前 FASTEST 设置
#   bash /mnt/d/wget2/github-proxy.sh --remove   移除所有 github / raw 代理
#   bash /mnt/d/wget2/github-proxy.sh --show     显示当前代理规则
# 产出物：/mnt/d/wget2/proxy-speed-report.txt   （测速报告）
# ============================================================

# ---------- 候选代理列表（github 前缀代理） ----------
PROXIES=(
  "github.boki.moe"
  "ghproxy.cxkpro.top"
  "ghproxy.monkeyray.net"
  "gh-proxy.org"
  "ghfast.top"
  "gh.monlor.com"
  "cdn.crashmc.com"
  "gitproxy.mrhjx.cn"
  "github.geekery.cn"
  "ghproxy.it"
  "gh.chjina.com"
  "gh.ddlc.top"
  "gh.h233.eu.org"
  "gh-proxy.org"
  "cdn.gh-proxy.org"
  "edgeone.gh-proxy.org"
  "cors.isteed.cc"
  "gh.jasonzeng.dev"
  "github.ednovas.xyz"
  "ghfile.geekertao.top"
  "ghp.keleyaa.com"
  "ghpxy.hwinzniej.top"
  "git.yylx.win"
  "gh.xxooo.cf"
  "gh.idayer.com"
  "down.npee.cn"
  "raw.ihtw.moe"
  "xget.xi-xu.me"
  "gh.zwy.one"
  "ghproxy.net"
  "wget.la"
)

# 测速仓库（中等大小，depth=1，用于区分吞吐）
REPO="facebook/zstd"
# 当前已知最快（--set / build-msys64.sh --ensure 时直接使用；由 --test 更新报告）
FASTEST="github.boki.moe"
REPORT=/mnt/d/wget2/proxy-speed-report.txt

# ---------- 工具函数 ----------
die() { echo "ERROR: $1"; exit 1; }

remove_proxy() {
  echo "== 移除现有 github/raw 代理 =="
  local rules key line
  # 先列出全部 url 重写规则；无返回说明没有代理
  rules=$(git config --global --get-regexp url 2>/dev/null)
  if [ -z "$rules" ]; then
    echo "  (当前无代理规则)"
    return 0
  fi
  # 每行形如: url.https://host/https://github.com/.insteadof https://github.com/
  # 取空格分隔的左部分作为键名，直接 unset（不依赖任何预置代理列表，通用）
  while IFS= read -r line; do
    key="${line%% *}"
    echo "  移除: $key"
    git config --global --unset "$key" 2>/dev/null
  done <<< "$rules"
  echo "  已清理完毕"
}

show_proxy() {
  echo "== 当前 github 代理规则 =="
  local rules
  rules=$(git config --global --get-regexp url 2>/dev/null)
  if [ -z "$rules" ]; then echo "  (无 —— 直连)"; else echo "$rules"; fi
}

set_proxy() { # $1 = 代理域名
  local host="$1"
  [ -z "$host" ] && die "set_proxy 需要代理域名参数"
  git config --global url."https://$host/https://github.com/".insteadOf "https://github.com/"
  git config --global url."https://$host/https://raw.githubusercontent.com/".insteadOf "https://raw.githubusercontent.com/"
  echo "已设置 git 代理: $host"
  echo "  url.https://$host/https://github.com/.insteadof  https://github.com/"
  echo "  url.https://$host/https://raw.githubusercontent.com/.insteadof  https://raw.githubusercontent.com/"
}

# 测速：连通性预筛 + git clone 实测，输出报告并更新 FASTEST
test_speed() {
  local TMP=/tmp/ghproxy_sel
  rm -rf "$TMP" && mkdir -p "$TMP"
  echo "== 测速开始：连通性预筛 ${#PROXIES[@]} 个代理 =="
  local -a ALIVE=()
  local p code
  for p in "${PROXIES[@]}"; do
    code=$(timeout 8 curl -sI -o /dev/null -w '%{http_code}' "https://$p/https://github.com/" 2>/dev/null)
    if [ -n "$code" ] && [ "$code" != "000" ]; then
      echo "  ALIVE  $p (HTTP $code)"
      ALIVE+=("$p")
    else
      echo "  DEAD   $p"
    fi
  done
  echo "可达 ${#ALIVE[@]} 个，进行 git clone 实测（$REPO, depth=1, 45s 上限）..."
  : > "$REPORT"
  local fastest="" fastest_t=999999
  for p in "${ALIVE[@]}"; do
    rm -rf "$TMP/$p"
    local st en dur rc sz
    st=$(date +%s.%N)
    GIT_TERMINAL_PROMPT=0 timeout 45 git clone --depth=1 -q "https://$p/https://github.com/$REPO" "$TMP/$p" 2>"$TMP/$p.err"
    rc=$?; en=$(date +%s.%N)
    dur=$(echo "$en - $st" | bc | xargs printf "%.2f")
    if [ $rc -eq 0 ]; then
      sz=$(du -sk "$TMP/$p" 2>/dev/null | cut -f1)
      echo "  OK   $p  ${dur}s  ${sz}KB"
      echo "OK   $p  ${dur}s  ${sz}KB" >> "$REPORT"
      # 取耗时最小者（>1MB 才算有效克隆）
      if [ "${sz:-0}" -gt 1024 ] && [ "$(echo "$dur < $fastest_t" | bc)" = "1" ]; then
        fastest_t="$dur"; fastest="$p"
      fi
    else
      echo "  FAIL $p  rc=$rc"
      echo "FAIL $p  rc=$rc" >> "$REPORT"
    fi
  done
  if [ -n "$fastest" ]; then
    FASTEST="$fastest"
    echo "" >> "$REPORT"
    echo "推荐代理: $fastest （clone 实测 ${fastest_t}s）" >> "$REPORT"
    echo "== 测速完成：最快 = $fastest （${fastest_t}s）=="
    echo "报告已保存: $REPORT"
  else
    echo "== 无可用代理 ==（可能网络异常，请稍后重试）"
    echo "推荐代理: none" >> "$REPORT"
  fi
}

# ---------- 主流程 ----------
MODE="${1:-all}"
case "$MODE" in
  --remove) remove_proxy; show_proxy ;;
  --show)   show_proxy ;;
  --test)   test_speed ;;
  --set)    remove_proxy; set_proxy "$1"; show_proxy ;;
  --ensure) remove_proxy; set_proxy "$FASTEST"; show_proxy ;;
  all)
    remove_proxy
    test_speed
    if [ "$FASTEST" != "none" ] && [ -n "$FASTEST" ]; then
      set_proxy "$FASTEST"; show_proxy
    else
      echo "测速未选到可用代理，未设置。"
    fi
    ;;
  *)
    echo "未知参数: $MODE"; echo "用法见脚本头注释。"; exit 1 ;;
esac
