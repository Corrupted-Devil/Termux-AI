# 🤖 Termux-AI · Terminal AI Chat Client

A powerful, feature-rich terminal-based AI chat client powered by **OpenRouter API**. Works seamlessly on **Termux (Android)**, **Linux**, and **macOS**.

![Version](https://img.shields.io/badge/version-3.0-blue)
![Language](https://img.shields.io/badge/language-Bash-green)
![License](https://img.shields.io/badge/license-MIT-brightgreen)

---

## ✨ Features

- **🎯 Multi-Model Support** — Access 50+ AI models (GPT-5.5, Claude, Gemini, Llama, etc.)
- **📝 Markdown Rendering** — Beautiful syntax highlighting with `glow`, `bat`, or ANSI fallback
- **💾 Chat Persistence** — Save and load conversations as JSON files
- **🎨 Rich Terminal UI** — Colored output, spinners, and formatted responses
- **🔐 Secure Configuration** — API keys stored securely (mode 600)
- **🔄 Auto-Dependency Install** — Detects and installs `curl` & `jq` automatically
- **⚡ Network Resilient** — Built-in retry logic and timeout handling
- **🌍 Cross-Platform** — Termux, Ubuntu, Fedora, Arch, macOS, and more

---

## 📋 Requirements

- **curl** — For HTTP requests (auto-installed)
- **jq** — For JSON processing (auto-installed)
- **OpenRouter API Key** — Get one free at https://openrouter.ai/keys

---

## 🚀 Quick Start

### 1. Clone the Repository
```bash
git clone https://github.com/Master-Tronix/Termux-AI
cd Termux-AI
```

### 2. Make it Executable
```bash
chmod +x Termux-AI.sh
```

### 3. Run the Script
```bash
./Termux-AI.sh
```

### 4. Provide Your API Key
On first run, you'll be prompted to enter your OpenRouter API key. It will be saved to `~/.openrouter_chat.conf` for future sessions.

---

## 💬 Available Commands

| Command | Description |
|---------|-------------|
| `/help` | Display all available commands |
| `/clear` | Clear conversation history |
| `/history` | Show full chat with formatting |
| `/model` | Switch to a different AI model |
| `/key` | Update or change your API key |
| `/md` | Toggle markdown rendering on/off |
| `/save` | Save current chat to a file |
| `/load` | Load a previously saved chat |
| `/exit` / `/quit` | Exit the program |

---

## 🎮 Usage Examples

### Start a conversation
```
You › Tell me about machine learning
```

### Switch models mid-conversation
```
You › /model
Current model: openai/gpt-5.5
New model (blank = keep current): anthropic/claude-opus-4-5
```

### Save your chat
```
You › /save
Filename (default: chat_20260628_120000.json): my_conversation.json
```

### Toggle markdown rendering
```
You › /md
Markdown rendering OFF (raw text + typing effect).
```

---

## 📂 File Structure

```
~/.openrouter_chat.conf       # Configuration file (API key + default model)
~/.openrouter_chats/          # Directory for saved conversations
  ├── chat_20260628_120000.json
  ├── my_conversation.json
  └── ...
```

---

## 🎨 Supported AI Models

Some popular models available through OpenRouter:

- **OpenAI** — `openai/gpt-5.5`, `openai/gpt-4o-mini`
- **Anthropic** — `anthropic/claude-opus-4-5`
- **Google** — `google/gemini-2.0-flash-001`
- **Meta** — `meta-llama/llama-3.3-70b-instruct`
- **And 50+ more!**

For the complete list, visit: https://openrouter.ai/models

---

## 🖥️ Installation on Different Platforms

### Termux (Android)
```bash
pkg install bash curl jq git
git clone https://github.com/Master-Tronix/Termux-AI
cd Termux-AI
chmod +x Termux-AI.sh
./Termux-AI.sh
```

### Ubuntu/Debian
```bash
sudo apt-get install curl jq git
git clone https://github.com/Master-Tronix/Termux-AI
cd Termux-AI
chmod +x Termux-AI.sh
./Termux-AI.sh
```

### macOS
```bash
brew install curl jq git
git clone https://github.com/Master-Tronix/Termux-AI
cd Termux-AI
chmod +x Termux-AI.sh
./Termux-AI.sh
```

### Fedora/RHEL
```bash
sudo dnf install curl jq git
git clone https://github.com/Master-Tronix/Termux-AI
cd Termux-AI
chmod +x Termux-AI.sh
./Termux-AI.sh
```

---

## 🔧 Configuration

The script stores settings in `~/.openrouter_chat.conf`:

```ini
API_KEY=sk-or-xxxxxxxxxxxxxxxx
DEFAULT_MODEL=openai/gpt-5.5
```

Edit this file directly or use the `/key` and `/model` commands in the chat interface.

---

## 🎨 UI Features

### Syntax Highlighting
Code blocks are highlighted by language with color-coded output:
- **Python** → Amber
- **JavaScript** → Bright Yellow
- **TypeScript** → Sky Blue
- **Bash** → Light Green
- And many more!

### Markdown Support
- **Headers** (# ## ###) with underlines
- **Bold** and *italic* text
- `Inline code` with dark background
- ```code blocks``` with syntax highlighting
- > Blockquotes with visual bars
- Lists (ordered & unordered)
- Horizontal rules

---

## ⚙️ Advanced Options

### Disable Automatic Dependency Installation
Modify the `check_dependencies()` function if you prefer manual installation.

### Custom Models
In the `/model` command, enter any model ID from https://openrouter.ai/models

### Typing Effect
When markdown rendering is disabled (`/md`), responses display with a typing effect for a more interactive feel.

---

## 🐛 Troubleshooting

### "Missing required deps: curl jq"
The script will attempt auto-install. If it fails, install manually:
```bash
# Ubuntu/Debian
sudo apt-get install curl jq

# Fedora
sudo dnf install curl jq

# macOS
brew install curl jq
```

### "Invalid API key (401)"
Run `/key` to update your OpenRouter API key. Get one at https://openrouter.ai/keys

### "Network error — check your connection"
Ensure you have internet connectivity and OpenRouter API is accessible.

### "Empty response. Model may be unavailable"
Try switching models with `/model` or check https://openrouter.ai/status

---

## 📝 Chat History Format

Saved chats are stored as JSON:

```json
{
  "metadata": {
    "model": "openai/gpt-5.5",
    "saved_at": "2026-06-28T12:00:00Z",
    "messages": 5
  },
  "messages": [
    {"role": "user", "content": "Hello!"},
    {"role": "assistant", "content": "Hi there! How can I help?"}
  ]
}
```

---

## 🤝 Contributing

Contributions are welcome! Feel free to:
- Report bugs
- Suggest features
- Submit pull requests
- Share improvements

---

## 📄 License

This project is licensed under the **MIT License**. See `LICENSE` for details.

---

## 🔗 Links

- **OpenRouter**: https://openrouter.ai
- **Get API Key**: https://openrouter.ai/keys
- **Available Models**: https://openrouter.ai/models
- **GitHub Repository**: https://github.com/Corrupted-Devil/Termux-AI

---

## 💡 Tips & Tricks

1. **Context Matters** — Keep your conversation history for better context-aware responses
2. **Switch Models** — Different models excel at different tasks; experiment!
3. **Save Interesting Chats** — Use `/save` to preserve valuable conversations
4. **Markdown Toggle** — Disable markdown (`/md`) for a simpler, faster view
5. **History Export** — Your saved chats are plain JSON—easily shareable or parseable

---

**Made with ❤️ for terminal enthusiasts everywhere** 
**By MasterTronix**

Happy chatting! **🚀😏**
