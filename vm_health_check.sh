#!/usr/bin/env bash
# vm_health_check.sh
# Checks VM health on Ubuntu based on CPU, Memory and Disk utilization.
# Healthy if ALL metrics are less than 60% utilized.
# Unhealthy if ANY metric is more than 60% utilized.
# Usage:
#   ./vm_health_check.sh            # just prints health
#   ./vm_health_check.sh explain    # prints health and explains the reason

set -euo pipefail

THRESHOLD=60    # threshold percent. Per spec: <60 => healthy; >60 => unhealthy
EXPLAIN=false

if [[ "${1:-}" == "explain" ]]; then
  EXPLAIN=true
fi

# Get CPU usage by reading /proc/stat twice to compute utilization over a short interval.
get_cpu_usage() {
  # read first
  read -r _user _nice _system _idle _iowait _irq _softirq _steal _guest _guest_nice < <(awk '/^cpu /{for(i=2;i<=11;i++) printf "%s ", $i; print ""}' /proc/stat)
  prev_idle=$((_idle + _iowait))
  prev_total=$((_user + _nice + _system + _idle + _iowait + _irq + _softirq + _steal + _guest + _guest_nice))

  sleep 0.5

  read -r _user _nice _system _idle _iowait _irq _softirq _steal _guest _guest_nice < <(awk '/^cpu /{for(i=2;i<=11;i++) printf "%s ", $i; print ""}' /proc/stat)
  idle=$((_idle + _iowait))
  total=$((_user + _nice + _system + _idle + _iowait + _irq + _softirq + _steal + _guest + _guest_nice))

  diff_idle=$((idle - prev_idle))
  diff_total=$((total - prev_total))

  # avoid division by zero
  if [[ $diff_total -eq 0 ]]; then
    echo "0.00"
    return
  fi

  usage=$(awk -v dt="$diff_total" -v di="$diff_idle" 'BEGIN { printf("%.2f", (1 - (di/dt)) * 100) }')
  echo "$usage"
}

# Get memory usage (%) using (total - available) / total * 100 for realistic usage on modern kernels
get_mem_usage() {
  # Use free's columns: total used free shared buff/cache available
  # Calculate (total - available) / total * 100
  awk '/^Mem:/ {
    total=$2; avail=$7;
    if (total>0) printf("%.2f", (total - avail) / total * 100);
    else printf("0.00");
  }' <(free -b)
}

# Get root (/) disk usage percentage (integer or decimal)
get_disk_usage() {
  # Use POSIX df -P to ensure consistent columns; target root filesystem "/"
  # output example: Use the Use% field
  pct=$(df -P / | awk 'NR==2 {gsub(/%/,"",$5); printf("%.2f", $5)}')
  echo "$pct"
}

cpu_usage=$(get_cpu_usage)
mem_usage=$(get_mem_usage)
disk_usage=$(get_disk_usage)

# Determine health: unhealthy if ANY metric is strictly greater than THRESHOLD
is_unhealthy=false
if awk -v v="$cpu_usage" -v t="$THRESHOLD" 'BEGIN{ if (v > t) exit 0; else exit 1 }'; then
  is_unhealthy=true
fi
if awk -v v="$mem_usage" -v t="$THRESHOLD" 'BEGIN{ if (v > t) exit 0; else exit 1 }'; then
  is_unhealthy=true
fi
if awk -v v="$disk_usage" -v t="$THRESHOLD" 'BEGIN{ if (v > t) exit 0; else exit 1 }'; then
  is_unhealthy=true
fi

if $is_unhealthy; then
  echo "VM Health: Unhealthy"
  if $EXPLAIN; then
    echo "Explanation (threshold > ${THRESHOLD}% = unhealthy):"
    printf "  CPU utilization:   %6s%%\n" "$cpu_usage"
    printf "  Memory utilization:%6s%%\n" "$mem_usage"
    printf "  Disk (/) used:     %6s%%\n" "$disk_usage"
    echo ""
    echo "  Metric(s) exceeding ${THRESHOLD}% (cause of 'Unhealthy'):" 
    if awk -v v="$cpu_usage" -v t="$THRESHOLD" 'BEGIN{ if (v > t) exit 0; else exit 1 }'; then
      echo "    - CPU utilization is above ${THRESHOLD}%"
    fi
    if awk -v v="$mem_usage" -v t="$THRESHOLD" 'BEGIN{ if (v > t) exit 0; else exit 1 }'; then
      echo "    - Memory utilization is above ${THRESHOLD}%"
    fi
    if awk -v v="$disk_usage" -v t="$THRESHOLD" 'BEGIN{ if (v > t) exit 0; else exit 1 }'; then
      echo "    - Disk usage (/) is above ${THRESHOLD}%"
    fi
  fi
  exit 1
else
  echo "VM Health: Healthy"
  if $EXPLAIN; then
    echo "Explanation (threshold > ${THRESHOLD}% = unhealthy):"
    printf "  CPU utilization:   %6s%% (below or equal to ${THRESHOLD}%)\n" "$cpu_usage"
    printf "  Memory utilization:%6s%% (below or equal to ${THRESHOLD}%)\n" "$mem_usage"
    printf "  Disk (/) used:     %6s%% (below or equal to ${THRESHOLD}%)\n" "$disk_usage"
    echo ""
    echo "  All metrics are at or below the threshold => VM declared Healthy."
  fi
  exit 0
fi
