<p align="center"><img src="icon/Glimpse.png" width="128" alt="Glimpse icon"></p>

<h1 align="center">Glimpse</h1>

<p align="center">
  Screenshot a question, paste the answer.<br>
  <a href="https://github.com/haosenssss/Glimpse/releases/latest">Download</a> · macOS 14+ · Apple Silicon · MIT
</p>

Glimpse is a small macOS menu-bar app for answering questions on your screen. You drag a box around a question, a vision model of your choice reads it, and the answer is typed in wherever your cursor is. There is no window to switch to and nothing on screen except a faint indicator while it works.

## How it works

| Step | What you do | What you see |
|---|---|---|
| 1 | Press **⌃⌥G** and drag over a question | A hairline selection box. Focus stays in the app you were using. |
| 2 | Wait a few seconds | A small ring spinning in a corner of the screen |
| 3 | Press **Return** | The ring closes with a check, then the answer is pasted at the cursor |

Press **Esc** at any point to cancel. Return and Esc are only intercepted while an answer is pending, and an answer you don't paste expires after a minute (it stays in History).

## Install

1. Download `Glimpse-x.y.z.zip` from [Releases](https://github.com/haosenssss/Glimpse/releases/latest), unzip it, and move `Glimpse.app` to Applications.
2. The app isn't notarized, so macOS blocks the first launch. Open **System Settings → Privacy & Security** and click **Open Anyway**, or run:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Glimpse.app
   ```
3. Click the menu-bar icon and grant both items under **Permissions**: Accessibility (to paste) and Screen Recording (to capture).

## Set up a model

Open **Model** in the menu, set the base URL, paste your API key, and pick a model from the list. Any OpenAI-compatible endpoint works, as long as the model accepts images.

## The menu

Everything is set from the menu-bar icon, and changes apply immediately:

```
History          recent answers (click to copy) · Show Last Screenshot
Model            base URL · API key · model · timeout
System Prompt    edit · reset to default
Shortcuts        capture · quit
Indicator        size · opacity · drag to any position
Permissions      Accessibility · Screen Recording
```

## Privacy

- Your API key is stored in the macOS Keychain.
- Screenshots, answers, and history live in memory only and are gone when you quit.
- Requests go straight to the endpoint you configured over HTTPS (plain HTTP is only allowed for localhost), with no caching.

## Build from source

You need macOS 14 or later and the Xcode Command Line Tools.

```bash
scripts/spm.sh test      # run the tests
scripts/install.sh       # build, sign and copy to /Applications
scripts/release.sh       # build the distributable zip
```

`install.sh` signs with your Apple Development certificate if you have one, so permissions survive rebuilds. `spm.sh` is plain `swift` plus a workaround for a broken Command Line Tools install that only kicks in when needed.

## License

MIT
