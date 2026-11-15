#!/usr/bin/env bash
# First-launch test: start a PayCon binary the way a new user would -- empty
# home folder, no data directory, no PayCon.conf, default networking (DNS
# seeds, UPnP, listening, external address lookup) -- and check it is still
# running after a while. It runs under gdb when available so a crash prints a
# backtrace.
#
#   contrib/ci/first-launch.sh <binary> [seconds] [extra args...]
set -u
BIN=$(cd "$(dirname "$1")" && pwd)/$(basename "$1"); shift
SECS=${1:-90}; shift || true
APPDATA_REAL=${APPDATA:-}
H=$(mktemp -d); export HOME="$H"
# (Windows finds the data folder through the shell API, so on Windows this
# uses the runner's real, still-empty %APPDATA%\PayCon)
LOGDIR="$H/.PayCon"; case "$(uname -s)" in
  Darwin) LOGDIR="$H/Library/Application Support/PayCon";;
  MINGW*|MSYS*) LOGDIR="$(cygpath -u "$APPDATA_REAL")/PayCon";;
esac
echo "== first launch of $BIN (HOME=$H), watching for ${SECS}s"
if command -v gdb >/dev/null; then
  gdb -q -batch -ex "set pagination off" -ex "handle SIGPIPE nostop noprint pass" \
      -ex run -ex "thread apply all bt 25" --args "$BIN" "$@" > launch.log 2>&1 &
else
  "$BIN" "$@" > launch.log 2>&1 &
fi
PID=$!
ok=1
for i in $(seq 1 "$SECS"); do
  if ! kill -0 $PID 2>/dev/null; then ok=0; break; fi
  # under gdb the process stays alive while gdb prints the backtrace
  grep -q "received signal\|exited with code\|exited normally" launch.log 2>/dev/null && { ok=0; break; }
  sleep 1
done
sleep 3
echo "---- program output / backtrace"; cat launch.log
echo "---- end of debug.log"; tail -n 60 "$LOGDIR/debug.log" 2>/dev/null || echo "(no debug.log in $LOGDIR)"
pkill -P $PID 2>/dev/null; kill $PID 2>/dev/null
command -v taskkill >/dev/null && taskkill //F //IM "$(basename "$BIN")" >/dev/null 2>&1
if [ $ok = 1 ]; then echo "first launch: still running after ${SECS}s"; else echo "first launch: PROGRAM DIED"; exit 1; fi
