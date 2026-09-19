#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Smoke test for yoloagy on Linux/macOS with tmux. Needs no agy: a stub `agy`
# on PATH records its working directory and sleeps.
#
# Isolation: TMUX_TMPDIR points at a private temp directory, so every tmux
# server this test starts has its socket there and none of the caller's own
# sessions are visible to it or reachable by it. Cleanup kills only the
# servers this test started, by exact socket name.
set -eu

here=$(cd "$(dirname -- "$0")/.." && pwd)
yoloagy="$here/yoloagy"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/yoloagy-smoke.XXXXXX")
export TMUX_TMPDIR="$tmp/tmux"
mkdir -p "$TMUX_TMPDIR"
unset TMUX TMUX_PANE

started=()
cleanup() {
    local s
    for s in "${started[@]}"; do
        tmux -L "$s" kill-server 2>/dev/null || true
    done
    rm -rf "$tmp"
}
trap cleanup EXIT

pass=0
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { pass=$((pass + 1)); echo "ok - $*"; }

# Stub agy: writes its cwd to $SMOKE_MARKS/<session>, then stays alive.
mkdir -p "$tmp/bin" "$tmp/marks"
cat > "$tmp/bin/agy" <<'EOF'
#!/usr/bin/env bash
s=$(tmux display-message -p '#{session_name}' 2>/dev/null || echo unknown)
pwd > "$SMOKE_MARKS/$s"
exec sleep 600
EOF
chmod +x "$tmp/bin/agy"
export PATH="$tmp/bin:$PATH" SMOKE_MARKS="$tmp/marks"

wait_for_file() {
    local f="$1"
    for _ in $(seq 1 50); do
        [ -s "$f" ] && return 0
        sleep 0.1
    done
    return 1
}

server_pid() { tmux -L "$1" list-sessions -F '#{pid}' 2>/dev/null | head -n1; }

# --help
out=$("$yoloagy" --help)
case "$out" in *"Usage:"*) ok "--help prints usage" ;; *) fail "--help: $out" ;; esac

# --list with nothing running
out=$("$yoloagy" --list)
[ "$out" = "no yoloagy sessions" ] || fail "--list on empty: $out"
ok "--list reports no sessions"

# Argument validation
if "$yoloagy" --bogus >/dev/null 2>&1; then fail "--bogus accepted"; fi
if "$yoloagy" 'a/b' >/dev/null 2>&1; then fail "alias with / accepted"; fi
ok "rejects unknown flags and unsafe aliases"

# A temp repository with a main branch.
repo="$tmp/proj"
mkdir -p "$repo"
git -C "$repo" init -q -b main
git -C "$repo" -c user.name=smoke -c user.email=smoke@example.invalid \
    commit -q --allow-empty -m init
cd "$repo"

[ "$("$yoloagy" --prefix)" = "proj" ] || fail "--prefix in repo"
ok "--prefix derives the repo name"

# Named session from the primary checkout: detached, isolated in a worktree.
session=proj-smoke
started+=("$session")
out=$("$yoloagy" --detach smoke 2>"$tmp/err")
wt="$repo/.worktrees/$session"
case "$out" in *"created detached session: $session"*) ;; *) fail "detach: $out" ;; esac
case "$out" in *"session=$session"*) ;; *) fail "no session= line: $out" ;; esac
case "$out" in *"dir=$wt"*) ;; *) fail "no dir= line for worktree: $out" ;; esac
ok "--detach creates $session and prints session= and dir="

[ -d "$wt" ] || fail "worktree $wt missing"
[ "$(git -C "$wt" rev-parse --abbrev-ref HEAD)" = "yolo/$session" ] \
    || fail "worktree not on yolo/$session"
ok "named session gets worktree on branch yolo/$session"

wait_for_file "$SMOKE_MARKS/$session" || fail "stub agy never started"
[ "$(cat "$SMOKE_MARKS/$session")" = "$wt" ] || fail "agy ran in $(cat "$SMOKE_MARKS/$session")"
ok "agy runs inside the worktree"

[ "$(tmux -L "$session" show-options -s -v escape-time)" = "10" ] \
    || fail "escape-time not tuned"
ok "escape-time set to 10ms"

# A foreign tmux server in the same socket dir must not be listed.
started+=("foreign")
tmux -L foreign new-session -d -s unrelated "sleep 600"

out=$("$yoloagy" --list)
[ "$out" = "$session" ] || fail "--list: expected only $session, got: $out"
ok "--list shows the session and not unrelated servers"

# Completion offers the alias.
# shellcheck source=completion/yoloagy.bash
. "$here/completion/yoloagy.bash"
ln -s "$yoloagy" "$tmp/bin/yoloagy"
COMP_WORDS=(yoloagy "")
COMP_CWORD=1
_yoloagy_complete
[ "${COMPREPLY[*]}" = "smoke" ] || fail "completion offered: ${COMPREPLY[*]}"
COMP_WORDS=(yoloagy "--res")
_yoloagy_complete
[ "${COMPREPLY[*]}" = "--restart" ] || fail "flag completion: ${COMPREPLY[*]}"
ok "completion offers live aliases and flags"

# Relaunch reattaches rather than replacing.
pid1=$(server_pid "$session")
out=$("$yoloagy" --detach smoke 2>/dev/null)
case "$out" in *"session already running: $session"*) ;; *) fail "rerun: $out" ;; esac
[ "$(server_pid "$session")" = "$pid1" ] || fail "rerun replaced the server"
ok "re-running keeps the existing session"

# From inside the worktree, the same alias resolves to the same session.
out=$(cd "$wt" && "$yoloagy" --detach smoke 2>/dev/null)
case "$out" in *"session=$session"*"dir=$wt"*) ;; *) fail "from worktree: $out" ;; esac
ok "same alias from inside the worktree finds the session"

# --restart kills and recreates.
rm -f "$SMOKE_MARKS/$session"
out=$("$yoloagy" --restart --detach smoke 2>/dev/null)
case "$out" in *"killing existing session: $session"*) ;; *) fail "restart: $out" ;; esac
[ "$(server_pid "$session")" != "$pid1" ] || fail "restart kept the old server"
kill -0 "$pid1" 2>/dev/null && fail "old server $pid1 still alive"
wait_for_file "$SMOKE_MARKS/$session" || fail "agy not restarted"
ok "--restart kills the old server and starts a new one"

# --here keeps the current directory.
started+=("proj-inplace")
out=$("$yoloagy" --here --detach inplace 2>/dev/null)
case "$out" in *"dir=$repo"*) ;; *) fail "--here: $out" ;; esac
[ ! -e "$repo/.worktrees/proj-inplace" ] || fail "--here created a worktree"
ok "--here launches in place"

# YOLOAGY_WORKTREE=0 turns worktrees off for every launch; --worktree turns
# one back on.
started+=("proj-envoff")
out=$(YOLOAGY_WORKTREE=0 "$yoloagy" --detach envoff 2>/dev/null)
case "$out" in *"dir=$repo"*) ;; *) fail "YOLOAGY_WORKTREE=0: $out" ;; esac
[ ! -e "$repo/.worktrees/proj-envoff" ] || fail "YOLOAGY_WORKTREE=0 created a worktree"
ok "YOLOAGY_WORKTREE=0 launches named sessions in place"

started+=("proj-envforce")
out=$(YOLOAGY_WORKTREE=0 "$yoloagy" --worktree --detach envforce 2>/dev/null)
case "$out" in *"dir=$repo/.worktrees/proj-envforce"*) ;; *) fail "--worktree over YOLOAGY_WORKTREE=0: $out" ;; esac
[ -d "$repo/.worktrees/proj-envforce" ] || fail "--worktree made no worktree"
ok "--worktree overrides YOLOAGY_WORKTREE=0"

# The bare session launches in place, as "agy".
started+=("agy")
out=$("$yoloagy" --detach 2>/dev/null)
case "$out" in *"session=agy"*"dir=$repo"*) ;; *) fail "bare: $out" ;; esac
ok "bare yoloagy is session 'agy' in the current directory"

# A missing agy fails clearly.
if out=$(YOLOAGY_AGY=no-such-agy-binary "$yoloagy" --detach missing 2>&1); then
    fail "missing agy accepted"
fi
case "$out" in *"not found on PATH"*) ;; *) fail "missing agy message: $out" ;; esac
ok "missing agy is reported"

echo "all $pass checks passed"
