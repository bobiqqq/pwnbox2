#!/usr/bin/env bash
set -euo pipefail

PROFILE="${PWNBOX_PROFILE:-x64}"
DOCKER_CONTEXT="${PWNBOX_DOCKER_CONTEXT:-}"
DOCKER_HOST="${PWNBOX_DOCKER_HOST:-}"
IMAGE="${PWNBOX_IMAGE:-pwnbox}"
INSTALL_PATH="${PWNBOX_INSTALL_PATH:-/usr/local/bin/pwnbox}"
DRY_RUN=false
DISABLE_COLOR=false
SKIP_BUILD=false

if [ -n "${NO_COLOR:-}" ]; then
  DISABLE_COLOR=true
fi

usage() {
  cat <<'EOF'
usage: setup.sh [options]

Options:
  --profile <name>         colima profile (default: x64 or PWNBOX_PROFILE)
  --context <name>         docker context (default: colima-<profile>)
  --docker-host <uri>      docker host uri (default: unix://$HOME/.colima/<profile>/docker.sock)
  --image <name>           image name to build (default: pwnbox)
  --install-path <path>    path for launcher install (default: /usr/local/bin/pwnbox)
  --skip-build             reuse an existing image instead of building it
  --dry-run                show steps without executing commands
  --no-color               disable colorized output
  -h, --help               show this help

Notes:
  - Run this script WITHOUT sudo.
  - It will request sudo only for final launcher install if needed.
  - On macOS/Homebrew, this script also fixes docker-buildx plugin visibility.
EOF
}

need_value() {
  if [ "$#" -lt 2 ] || [ -z "${2:-}" ]; then
    echo "error: option '$1' requires a value" >&2
    exit 2
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --profile)
      need_value "$@"
      PROFILE="$2"
      shift 2
      ;;
    --context)
      need_value "$@"
      DOCKER_CONTEXT="$2"
      shift 2
      ;;
    --docker-host)
      need_value "$@"
      DOCKER_HOST="$2"
      shift 2
      ;;
    --image)
      need_value "$@"
      IMAGE="$2"
      shift 2
      ;;
    --install-path)
      need_value "$@"
      INSTALL_PATH="$2"
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --no-color)
      DISABLE_COLOR=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ -z "$DOCKER_CONTEXT" ]; then
  DOCKER_CONTEXT="colima-${PROFILE}"
fi

if [ -z "$DOCKER_HOST" ]; then
  DOCKER_HOST="unix://${HOME}/.colima/${PROFILE}/docker.sock"
fi

if [ "$(id -u)" -eq 0 ]; then
  echo "error: do not run setup as root/sudo." >&2
  echo "hint: run './setup.sh' instead." >&2
  echo "hint: the script will use sudo only for final launcher install if required." >&2
  exit 1
fi

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$REPO_DIR"

if [ ! -f "$REPO_DIR/Dockerfile" ] || [ ! -f "$REPO_DIR/pwnbox" ]; then
  echo "error: expected Dockerfile and pwnbox launcher in $REPO_DIR" >&2
  exit 1
fi

if [ -t 1 ] && ! $DISABLE_COLOR; then
  C_RESET="$(printf '\033[0m')"
  C_BOLD="$(printf '\033[1m')"
  C_DIM="$(printf '\033[2m')"
  C_RED="$(printf '\033[31m')"
  C_GREEN="$(printf '\033[32m')"
  C_YELLOW="$(printf '\033[33m')"
  C_BLUE="$(printf '\033[34m')"
  C_CYAN="$(printf '\033[36m')"
else
  C_RESET=""
  C_BOLD=""
  C_DIM=""
  C_RED=""
  C_GREEN=""
  C_YELLOW=""
  C_BLUE=""
  C_CYAN=""
fi

print_logo() {
  cat <<'EOF'

██████╗ ██╗    ██╗███╗   ██╗██████╗  ██████╗ ██╗  ██╗
██╔══██╗██║    ██║████╗  ██║██╔══██╗██╔═████╗╚██╗██╔╝
██████╔╝██║ █╗ ██║██╔██╗ ██║██████╔╝██║██╔██║ ╚███╔╝
██╔═══╝ ██║███╗██║██║╚██╗██║██╔══██╗████╔╝██║ ██╔██╗
██║     ╚███╔███╔╝██║ ╚████║██████╔╝╚██████╔╝██╔╝ ██╗
╚═╝      ╚══╝╚══╝ ╚═╝  ╚═══╝╚═════╝  ╚═════╝ ╚═╝  ╚═╝

EOF
}

info() {
  printf "%b%s%b\n" "$C_CYAN" "$1" "$C_RESET"
}

warn() {
  printf "%b%s%b\n" "$C_YELLOW" "$1" "$C_RESET"
}

ok() {
  printf "%b%s%b\n" "$C_GREEN" "$1" "$C_RESET"
}

fail() {
  printf "%b%s%b\n" "$C_RED" "$1" "$C_RESET" >&2
}

print_progress() {
  local current="$1"
  local total="$2"
  local width=30
  local filled=0
  local empty=0
  local pct=0
  local left=""
  local right=""

  filled=$((current * width / total))
  empty=$((width - filled))
  pct=$((current * 100 / total))

  left="$(printf '%*s' "$filled" '' | tr ' ' '#')"
  right="$(printf '%*s' "$empty" '' | tr ' ' '-')"

  printf "  %b[%s%s]%b %3d%%\n" "$C_BLUE" "$left" "$right" "$C_RESET" "$pct"
}

show_log_tail() {
  local log_file="$1"

  if [ -s "$log_file" ]; then
    warn "Last command output:"
    tail -n 120 "$log_file" >&2
  fi
}

run_step() {
  local step_no="$1"
  local total="$2"
  local title="$3"
  shift 3

  local log_file
  log_file="$(mktemp -t pwnbox-setup)"

  printf "%b[%d/%d]%b %s\n" "$C_BOLD" "$step_no" "$total" "$C_RESET" "$title"

  if $DRY_RUN; then
    printf "  %b[dry-run]%b %q" "$C_DIM" "$C_RESET" "$1"
    shift

    while [ "$#" -gt 0 ]; do
      printf " %q" "$1"
      shift
    done

    printf "\n"
    print_progress "$step_no" "$total"
    rm -f "$log_file"
    return 0
  fi

  if [ -t 1 ]; then
    "$@" >"$log_file" 2>&1 &
    local pid=$!
    local spin='|/-\'
    local i=0

    while kill -0 "$pid" >/dev/null 2>&1; do
      printf "\r  %b%c%b working..." "$C_DIM" "${spin:$((i % 4)):1}" "$C_RESET"
      sleep 0.1
      i=$((i + 1))
    done

    printf "\r\033[K"

    if ! wait "$pid"; then
      fail "  failed: $title"
      show_log_tail "$log_file"
      rm -f "$log_file"
      exit 1
    fi
  else
    if ! "$@" >"$log_file" 2>&1; then
      fail "failed: $title"
      show_log_tail "$log_file"
      rm -f "$log_file"
      exit 1
    fi
  fi

  ok "  done"
  print_progress "$step_no" "$total"
  rm -f "$log_file"
}

preflight() {
  if [ "$(uname -s)" != "Darwin" ]; then
    echo "error: this installer targets macOS." >&2
    return 1
  fi

  if [ "$(uname -m)" != "arm64" ]; then
    warn "non-arm64 host detected, proceeding anyway"
  fi

  if ! command -v brew >/dev/null 2>&1; then
    echo "error: Homebrew is required." >&2
    echo "hint: install it from https://brew.sh" >&2
    return 1
  fi

  if ! command -v git >/dev/null 2>&1; then
    echo "error: git is required." >&2
    echo "hint: install Command Line Tools or run: brew install git" >&2
    return 1
  fi
}

install_dependencies() {
  local missing=()
  local pkg

  for pkg in docker docker-buildx colima; do
    if ! brew list --formula "$pkg" >/dev/null 2>&1; then
      missing+=("$pkg")
    fi
  done

  if [ "${#missing[@]}" -eq 0 ]; then
    echo "all dependencies are already installed"
    return 0
  fi

  brew install "${missing[@]}"
}

ensure_buildx_plugin() {
  local plugin_dir="${HOME}/.docker/cli-plugins"
  local plugin_path="${plugin_dir}/docker-buildx"
  local brew_prefix=""
  local buildx_bin=""
  local candidate=""

  if docker buildx version >/dev/null 2>&1; then
    echo "docker buildx is already available"
    docker buildx version
    return 0
  fi

  brew_prefix="$(brew --prefix)"

  for candidate in \
    "${brew_prefix}/bin/docker-buildx" \
    "${brew_prefix}/lib/docker/cli-plugins/docker-buildx" \
    "/opt/homebrew/bin/docker-buildx" \
    "/opt/homebrew/lib/docker/cli-plugins/docker-buildx" \
    "/usr/local/bin/docker-buildx" \
    "/usr/local/lib/docker/cli-plugins/docker-buildx"
  do
    if [ -x "$candidate" ]; then
      buildx_bin="$candidate"
      break
    fi
  done

  if [ -z "$buildx_bin" ]; then
    echo "error: docker-buildx binary was not found." >&2
    echo "hint: try: brew reinstall docker-buildx" >&2
    return 1
  fi

  mkdir -p "$plugin_dir"
  ln -sf "$buildx_bin" "$plugin_path"

  if ! docker buildx version >/dev/null 2>&1; then
    echo "error: docker buildx is still unavailable after plugin symlink." >&2
    echo "hint: plugin path: $plugin_path" >&2
    echo "hint: target path: $buildx_bin" >&2
    echo "hint: try: chmod +x '$buildx_bin'" >&2
    return 1
  fi

  echo "docker buildx plugin linked:"
  echo "  $plugin_path -> $buildx_bin"
  docker buildx version
}

start_colima() {
  if colima status -p "$PROFILE" >/dev/null 2>&1; then
    echo "colima profile '$PROFILE' is already running"
    return 0
  fi

  colima start \
    -p "$PROFILE" \
    -a x86_64 \
    -c 4 \
    -m 2 \
    -d 10 \
    --vm-type qemu \
    --activate=false
}

ensure_docker_context() {
  if docker context inspect "$DOCKER_CONTEXT" >/dev/null 2>&1; then
    echo "docker context '$DOCKER_CONTEXT' already exists"
    return 0
  fi

  docker context create "$DOCKER_CONTEXT" --docker "host=${DOCKER_HOST}"
}

check_docker_context() {
  if ! docker --context "$DOCKER_CONTEXT" info >/dev/null 2>&1; then
    echo "error: docker context '$DOCKER_CONTEXT' is not reachable." >&2
    echo "hint: expected Docker host: $DOCKER_HOST" >&2
    echo "hint: try: colima status -p '$PROFILE'" >&2
    echo "hint: try: colima start -p '$PROFILE' -a x86_64 --vm-type qemu --activate=false" >&2
    return 1
  fi

  echo "docker context '$DOCKER_CONTEXT' is reachable"
}

build_image() {
  if $SKIP_BUILD; then
    if docker --context "$DOCKER_CONTEXT" image inspect "$IMAGE" >/dev/null 2>&1; then
      echo "skipping build: reusing existing image '$IMAGE'"
      return 0
    fi
    echo "error: --skip-build requested but image '$IMAGE' not found in context '$DOCKER_CONTEXT'" >&2
    echo "hint: rerun without --skip-build to build it" >&2
    return 1
  fi

  docker --context "$DOCKER_CONTEXT" buildx build \
    --progress=plain \
    --load \
    -t "$IMAGE" \
    "$REPO_DIR"
}

ensure_config() {
  local cfg_dir="${XDG_CONFIG_HOME:-$HOME/.config}/pwnbox"
  local cfg="${cfg_dir}/config"

  mkdir -p "$cfg_dir"

  if [ -f "$cfg" ]; then
    echo "config already exists (left untouched): $cfg"
    return 0
  fi

  cat >"$cfg" <<'EOF'
# pwnbox config: KEY=VALUE per line, '#' starts a comment.
# Environment variables (PWNBOX_*) take precedence over this file.
# Keys: PROFILE, DOCKER_CONTEXT, AUTO_CONTEXT, DOCKER_HOST, IMAGE,
#       CONTAINER, DIR_FILE_LIMIT, PRIVILEGED, SECCOMP, STOP_COLIMA, NO_BANNER

#NO_BANNER=1
#STOP_COLIMA=ask
#DIR_FILE_LIMIT=5
EOF
  echo "created default config: $cfg"
}

install_launcher() {
  local src="$REPO_DIR/pwnbox"

  if install -m 0755 "$src" "$INSTALL_PATH" >/dev/null 2>&1; then
    return 0
  fi

  if command -v sudo >/dev/null 2>&1; then
    sudo install -m 0755 "$src" "$INSTALL_PATH"
    return 0
  fi

  echo "error: cannot write to '$INSTALL_PATH' and sudo is unavailable" >&2
  return 1
}

TOTAL_STEPS=9

printf "%b" "$C_BOLD"
print_logo
printf "%b\n" "$C_RESET"

info "pwnbox setup started"
printf "  repo: %s\n" "$REPO_DIR"
printf "  profile: %s\n" "$PROFILE"
printf "  context: %s\n" "$DOCKER_CONTEXT"
printf "  docker host: %s\n" "$DOCKER_HOST"
printf "  image: %s\n" "$IMAGE"
printf "  install path: %s\n" "$INSTALL_PATH"

if $DRY_RUN; then
  warn "dry-run mode enabled: commands will not be executed"
fi

printf "\n"

run_step 1 "$TOTAL_STEPS" "Preflight checks" preflight
run_step 2 "$TOTAL_STEPS" "Install dependencies with Homebrew" install_dependencies
run_step 3 "$TOTAL_STEPS" "Ensure Docker buildx plugin" ensure_buildx_plugin
run_step 4 "$TOTAL_STEPS" "Start Colima profile '$PROFILE'" start_colima
run_step 5 "$TOTAL_STEPS" "Ensure Docker context '$DOCKER_CONTEXT'" ensure_docker_context
run_step 6 "$TOTAL_STEPS" "Check Docker context '$DOCKER_CONTEXT'" check_docker_context
BUILD_TITLE="Build Docker image '$IMAGE'"
if $SKIP_BUILD; then
  BUILD_TITLE="Reuse existing Docker image '$IMAGE'"
fi
run_step 7 "$TOTAL_STEPS" "$BUILD_TITLE" build_image
run_step 8 "$TOTAL_STEPS" "Create default config" ensure_config
run_step 9 "$TOTAL_STEPS" "Install launcher to '$INSTALL_PATH'" install_launcher

printf "\n"
ok "Setup completed successfully."
printf "Run: %bpwnbox%b\n" "$C_BOLD" "$C_RESET"