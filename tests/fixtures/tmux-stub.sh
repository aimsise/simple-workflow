#!/usr/bin/env bash
# tests/fixtures/tmux-stub.sh — hermetic `tmux` replacement for the
# P1-1 inject-keys verify tests.
#
# Behaviour:
#   * `tmux send-keys ...`     -> exit 0 (real tmux returns 0 when the
#                                  pane exists; the rc the real binary
#                                  surfaces is what `inject_keys` reads
#                                  before the verify step). Optional
#                                  override: set SW_TEST_TMUX_SENDKEYS_RC
#                                  to make the stub return a non-zero
#                                  rc, mirroring "pane gone" errors.
#   * `tmux capture-pane ...`  -> print the contents of the env var
#                                  SW_TEST_TMUX_CAPTURE_OUT to stdout
#                                  and exit 0. If unset, print nothing
#                                  (mirrors a verify miss).
#   * any other tmux subcommand -> exit 0 silently. The library does
#                                  not call other tmux subcommands on
#                                  the post-inject path, but a
#                                  defensive default keeps the stub
#                                  forward-compatible.
#
# How to use: place this file's parent dir (tests/fixtures/) at the
# front of PATH and symlink/rename this script to `tmux`. Or, more
# commonly, materialise an ad-hoc bin/ inside the test, point a
# `tmux` symlink at this file, and prepend that bin/ to PATH.

set -u

# First positional arg is the tmux subcommand.
sub="${1:-}"
shift || true

case "$sub" in
  send-keys)
    exit "${SW_TEST_TMUX_SENDKEYS_RC:-0}"
    ;;
  capture-pane)
    # `-p` is mandatory in the production call (`-p -S -3 -E -`); we
    # don't bother parsing flags — the verify block only inspects
    # stdout, so emit the canned capture text verbatim.
    printf '%s' "${SW_TEST_TMUX_CAPTURE_OUT:-}"
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
