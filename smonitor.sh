#!/usr/bin/env bash
if [ "x$BASH" = x ] || [ ! "$BASH_VERSINFO" ] || [ "$BASH_VERSINFO" -lt 4 ]; then
  echo "Error: Must use bash version 4+." >&2
  exit 1
fi
set -ue

USER=${USER:-nick}
LockFile=.smonitor.pid
ScriptName=$(basename "$0")

Usage="Usage: \$ $ScriptName my/cron/dir"

function main {
  if [[ "$#" -lt 1 ]] || [[ "$1" == '-h' ]]; then
    fail "$Usage"
  fi
  output_dir="$1"
  lock_path="$output_dir/$LockFile"

  set +e
  if already_running "$lock_path"; then
    fail "Error: Looks like it's already running (pid $(cat "$lock_path"))."
  fi
  set -e
  echo "$$" > "$lock_path"

  date=$(date)

  print_jobs "$date" > "$output_dir/jobs.txt"

  print_jobs "$date" "$USER" > "$output_dir/myjobs.txt"

  print_cpus "$date" > "$output_dir/cpus.txt"

  print_sinfo "$date" > "$output_dir/sinfo.txt"

  rm "$lock_path"
}

function print_jobs {
  date="$1"
  if [[ "$#" -ge 2 ]]; then
    user_arg="-u $2"
  else
    user_arg=
  fi
  echo "As of $date:"
  echo
  echo '  JOBID PRIORITY     USER      STATE        TIME     MEM CPUS SHARED NODE           NAME'
  squeue -h -p general $user_arg -o '%.7i %.8Q %.8u %.10T %.11M %.7m %.4C %6h %14R %j' \
    | sort -g -k 2
}

function print_cpus {
  date="$1"
  echo "As of $date:"
  echo
  echo -e    "\t     CPUs\t  Mem (GB)"
  echo -e "Node\tTotal\tFree\tTotal\tFree"
  sinfo --noheader --Node --partition general --states idle,alloc \
      --Format nodelist,memory,allocmem,freemem,cpusstate \
    | tr '/' ' ' \
    | awk -v OFS='\t' '
      {
        totl_cpus += $8
        free_cpus += $6
        totl_mem += $2/1024
        free_mem += ($2-$3)/1024
        printf("%-8s%4d%7d%9.0f%7.0f\n", $1, $8, $6, $2/1024, ($2-$3)/1024)
      }
      END {
        printf("Total   %4d%7d%9.0f%7.0f\n", totl_cpus, free_cpus, totl_mem, free_mem)
        printf("         100%%%8.1f%%   100%%%8.1f%%\n", 100*free_cpus/totl_cpus, 100*free_mem/totl_mem)
      }'
}

function print_sinfo {
  date="$1"
  echo "As of $date:"
  echo
  sinfo
}

function already_running {
  lock_path="$1"
  if [[ -s "$lock_path" ]]; then
    pid=$(cat "$lock_path")
  else
    return 1
  fi
  awk_script='
$1 == "'"$USER"'" && $2 == '"$pid"' {
  for (i=11; i<=NF; i++) {
    if ($i ~ /\/'"$ScriptName"'$/) {
      print $i
    }
  }
}'
  if [[ $(ps aux | awk "$awk_script") ]]; then
    return 0
  else
    return 1
  fi
}

function fail {
  echo "$@" >&2
  exit 1
}

main "$@"
