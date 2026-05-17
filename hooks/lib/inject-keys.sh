#!/usr/bin/env bash
# hooks/lib/inject-keys.sh — terminal-aware keystroke injector.
#
# Public function:
#   inject_keys "<text>" [--enter|--no-enter]
#
# Detection priority (multiplexer-first):
#   1. tmux              ($TMUX set)
#   2. GNU screen        ($STY set)
#   3. kitty             (kitty + remote control enabled)
#   4. WezTerm           ($TERM_PROGRAM=WezTerm)
#   5. iTerm2 (macOS)    ($TERM_PROGRAM=iTerm.app)
#
# Apple Terminal is deliberately NOT supported (S3 fix). The macOS
# Accessibility keystroke API is system-wide and would focus-leak
# `/compact<Enter>` to whatever app the user has focused at injection
# time (Slack, VSCode, browser, etc.). Apple Terminal users fall
# through to "no backend" with a silent skip; install tmux for
# auto-compact support.
#
# Testing hook (M3): set `INJECT_KEYS_DRY_RUN=1` to detect-and-log the
# would-be backend without invoking it. Useful for CT-AC-06 fixtures.
#
# Return codes: 0 = injected (or dry-run logged), 1 = no supported
# backend OR backend command failed (S5 fix), 2 = bad args.
# Stdout: empty. Stderr: single status line "[inject-keys] ...".

# Internal: detect backend name. Echoes one of: tmux / screen / kitty /
# wezterm / iterm2 / none. Returns 0 if a backend was detected, 1 if
# none.
_inject_detect_backend() {
  if [ -n "${TMUX:-}" ] && command -v tmux >/dev/null 2>&1; then
    echo "tmux"; return 0
  fi
  if [ -n "${STY:-}" ] && command -v screen >/dev/null 2>&1; then
    echo "screen"; return 0
  fi
  if { [ -n "${KITTY_PID:-}" ] || [ "${TERM:-}" = "xterm-kitty" ]; } \
     && command -v kitty >/dev/null 2>&1; then
    echo "kitty"; return 0
  fi
  if [ "${TERM_PROGRAM:-}" = "WezTerm" ] && command -v wezterm >/dev/null 2>&1; then
    echo "wezterm"; return 0
  fi
  if [ "${TERM_PROGRAM:-}" = "iTerm.app" ] && command -v osascript >/dev/null 2>&1; then
    echo "iterm2"; return 0
  fi
  echo "none"
  return 1
}

inject_keys() {
  local text="$1" enter="${2:---enter}"
  [ -z "$text" ] && { echo "inject_keys: empty text" >&2; return 2; }

  local backend rc
  backend=$(_inject_detect_backend) || {
    echo "[inject-keys] no backend (TMUX=${TMUX:-} STY=${STY:-} TERM_PROGRAM=${TERM_PROGRAM:-} TERM=${TERM:-})" >&2
    return 1
  }

  # M3 + H11: DRY_RUN short-circuit for testing. Include target pane /
  # window in the log so CT-AC-26 can assert the dispatcher would target
  # the calling pane (tmux $TMUX_PANE) / window (screen $WINDOW) rather
  # than whichever pane the user happens to be active in at injection
  # time. H11 fix: DRY_RUN requires `SW_TEST_HARNESS=1` to also be set —
  # if a user accidentally exports `INJECT_KEYS_DRY_RUN=1` in their shell
  # profile (e.g. after copy-pasting from a debug session), the
  # auto-compact would silently no-op forever. With the guard, the
  # leaked env var alone is harmless: real injection proceeds.
  if [ "${INJECT_KEYS_DRY_RUN:-0}" = "1" ] && [ "${SW_TEST_HARNESS:-0}" = "1" ]; then
    echo "[inject-keys] DRY_RUN backend=$backend target=${TMUX_PANE:-${WINDOW:-}} text=${text} enter=${enter}" >&2
    return 0
  fi

  rc=0
  case "$backend" in
    tmux)
      # C3 fix: target the pane that owns this hook's process. Without
      # `-t "$TMUX_PANE"`, `tmux send-keys` defaults to the currently
      # active pane of the attached client — if the user switched to a
      # different pane (vim, ssh, log tail) between turn-start and the
      # hook firing, `/compact<Enter>` would be typed into THAT pane.
      # `$TMUX_PANE` is always populated by tmux for child processes; if
      # absent (set -u tolerant default), fall back to the untargeted
      # call so degraded execution still attempts the send rather than
      # silently no-op.
      if [ -n "${TMUX_PANE:-}" ]; then
        if [ "$enter" = "--enter" ]; then
          tmux send-keys -t "$TMUX_PANE" -- "$text" Enter
        else
          tmux send-keys -t "$TMUX_PANE" -- "$text"
        fi
      else
        if [ "$enter" = "--enter" ]; then
          tmux send-keys -- "$text" Enter
        else
          tmux send-keys -- "$text"
        fi
      fi
      rc=$?
      ;;

    screen)
      # C3 fix: same risk for screen. `$WINDOW` is screen's
      # current-window number for the calling process; without `-p`,
      # `screen stuff` injects into the currently-displayed window of
      # the session, which may be different from where Claude Code is
      # attached. Fall back to untargeted call if $WINDOW is unset.
      if [ -n "${WINDOW:-}" ]; then
        if [ "$enter" = "--enter" ]; then
          screen -S "$STY" -p "$WINDOW" -X stuff "${text}$(printf '\r')"
        else
          screen -S "$STY" -p "$WINDOW" -X stuff "$text"
        fi
      else
        if [ "$enter" = "--enter" ]; then
          screen -S "$STY" -X stuff "${text}$(printf '\r')"
        else
          screen -S "$STY" -X stuff "$text"
        fi
      fi
      rc=$?
      ;;

    kitty)
      # NOTE: kitty must have `allow_remote_control yes` in kitty.conf.
      # Without it, `kitty @ send-text` fails with rc != 0 and we
      # surface that via the post-case rc check.
      if [ "$enter" = "--enter" ]; then
        kitty @ send-text "${text}"$'\n'
      else
        kitty @ send-text "$text"
      fi
      rc=$?
      ;;

    wezterm)
      wezterm cli send-text --no-paste "$text"
      rc=$?
      if [ "$rc" = "0" ] && [ "$enter" = "--enter" ]; then
        wezterm cli send-text --no-paste $'\r'
        rc=$?
      fi
      ;;

    iterm2)
      # S4 fix: pass `text` via env var read by AppleScript
      # `system attribute` instead of interpolating into the
      # AppleScript source. This eliminates shell-quote risk on
      # arbitrary text (current caller passes a fixed `/compact` but
      # the library may be reused elsewhere).
      if [ "$enter" = "--enter" ]; then
        TEXT_FOR_AS="$text" osascript <<'OSA'
set t to system attribute "TEXT_FOR_AS"
tell application "iTerm" to tell current session of current window to write text t
OSA
      else
        TEXT_FOR_AS="$text" osascript <<'OSA'
set t to system attribute "TEXT_FOR_AS"
tell application "iTerm" to tell current session of current window to write text t newline NO
OSA
      fi
      rc=$?
      ;;
  esac

  # S5 fix: surface backend failure rather than reporting success
  # unconditionally.
  if [ "$rc" = "0" ]; then
    echo "[inject-keys] backend=$backend" >&2
    return 0
  else
    echo "[inject-keys] backend=$backend failed (rc=$rc)" >&2
    return 1
  fi
}

# H9 fix: produce a human-readable hint from inject_keys's stderr so
# downstream hooks can render an additionalContext that disambiguates
# "no backend detected" (terminal needs tmux/screen/...) from "backend
# detected but command failed" (kitty allow_remote_control off, iTerm2
# Automation permission denied, WezTerm flag unsupported, etc.).
# Returns the hint on stdout — never empty when log is non-empty —
# and always exits 0 so it cannot break the calling hook.
inject_keys_failure_hint() {
  local log="$1"
  if printf '%s' "$log" | grep -qE 'no backend'; then
    printf '%s\n' 'no supported terminal multiplexer detected — install tmux or GNU screen, or run Claude Code under kitty / WezTerm / iTerm2'
    return 0
  fi
  if printf '%s' "$log" | grep -qE 'backend=kitty.*failed'; then
    printf '%s\n' 'kitty backend failed — ensure `allow_remote_control yes` (or `socket-only`) is set in your kitty.conf and reload'
    return 0
  fi
  if printf '%s' "$log" | grep -qE 'backend=iterm2.*failed'; then
    printf '%s\n' 'iTerm2 backend failed — macOS Automation permission for osascript is likely required (System Settings → Privacy & Security → Automation → Terminal/Claude Code → iTerm)'
    return 0
  fi
  if printf '%s' "$log" | grep -qE 'backend=wezterm.*failed'; then
    printf '%s\n' 'WezTerm backend failed — ensure `wezterm cli send-text --no-paste` is supported (update WezTerm if the flag was rejected)'
    return 0
  fi
  if printf '%s' "$log" | grep -qE 'backend=screen.*failed'; then
    printf '%s\n' 'GNU screen backend failed — verify $STY is set and the session window accepts the `stuff` command'
    return 0
  fi
  if printf '%s' "$log" | grep -qE 'backend=tmux.*failed'; then
    printf '%s\n' 'tmux backend failed — verify $TMUX is set and tmux send-keys has access to the target pane'
    return 0
  fi
  if printf '%s' "$log" | grep -qE 'backend=([a-z0-9]+).*failed'; then
    local backend
    backend=$(printf '%s' "$log" | sed -nE 's/.*backend=([a-z0-9]+).*failed.*/\1/p' | head -1)
    printf '%s\n' "${backend:-unknown} backend command failed (check terminal config)"
    return 0
  fi
  printf '%s\n' 'injection backend failure of unknown cause (see stderr [inject-keys] line in hook logs)'
  return 0
}

export -f inject_keys inject_keys_failure_hint 2>/dev/null || true
