#!/bin/bash
# Claude "waiting on you" notification - installer for macOS
#
# Adds Claude Code hooks that show a macOS notification whenever a Claude
# session (desktop app or CLI) is waiting on you for a permission prompt or a
# question, and removes it automatically once that session moves on.
#
#   Install:    bash install.sh
#   Uninstall:  bash install.sh --uninstall
#
# Safe to re-run: it replaces only its own hook entries and leaves every other
# setting and hook in ~/.claude/settings.json alone (a backup is written
# whenever the file actually changes).

set -euo pipefail

UNINSTALL=0
SAMPLE=1
for arg in "$@"; do
  case "$arg" in
    -u|--uninstall) UNINSTALL=1 ;;
    --no-sample)    SAMPLE=0 ;;
    -h|--help)
      echo "Usage: bash install.sh [--uninstall] [--no-sample]"
      exit 0 ;;
    *) echo "Unknown option: $arg (try --help)" >&2; exit 1 ;;
  esac
done

say()  { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
# Single-quote a string for safe use inside a shell command.
shq()  { local s=${1//\'/\'\\\'\'}; printf "'%s'" "$s"; }

[ "$(uname -s)" = "Darwin" ] || fail "This installer is for macOS only."

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
case "$CLAUDE_DIR" in /*) ;; *) CLAUDE_DIR="$PWD/$CLAUDE_DIR" ;; esac
NOTIFY_DIR="$CLAUDE_DIR/hooks/notify-mac"
SETTINGS="$CLAUDE_DIR/settings.json"
HOOK="$NOTIFY_DIR/waiting-notify.sh"
SAMPLE_GROUP="claude-waiting-install-test"

WORK="$(mktemp -d -t claude-notify)"
trap 'rm -rf "$WORK"' EXIT

# ------------------------------------------------------------- settings merge
# Uses JavaScript for Automation (built into every Mac), so there is nothing
# extra to install. It never writes settings.json itself: it computes the new
# content into a temp file, and the shell copies it over only if it differs.
#
#   mode check     : only validate settings.json (throws on any problem)
#   mode install   : remove earlier copies of our hooks, then add them
#   mode uninstall : remove our hooks
#
# Prints the real path of settings.json (symlinks resolved).
cat > "$WORK/merge.js" <<'JXA'
ObjC.import('Foundation');
function run(argv) {
  const [given, mode, hook, outPath] = argv;
  const fm = $.NSFileManager.defaultManager;
  const path = ObjC.unwrap($(given).stringByResolvingSymlinksInPath);
  let s = {};
  if (fm.fileExistsAtPath(path)) {
    const data = $.NSData.dataWithContentsOfFile(path);
    if (data.isNil()) throw new Error('could not read ' + path + '; it was left untouched.');
    let txt = '';
    if (data.length > 0) {
      const str = $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding);
      if (str.isNil()) throw new Error('settings.json is not saved as UTF-8 text, so it was left untouched.');
      txt = ObjC.unwrap(str);
    }
    if (txt.trim()) {
      try { s = JSON.parse(txt); }
      catch (e) { throw new Error('settings.json is not valid JSON, so it was left untouched (' + e.message + ').'); }
    }
  }
  if (typeof s !== 'object' || s === null || Array.isArray(s))
    throw new Error('settings.json is not a JSON object, so it was left untouched.');
  if ('hooks' in s && (typeof s.hooks !== 'object' || s.hooks === null || Array.isArray(s.hooks)))
    throw new Error('"hooks" in settings.json is not an object, so it was left untouched.');
  const hooks = s.hooks || {};
  for (const evt of Object.keys(hooks))
    if (!Array.isArray(hooks[evt]))
      throw new Error('"hooks.' + evt + '" in settings.json is not a list, so it was left untouched.');
  if (mode === 'check') return path;

  // Remove exactly our own hook commands, one hook at a time.
  const q = "'" + hook.replace(/'/g, "'\\''") + "'";
  const mine = new Set([q + ' show', q + ' clear']);
  const isMine = h => h && h.type === 'command' && mine.has(String(h.command || ''));
  for (const evt of Object.keys(hooks)) {
    let touched = false;
    const groups = [];
    for (const g of hooks[evt]) {
      if (g && Array.isArray(g.hooks) && g.hooks.some(isMine)) {
        touched = true;
        const rest = g.hooks.filter(h => !isMine(h));
        if (rest.length) groups.push(Object.assign({}, g, { hooks: rest }));
      } else groups.push(g);
    }
    if (touched && groups.length === 0) delete hooks[evt];
    else hooks[evt] = groups;
  }
  if (mode === 'install') {
    const group = (cmd, matcher) => {
      const g = {};
      if (matcher) g.matcher = matcher;
      g.hooks = [{ type: 'command', command: cmd, timeout: 20, async: true }];
      return g;
    };
    const add = (evt, g) => { (hooks[evt] = hooks[evt] || []).push(g); };
    add('PermissionRequest', group(q + ' show'));
    add('Notification', group(q + ' show', 'permission_prompt|elicitation_dialog'));
    for (const evt of ['PostToolUse', 'PostToolUseFailure', 'PermissionDenied', 'Stop', 'UserPromptSubmit', 'SessionEnd'])
      add(evt, group(q + ' clear'));
  }
  if (Object.keys(hooks).length || 'hooks' in s) s.hooks = hooks;
  if (mode === 'uninstall' && 'hooks' in s && Object.keys(s.hooks).length === 0) delete s.hooks;
  const out = JSON.stringify(s, null, 2) + '\n';
  JSON.parse(out);
  if (!$(out).writeToFileAtomicallyEncodingError(outPath, true, $.NSUTF8StringEncoding, null))
    throw new Error('could not write a temp file.');
  return path;
}
JXA

# Runs merge.js; prints the resolved settings path, or fails with a clean message.
run_merge() {  # $1 = check | install | uninstall
  local out err
  if ! out="$(osascript -l JavaScript "$WORK/merge.js" "$SETTINGS" "$1" "$HOOK" "$WORK/new.json" 2>"$WORK/err")"; then
    err="$(sed -e 's/^.*Error: //' -e 's/ (-[0-9]*)$//' "$WORK/err")"
    fail "${err:-Could not read $SETTINGS.}
Nothing was changed."
  fi
  printf '%s' "$out"
}

# Copies the merged result over settings.json, only if it changed.
apply_merge() {  # $1 = install | uninstall
  local real backup n=1
  real="$(run_merge "$1")"
  if [ -f "$real" ] && cmp -s "$WORK/new.json" "$real"; then
    say "Settings already up to date."
    return
  fi
  if [ -f "$real" ]; then
    backup="$real.bak-$(date +%Y%m%d-%H%M%S)"
    while [ -e "$backup" ]; do backup="$real.bak-$(date +%Y%m%d-%H%M%S)-$n"; n=$((n + 1)); done
    cp -p "$real" "$backup"
    say "Backed up settings to $backup"
  fi
  # cat > keeps the file's permissions (and writes through to the real file).
  cat "$WORK/new.json" > "$real"
}

find_notifier() {
  local tn="${CLAUDE_NOTIFY_TN:-}" p
  if [ -n "$tn" ]; then
    [ -x "$tn" ] || fail "CLAUDE_NOTIFY_TN is set but $tn is not an executable file."
    printf '%s' "$tn"; return
  fi
  tn="$(command -v terminal-notifier 2>/dev/null || true)"
  for p in /opt/homebrew/bin/terminal-notifier /usr/local/bin/terminal-notifier; do
    [ -z "$tn" ] && [ -x "$p" ] && tn="$p"
  done
  printf '%s' "$tn"
}

# ----------------------------------------------------------------- uninstall
if [ "$UNINSTALL" = 1 ]; then
  if [ -e "$SETTINGS" ]; then
    apply_merge uninstall
  else
    say "No settings file at $SETTINGS; nothing to remove there."
  fi
  # Clear any notifications we left on screen.
  TN="$(find_notifier)"
  if [ -n "$TN" ]; then
    "$TN" -remove "$SAMPLE_GROUP" >/dev/null 2>&1 || true
    for m in "$NOTIFY_DIR"/pending/*; do
      [ -e "$m" ] || continue
      "$TN" -remove "claude-waiting-$(basename "$m")" >/dev/null 2>&1 || true
    done
  fi
  rm -rf "$NOTIFY_DIR"
  rmdir "$CLAUDE_DIR/hooks" 2>/dev/null || true
  say "Uninstalled. Start a new Claude session (or restart the app) for it to take effect."
  say "(terminal-notifier was left installed. Remove it with: brew uninstall terminal-notifier)"
  exit 0
fi

# ------------------------------------------------- check settings before anything
run_merge check >/dev/null

# ------------------------------------------------- make sure the notifier exists
TN="$(find_notifier)"
if [ -z "$TN" ]; then
  BREW="$(command -v brew 2>/dev/null || true)"
  for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -z "$BREW" ] && [ -x "$p" ] && BREW="$p"
  done
  [ -n "$BREW" ] || fail "terminal-notifier is needed and Homebrew isn't installed.
Install Homebrew first (https://brew.sh), then run this installer again."
  say "Installing terminal-notifier with Homebrew..."
  "$BREW" install terminal-notifier
  TN="$("$BREW" --prefix)/bin/terminal-notifier"
fi
[ -x "$TN" ] || fail "Could not find terminal-notifier after installing it."

# --------------------------------------------------------------- hook script
mkdir -p "$NOTIFY_DIR/pending"
{
  printf '#!/bin/bash\n'
  # Full path baked in: apps launched from the Dock don't have Homebrew on PATH.
  printf 'TN=%s\n' "$(shq "$TN")"
  cat <<'HOOK'
# Claude "waiting on you" notification for Claude Code sessions (macOS).
#
#   waiting-notify.sh show    (hook stdin JSON: PermissionRequest / Notification)
#   waiting-notify.sh clear   (hook stdin JSON: any event; removes that session's notification)
#
# One notification per session (group = session id): a repeat replaces it,
# never stacks. A marker file per waiting session lets "clear" exit at once,
# without running the notifier, when nothing is pending.

export LC_ALL=en_US.UTF-8
MODE="${1:-show}"
PENDING="$(cd "$(dirname "$0")" && pwd)/pending"

IN="$(cat)"
# Prints a text field from the hook JSON (nothing for lists or objects).
get() {
  local v
  # Newer macOS: ask plutil for text only.
  if v="$(printf '%s' "$IN" | /usr/bin/plutil -extract "$1" raw -expect string -o - - 2>/dev/null)"; then
    printf '%s' "$v"; return 0
  fi
  # Fallback: "json" output only works for lists/objects, so success means "skip it".
  printf '%s' "$IN" | /usr/bin/plutil -extract "$1" json -o - - >/dev/null 2>&1 && return 0
  printf '%s' "$IN" | /usr/bin/plutil -extract "$1" raw -o - - 2>/dev/null
  return 0
}
# terminal-notifier treats a leading "-" or "[" specially; keep text plain.
plain() { case "$1" in -*|\[*) printf ' %s' "$1" ;; *) printf '%s' "$1" ;; esac; }

SID="$(get session_id)"
[ -n "$SID" ] || SID="unknown"
SID="$(printf '%s' "$SID" | LC_ALL=C tr -c 'A-Za-z0-9_-' '_' | cut -c1-64)"
GROUP="claude-waiting-$SID"
MARK="$PENDING/$SID"

if [ "$MODE" = "clear" ]; then
  [ -f "$MARK" ] || exit 0
  rm -f "$MARK"
  "$TN" -remove "$GROUP" >/dev/null 2>&1
  exit 0
fi

mkdir -p "$PENDING"
# PermissionRequest and Notification(permission_prompt) can both fire for one
# prompt; show it once.
if [ -f "$MARK" ]; then
  AGE=$(( $(date +%s) - $(/usr/bin/stat -f %m "$MARK") ))
  [ "$AGE" -lt 5 ] && exit 0
fi
date +%s > "$MARK"

CWD="$(get cwd)"
while [ "${CWD%/}" != "$CWD" ]; do CWD="${CWD%/}"; done
PROJECT="${CWD##*/}"
[ -n "$PROJECT" ] || PROJECT="Claude Code"

if [ "$(get hook_event_name)" = "PermissionRequest" ]; then
  TOOL="$(get tool_name)"
  DETAIL=""
  case "$TOOL" in
    AskUserQuestion) WHAT="Has a question for you" ;;
    ExitPlanMode)    WHAT="Has a plan ready for you to review" ;;
    *)
      WHAT="Wants to use ${TOOL:-a tool}"
      for k in command file_path url pattern description; do
        DETAIL="$(get "tool_input.$k")"
        [ -n "$DETAIL" ] && break
      done ;;
  esac
  DETAIL="$(printf '%s' "$DETAIL" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')"
  if [ "${#DETAIL}" -gt 140 ]; then DETAIL="${DETAIL:0:137}..."; fi
else
  WHAT="$(get message)"
  [ -n "$WHAT" ] || WHAT="Claude is waiting for you"
  DETAIL=""
fi

MSG="$WHAT"
[ -n "$DETAIL" ] && MSG="$WHAT: $DETAIL"

ARGS=(-title "Waiting on you" -subtitle "$(plain "$PROJECT")" -message "$(plain "$MSG")" -group "$GROUP" -sound default)
# Clicking the notification brings back the app this session runs in.
[ -n "${__CFBundleIdentifier:-}" ] && ARGS+=(-activate "$__CFBundleIdentifier")
"$TN" "${ARGS[@]}" >/dev/null 2>&1
# If the session moved on while the notification was being posted, take it down.
[ -f "$MARK" ] || "$TN" -remove "$GROUP" >/dev/null 2>&1
exit 0
HOOK
} > "$HOOK"
chmod +x "$HOOK"

apply_merge install
say "Installed the hook script to $HOOK"

# ------------------------------------------------------------------- sample
if [ "$SAMPLE" = 1 ]; then
  OUT="$("$TN" -title "Waiting on you" -subtitle "your-project" \
          -message "Sample notification - the install worked." \
          -group "$SAMPLE_GROUP" -sound default 2>&1)" || true
  say ""
  if printf '%s' "$OUT" | grep -qiE 'not allowed|turned off|permission'; then
    say "Installed, but macOS is BLOCKING notifications from terminal-notifier, so no sample appeared."
    say "Fix it (takes 20 seconds):"
    say "  1. System Settings > Notifications > find \"terminal-notifier\" in the list."
    say "  2. Turn ON \"Allow notifications\"."
    say "  3. Set the style to \"Persistent\" (called \"Alerts\" on older macOS)."
    say "  4. Run this installer again to see the sample."
  else
    say "Done. You should see a sample \"Waiting on you\" notification now."
    say "(The first time, macOS may ask whether terminal-notifier can send notifications. Click Allow.)"
    say ""
    say "ONE MORE STEP so it stays on screen until you dismiss it:"
    say "  System Settings > Notifications > terminal-notifier > set the style to \"Persistent\" (called \"Alerts\" on older macOS)."
  fi
  if [ -z "${CLAUDE_NOTIFY_NO_OPEN:-}" ]; then
    say "Opening Notifications settings for you now..."
    open "x-apple.systempreferences:com.apple.Notifications-Settings.extension" >/dev/null 2>&1 || true
  fi
fi

say ""
say "Start a NEW Claude session (or restart the Claude app) so it picks up the hooks."
