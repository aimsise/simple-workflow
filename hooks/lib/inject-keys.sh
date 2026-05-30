#!/usr/bin/env bash
# hooks/lib/inject-keys.sh — terminal-aware keystroke injector.
#
# Public function:
#   inject_keys "<text>" [--enter|--no-enter]
#
# Detection priority (multiplexer-first):
#   1. tmux              ($TMUX set; target via $TMUX_PANE)
#   2. GNU screen        ($STY set; target via $WINDOW)
#   3. kitty             (kitty + remote control enabled; target via $KITTY_WINDOW_ID)
#   4. WezTerm           ($TERM_PROGRAM=WezTerm; target via $WEZTERM_PANE)
#   5. iTerm2 (macOS)    ($TERM_PROGRAM=iTerm.app; target via $ITERM_SESSION_ID UUID)
#
# Every backend targets the ORIGINATING surface (pane / window / session)
# rather than whichever the user is focused on at injection time. This
# prevents `/compact<Enter>` from being typed into the wrong window when
# the user switches focus between turn-start and hook fire. See the C3
# fix (tmux/screen, v7.0.0) and the WI-1 fix (iTerm2 + kitty + WezTerm
# explicit pane-id) for the audit trail.
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
# Post-inject verify (P1-1): after `tmux send-keys` returns rc=0, this
# library performs a `capture-pane -p -S -3` check on the TMUX_PANE to
# confirm the injected text actually echoed back to the TUI. If the
# text is not visible within `SW_INJECT_KEYS_VERIFY_SLEEP_MS` (default
# 150ms), inject_keys returns rc=1 even though send-keys itself
# succeeded. This catches the failure mode where the TUI input loop is
# paused (e.g. raw-mode subagent execution) and the queued keystroke
# would be discarded at the next turn boundary.
#
# Opt-out: `SW_INJECT_KEYS_VERIFY=0` disables the verify step (legacy
# behaviour — rc reflects send-keys exit code only). Currently
# implemented for the tmux backend only; screen / kitty / wezterm /
# iterm2 fall through unchanged. The DRY_RUN early-return runs before
# the verify block, so `INJECT_KEYS_DRY_RUN=1 + SW_TEST_HARNESS=1`
# fixtures never exercise capture-pane.
#
# Return codes: 0 = injected (or dry-run logged), 1 = no supported
# backend OR backend command failed (S5 fix) OR verify missed (P1-1),
# 2 = bad args.
# Stdout: empty. Stderr: single status line "[inject-keys] ..."; on
# verify miss also "[INJECT-VERIFY] missed: ..." preceding the status.

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

  # M3 + H11 + WI-1: DRY_RUN short-circuit for testing. Include the
  # per-backend target identifier in the log so callers can assert the
  # dispatcher would target the originating pane / window / session
  # rather than whichever surface the user happens to focus at injection
  # time. H11 fix: DRY_RUN requires `SW_TEST_HARNESS=1` to also be set —
  # if a user accidentally exports `INJECT_KEYS_DRY_RUN=1` in their shell
  # profile (e.g. after copy-pasting from a debug session), the
  # auto-compact would silently no-op forever. With the guard, the
  # leaked env var alone is harmless: real injection proceeds.
  # WI-1 fix: pick the per-backend env var so iTerm/kitty/wezterm/etc.
  # each surface their own targeting identifier (CT-AC-26/46/47/48).
  if [ "${INJECT_KEYS_DRY_RUN:-0}" = "1" ] && [ "${SW_TEST_HARNESS:-0}" = "1" ]; then
    local target=""
    case "$backend" in
      tmux)    target="${TMUX_PANE:-}" ;;
      screen)  target="${WINDOW:-}" ;;
      kitty)   target="${KITTY_WINDOW_ID:-}" ;;
      wezterm) target="${WEZTERM_PANE:-}" ;;
      iterm2)  target="${ITERM_SESSION_ID:-}" ;;
    esac
    echo "[inject-keys] DRY_RUN backend=$backend target=$target text=${text} enter=${enter}" >&2
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

      # P1-1 post-inject verify: `tmux send-keys` returning rc=0 means
      # the command was queued, NOT that the Claude Code TUI input loop
      # consumed it. When the TUI is mid-subagent execution it may park
      # in raw mode and drop keystrokes at the next turn boundary,
      # leaving autopilot frozen with no surface signal. Capture the
      # pane after a short sleep and check that the injected text
      # echoed back; if not, downgrade rc to 1 so the caller skips the
      # `.auto-compact-pending` sentinel / `runtime_metrics` write and
      # surfaces a verify-missed hint via inject_keys_failure_hint.
      # Guards: only run when send-keys itself succeeded
      # (`rc=0`), the verify knob is on (`SW_INJECT_KEYS_VERIFY` != "0";
      # default 1), and `TMUX_PANE` is non-empty (without a target we
      # cannot scope capture-pane reliably). Sleep is configurable via
      # `SW_INJECT_KEYS_VERIFY_SLEEP_MS` (default 150ms); ms→s
      # conversion goes through POSIX awk so BSD / GNU sleep both
      # accept the resulting decimal.
      if [ "$rc" = "0" ] \
         && [ "${SW_INJECT_KEYS_VERIFY:-1}" != "0" ] \
         && [ -n "${TMUX_PANE:-}" ]; then
        local _verify_sleep_ms="${SW_INJECT_KEYS_VERIFY_SLEEP_MS:-150}"
        local _verify_sleep_s
        _verify_sleep_s=$(awk -v ms="$_verify_sleep_ms" 'BEGIN { printf "%.3f", ms / 1000 }' 2>/dev/null || echo "0.150")
        sleep "$_verify_sleep_s" 2>/dev/null || sleep 1 2>/dev/null || true
        local _capture
        _capture=$(tmux capture-pane -t "$TMUX_PANE" -p -S -3 -E - 2>/dev/null || printf '%s' "")
        if ! printf '%s' "$_capture" | grep -qF -- "$text"; then
          echo "[INJECT-VERIFY] missed: text=${text} not in capture-pane after ${_verify_sleep_ms}ms (TMUX_PANE=${TMUX_PANE})" >&2
          rc=1
        fi
        unset _verify_sleep_ms _verify_sleep_s _capture
      fi
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
      # WI-1 fix: target the originating kitty window via
      # `--match id:$KITTY_WINDOW_ID`. Without that, `kitty @ send-text`
      # defaults to the currently focused window — same focus-leak
      # failure mode that the tmux/screen C3 fix addresses. Fall back
      # to untargeted call when $KITTY_WINDOW_ID is unset (kitty <0.40
      # or process not launched as a kitty child).
      if [ -n "${KITTY_WINDOW_ID:-}" ]; then
        if [ "$enter" = "--enter" ]; then
          kitty @ send-text --match "id:$KITTY_WINDOW_ID" "${text}"$'\n'
        else
          kitty @ send-text --match "id:$KITTY_WINDOW_ID" "$text"
        fi
      else
        if [ "$enter" = "--enter" ]; then
          kitty @ send-text "${text}"$'\n'
        else
          kitty @ send-text "$text"
        fi
      fi
      rc=$?
      ;;

    wezterm)
      # WI-1 fix: target the originating pane via `--pane-id
      # $WEZTERM_PANE` explicitly. The WezTerm CLI does infer the
      # caller's pane from $WEZTERM_PANE when --pane-id is omitted, but
      # the explicit flag is defense-in-depth: it removes the dependency
      # on CLI implementation detail and keeps DRY_RUN log + source-grep
      # contracts consistent with the other backends. Falls back to the
      # implicit form if $WEZTERM_PANE is unset.
      if [ -n "${WEZTERM_PANE:-}" ]; then
        wezterm cli send-text --no-paste --pane-id "$WEZTERM_PANE" "$text"
        rc=$?
        if [ "$rc" = "0" ] && [ "$enter" = "--enter" ]; then
          wezterm cli send-text --no-paste --pane-id "$WEZTERM_PANE" $'\r'
          rc=$?
        fi
      else
        wezterm cli send-text --no-paste "$text"
        rc=$?
        if [ "$rc" = "0" ] && [ "$enter" = "--enter" ]; then
          wezterm cli send-text --no-paste $'\r'
          rc=$?
        fi
      fi
      ;;

    iterm2)
      # S4 fix: pass `text` via env var read by AppleScript
      # `system attribute` instead of interpolating into the
      # AppleScript source. This eliminates shell-quote risk on
      # arbitrary text (current caller passes a fixed `/compact` but
      # the library may be reused elsewhere).
      #
      # WI-1 fix: target the originating iTerm session by
      # $ITERM_SESSION_ID rather than `current session of current
      # window`. iTerm sets ITERM_SESSION_ID in each shell session
      # (format `w<W>t<T>p<P>:<UUID>`); the UUID portion matches the
      # AppleScript `id` of a session. Without this fix, the
      # AppleScript resolves at osascript runtime to whichever iTerm
      # window the user has focused, so a tab/pane switch between
      # turn-start and hook fire (e.g. user clicks a different pane
      # in the same iTerm window) would inject `/compact<Enter>`
      # into the wrong session — the iTerm2 analog of the
      # tmux/screen C3 focus-leak. When ITERM_SESSION_ID is absent
      # (very old iTerm or detached Claude Code), fall back to the
      # pre-WI-1 untargeted path so degraded execution still
      # attempts injection.
      local _ik_iterm_uuid=""
      if [ -n "${ITERM_SESSION_ID:-}" ]; then
        _ik_iterm_uuid="${ITERM_SESSION_ID##*:}"
      fi
      # WI-2 fix: iTerm2's AppleScript does NOT expose a `windows`
      # collection — `count of windows` returns 0 even when iTerm has
      # active terminal windows. Only `current window` is reachable.
      # Iterate that window's tabs and sessions to locate the
      # originating session by UUID. This covers:
      #   - same iTerm window, different tab → found
      #   - same iTerm window, different pane → found
      #   - focus moved to a non-iTerm app (Chrome, VS Code, etc.) →
      #     iTerm's current window is unchanged, found
      #   - focus moved to a different iTerm WINDOW → current window
      #     updates to that one, UUID not found, hard-fail with hint
      # Multi-iTerm-window cases are unsolvable via AppleScript alone
      # (no enumeration API); recommend tmux for that workflow.
      if [ -n "$_ik_iterm_uuid" ]; then
        if [ "$enter" = "--enter" ]; then
          TEXT_FOR_AS="$text" ITERM_TARGET_UUID="$_ik_iterm_uuid" osascript <<'OSA'
set t to system attribute "TEXT_FOR_AS"
set targetUUID to system attribute "ITERM_TARGET_UUID"
set didInject to false
tell application "iTerm"
  repeat with tt in tabs of current window
    repeat with s in sessions of tt
      try
        if id of s is targetUUID then
          tell s to write text t
          set didInject to true
          exit repeat
        end if
      end try
    end repeat
    if didInject then exit repeat
  end repeat
  if not didInject then
    error "iTerm session " & targetUUID & " not in current iTerm window (focus the originating iTerm window or switch to tmux)"
  end if
end tell
OSA
        else
          TEXT_FOR_AS="$text" ITERM_TARGET_UUID="$_ik_iterm_uuid" osascript <<'OSA'
set t to system attribute "TEXT_FOR_AS"
set targetUUID to system attribute "ITERM_TARGET_UUID"
set didInject to false
tell application "iTerm"
  repeat with tt in tabs of current window
    repeat with s in sessions of tt
      try
        if id of s is targetUUID then
          tell s to write text t newline NO
          set didInject to true
          exit repeat
        end if
      end try
    end repeat
    if didInject then exit repeat
  end repeat
  if not didInject then
    error "iTerm session " & targetUUID & " not in current iTerm window (focus the originating iTerm window or switch to tmux)"
  end if
end tell
OSA
        fi
      else
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
  if printf '%s' "$log" | grep -qE 'iTerm session .* not in current iTerm window'; then
    printf '%s\n' 'iTerm2 backend failed — the originating iTerm session is not in the currently active iTerm window (iTerm AppleScript can only reach the `current window`; if you have multiple iTerm windows, refocus the Claude Code window before the next ticket boundary, or use tmux for reliable multi-window injection)'
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
  # P1-1: verify-missed branch. Detected when the tmux send-keys path
  # returned rc=0 but capture-pane did not show the injected text
  # within the verify window. Must precede the generic `backend=tmux`
  # branch because verify-missed logs do NOT include the
  # `backend=tmux ... failed` literal — `inject_keys` overwrites rc to
  # 1 after the verify check, and the trailing status line emits
  # `backend=tmux failed (rc=1)` only when send-keys itself errored.
  if printf '%s' "$log" | grep -qE '\[INJECT-VERIFY\] missed'; then
    printf '%s\n' 'inject keys reached tmux but the TUI input loop did not echo the text within the verify window — Claude Code may be in raw-mode subagent execution; the queued operation will be retried on the next ship boundary or on the next session start (see SW_INJECT_KEYS_VERIFY in CLAUDE.md)'
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
