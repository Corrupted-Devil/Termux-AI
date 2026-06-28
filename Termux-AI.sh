#!/usr/bin/env bash
# ================================================================
#  openrouter-chat.sh  ·  v3.0
#  Terminal AI Chat Client  ·  OpenRouter API
#  Environments: Termux (Android) · Linux · macOS
# ================================================================

# ─── Global Constants ───────────────────────────────────────────
CONFIG_FILE="${HOME}/.openrouter_chat.conf"
HISTORY_DIR="${HOME}/.openrouter_chats"
API_ENDPOINT="https://openrouter.ai/api/v1/chat/completions"
DEFAULT_MODEL="openai/gpt-5.5"

# ─── Runtime State ──────────────────────────────────────────────
CURRENT_MODEL="${DEFAULT_MODEL}"
API_KEY=""
CHAT_HISTORY="[]"
THINKING_PID=""
MD_RENDER=true          # markdown rendering toggle (/md command)

# ─── ANSI Color Codes ($'...' so ESC is an actual byte everywhere) ──
R=$'\033[0m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
MAGENTA=$'\033[0;35m'
WHITE=$'\033[0;37m'
BWHITE=$'\033[1;37m'

# ================================================================
# §1  DEPENDENCY CHECK
# ================================================================

check_dependencies() {
  local missing=()
  for cmd in curl jq; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  [[ ${#missing[@]} -eq 0 ]] && return 0

  echo -e "${YELLOW}[!] Missing required deps: ${missing[*]}${R}"
  echo -e "${YELLOW}[*] Attempting automatic install...${R}\n"

  if   command -v pkg     &>/dev/null; then pkg install -y "${missing[@]}"
  elif command -v apt-get &>/dev/null; then sudo apt-get install -y "${missing[@]}"
  elif command -v dnf     &>/dev/null; then sudo dnf install -y "${missing[@]}"
  elif command -v pacman  &>/dev/null; then sudo pacman -Sy --noconfirm "${missing[@]}"
  elif command -v brew    &>/dev/null; then brew install "${missing[@]}"
  elif command -v apk     &>/dev/null; then sudo apk add "${missing[@]}"
  elif command -v zypper  &>/dev/null; then sudo zypper install -y "${missing[@]}"
  else
    echo -e "${RED}[✗] No supported package manager found.\n    Install manually: ${missing[*]}${R}"
    exit 1
  fi

  for cmd in "${missing[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
      echo -e "${RED}[✗] Failed to install '${cmd}'. Aborting.${R}"
      exit 1
    fi
  done
  echo -e "${GREEN}[✓] Dependencies ready.${R}\n"
}

# ================================================================
# §2  CONFIG — API KEY MANAGEMENT
# ================================================================

load_config() {
  [[ -f "$CONFIG_FILE" ]] || return 0
  local saved_key saved_model
  saved_key=$(grep -E '^API_KEY='       "$CONFIG_FILE" 2>/dev/null | head -1 | cut -d'=' -f2-)
  saved_model=$(grep -E '^DEFAULT_MODEL=' "$CONFIG_FILE" 2>/dev/null | head -1 | cut -d'=' -f2-)
  [[ -n "$saved_key"   ]] && API_KEY="$saved_key"
  [[ -n "$saved_model" ]] && CURRENT_MODEL="$saved_model"
}

save_config() {
  printf 'API_KEY=%s\nDEFAULT_MODEL=%s\n' "$API_KEY" "$CURRENT_MODEL" > "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
}

prompt_for_api_key() {
  echo -e "\n${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
  echo -e "  ║      OpenRouter API Key Setup          ║"
  echo -e "  ╚══════════════════════════════════════════╝${R}"
  echo -e "${DIM}  Get your key → https://openrouter.ai/keys${R}\n"
  while true; do
    echo -ne "${YELLOW}  Paste API key: ${R}"
    read -rs raw_key; echo ""
    if [[ -z "$raw_key" ]]; then
      echo -e "${RED}  [✗] Key cannot be empty.${R}"; continue
    fi
    API_KEY="$raw_key"
    save_config
    echo -e "${GREEN}  [✓] Key saved → ${CONFIG_FILE}${R}\n"
    break
  done
}

setup_api_key() {
  load_config
  [[ -z "$API_KEY" ]] && prompt_for_api_key
}

# ================================================================
# §3  UI HELPERS  (spinner · typing · status messages · header)
# ================================================================

# ── Thinking spinner (background process) ───────────────────────
_spin() {
  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local i=0
  trap 'exit 0' TERM INT
  while true; do
    printf "\r${MAGENTA}  %s Thinking...${R}   " "${frames[$((i % 10))]}"
    i=$(( i + 1 )); sleep 0.08
  done
}

start_thinking() { _spin & THINKING_PID=$!; }

stop_thinking() {
  if [[ -n "${THINKING_PID}" ]] && kill -0 "${THINKING_PID}" 2>/dev/null; then
    kill "${THINKING_PID}" 2>/dev/null
    wait "${THINKING_PID}" 2>/dev/null || true
  fi
  THINKING_PID=""
  printf "\r\033[2K"
}

# ── Typing effect (used when MD_RENDER=false) ───────────────────
print_typing() {
  local text="$1" delay="0.008" len i char
  len=${#text}
  if (( len > 900 )); then
    printf "${WHITE}"
    while IFS= read -r line; do printf '  %s\n' "$line"; done <<< "$text"
    printf "${R}"; return
  fi
  printf "${WHITE}  "; i=0
  while (( i < len )); do
    char="${text:$i:1}"
    [[ "$char" == $'\n' ]] && printf '\n  ' || printf '%s' "$char"
    sleep "$delay"; (( i++ )) || true
  done
  printf "${R}\n"
}

# ── Status helpers ───────────────────────────────────────────────
err()  { echo -e "\n${RED}  [✗] ${1}${R}\n"; }
ok()   { echo -e "\n${GREEN}  [✓] ${1}${R}\n"; }
info() { echo -e "\n${YELLOW}  [*] ${1}${R}\n"; }

# ── Header ──────────────────────────────────────────────────────
_md_engine() {
  command -v glow &>/dev/null && echo "glow"   && return
  command -v bat  &>/dev/null && echo "bat+ANSI" && return
  echo "ANSI"
}

print_header() {
  clear
  local mdisplay
  (( ${#CURRENT_MODEL} > 36 )) \
    && mdisplay="${CURRENT_MODEL:0:33}..." \
    || mdisplay="${CURRENT_MODEL}"
  echo -e "${CYAN}${BOLD}"
  printf '  ╔════════════════════════════════════════════════╗\n'
  printf '  ║   ◈  OpenRouter Terminal Chat  v3.0                                                                 ║\n'
  printf "  ║   Model:  %-37s║\n" "${mdisplay}"                                                                     
  printf "  ║   Render: %-37s║\n" "markdown[$(_md_engine)]"
  printf '  ╚════════════════════════════════════════════════╝\n'
  echo -e "${R}"
  echo -e "${DIM}  ${YELLOW}/help${R}${DIM} for commands  ·  ${YELLOW}/md${R}${DIM} toggle markdown  ·  Ctrl+C to quit${R}\n"
}

# ================================================================
# §4  MARKDOWN + SYNTAX RENDERING
# ================================================================

# ── 256-color map: language → foreground escape code ────────────
_lang_color() {
  case "${1,,}" in
    python|py)               printf '\033[38;5;220m' ;;  # amber
    javascript|js|jsx|mjs)  printf '\033[38;5;226m' ;;  # bright yellow
    typescript|ts|tsx)       printf '\033[38;5;39m'  ;;  # sky blue
    bash|sh|shell|zsh|fish) printf '\033[38;5;119m' ;;  # light green
    html|xml|svg|xhtml)      printf '\033[38;5;208m' ;;  # orange
    css|scss|sass|less)      printf '\033[38;5;81m'  ;;  # aqua
    json|jsonc|json5)        printf '\033[38;5;87m'  ;;  # bright cyan
    yaml|yml|toml|ini|env)   printf '\033[38;5;222m' ;;  # pale yellow
    sql|mysql|pgsql|sqlite)  printf '\033[38;5;213m' ;;  # lavender
    c|cpp|c++|cc|h|hpp)      printf '\033[38;5;75m'  ;;  # steel blue
    java|kotlin|kt)          printf '\033[38;5;214m' ;;  # orange
    go|golang)               printf '\033[38;5;86m'  ;;  # mint
    rust|rs)                 printf '\033[38;5;196m' ;;  # red
    php)                     printf '\033[38;5;147m' ;;  # soft purple
    ruby|rb)                 printf '\033[38;5;196m' ;;  # red
    lua)                     printf '\033[38;5;74m'  ;;  # blue
    swift)                   printf '\033[38;5;208m' ;;  # orange
    r|rlang)                 printf '\033[38;5;39m'  ;;  # blue
    csharp|cs)               printf '\033[38;5;141m' ;;  # purple
    dart)                    printf '\033[38;5;39m'  ;;  # blue
    elixir|ex|exs)           printf '\033[38;5;171m' ;;  # purple-pink
    docker|dockerfile)       printf '\033[38;5;33m'  ;;  # blue
    make|makefile)           printf '\033[38;5;220m' ;;  # yellow
    vim|vimscript)           printf '\033[38;5;40m'  ;;  # green
    diff|patch)              printf '\033[38;5;155m' ;;  # lime
    markdown|md)             printf '\033[38;5;255m' ;;  # white
    *)                       printf '\033[38;5;252m' ;;  # light gray
  esac
}

# ── Inline markdown renderer (awk): **bold** *italic* `code` ────
# Uses leftmost-match priority; inline code is processed first
# to protect its content from bold/italic substitution.
_render_inline() {
  [[ -z "$1" ]] && return
  local _B; _B=$'\033[1m'          # bold
  local _I; _I=$'\033[2m'          # dim/italic
  local _R; _R=$'\033[0m'          # reset
  local _C; _C=$'\033[48;5;236m\033[38;5;220m'  # inline code bg+fg

  printf '%s' "$1" | awk \
    -v B="$_B" -v I="$_I" -v R="$_R" -v C="$_C" \
  '
  # Returns type(1=code,2=bold,3=italic), pos, len via globals
  function find_first(s,   p1,l1,p2,l2,p3,l3) {
    p1=0; l1=0; p2=0; l2=0; p3=0; l3=0
    if (match(s, /`[^`]+`/))       { p1=RSTART; l1=RLENGTH }
    if (match(s, /\*\*[^*]+\*\*/)) { p2=RSTART; l2=RLENGTH }
    if (match(s, /\*[^*]+\*/))     { p3=RSTART; l3=RLENGTH }

    # Prevent italic-inside-bold false match
    if (p2>0 && p3>0 && p3>=p2 && p3<p2+l2) { p3=0; l3=0 }

    # Pick leftmost non-zero match
    _typ=0; _pos=0; _len=0
    if (p1>0)                          { _typ=1; _pos=p1; _len=l1 }
    if (p2>0 && (p2<_pos || _typ==0)) { _typ=2; _pos=p2; _len=l2 }
    if (p3>0 && (p3<_pos || _typ==0)) { _typ=3; _pos=p3; _len=l3 }
  }

  function render(s,   result,inner) {
    result=""
    while (length(s)>0) {
      find_first(s)
      if (_typ==0) { result=result s; break }

      result = result substr(s, 1, _pos-1)

      if (_typ==1) {                             # `inline code`
        inner = substr(s, _pos+1, _len-2)
        result = result C " " inner " " R
      } else if (_typ==2) {                      # **bold**
        inner = substr(s, _pos+2, _len-4)
        result = result B inner R
      } else {                                   # *italic*
        inner = substr(s, _pos+1, _len-2)
        result = result I inner R
      }
      s = substr(s, _pos+_len)
    }
    return result
  }
  { print render($0) }
  '
}

# ── Render a buffered code block via bat or ANSI fallback ────────
_flush_code_block() {
  local lang="$1"
  local buf="$2"
  [[ -z "$buf" ]] && return

  if command -v bat &>/dev/null; then
    # bat: full syntax highlighting — just indent the output
    local bat_lang="${lang:-text}"
    printf '%s\n' "$buf" \
      | bat --style=plain --color=always \
            --language="$bat_lang" --paging=never \
            --theme="Monokai Extended" 2>/dev/null \
      | sed 's/^/  /' \
      && return
    # bat failed (unknown lang etc.) — fall through to ANSI
  fi

  # ANSI fallback: dark background + per-language foreground color
  local lc; lc=$(_lang_color "$lang")
  local BG=$'\033[48;5;233m'
  local RS=$'\033[0m'
  while IFS= read -r cline; do
    printf "  ${BG}${lc}%s${RS}\n" "$cline"
  done <<< "$buf"
}

# ── Master markdown → ANSI renderer ─────────────────────────────
# Priority: glow (full) > bat+ANSI (hybrid) > pure ANSI fallback
render_markdown() {
  local text="$1"

  # Tier 1: glow  — renders full CommonMark
  if command -v glow &>/dev/null; then
    printf '%s\n' "$text" | glow -s dark -
    return
  fi

  # Tier 2 & 3: custom renderer  (bat used inside _flush_code_block)
  local in_code=false
  local lang="" code_buf=""
  local HB=$'\033[48;5;235m'   # header/footer bar background
  local RS=$'\033[0m'

  while IFS= read -r line; do

    # ── Fenced code block open/close ( ```lang ) ─────────────────
    if [[ "$line" =~ ^\`\`\`([a-zA-Z0-9_.+\-]*)$ ]]; then
      if [[ "$in_code" == false ]]; then
        in_code=true
        lang="${BASH_REMATCH[1],,}"
        code_buf=""
        local label="${lang:-code}"
        printf "  ${HB}${CYAN}${BOLD} ◆ %-44s${RS}\n" "${label^^}"
      else
        # Close: flush buffered content then draw footer
        in_code=false
        _flush_code_block "$lang" "$code_buf"
        printf "  ${HB}${DIM}%s${RS}\n" \
          "──────────────────────────────────────────────────"
        lang=""; code_buf=""
      fi
      continue
    fi

    # ── Inside code block: buffer lines ──────────────────────────
    if [[ "$in_code" == true ]]; then
      [[ -n "$code_buf" ]] && code_buf+=$'\n'"$line" || code_buf="$line"
      continue
    fi

    # ── Blank line ───────────────────────────────────────────────
    if [[ -z "$line" ]]; then printf '\n'; continue; fi

    # ── Horizontal rule  ---  ***  ___ ──────────────────────────
    if [[ "$line" =~ ^[[:space:]]*[-*_]{3,}[[:space:]]*$ ]]; then
      printf "  ${DIM}%s${R}\n" \
        "────────────────────────────────────────────────────"
      continue
    fi

    # ── ATX Headers  # ## ### ####  ─────────────────────────────
    if [[ "$line" =~ ^(#{1,6})[[:space:]]+(.+)$ ]]; then
      local lvl="${#BASH_REMATCH[1]}" htxt="${BASH_REMATCH[2]}"
      case "$lvl" in
        1) local bar; bar=$(printf '─%.0s' $(seq 1 ${#htxt}))
           printf "\n  ${CYAN}${BOLD}%s${R}\n  ${CYAN}${DIM}%s${R}\n" "$htxt" "$bar" ;;
        2) printf "\n  ${CYAN}${BOLD}▶ %s${R}\n" "$htxt" ;;
        3) printf "  ${CYAN}${BOLD}● %s${R}\n"   "$htxt" ;;
        *) printf "  ${DIM}${CYAN}○ %s${R}\n"   "$htxt" ;;
      esac
      continue
    fi

    # ── Blockquote  > text ───────────────────────────────────────
    if [[ "$line" =~ ^[[:space:]]*\>[[:space:]]?(.*)$ ]]; then
      printf "  ${CYAN}${BOLD}▌${R}  ${DIM}%s${R}\n" \
        "$(_render_inline "${BASH_REMATCH[1]}")"
      continue
    fi

    # ── Unordered list  - * + ────────────────────────────────────
    if [[ "$line" =~ ^([[:space:]]*)[-*+][[:space:]](.+)$ ]]; then
      local ind="${BASH_REMATCH[1]}" item="${BASH_REMATCH[2]}"
      local blt="${CYAN}•${R}"
      (( ${#ind} >= 2 )) && blt="${DIM}◦${R}"
      (( ${#ind} >= 4 )) && blt="${DIM}▪${R}"
      printf "  %s%s %s\n" "$ind" "$blt" "$(_render_inline "$item")"
      continue
    fi

    # ── Numbered list  1. 2. ─────────────────────────────────────
    if [[ "$line" =~ ^([[:space:]]*)([0-9]+)\.[[:space:]](.+)$ ]]; then
      printf "  %s${CYAN}%s.${R} %s\n" \
        "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" \
        "$(_render_inline "${BASH_REMATCH[3]}")"
      continue
    fi

    # ── Plain paragraph ──────────────────────────────────────────
    printf "  %s\n" "$(_render_inline "$line")"

  done <<< "$text"

  # Safety: flush unclosed code block
  if [[ "$in_code" == true && -n "$code_buf" ]]; then
    _flush_code_block "$lang" "$code_buf"
    printf "  ${DIM}(unclosed code block)${R}\n"
  fi
}

# ================================================================
# §5  API — SEND MESSAGE
# ================================================================

send_message() {
  local user_input="$1"

  # Append user message to JSON conversation history
  CHAT_HISTORY=$(printf '%s' "$CHAT_HISTORY" | jq \
    --arg r "user" --arg c "$user_input" \
    '. + [{role: $r, content: $c}]')

  local body
  body=$(jq -n \
    --arg     model    "$CURRENT_MODEL" \
    --argjson messages "$CHAT_HISTORY" \
    '{model: $model, messages: $messages}')

  start_thinking

  local tmp_file http_code raw_response
  tmp_file=$(mktemp)

  http_code=$(curl -s \
    -o "$tmp_file" -w "%{http_code}" \
    --max-time 120 --connect-timeout 15 \
    --retry 2 --retry-delay 3 \
    -X POST "$API_ENDPOINT" \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -H "HTTP-Referer: https://github.com/openrouter-terminal-chat" \
    -H "X-Title: OpenRouter Terminal Chat" \
    -d "$body" 2>/dev/null)

  stop_thinking
  raw_response=$(cat "$tmp_file"); rm -f "$tmp_file"

  # ── Network failure ─────────────────────────────────────────────
  if [[ "$http_code" == "000" ]]; then
    CHAT_HISTORY=$(printf '%s' "$CHAT_HISTORY" | jq '.[:-1]')
    err "Network error — check your connection."; return 1
  fi

  # ── API error body ──────────────────────────────────────────────
  local api_err
  api_err=$(printf '%s' "$raw_response" | jq -r '.error.message // empty' 2>/dev/null)

  if [[ -n "$api_err" ]]; then
    CHAT_HISTORY=$(printf '%s' "$CHAT_HISTORY" | jq '.[:-1]')
    case "$http_code" in
      401) err "Invalid API key (401). Run /key to update." ;;
      402) err "Insufficient credits (402). Top up at openrouter.ai." ;;
      429) err "Rate limit (429). Wait a moment then retry." ;;
      502|503) err "Service unavailable (${http_code}). Try again shortly." ;;
      *)   err "API error ${http_code}: ${api_err}" ;;
    esac
    return 1
  fi

  if [[ "$http_code" != "200" ]]; then
    CHAT_HISTORY=$(printf '%s' "$CHAT_HISTORY" | jq '.[:-1]')
    err "Unexpected HTTP ${http_code}: $(printf '%s' "$raw_response" | head -c 200)"
    return 1
  fi

  # ── Parse content ───────────────────────────────────────────────
  local content
  content=$(printf '%s' "$raw_response" \
    | jq -r '.choices[0].message.content // empty' 2>/dev/null)

  if [[ -z "$content" ]]; then
    CHAT_HISTORY=$(printf '%s' "$CHAT_HISTORY" | jq '.[:-1]')
    err "Empty response. Model '${CURRENT_MODEL}' may be unavailable."
    return 1
  fi

  # Append assistant reply
  CHAT_HISTORY=$(printf '%s' "$CHAT_HISTORY" | jq \
    --arg r "assistant" --arg c "$content" \
    '. + [{role: $r, content: $c}]')

  # ── Render response ─────────────────────────────────────────────
  echo -e "\n${GREEN}${BOLD}  AI ›${R}"
  if [[ "$MD_RENDER" == true ]]; then
    render_markdown "$content"
  else
    print_typing "$content"
  fi
  echo ""
}

# ================================================================
# §6  COMMANDS
# ================================================================

cmd_help() {
  echo -e "\n${CYAN}${BOLD}  ╔══════════════════════════════════════════════╗"
  echo -e "  ║  Available Commands                          ║"
  echo -e "  ╠══════════════════════════════════════════════╣${R}"
  local -a cmds=(
    "/help       │ Show this help message"
    "/clear      │ Wipe conversation history"
    "/history  │ Print full chat history (with markdown)"
    "/model    │ Switch AI model"
    "/key         │ Update OpenRouter API key"
    "/md         │ Toggle markdown+syntax rendering"
    "/save       │ Save current chat to file"
    "/load       │ Load a saved chat file"
    "/exit        │ Quit the program"
  )
  for c in "${cmds[@]}"; do
    local name="  ${c%% │*}" desc="${c##* │ }"
    printf "${CYAN}${BOLD}  ║${R}  ${YELLOW}%-10s${R}  ${DIM}%s${R}\n" "$name" "$desc"
  done
  echo -e "${CYAN}${BOLD}  ╚══════════════════════════════════════════════╝${R}"
  local md_status; [[ "$MD_RENDER" == true ]] && md_status="ON [$(_md_engine)]" || md_status="OFF"
  echo -e "${DIM}  Model: ${CURRENT_MODEL}  ·  Markdown: ${md_status}${R}\n"
}

cmd_clear() {
  CHAT_HISTORY="[]"
  ok "Conversation history cleared."
}

cmd_history() {
  local count
  count=$(printf '%s' "$CHAT_HISTORY" | jq 'length')
  if (( count == 0 )); then info "History is Empty."; return; fi

  echo -e "\n${CYAN}${BOLD}─ History (${count} messages) ───────────────────────${R}\n"

  while IFS= read -r entry; do
    local role content
    role=$(printf '%s' "$entry" | jq -r '.role')
    content=$(printf '%s' "$entry" | jq -r '.content')
    case "$role" in
      user)
        echo -e "${BLUE}${BOLD}  You:${R}"
        echo -e "${BWHITE}  ${content}${R}\n"
        ;;
      assistant)
        echo -e "${GREEN}${BOLD}  AI:${R}"
        if [[ "$MD_RENDER" == true ]]; then
          render_markdown "$content"
        else
          echo -e "${WHITE}  ${content}${R}"
        fi
        echo ""
        ;;
      system)
        echo -e "${YELLOW}${BOLD}  System:${R}"
        echo -e "${DIM}  ${content}${R}\n"
        ;;
    esac
  done < <(printf '%s' "$CHAT_HISTORY" | jq -c '.[]')

  echo -e "${DIM}  ─ end of history ─${R}\n"
}

cmd_model() {
  echo -e "\n${CYAN}  Current model: ${BOLD}${CURRENT_MODEL}${R}"
  echo -e "${DIM}  Some available models:${R}"
  echo -e "${DIM}    openai/gpt-5.5${R}"
  echo -e "${DIM}    openai/gpt-4o-mini${R}"
  echo -e "${DIM}    anthropic/claude-opus-4-5${R}"
  echo -e "${DIM}    google/gemini-2.0-flash-001${R}"
  echo -e "${DIM}    meta-llama/llama-3.3-70b-instruct${R}"
  echo -e "${DIM}  Full list → https://openrouter.ai/models${R}\n"
  echo -ne "${YELLOW}  New model (blank = keep current): ${R}"
  read -r new_model
  if [[ -n "$new_model" ]]; then
    CURRENT_MODEL="$new_model"; save_config
    ok "Model → ${CURRENT_MODEL}"
  else
    info "Model unchanged: ${CURRENT_MODEL}"
  fi
}

cmd_key() { load_config; prompt_for_api_key; }

# /md — toggle markdown + syntax rendering on/off
cmd_md() {
  if [[ "$MD_RENDER" == true ]]; then
    MD_RENDER=false
    info "Markdown rendering OFF  (raw text + typing effect)."
  else
    MD_RENDER=true
    info "Markdown rendering ON   [engine: $(_md_engine)]"
  fi
}

cmd_save() {
  mkdir -p "$HISTORY_DIR"
  local ts; ts=$(date +"%Y%m%d_%H%M%S")
  local default_name="chat_${ts}.json"
  echo -ne "${YELLOW}  Filename (default: ${default_name}): ${R}"
  read -r name
  name="${name:-$default_name}"
  [[ "$name" != *.json ]] && name="${name}.json"
  local save_path="${HISTORY_DIR}/${name}"
  local msg_count
  msg_count=$(printf '%s' "$CHAT_HISTORY" | jq 'length')
  jq -n \
    --arg     model "$CURRENT_MODEL" \
    --arg     ts    "$(date -Iseconds 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --argjson count "$msg_count" \
    --argjson msgs  "$CHAT_HISTORY" \
    '{metadata:{model:$model,saved_at:$ts,messages:$count},messages:$msgs}' \
    > "$save_path"
  ok "Chat saved → ${save_path}  (${msg_count} messages)"
}

cmd_load() {
  mkdir -p "$HISTORY_DIR"
  local saves=()
  while IFS= read -r f; do saves+=("$f"); done \
    < <(find "$HISTORY_DIR" -maxdepth 1 -name "*.json" -type f 2>/dev/null | sort -r)
  if (( ${#saves[@]} == 0 )); then
    info "No saved chats in ${HISTORY_DIR}"; return
  fi
  echo -e "\n${CYAN}${BOLD}  ── Saved Chats ─────────────────────────────${R}\n"
  local i=1
  for f in "${saves[@]}"; do
    local fname msgs_n saved_at
    fname=$(basename "$f")
    msgs_n=$(jq -r '(.metadata.messages // (.messages|length) | tostring)' "$f" 2>/dev/null || echo "?")
    saved_at=$(jq -r '.metadata.saved_at // "unknown"' "$f" 2>/dev/null || echo "")
    printf "  ${YELLOW}%2d)${R}  %-36s ${DIM}%s msgs · %s${R}\n" \
      "$i" "$fname" "$msgs_n" "$saved_at"
    (( i++ )) || true
  done
  echo -ne "\n${YELLOW}  Select [1-${#saves[@]}] or blank to cancel: ${R}"
  read -r sel
  [[ -z "$sel" ]] && { info "Cancelled."; return; }
  if ! [[ "$sel" =~ ^[0-9]+$ ]] || (( sel < 1 || sel > ${#saves[@]} )); then
    err "Invalid selection."; return
  fi
  local file="${saves[$((sel - 1))]}"
  local loaded_msgs
  loaded_msgs=$(jq '.messages' "$file" 2>/dev/null)
  if [[ -z "$loaded_msgs" || "$loaded_msgs" == "null" ]]; then
    err "Could not read file: ${file}"; return
  fi
  CHAT_HISTORY="$loaded_msgs"
  local saved_model
  saved_model=$(jq -r '.metadata.model // empty' "$file" 2>/dev/null)
  [[ -n "$saved_model" ]] && CURRENT_MODEL="$saved_model"
  local cnt; cnt=$(printf '%s' "$CHAT_HISTORY" | jq 'length')
  ok "Loaded: $(basename "$file")  (${cnt} messages · model: ${CURRENT_MODEL})"
}

cmd_exit() {
  stop_thinking
  echo -e "\n${CYAN}  ◈  Session ended. Goodbye!${R}\n"
  exit 0
}

# ================================================================
# §7  SIGNAL HANDLING
# ================================================================

_cleanup() {
  stop_thinking
  echo -e "\n\n${CYAN}  Session interrupted. Goodbye!${R}\n"
  exit 0
}

trap _cleanup INT TERM HUP

# ================================================================
# §8  MAIN CHAT LOOP
# ================================================================

main_loop() {
  while true; do
    echo -ne "${BLUE}${BOLD}  You › ${R}"
    if ! IFS= read -r user_input; then cmd_exit; fi
    [[ -z "$user_input" ]] && continue

    local cmd_check
    cmd_check=$(printf '%s' "$user_input" | tr '[:upper:]' '[:lower:]')

    case "$cmd_check" in
      /help)               cmd_help    ;;
      /clear)              cmd_clear   ;;
      /history)            cmd_history ;;
      /model)              cmd_model   ;;
      /key)                cmd_key     ;;
      /md)                 cmd_md      ;;
      /save)               cmd_save    ;;
      /load)               cmd_load    ;;
      /exit|/quit|/q|/bye) cmd_exit   ;;
      /*)
        err "Unknown command: '${user_input}'  →  type /help."
        ;;
      *)
        send_message "$user_input"
        ;;
    esac
  done
}

# ================================================================
# §9  ENTRY POINT
# ================================================================

main() {
  check_dependencies
  setup_api_key
  mkdir -p "$HISTORY_DIR"
  print_header
  main_loop
}

main "$@"