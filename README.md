<p align="center"><img src="icon/Glimpse.png" width="128" alt="Glimpse icon"></p>

<h1 align="center">Glimpse</h1>

Glimpse is a small macOS menu-bar app for answering questions on your screen. Press the shortcut (⌃⌥G by default), drag a box around a question, and the screenshot goes to a vision model you pick. A faint ring spins while it thinks and closes with a check when the answer is ready. Press Return and the answer is pasted at your cursor; press Esc to throw it away.

There is no window. The model, API key, system prompt, shortcuts, and the indicator's size and position all live in the menu-bar icon's menu, along with a short history of recent answers. Any OpenAI-compatible endpoint that accepts images will work, including OpenAI, OpenRouter, Gemini, Qwen-VL, and local servers such as Ollama. Your API key is stored in the Keychain. Screenshots and answers are kept in memory only and disappear when you quit.

To build and install into /Applications, run `scripts/install.sh`. You need macOS 14 or later, and the Command Line Tools are enough. If you have an Apple Development certificate, the script signs the app with it, so the Accessibility and Screen Recording permissions survive rebuilds. Run the tests with `scripts/spm.sh test`. That script is plain `swift` plus a workaround for a broken Command Line Tools install that only kicks in when needed.

MIT licensed.
