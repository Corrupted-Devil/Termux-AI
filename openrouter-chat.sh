#!/usr/bin/env bash
# ================================================================
#  openrouter-chat.sh  ·  v2.0
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

# ─── ANSI Color Codes ───────────────────────────────────────────
R='\033[0m'          # Reset
BOLD='\033[1m'
DIM='\033[2m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[0;37m'
BWHITE='\033[1;37m'

# ================================================================
# §1  DEPENDENCY CHECK
# ================================================================

check_dependencies() {
  local missing=()
  for cmd in curl jq; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  [[ ${#missing[@]} -eq 0 ]] && return 0

  echo -e "${YELLOW}[!] Missing dependencies: ${missing[*]}${R}"
  echo -e "${YELLOW}[*] Attempting automatic install...${R}\n"

  # Detect package manager and install
  if   command -v pkg     &>/dev/null; then pkg install -y "${missing[@]}"
  elif command -v apt-get &>/dev/null; then sudo apt-get install -y "${missing[@]}"
  elif command -v dnf     &>/dev/null; then sudo dnf install -y "${missing[@]}"
  elif command -v pacman  &>/dev/null; then sudo pacman -Sy --noconfirm "${missing[@]}"
  elif command -v brew    &>/dev/null; then brew install "${missing[@]}"
  elif command -v apk     &>/dev/null; then sudo apk add "${missing[@]}"
  elif command -v zypper  &>/dev/null; then sudo zypper install -y "${missing[@]}"
  else
    echo -e "${RED}[✗] No supported package manager found."
    echo -e "    Please install manually: ${missing[*]}${R}"
    exit 1
  fi

  # Verify install succeeded
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

# Load API key and saved model from config file
load_config() {
  [[ -f "$CONFIG_FILE" ]] || return 0
  local saved_key saved_model
  saved_key=$(grep -E '^API_KEY='      "$CONFIG_FILE" 2>/dev/null | head -1 | cut -d'=' -f2-)
  saved_model=$(grep -E '^DEFAULT_MODEL=' "$CONFIG_FILE" 2>/dev/null | head -1 | cut -d'=' -f2-)
  [[ -n "$saved_key"   ]] && API_KEY="$saved_key"
  [[ -n "$saved_model" ]] && CURRENT_MODEL="$saved_model"
}

# Write API key and current model to config (chmod 600 for security)
save_config() {
  printf 'API_KEY=%s\nDEFAULT_MODEL=%s\n' "$API_KEY" "$CURRENT_MODEL" > "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
}

# Interactive API key prompt (input hidden)
prompt_for_api_key() {
  echo -e "\n${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
  echo -e "  ║      OpenRouter API Key Setup          ║"
  echo -e "  ╚══════════════════════════════════════════╝${R}"
  echo -e "${DIM}  Get your key → https://openrouter.ai/keys${R}\n"

  while true; do
    echo -ne "${YELLOW}  Paste API key: ${R}"
    read -rs raw_key
    echo ""

    if [[ -z "$raw_key" ]]; then
      echo -e "${RED}  [✗] Key cannot be empty.${R}"
      continue
    fi

    API_KEY="$raw_key"
    save_config
    echo -e "${GREEN}  [✓] Key saved → ${CONFIG_FILE}${R}\n"
    break
  done
}

# First-launch setup or skip if key already exists
setup_api_key() {
  load_config
  [[ -z "$API_KEY" ]] && prompt_for_api_key
}

# ================================================================
# §3  UI HELPERS
# ================================================================

# ── Thinking Spinner (runs as background process) ────────────────
_spin() {
  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local i=0
  trap 'exit 0' TERM INT
  while true; do
    printf "\r${MAGENTA}  %s Thinking...${R}   " "${frames[$((i % 10))]}"
    i=$(( i + 1 ))
    sleep 0.08
  done
}

start_thinking() {
  _spin &
  THINKING_PID=$!
}

stop_thinking() {
  if [[ -n "${THINKING_PID}" ]] && kill -0 "${THINKING_PID}" 2>/dev/null; then
    kill "${THINKING_PID}" 2>/dev/null
    wait "${THINKING_PID}" 2>/dev/null || true
  fi
  THINKING_PID=""
  printf "\r\033[2K"   # erase the spinner line
}

# ── Typing Effect ────────────────────────────────────────────────
# Prints text character by character for responses ≤ 900 chars;
# falls back to instant print for longer responses.
print_typing() {
  local text="$1"
  local delay="0.008"
  local len i char

  len=${#text}

  if (( len > 900 )); then
    # Instant print with indentation for each line
    printf "${WHITE}"
    while IFS= read -r line; do
      printf '  %s\n' "$line"
    done <<< "$text"
    printf "${R}"
    return
  fi

  printf "${WHITE}  "
  i=0
  while (( i < len )); do
    char="${text:$i:1}"
    if [[ "$char" == $'\n' ]]; then
      printf '\n  '
    else
      printf '%s' "$char"
    fi
    sleep "$delay"
    (( i++ )) || true
  done
  printf "${R}\n"
}

# ── Formatted Status Messages ────────────────────────────────────
err()  { echo -e "\n${RED}  [✗] ${1}${R}\n"; }
ok()   { echo -e "\n${GREEN}  [✓] ${1}${R}\n"; }
info() { echo -e "\n${YELLOW}  [*] ${1}${R}\n"; }

# ── Decorative Header ────────────────────────────────────────────
print_header() {
  clear
  local model_display
  # Truncate model name if too long for header box
  if (( ${#CURRENT_MODEL} > 38 )); then
    model_display="${CURRENT_MODEL:0:35}..."
  else
    model_display="${CURRENT_MODEL}"
  fi

  echo -e "${CYAN}${BOLD}"
  printf '  ╔══════════════════════════════════════════════╗\n'
  printf '  ║   ◈  OpenRouter Terminal Chat               ║\n'
  printf "  ║   Model: %-36s║\n" "${model_display}"
  printf '  ╚══════════════════════════════════════════════╝\n'
  echo -e "${R}"
  echo -e "${DIM}  Type ${R}${YELLOW}/help${R}${DIM} for commands  ·  Ctrl+C or /exit to quit${R}\n"
}

# ================================================================
# §4  API — SEND MESSAGE
# ================================================================

send_message() {
  local user_input="$1"

  # Append user message to conversation JSON array
  CHAT_HISTORY=$(printf '%s' "$CHAT_HISTORY" | jq \
    --arg r "user" \
    --arg c "$user_input" \
    '. + [{role: $r, content: $c}]')

  # Build request payload
  local body
  body=$(jq -n \
    --arg     model    "$CURRENT_MODEL" \
    --argjson messages "$CHAT_HISTORY" \
    '{model: $model, messages: $messages}')

  # Start spinner while waiting for response
  start_thinking

  # Send POST request; write body to temp file, capture HTTP code
  local tmp_file http_code raw_response
  tmp_file=$(mktemp)

  http_code=$(curl -s \
    -o "$tmp_file" \
    -w "%{http_code}" \
    --max-time 120 \
    --connect-timeout 15 \
    --retry 2 \
    --retry-delay 3 \
    -X POST "$API_ENDPOINT" \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -H "HTTP-Referer: https://github.com/openrouter-terminal-chat" \
    -H "X-Title: OpenRouter Terminal Chat" \
    -d "$body" 2>/dev/null)

  stop_thinking
  raw_response=$(cat "$tmp_file"); rm -f "$tmp_file"

  # ── Network failure (curl returned 000) ────────────────────────
  if [[ "$http_code" == "000" ]]; then
    CHAT_HISTORY=$(printf '%s' "$CHAT_HISTORY" | jq '.[:-1]')
    err "Network error — check your connection and try again."
    return 1
  fi

  # ── API-level error object in response body ─────────────────────
  local api_err
  api_err=$(printf '%s' "$raw_response" | jq -r '.error.message // empty' 2>/dev/null)

  if [[ -n "$api_err" ]]; then
    CHAT_HISTORY=$(printf '%s' "$CHAT_HISTORY" | jq '.[:-1]')
    case "$http_code" in
      401) err "Authentication failed (401) — invalid API key. Run /key to update." ;;
      402) err "Insufficient credits (402) — top up at openrouter.ai/credits." ;;
      429) err "Rate limit exceeded (429) — wait a moment before retrying." ;;
      503|502) err "OpenRouter service unavailable (${http_code}) — try again shortly." ;;
      *)   err "API error ${http_code}: ${api_err}" ;;
    esac
    return 1
  fi

  # ── Unexpected non-200 without error body ──────────────────────
  if [[ "$http_code" != "200" ]]; then
    CHAT_HISTORY=$(printf '%s' "$CHAT_HISTORY" | jq '.[:-1]')
    local snippet
    snippet=$(printf '%s' "$raw_response" | head -c 200)
    err "Unexpected HTTP ${http_code}. Response: ${snippet}"
    return 1
  fi

  # ── Parse assistant content ────────────────────────────────────
  local content
  content=$(printf '%s' "$raw_response" | jq -r '.choices[0].message.content // empty' 2>/dev/null)

  if [[ -z "$content" ]]; then
    CHAT_HISTORY=$(printf '%s' "$CHAT_HISTORY" | jq '.[:-1]')
    err "Empty response. Model '${CURRENT_MODEL}' may be unavailable or unsupported."
    return 1
  fi

  # Append assistant reply to conversation history
  CHAT_HISTORY=$(printf '%s' "$CHAT_HISTORY" | jq \
    --arg r "assistant" \
    --arg c "$content" \
    '. + [{role: $r, content: $c}]')

  # Display response with typing effect
  echo -e "\n${GREEN}${BOLD}  AI ›${R}"
  print_typing "$content"
  echo ""
}

# ================================================================
# §5  COMMANDS
# ================================================================

# /help — list all available commands
cmd_help() {
  echo -e "\n${CYAN}${BOLD}  ╔══════════════════════════════════════════════╗"
  echo -e "  ║  Available Commands                         ║"
  echo -e "  ╠══════════════════════════════════════════════╣${R}"

  local -a cmds=(
    "/help    │ Show this help message"
    "/clear   │ Wipe conversation history"
    "/history │ Print full chat history"
    "/model   │ Switch AI model"
    "/key     │ Update OpenRouter API key"
    "/save    │ Save current chat to file"
    "/load    │ Load a saved chat file"
    "/exit    │ Quit the program"
  )

  for c in "${cmds[@]}"; do
    local name="  ${c%% │*}"
    local desc="${c##* │ }"
    printf "${CYAN}${BOLD}  ║${R}  ${YELLOW}%-10s${R}  ${DIM}%s${R}\n" "${name}" "${desc}"
  done

  echo -e "${CYAN}${BOLD}  ╚══════════════════════════════════════════════╝${R}"
  echo -e "${DIM}  Active model: ${CURRENT_MODEL}${R}\n"
}

# /clear — reset conversation history
cmd_clear() {
  CHAT_HISTORY="[]"
  ok "Conversation history cleared."
}

# /history — display all messages in the current session
cmd_history() {
  local count
  count=$(printf '%s' "$CHAT_HISTORY" | jq 'length')

  if (( count == 0 )); then
    info "History is empty — start chatting!"
    return
  fi

  echo -e "\n${CYAN}${BOLD}  ── Conversation History (${count} messages) ───────────${R}\n"

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
        echo -e "${WHITE}  ${content}${R}\n"
        ;;
      system)
        echo -e "${YELLOW}${BOLD}  System:${R}"
        echo -e "${DIM}  ${content}${R}\n"
        ;;
    esac
  done < <(printf '%s' "$CHAT_HISTORY" | jq -c '.[]')

  echo -e "${DIM}  ── end of history ──${R}\n"
}

# /model — display current model and switch to a new one
cmd_model() {
  echo -e "\n${CYAN}  Current model: ${BOLD}${CURRENT_MODEL}${R}"
  echo -e "${DIM}  Some available models on OpenRouter:${R}"
  echo -e "${DIM}    openai/gpt-5.5                     openai/gpt-4o${R}"
  echo -e "${DIM}    openai/gpt-4o-mini                 openai/o3-mini${R}"
  echo -e "${DIM}    anthropic/claude-opus-4-5          anthropic/claude-sonnet-4-5${R}"
  echo -e "${DIM}    google/gemini-2.0-flash-001        google/gemini-pro${R}"
  echo -e "${DIM}    meta-llama/llama-3.3-70b-instruct  mistralai/mistral-7b-instruct${R}"
  echo -e "${DIM}  Full list → https://openrouter.ai/models${R}\n"
  echo -ne "${YELLOW}  New model (blank = keep current): ${R}"
  read -r new_model

  if [[ -n "$new_model" ]]; then
    CURRENT_MODEL="$new_model"
    save_config
    ok "Model → ${CURRENT_MODEL}"
  else
    info "Model unchanged: ${CURRENT_MODEL}"
  fi
}

# /key — update stored API key
cmd_key() {
  load_config
  prompt_for_api_key
}

# /save — save current chat history to a JSON file
cmd_save() {
  mkdir -p "$HISTORY_DIR"

  local ts
  ts=$(date +"%Y%m%d_%H%M%S")
  local default_name="chat_${ts}.json"

  echo -ne "${YELLOW}  Filename (default: ${default_name}): ${R}"
  read -r name
  name="${name:-$default_name}"
  [[ "$name" != *.json ]] && name="${name}.json"

  local save_path="${HISTORY_DIR}/${name}"
  local msg_count
  msg_count=$(printf '%s' "$CHAT_HISTORY" | jq 'length')

  jq -n \
    --arg     model   "$CURRENT_MODEL" \
    --arg     ts      "$(date -Iseconds 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --argjson count   "$msg_count" \
    --argjson msgs    "$CHAT_HISTORY" \
    '{
      metadata: {
        model:      $model,
        saved_at:   $ts,
        messages:   $count
      },
      messages: $msgs
    }' > "$save_path"

  ok "Chat saved → ${save_path}  (${msg_count} messages)"
}

# /load — list saved chats and restore selected one
cmd_load() {
  mkdir -p "$HISTORY_DIR"

  # Collect all saved .json files, newest first
  local saves=()
  while IFS= read -r f; do
    saves+=("$f")
  done < <(find "$HISTORY_DIR" -maxdepth 1 -name "*.json" -type f 2>/dev/null | sort -r)

  if (( ${#saves[@]} == 0 )); then
    info "No saved chats found in ${HISTORY_DIR}"
    return
  fi

  echo -e "\n${CYAN}${BOLD}  ── Saved Chats ──────────────────────────────${R}\n"
  local i=1
  for f in "${saves[@]}"; do
    local fname msgs_n saved_at
    fname=$(basename "$f")
    msgs_n=$(jq -r '(.metadata.messages // (.messages|length) | tostring)' "$f" 2>/dev/null || echo "?")
    saved_at=$(jq -r '.metadata.saved_at // "unknown"' "$f" 2>/dev/null || echo "")
    printf "  ${YELLOW}%2d)${R}  %-35s ${DIM}%s msgs · %s${R}\n" \
      "$i" "$fname" "$msgs_n" "$saved_at"
    (( i++ )) || true
  done

  echo -ne "\n${YELLOW}  Select [1-${#saves[@]}] or blank to cancel: ${R}"
  read -r sel

  if [[ -z "$sel" ]]; then
    info "Load cancelled."
    return
  fi

  if ! [[ "$sel" =~ ^[0-9]+$ ]] || (( sel < 1 || sel > ${#saves[@]} )); then
    err "Invalid selection: ${sel}"
    return
  fi

  local file="${saves[$((sel - 1))]}"

  local loaded_msgs
  loaded_msgs=$(jq '.messages' "$file" 2>/dev/null)

  if [[ -z "$loaded_msgs" || "$loaded_msgs" == "null" ]]; then
    err "Failed to read chat file: ${file}"
    return
  fi

  CHAT_HISTORY="$loaded_msgs"

  # Restore model used when chat was saved
  local saved_model
  saved_model=$(jq -r '.metadata.model // empty' "$file" 2>/dev/null)
  [[ -n "$saved_model" ]] && CURRENT_MODEL="$saved_model"

  local loaded_count
  loaded_count=$(printf '%s' "$CHAT_HISTORY" | jq 'length')
  ok "Loaded: $(basename "$file")  (${loaded_count} messages · model: ${CURRENT_MODEL})"
}

# /exit — clean shutdown
cmd_exit() {
  stop_thinking
  echo -e "\n${CYAN}  ◈  Session ended. Goodbye!${R}\n"
  exit 0
}

# ================================================================
# §6  SIGNAL HANDLING
# ================================================================

_cleanup() {
  stop_thinking
  echo -e "\n\n${CYAN}  Session interrupted. Goodbye!${R}\n"
  exit 0
}

trap _cleanup INT TERM HUP

# ================================================================
# §7  MAIN CHAT LOOP
# ================================================================

main_loop() {
  while true; do
    # Prompt — Ctrl+D (EOF) triggers graceful exit
    echo -ne "${BLUE}${BOLD}  You › ${R}"

    if ! IFS= read -r user_input; then
      cmd_exit
    fi

    # Skip empty lines
    [[ -z "$user_input" ]] && continue

    # Normalise for command matching (lowercase copy only)
    local cmd_check
    cmd_check=$(printf '%s' "$user_input" | tr '[:upper:]' '[:lower:]')

    case "$cmd_check" in
      /help)              cmd_help    ;;
      /clear)             cmd_clear   ;;
      /history)           cmd_history ;;
      /model)             cmd_model   ;;
      /key)               cmd_key     ;;
      /save)              cmd_save    ;;
      /load)              cmd_load    ;;
      /exit|/quit|/q|/bye) cmd_exit  ;;
      /*)
        err "Unknown command: '${user_input}'  →  type /help for a list."
        ;;
      *)
        # Regular message — send to OpenRouter API
        send_message "$user_input"
        ;;
    esac
  done
}

# ================================================================
# §8  ENTRY POINT
# ================================================================

main() {
  check_dependencies
  setup_api_key
  mkdir -p "$HISTORY_DIR"
  print_header
  main_loop
}

main "$@"
