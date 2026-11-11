#!/usr/bin/env bash
# always-on.sh: one-command setup for the Terminal-settable parts of the
# Always-On AI Mac Mini guide (Parts 3 and 4).
# https://github.com/jupiter-revenue-systems/always-on-ai-mac-mini
#
# Run it:
#   curl -fsSL https://raw.githubusercontent.com/jupiter-revenue-systems/always-on-ai-mac-mini/main/scripts/always-on.sh | bash
#   bash scripts/always-on.sh [--dry-run | --status | --undo | --yes | --help]
# With curl, pass flags like this:  ... | bash -s -- --status
#
# It only changes what the guide covers. It never touches FileVault or
# automatic login (both need your password in System Settings), it just
# checks them and prints the steps.

set -euo pipefail

STATE_DIR="${HOME}/.always-on-mac-mini"
STATE_FILE="${STATE_DIR}/before.txt"
SCREEN_PLIST="/System/Library/LaunchDaemons/com.apple.screensharing.plist"

MODE="apply"   # apply | dry-run | status | undo
ASSUME_YES=0
SUDO_READY=0

usage() {
  cat <<'EOF'
always-on.sh: set up a Mac mini to stay on, come back after a power cut,
and be reachable over the network. Same settings as Parts 3 and 4 of the guide.

Usage:
  bash always-on.sh            Show the plan, then ask "Apply these settings? [y/N]"
  bash always-on.sh --yes      Apply without asking
  bash always-on.sh --dry-run  Print every command it would run, change nothing
  bash always-on.sh --status   Show current values next to the targets, change nothing
  bash always-on.sh --undo     Put back what it changed (asks first, or add --yes)
  bash always-on.sh --help     This help

From curl:
  curl -fsSL https://raw.githubusercontent.com/jupiter-revenue-systems/always-on-ai-mac-mini/main/scripts/always-on.sh | bash -s -- --status

What it sets (only if it isn't already set):
  Never sleep on power        pmset -c sleep 0 displaysleep 10 disksleep 0
  Restart after power failure pmset -a autorestart 1
  Wake for network access     pmset -a womp 1
  Restart after a freeze      systemsetup -setrestartfreeze on
  Remote Login                systemsetup -setremotelogin on
  Screen Sharing              launchctl enable + bootstrap com.apple.screensharing

What it only checks (you do these in System Settings):
  FileVault off, automatic login.
EOF
}

say()  { printf '%s\n' "$*"; }
warn() { printf 'Note: %s\n' "$*" >&2; }

# ---------- reading current values (no admin needed) ----------

# Read one pmset key from the "AC Power" block, falling back to the live settings.
pmset_get() {
  local key="$1" val
  val="$(pmset -g custom 2>/dev/null | awk -v k="$key" '
    /^AC Power:/ {ac=1; next}
    /^[A-Za-z]/  {ac=0}
    ac && $1==k  {print $2; exit}')"
  if [[ -z "$val" ]]; then
    val="$(pmset -g 2>/dev/null | awk -v k="$key" '$1==k {print $2; exit}')"
  fi
  printf '%s' "${val:-n/a}"
}

# Restart after freeze can only be read with admin rights. Use them only if
# sudo is already unlocked, so --status never asks for a password.
restartfreeze_get() {
  local out=""
  if [[ $EUID -eq 0 ]]; then
    out="$(systemsetup -getrestartfreeze 2>/dev/null || true)"
  elif sudo -n true 2>/dev/null; then
    out="$(sudo -n systemsetup -getrestartfreeze 2>/dev/null || true)"
  fi
  case "$out" in
    *": On"*)  printf 'on' ;;
    *": Off"*) printf 'off' ;;
    *Not\ supported*|*not\ supported*) printf 'n/a' ;;
    *)         printf 'unknown' ;;
  esac
}

# Is anything listening on a local TCP port? (22 = Remote Login, 5900 = Screen Sharing)
port_open() {
  nc -z -G 1 127.0.0.1 "$1" >/dev/null 2>&1
}

# On if the service is switched on in launchd or its port is listening.
service_get() {
  local label="$1" port="$2"
  if launchctl print-disabled system 2>/dev/null | grep -Eq "\"${label}\" => (enabled|false)"; then
    printf 'on'
  elif port_open "$port"; then
    printf 'on'
  else
    printf 'off'
  fi
}

remotelogin_get()   { service_get com.openssh.sshd 22; }
screensharing_get() { service_get com.apple.screensharing 5900; }

filevault_get() {
  case "$(fdesetup status 2>/dev/null || true)" in
    *"FileVault is On"*)  printf 'on' ;;
    *"FileVault is Off"*) printf 'off' ;;
    *)                    printf 'unknown' ;;
  esac
}

autologin_get() {
  if defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser >/dev/null 2>&1; then
    printf 'on'
  else
    printf 'off'
  fi
}

# ---------- status table ----------

CUR_SLEEP="" CUR_DSLEEP="" CUR_DISK="" CUR_AUTORESTART="" CUR_WOMP=""
CUR_FREEZE="" CUR_SSH="" CUR_VNC="" CUR_FV="" CUR_AUTOLOGIN=""

read_all() {
  CUR_SLEEP="$(pmset_get sleep)"
  CUR_DSLEEP="$(pmset_get displaysleep)"
  CUR_DISK="$(pmset_get disksleep)"
  CUR_AUTORESTART="$(pmset_get autorestart)"
  CUR_WOMP="$(pmset_get womp)"
  CUR_FREEZE="$(restartfreeze_get)"
  CUR_SSH="$(remotelogin_get)"
  CUR_VNC="$(screensharing_get)"
  CUR_FV="$(filevault_get)"
  CUR_AUTOLOGIN="$(autologin_get)"
}

verdict() {
  local cur="$1" target="$2"
  case "$cur" in
    unknown) printf 'CHECK' ;;
    n/a)     printf 'N/A' ;;
    "$target") printf 'OK' ;;
    *)       printf 'CHANGE' ;;
  esac
}

row() { printf '  %-32s %-10s %-8s %s\n' "$1" "$2" "$3" "$4"; }

print_status() {
  say ""
  row "Setting" "Current" "Target" "Result"
  row "--------------------------------" "----------" "--------" "------"
  row "System sleep (minutes, 0=never)" "$CUR_SLEEP" "0" "$(verdict "$CUR_SLEEP" 0)"
  row "Display sleep (minutes)" "$CUR_DSLEEP" "10" "$(verdict "$CUR_DSLEEP" 10)"
  row "Disk sleep (minutes, 0=never)" "$CUR_DISK" "0" "$(verdict "$CUR_DISK" 0)"
  row "Restart after power failure" "$CUR_AUTORESTART" "1" "$(verdict "$CUR_AUTORESTART" 1)"
  row "Wake for network access" "$CUR_WOMP" "1" "$(verdict "$CUR_WOMP" 1)"
  row "Restart after a freeze" "$CUR_FREEZE" "on" "$(verdict "$CUR_FREEZE" on)"
  row "Remote Login" "$CUR_SSH" "on" "$(verdict "$CUR_SSH" on)"
  row "Screen Sharing" "$CUR_VNC" "on" "$(verdict "$CUR_VNC" on)"
  local fv al
  fv="$(verdict "$CUR_FV" off)"; [[ "$fv" == CHANGE ]] && fv="MANUAL"
  al="$(verdict "$CUR_AUTOLOGIN" on)"; [[ "$al" == CHANGE ]] && al="MANUAL"
  row "FileVault" "$CUR_FV" "off" "$fv"
  row "Automatic login" "$CUR_AUTOLOGIN" "on" "$al"
  say ""
  if [[ "$CUR_FREEZE" == unknown ]]; then
    say "Restart after a freeze needs admin rights to read. It's shown as CHECK."
  fi
  say "MANUAL rows need your password, so the script leaves them to you:"
  print_manual_steps
}

print_manual_steps() {
  if [[ "$CUR_FV" != off ]]; then
    say "  FileVault: System Settings > Privacy & Security > FileVault > Turn Off."
  fi
  if [[ "$CUR_AUTOLOGIN" != on ]]; then
    say "  Automatic login: System Settings > Users & Groups > Automatically log in as > your Admin user, then type the password."
  fi
  if [[ "$CUR_FV" == off && "$CUR_AUTOLOGIN" == on ]]; then
    say "  None. Both are already set."
  fi
}

# ---------- planning ----------

PLAN=()   # each entry is one command, as a single string

build_plan() {
  PLAN=()
  if [[ "$CUR_SLEEP" != 0 || "$CUR_DSLEEP" != 10 || "$CUR_DISK" != 0 ]]; then
    PLAN+=("pmset -c sleep 0 displaysleep 10 disksleep 0")
  fi
  if [[ "$CUR_AUTORESTART" != 1 && "$CUR_AUTORESTART" != n/a ]]; then
    PLAN+=("pmset -a autorestart 1")
  fi
  if [[ "$CUR_WOMP" != 1 && "$CUR_WOMP" != n/a ]]; then
    PLAN+=("pmset -a womp 1")
  fi
  if [[ "$CUR_FREEZE" != on && "$CUR_FREEZE" != n/a ]]; then
    PLAN+=("systemsetup -setrestartfreeze on")
  fi
  if [[ "$CUR_SSH" != on ]]; then
    PLAN+=("systemsetup -setremotelogin on")
  fi
  if [[ "$CUR_VNC" != on ]]; then
    PLAN+=("launchctl enable system/com.apple.screensharing")
    PLAN+=("launchctl bootstrap system ${SCREEN_PLIST}")
  fi
}

explain() {
  case "$1" in
    "pmset -c sleep"*)          say "  # Never sleep on power; screen off after 10 min; disks never spin down." ;;
    "pmset -a autorestart"*)    say "  # Turn back on by itself after a power failure." ;;
    "pmset -a womp"*)           say "  # Wake for network access, so remote connections can reach it." ;;
    "systemsetup -setrestartfreeze"*) say "  # Restart by itself if macOS freezes." ;;
    "systemsetup -setremotelogin"*)   say "  # Remote Login (SSH), from Part 3." ;;
    "launchctl enable"*)        say "  # Screen Sharing, from Part 3: allow the service to run." ;;
    "launchctl bootstrap"*)     say "  # Screen Sharing: start it now." ;;
    "pmset -c displaysleep"*)   say "  # Put sleep settings back." ;;
    "systemsetup -f -setremotelogin"*) say "  # Turn Remote Login back off (it was off before)." ;;
    "launchctl bootout"*)       say "  # Stop Screen Sharing (it was off before)." ;;
    "launchctl disable"*)       say "  # Keep Screen Sharing off after restarts." ;;
  esac
}

print_plan() {
  if [[ ${#PLAN[@]} -eq 0 ]]; then
    say "Nothing to change. Everything the script can set is already set."
    return
  fi
  say "Commands (each runs with sudo):"
  local c
  for c in "${PLAN[@]}"; do
    explain "$c"
    say "  sudo $c"
  done
}

# ---------- running ----------

ask() {
  local prompt="$1" reply=""
  if [[ $ASSUME_YES -eq 1 ]]; then
    return 0
  fi
  if ! { : </dev/tty; } 2>/dev/null; then
    say ""
    say "No terminal to ask in, so nothing was changed."
    say "Run it again with --yes to apply, or --dry-run to preview."
    exit 0
  fi
  printf '%s' "$prompt" >/dev/tty
  read -r reply </dev/tty || reply=""
  [[ "$reply" == y || "$reply" == Y || "$reply" == yes || "$reply" == YES ]]
}

get_sudo() {
  [[ $SUDO_READY -eq 1 ]] && return 0
  if [[ $EUID -ne 0 ]]; then
    say ""
    say "These are system-wide settings, so macOS needs your admin password."
    say "sudo is used only for pmset, systemsetup and launchctl, nothing else."
    sudo -v
  fi
  SUDO_READY=1
}

as_root() {
  if [[ $EUID -eq 0 ]]; then "$@"; else sudo "$@"; fi
}

# Runs one plan entry. Words in the plan never contain spaces, so splitting is safe.
run_cmd() {
  local cmd="$1" args
  read -r -a args <<<"$cmd"
  say "+ sudo $cmd"
  case "$cmd" in
    "systemsetup -setremotelogin on")
      if ! as_root "${args[@]}"; then
        warn "macOS blocked Remote Login from Terminal (it needs Full Disk Access)."
        warn "Turn it on here: System Settings > General > Sharing > Remote Login."
      fi
      ;;
    "launchctl bootstrap"*)
      # Error 5 or 37 means it's already loaded. That's fine.
      as_root "${args[@]}" 2>/dev/null || true
      ;;
    "launchctl bootout"*)
      as_root "${args[@]}" 2>/dev/null || true
      ;;
    *)
      if ! as_root "${args[@]}"; then
        warn "This one didn't apply: sudo $cmd"
      fi
      ;;
  esac
}

save_before() {
  if [[ -f "$STATE_FILE" ]]; then
    return 0   # keep the very first snapshot, so --undo goes back to the original
  fi
  mkdir -p "$STATE_DIR"
  cat >"$STATE_FILE" <<EOF
sleep=$CUR_SLEEP
displaysleep=$CUR_DSLEEP
disksleep=$CUR_DISK
autorestart=$CUR_AUTORESTART
womp=$CUR_WOMP
restartfreeze=$CUR_FREEZE
remotelogin=$CUR_SSH
screensharing=$CUR_VNC
EOF
  say "Saved your current values to ${STATE_FILE} for --undo."
}

check_screensharing() {
  local i
  for i in 1 2 3; do
    if port_open 5900; then return 0; fi
    sleep "$i"
  done
  warn "Screen Sharing didn't start from Terminal on this macOS version."
  warn "Turn it on here: System Settings > General > Sharing > Screen Sharing."
}

do_apply() {
  read_all
  say "Always-on setup for this Mac. It only changes what the guide covers."
  print_status
  build_plan
  say ""
  print_plan
  if [[ ${#PLAN[@]} -eq 0 ]]; then
    return 0
  fi
  if [[ "$MODE" == dry-run ]]; then
    say ""
    say "Dry run: nothing was changed."
    return 0
  fi
  say ""
  if ! ask "Apply these settings? [y/N] "; then
    say "Nothing was changed."
    return 0
  fi
  get_sudo
  save_before
  local c
  for c in "${PLAN[@]}"; do
    run_cmd "$c"
  done
  if [[ "$CUR_VNC" != on ]]; then
    check_screensharing
  fi
  say ""
  say "Done running the commands. Here's how it looks now:"
  read_all
  print_status
}

# ---------- undo ----------

state_get() {
  local key="$1" fallback="$2" val=""
  if [[ -f "$STATE_FILE" ]]; then
    val="$(awk -F= -v k="$key" '$1==k {print $2; exit}' "$STATE_FILE")"
  fi
  case "$val" in
    ""|unknown|n/a) printf '%s' "$fallback" ;;
    *)              printf '%s' "$val" ;;
  esac
}

do_undo() {
  read_all
  local s d k a w f r v
  # Saved values first. Without them, these are the usual macOS defaults.
  s="$(state_get sleep 1)"
  d="$(state_get displaysleep 10)"
  k="$(state_get disksleep 10)"
  a="$(state_get autorestart 0)"
  w="$(state_get womp 1)"
  f="$(state_get restartfreeze off)"
  r="$(state_get remotelogin keep)"
  v="$(state_get screensharing keep)"

  if [[ -f "$STATE_FILE" ]]; then
    say "Putting back the values saved in ${STATE_FILE}."
  else
    say "No saved values found, so this puts back the usual macOS defaults."
    say "Remote Login and Screen Sharing are left as they are."
  fi

  PLAN=()
  PLAN+=("pmset -c displaysleep $d sleep $s disksleep $k")
  [[ "$CUR_AUTORESTART" != n/a ]] && PLAN+=("pmset -a autorestart $a")
  [[ "$CUR_WOMP" != n/a ]] && PLAN+=("pmset -a womp $w")
  [[ "$CUR_FREEZE" != n/a ]] && PLAN+=("systemsetup -setrestartfreeze $f")
  if [[ "$r" == off ]]; then
    PLAN+=("systemsetup -f -setremotelogin off")
  fi
  if [[ "$v" == off ]]; then
    PLAN+=("launchctl bootout system ${SCREEN_PLIST}")
    PLAN+=("launchctl disable system/com.apple.screensharing")
  fi

  say ""
  print_plan
  if [[ "$r" == off || "$v" == off ]]; then
    say ""
    say "Careful: turning off Remote Login or Screen Sharing cuts off remote access to this Mac."
  fi
  say ""
  if ! ask "Undo these settings? [y/N] "; then
    say "Nothing was changed."
    return 0
  fi
  get_sudo
  local c
  for c in "${PLAN[@]}"; do
    run_cmd "$c"
  done
  rm -f "$STATE_FILE"
  rmdir "$STATE_DIR" 2>/dev/null || true
  say ""
  say "Undo commands ran. Here's how it looks now:"
  read_all
  print_status
}

# ---------- main ----------

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) MODE="dry-run" ;;
      --status)  MODE="status" ;;
      --undo)    MODE="undo" ;;
      --yes|-y)  ASSUME_YES=1 ;;
      --help|-h) usage; exit 0 ;;
      *) say "Unknown option: $1"; say ""; usage; exit 2 ;;
    esac
    shift
  done

  if [[ "$(uname -s)" != Darwin ]]; then
    say "This script is for macOS only. Nothing was changed."
    exit 0
  fi

  case "$MODE" in
    status)
      read_all
      say "Always-on status for this Mac (read-only, nothing changed)."
      print_status
      ;;
    undo)
      do_undo
      ;;
    *)
      do_apply
      ;;
  esac
}

main "$@"
