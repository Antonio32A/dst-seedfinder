#!/usr/bin/env bash
# usage: proof.sh [-j JOBS]
# The proof gate, file by file: checks LAWS.bend and every laws/*.bend on its own (JOBS at a time, default 1, each
# under a 16 GB cap), prints each file's wall time and peak RSS, and fails when any file fails. It also fails when
# PROOF.bend holds anything but imports or misses a law file, so `scripts/bend.sh PROOF.bend` checks exactly the same
# laws.
# Budgets: PROOF_FILE_SECS (30) and PROOF_FILE_MB (2000) per file, flagged "over budget".
set -uo pipefail
root="$(cd "$(dirname "$(realpath "$0")")/.." && pwd)"
parallel=1
[[ "${1:-}" == "-j" ]] && parallel="${2:?usage: proof.sh [-j JOBS]}"
secs_budget="${PROOF_FILE_SECS:-30}"
mb_budget="${PROOF_FILE_MB:-2000}"
cd "$root/seedfinder" || exit 2
files=(LAWS.bend laws/*.bend)
status=0
for file in "${files[@]}"; do
  grep -qx "import \./${file} as [A-Za-z]*" PROOF.bend || { echo "proof: PROOF.bend does not import $file"; status=1; }
done
extra="$(grep -v -e '^import ' -e '^$' PROOF.bend)"
[[ -z "$extra" ]] || { echo "proof: PROOF.bend may only hold imports; move this into a law file:"; echo "$extra"; status=1; }
logs="$(mktemp -d "${TMPDIR:-/tmp}/proof.XXXXXX")"
trap 'rm -rf "$logs"' EXIT
start=$(date +%s.%N)
for i in "${!files[@]}"; do
  while (( $(jobs -rp | wc -l) >= parallel )); do wait -n; done
  ( ulimit -v 16000000
    timeout 900 /usr/bin/time -o "$logs/$i.time" -f '%e %M' "$root/scripts/bend.sh" "${files[$i]}" > "$logs/$i.out" 2>&1
    echo $? > "$logs/$i.exit" ) &
done
wait
for i in "${!files[@]}"; do
  read -r wall kb < <(tail -1 "$logs/$i.time" 2>/dev/null) || { wall=0; kb=0; }
  result="$(tail -1 "$logs/$i.out")"
  exit_code="$(cat "$logs/$i.exit")"
  mb=$((kb / 1024))
  note=""
  if [[ "$exit_code" != 0 || "$result" != "All terms check." ]]; then
    note="FAILED (exit $exit_code)"; status=1
  elif (( mb > mb_budget )) || [[ "$(echo "$wall > $secs_budget" | bc)" == 1 ]]; then
    note="over budget (${secs_budget} s, ${mb_budget} MB)"
  fi
  printf '%-16s %7.1f s %6d MB  %s\n' "${files[$i]}" "$wall" "$mb" "${note:-ok}"
  [[ "$exit_code" != 0 || "$result" != "All terms check." ]] && sed 's/^/    /' "$logs/$i.out" | tail -20
done
printf 'proof: %d files, %.1f s wall, %s\n' "${#files[@]}" "$(echo "$(date +%s.%N) - $start" | bc)" \
  "$([[ $status == 0 ]] && echo "All terms check." || echo "FAILED")"
exit $status
