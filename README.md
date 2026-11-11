# Claude "Waiting on you" notifications for Mac

Never miss a Claude Code session that's stuck waiting on you again.

When Claude needs your OK (a permission prompt) or asks you a question, a Mac notification pops up and **stays on screen until you deal with it**. Once the session moves on, the notification **clears itself**.

> **Already have a desk gadget, status light or other alert setup that tells you when Claude is waiting?** You don't need this.

Works with the **Claude desktop app** and **Claude Code in the terminal**.

---

## What you'll see

> **Waiting on you**
> my-project
> Wants to use Bash: npm run build

- One notification per session. A new one replaces the old one. They never pile up.
- Questions say **"Has a question for you"**. Plans say **"Has a plan ready for you to review"**.
- Click it to jump back to the app the session is running in.
- It clears on its own once Claude moves on: after you answer, after an approved step finishes, when Claude finishes its reply, or when you send a new message.

**Good to know:** if you approve a slow step (say, a 5-minute build), the notification stays up until that step finishes. Just close it if it bugs you.

---

## Before you start

You need:

1. **A Mac** (macOS 12 or newer) with an **up-to-date Claude app or Claude Code**. Update first if you haven't in a while.
2. **Homebrew**, the free Mac app installer. Not sure if you have it? Open **Terminal** and paste:

   ```bash
   brew --version
   ```

   If you see a version number, you're set. If you see `command not found`, install Homebrew from [brew.sh](https://brew.sh) first (one copy-paste command), then come back.

The installer adds one small free tool, [terminal-notifier](https://github.com/julienXX/terminal-notifier), which is what shows the notifications. You don't need to install it yourself.

---

## Install (about 2 minutes)

**Step 1.** Open **Terminal** (press `Cmd + Space`, type `Terminal`, press Return).

**Step 2.** Paste this and press Return:

```bash
curl -fsSL https://raw.githubusercontent.com/troybrave/claude-waiting-notify-mac/main/install.sh -o /tmp/claude-waiting-install.sh && bash /tmp/claude-waiting-install.sh
```

**Step 3.** A sample **"Waiting on you"** notification appears.
If macOS asks whether **terminal-notifier** can send notifications, click **Allow**.

**Step 4. Make it stay on screen** (this is the important one). The installer opens System Settings for you.

1. In **System Settings > Notifications**, scroll the app list and click **terminal-notifier**.
2. Make sure **Allow notifications** is **on**.
3. Set the style to **Persistent**. (On older macOS this is called **Alerts**.)

   If you skip this, notifications still work but slide away after a few seconds, like normal banners.

**Step 5.** Start a **new** Claude session, or quit and reopen the Claude app. Sessions that were already open won't pick it up.

That's it.

---

## Test that it works

1. Start a new Claude session.
2. Ask Claude to do something that needs your permission, like *"run `ls` in the terminal"* (in a mode where it asks before running commands).
3. When the permission prompt shows up, the notification should appear.
4. Approve the prompt. Once the command finishes, the notification should disappear by itself.

---

## Uninstall

Paste this in Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/troybrave/claude-waiting-notify-mac/main/install.sh -o /tmp/claude-waiting-install.sh && bash /tmp/claude-waiting-install.sh --uninstall
```

Then start a new Claude session. To also remove the notification tool:

```bash
brew uninstall terminal-notifier
```

---

## Troubleshooting

**No notification at all**

- **Focus / Do Not Disturb is on.** Check the Control Center (top-right of the screen). Turn Focus off, or allow terminal-notifier in that Focus.
- **Notifications are blocked.** Go to **System Settings > Notifications > terminal-notifier** and turn on **Allow notifications**. Then run the installer again to see the sample.
- **terminal-notifier isn't in the Notifications list.** Run the installer again. The list entry is created the first time a notification is sent.
- **Old session.** Hooks only load when a session starts. Start a new one.

**The notification disappears after a few seconds**

Set the style to **Persistent** (or **Alerts**): **System Settings > Notifications > terminal-notifier**.

**The installer says `settings.json is not valid JSON` (or "not saved as UTF-8", or "not an object")**

Your Claude settings file has a problem in it, so the installer stopped before changing anything. Fix the file at `~/.claude/settings.json` (or ask Claude to fix it), then run the installer again.

**A notification is stuck on screen**

Just close it. It can happen if a session ends in an unusual way, such as the app being force-quit.

**I want my old settings back**

Whenever the installer changes your settings, it first saves a backup next to the original: `~/.claude/settings.json.bak-<date>-<time>` (sometimes with `-1`, `-2` on the end). Copy the newest one back over `settings.json`. These backups are small. You can delete old ones any time.

---

## Is it safe?

- **Your other settings and hooks are left alone.** The installer only adds or removes its own entries.
- **It checks your settings file first.** If anything looks wrong, it stops before changing anything.
- **A backup is saved** every time it changes your settings.
- **Safe to run again.** Re-running replaces its own entries, it never duplicates them.
- **Nothing leaves your Mac.** Installing downloads the script and terminal-notifier. After that: no network calls, no accounts, no tracking. It reads the session info Claude Code hands it and shows a local notification.
- **Fast.** On ordinary tool calls it does a quick check and exits. The notification tool only runs when something is actually waiting.

---

## How it works (for the curious)

The installer:

1. Installs `terminal-notifier` with Homebrew if it's missing.
2. Writes one script: `~/.claude/hooks/notify-mac/waiting-notify.sh`.
3. Adds [Claude Code hooks](https://docs.claude.com/en/docs/claude-code/hooks) to `~/.claude/settings.json`:

| When | What it does |
|------|--------------|
| `PermissionRequest`, `Notification` (permission prompt or question) | Show the notification |
| `PostToolUse`, `PostToolUseFailure`, `PermissionDenied`, `Stop`, `UserPromptSubmit`, `SessionEnd` | Clear that session's notification |

All hooks run in the background, so they never slow Claude down.

If you use a custom Claude config folder (`CLAUDE_CONFIG_DIR`), the installer uses that instead of `~/.claude`.

Options:

```bash
bash install.sh --uninstall    # remove it
bash install.sh --no-sample    # install without the sample notification
```

---

## What's been tested

Two rounds of automated testing ran on macOS 27, with a stand-in for the notification tool. They covered: fresh install, re-install, uninstall (settings restored exactly), broken or unusual settings files, symlinked settings, odd session data, and the "notifications blocked" message.

Not yet confirmed on a real screen: how the notification looks, its sound, and the Persistent style. If something's off, please [open an issue](https://github.com/troybrave/claude-waiting-notify-mac/issues).

---

## License

MIT. See [LICENSE](LICENSE).

Inspired by a Windows version shared in the Claude Code community.
