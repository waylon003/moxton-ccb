#!/bin/bash
# CCB 包装脚本 - 从正确的目录运行 CCB

CCB_HOME="$HOME/.local/share/codex-dual"
export PYTHONPATH="$CCB_HOME/lib:$PYTHONPATH"

cd "$CCB_HOME" && python "$HOME/.local/bin/ccb" "$@"
