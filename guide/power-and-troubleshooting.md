# Power and troubleshooting

[Back to the contents](../README.md#the-guide)

## Power: the lesson

A battery backup alone isn't enough. Some battery power stations switch over too slowly for a short flicker. The power blinks, the Mac shuts off hard, and the battery never kicks in.

So the Mac has to restart by itself:

- Turn on **Start up automatically after a power failure** ([Step 10](04-always-on.md)) on every Mac you rely on.
- Turn on **Automatically log in as** ([Step 11](04-always-on.md)), so it logs back in with no one there.

For a machine that must never drop, use an **online (double-conversion) UPS**. It switches with no gap.

Put your router on backup power too. A Mac that's on with no internet is still offline.

## Troubleshooting

| Problem | Fix |
|---|---|
| `claude: command not found` | Run the PATH line in [Step 13](05-install-the-apps.md), then close and reopen Terminal. |
| Typed `restart` and Claude just chatted back | Commands need the slash: `/restart` ([Step 27](08-log-in-to-claude-code.md)). |
| Claude doesn't see your business files | Start it in your business folder ([Step 21](08-log-in-to-claude-code.md)), or pick the folder in the Claude app. |
| The screen looks small or blurry with no monitor | Reconnect with **High Performance** and **1 Virtual Display** ([Step 16](06-go-headless.md)). If it's still bad, use a cheap HDMI dummy plug. |
| Can't connect with Screen Sharing | Check the Mac mini is on and wired to the router, and Screen Sharing is on ([Step 9](03-remote-access.md)). |
| The Mac mini didn't come back after a power cut | Check the Energy settings in [Step 10](04-always-on.md) and automatic login in [Step 11](04-always-on.md). Check FileVault is off. |

---

More parts (remote control from your phone, connections, phone lines) are coming. Watch the repo to get them.

Next: [Back to the start](../README.md)
