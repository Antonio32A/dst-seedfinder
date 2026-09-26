#!/bin/sh
set -u
: "${CALLBACK_URL:?}" "${RUNNER_TOKEN:?}" "${JOB_LIMIT:?}" "${JOB_TIME_LIMIT:?}" "${JOB_START_SEED:?}"

max_chunk=262144
work=$(mktemp -d)
config=$work/config.json
output=$work/output
chunk=$work/chunk
errors=$work/errors
exit_file=$work/exit
offset=0
exit_code=
status=

stop() {
    pkill -x seedfinder
    exit "$1"
}

trap 'stop 143' TERM
trap 'stop 130' INT

request() {
    target=$1
    shift
    wget -q -T 20 -U dst-seedfinder-runner -O "$target" \
        --header "Authorization: Bearer $RUNNER_TOKEN" "$@" "$CALLBACK_URL" 2>"$errors" &
    if wait $!; then
        status=200
        return
    fi
    cat "$errors" >&2
    status=$(sed -n 's|.*server returned error: HTTP/[0-9.]* \([0-9]*\).*|\1|p' "$errors")
}

fetch_config() {
    while :; do
        request "$config"
        case $status in
        200) return ;;
        410) exit 0 ;;
        4*) exit 1 ;;
        esac
        sleep 2
    done
}

start_search() {
    : >"$output"
    (
        {
            seedfinder -- world find --start-seed "$JOB_START_SEED" \
                --limit "$JOB_LIMIT" --time-limit "$JOB_TIME_LIMIT" --config "$config" 2>&1
            echo $? >"$work/status"
        } | tr -d '\000' >"$output"
        mv "$work/status" "$exit_file"
    ) &
}

accept_status() {
    case $status in
    200) offset=$((offset + size)) ;;
    409) offset=0 ;;
    410) stop 0 ;;
    esac
    [ "$status" = 200 ]
}

post_chunk() {
    tail -c +$((offset + 1)) "$output" | head -c $max_chunk >"$chunk"
    size=$(stat -c %s "$chunk")
    set -- --header "X-Offset: $offset"
    if [ -n "$exit_code" ] && [ $((offset + size)) -eq "$(stat -c %s "$output")" ]; then
        set -- "$@" --header "X-Exit: $exit_code"
    fi
    request /dev/null "$@" --header "Content-Type: application/octet-stream" --post-file "$chunk"
    accept_status
}

stream_output() {
    until [ -s "$exit_file" ]; do
        sleep 1
        post_chunk
    done
}

flush() {
    post_chunk || {
        sleep 1
        return 1
    }
    [ "$offset" -eq "$(stat -c %s "$output")" ]
}

finish() {
    exit_code=$(cat "$exit_file")
    until flush; do :; done
}

fetch_config
start_search
stream_output
finish
