#!/usr/bin/env bash
# health_check.sh - Simple VM health checker (Linux/macOS)
set -euo pipefail

OS="$(uname -s)"

# ---------- Helpers ----------
human_bytes() {
  local bytes=${1:-0}
  local units=(B KB MB GB TB)
  local i=0
  while (( bytes > 1024 && i < ${#units[@]}-1 )); do
    bytes=$((bytes/1024))
    ((i++))
  done
  echo "${bytes}${units[$i]}"
}

round() { awk 'BEGIN {printf "%.1f\n", '"$1"'}'; }

# ---------- Metrics ----------
cpu_usage_linux() {
  local idle
  idle=$(top -bn1 | awk -F',' '/Cpu\(s\)/ {
      for(i=1;i<=NF;i++) if ($i ~ /id/) { gsub(/[^0-9.]/,"",$i); idle=$i }
    } END { if (idle=="") print "NA"; else print idle }')
  if [[ "$idle" == "NA" || -z "$idle" ]]; then echo "NA"; else
    awk 'BEGIN{printf "%.1f\n", 100-'"$idle"'}'
  fi
}

cpu_usage_macos() {
  local idle
  idle=$(top -l 1 | awk -F'[:,% ]+' '/CPU usage/ {for(i=1;i<=NF;i++) if($i=="idle") print $(i-1)}')
  if [[ -z "$idle" ]]; then echo "NA"; else
    awk 'BEGIN{printf "%.1f\n", 100-'"$idle"'}'
  fi
}

mem_usage_linux() {
  local total used
  read -r _ total used _ < <(free -m | awk '/^Mem:/ {print $1,$2,$3,$4}')
  awk 'BEGIN{printf "%.1f\n",('"$used"'/'"$total"')*100}'
}

mem_usage_macos() {
  local total free inactive speculative pagesize free_bytes used_bytes pct
  total=$(sysctl -n hw.memsize) || total=0
  pagesize=$(vm_stat | awk 'NR==1{gsub("[^0-9]","",$8);print $8}')
  free=$(vm_stat | awk '/Pages free/ {gsub("[^0-9]","",$3); print $3}')
  inactive=$(vm_stat | awk '/Pages inactive/ {gsub("[^0-9]","",$3); print $3}')
  speculative=$(vm_stat | awk '/Pages speculative/ {gsub("[^0-9]","",$3); print $3}')
  free=${free:-0}; inactive=${inactive:-0}; speculative=${speculative:-0}; pagesize=${pagesize:-4096}
  free_bytes=$(( (free+inactive+speculative) * pagesize ))
  used_bytes=$(( total - free_bytes ))
  if (( total > 0 )); then
    pct=$(awk 'BEGIN{printf "%.1f\n",('"$used_bytes"'/'"$total"')*100}')
  else
    pct="NA"
  fi
  echo "$pct"
}

disk_usage_root() {
  df -P / | awk 'END{gsub("%","",$5); print $5}'
}

# ---------- Collect ----------
get_metrics() {
  local cpu mem disk
  case "$OS" in
    Linux) cpu=$(cpu_usage_linux); mem=$(mem_usage_linux) ;;
    Darwin) cpu=$(cpu_usage_macos); mem=$(mem_usage_macos) ;;
    *) cpu="NA"; mem="NA" ;;
  esac
  disk=$(disk_usage_root)
  echo "$cpu|$mem|$disk"
}

# ---------- Interpret ----------
interpret() {
  local cpu="$1" mem="$2" disk="$3"
  local level="healthy" reasons=()

  if [[ "$cpu" != "NA" ]]; then
    awk -v v="$cpu" 'BEGIN{ if(v>95) exit 2; else if(v>85) exit 1; else exit 0 }'
    case $? in
      1) level="warning"; reasons+=("CPU使用率较高（"$(round "$cpu")"%）");;
      2) level="critical"; reasons+=("CPU使用率过高（"$(round "$cpu")"%）");;
    esac
  fi
  if [[ "$mem" != "NA" ]]; then
    awk -v v="$mem" 'BEGIN{ if(v>95) exit 2; else if(v>85) exit 1; else exit 0 }'
    case $? in
      1) [[ "$level" == "healthy" ]] && level="warning"; reasons+=("内存占用较高（"$(round "$mem")"%）");;
      2) level="critical"; reasons+=("内存占用过高（"$(round "$mem")"%）");;
    esac
  fi
  if [[ -n "$disk" ]]; then
    awk -v v="$disk" 'BEGIN{ if(v>95) exit 2; else if(v>90) exit 1; else exit 0 }'
    case $? in
      1) [[ "$level" == "healthy" ]] && level="warning"; reasons+=("磁盘使用率偏高（${disk}%）");;
      2) level="critical"; reasons+=("磁盘空间几乎耗尽（${disk}% 已用）");;
    esac
  fi
  echo "$level|${reasons[*]:-无明显异常}"
}

# ---------- UI ----------
usage() {
cat <<'EOF'
用法：
  ./health_check.sh             # 交互式检查
  ./health_check.sh explain     # 解释性摘要
  ./health_check.sh --help      # 查看帮助
  ./health_check.sh --json      # JSON 输出
EOF
}

json_out() {
  local cpu="$1" mem="$2" disk="$3" level="$4" reason="$5"
  cat <<JSON
{
  "os": "$OS",
  "cpu_usage_percent": "$cpu",
  "memory_usage_percent": "$mem",
  "disk_usage_percent": "$disk",
  "overall": "$level",
  "reasons": "$(echo "$reason" | sed 's/"/\"/g')"
}
JSON
}

explain_out() {
  local cpu="$1" mem="$2" disk="$3" level="$4" reason="$5"
  echo "===== VM 健康报告 ====="
  echo "CPU: ${cpu}%"
  echo "内存: ${mem}%"
  echo "磁盘: ${disk}%"
  echo "结论: $level"
  echo "原因: $reason"
  echo "======================"
}

interactive_out() {
  local cpu="$1" mem="$2" disk="$3" level="$4" reason="$5"
  echo "== VM 快速体检 =="
  printf "CPU: %s%% | MEM: %s%% | DISK: %s%% | 结论: %s\n" "$cpu" "$mem" "$disk" "$level"
  read -r -p "需要详细解释吗？(Y/n) " ans
  if [[ "${ans:-Y}" =~ ^[Yy]$ ]]; then
    explain_out "$cpu" "$mem" "$disk" "$level" "$reason"
  fi
}

main() {
  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then usage; exit 0; fi
  IFS='|' read -r CPU MEM DISK <<<"$(get_metrics)"
  IFS='|' read -r LEVEL REASON <<<"$(interpret "$CPU" "$MEM" "$DISK")"
  case "${1:-}" in
    explain) explain_out "$CPU" "$MEM" "$DISK" "$LEVEL" "$REASON" ;;
    --json)  json_out "$CPU" "$MEM" "$DISK" "$LEVEL" "$REASON" ;;
    "" )     interactive_out "$CPU" "$MEM" "$DISK" "$LEVEL" "$REASON" ;;
    * )      echo "未知参数：$1"; usage; exit 1 ;;
  esac
}
main "$@"
