# Part 5. Install the apps

[Back to the contents](../README.md#the-guide)

## Step 12. The Claude app

1. In Safari, go to **claude.ai/download**.
2. Download the Mac app and drag it into **Applications**.
3. Open it and sign in to your Claude account.

## Step 13. Claude Code

1. Open **Terminal** (Cmd + Space, type "Terminal").
2. Paste this and press Return. It's the official installer from claude.ai:

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

3. If it says "~/.local/bin is not in your PATH", paste this too, then close and reopen Terminal:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
```

## Step 14. Google Chrome

1. Go to **google.com/chrome**.
2. Download it and drag it into **Applications**.
3. Open it, but don't sign in to Google yet. Pick the right Google account later.

## Step 15. Developer tools (needed for GitHub)

1. In Terminal, paste `xcode-select --install` and press Return.
2. When the dialog asks to install the developer tools, click **Install**. Wait for it to finish.
3. To check it, paste `git --version` and press Return. You should see a version number.

---

Next: [Part 6. Go headless (no monitor)](06-go-headless.md)
