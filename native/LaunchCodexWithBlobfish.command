#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OBSERVER="$HERE/blobfish-codex-observer"
if [ ! -x "$OBSERVER" ]; then
  printf '%s\n' '缺少水滴鱼事件转发程序，请将启动器与 blobfish-codex-observer 放在同一个文件夹。'
  exit 1
fi
APP='/Applications/ChatGPT.app'
PROCESS_NAME='ChatGPT'
if [ ! -x "$APP/Contents/Resources/codex" ]; then
  APP='/Applications/Codex.app'
  PROCESS_NAME='Codex'
fi
if [ ! -x "$APP/Contents/Resources/codex" ]; then
  printf '%s\n' '未找到 Codex 桌面附带的 CLI；没有改动任何设置。'
  exit 1
fi
if /usr/bin/pgrep -x "$PROCESS_NAME" >/dev/null 2>&1; then
  printf '%s\n' 'Codex 仍在运行。请先保存工作并自行退出，再双击此启动器；不会自动退出或重启你的任务。'
  exit 1
fi
# Per-launch environment only: no global configuration, launchctl, trust or auth changes.
/usr/bin/open -a "$APP" \
  --env "CODEX_CLI_PATH=$OBSERVER" \
  --env "BLOBFISH_CODEX_REAL_CLI=$APP/Contents/Resources/codex"
printf '%s\n' '已启动 Codex。问题预览可在水滴鱼「连接与隐私」中开启或关闭；普通方式打开 Codex 即可停用转发层。'
