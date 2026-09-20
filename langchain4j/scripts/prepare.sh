#!/usr/bin/env bash
#
# Quarkus Club - machine preparation for the Quarkus LangChain4j workshop
#
# Specific to this workshop: it installs a per-user JDK if you need one, fetches
# the material, warms this workshop's Maven dependencies and pulls the one
# container image it needs. Another workshop gets its own script.
#
#   curl -fsSL https://quarkusclub.github.io/workshops/langchain4j/scripts/prepare.sh | bash
#
# Prefer to read it first (recommended):
#
#   curl -fsSL https://quarkusclub.github.io/workshops/langchain4j/scripts/prepare.sh -o prepare.sh
#   less prepare.sh && bash prepare.sh
#
# Options:
#   --dir <path>        where to put the workshop material
#   --skip-build        do not run the Maven warm-up build
#   --skip-images       do not pull the pgvector container image
#   --no-persist-env    do not touch your shell rc file
#
# This script never installs system packages, never asks for sudo and never
# elevates. Everything it installs lives under your home directory. Whatever it
# cannot do without administrator rights is printed at the end, with the exact
# command or click path for you to run yourself.
#
# Licensed under the Apache License 2.0.

set -uo pipefail

# Everything below runs inside this brace group on purpose. Piped straight into
# bash, a dropped connection delivers a truncated script, and bash would happily
# run the half it received: install a JDK, skip the verification, print half a
# verdict. Bash must parse a compound command to its closing brace before it can
# execute any of it, so a truncated copy dies on a syntax error having done
# nothing at all. The matching `}` is the last line of the file.
{

WORKSHOP="langchain4j"   # fixed: this script belongs to this workshop
TARGET_DIR="${HOME}/quarkusclub-workshops"
REPO_URL="https://github.com/quarkusclub/workshops.git"
REPO_TARBALL="https://codeload.github.com/quarkusclub/workshops/tar.gz/refs/heads/main"
TARBALL_MARKER=".quarkusclub-tarball"
PGVECTOR_IMAGE="pgvector/pgvector:pg17"
MIN_JAVA=21
MIN_DISK_GB=5
QC_HOME="${HOME}/.quarkusclub"
JDK_DIR="${QC_HOME}/jdk-${MIN_JAVA}"
ADOPTIUM_API="https://api.adoptium.net/v3"
DO_BUILD=1
DO_IMAGES=1
DO_PERSIST=1

while [ $# -gt 0 ]; do
  case "$1" in
    --dir)      TARGET_DIR="${2:-}"; shift 2 ;;
    --skip-build)  DO_BUILD=0; shift ;;
    --skip-images) DO_IMAGES=0; shift ;;
    --no-persist-env) DO_PERSIST=0; shift ;;
    -h|--help)
      # Printed from here rather than read back out of $0: piped into bash, $0
      # is the interpreter, and the pipe is the documented way to run this.
      cat <<'USAGE'
Quarkus Club - machine preparation for the Quarkus LangChain4j workshop

  curl -fsSL https://quarkusclub.github.io/workshops/langchain4j/scripts/prepare.sh | bash

Prefer to read it first (recommended):

  curl -fsSL https://quarkusclub.github.io/workshops/langchain4j/scripts/prepare.sh -o prepare.sh
  less prepare.sh && bash prepare.sh

Options:
  --dir <path>        where to put the workshop material
  --skip-build        do not run the Maven warm-up build
  --skip-images       do not pull the pgvector container image
  --no-persist-env    do not touch your shell rc file
  -h, --help          show this text

Passing options through the pipe:

  curl -fsSL .../prepare.sh | bash -s -- --skip-images

This script never installs system packages, never asks for sudo and never
elevates. Everything it installs lives under your home directory. Whatever it
cannot do without administrator rights is printed at the end, with the exact
command or click path for you to run yourself.

See https://quarkusclub.github.io/workshops/langchain4j/
USAGE
      exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

# The tarball fallback replaces the target directory, so never accept a root.
REQUESTED_DIR="$TARGET_DIR"
TARGET_DIR="${TARGET_DIR%/}"
case "$TARGET_DIR" in
  ""|"/"|"$HOME")
    echo "Refusing to use '${REQUESTED_DIR}' as the target directory: it is too broad to replace safely." >&2
    exit 2 ;;
esac

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'
  BLUE=$'\033[34m'; DIM=$'\033[2m'; RESET=$'\033[0m'; CYAN=$'\033[36m'
else
  BOLD=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; DIM=""; RESET=""; CYAN=""
fi

# Counters are tracked separately: under 'set -u' the bash 3.2 that ships with
# macOS refuses to expand an empty array.
FAILURES=()
WARNINGS=()
MANUAL=()
FAIL_COUNT=0
WARN_COUNT=0
MANUAL_COUNT=0

ok()   { printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$1"; }
warn() { printf '  %s!%s %s\n' "$YELLOW" "$RESET" "$1"; WARNINGS+=("$1"); WARN_COUNT=$((WARN_COUNT + 1)); }
fail() { printf '  %s✗%s %s\n' "$RED" "$RESET" "$1"; FAILURES+=("$1"); FAIL_COUNT=$((FAIL_COUNT + 1)); }
step() { printf '\n%s%s%s\n' "$BOLD" "$1" "$RESET"; }
hint() { printf '    %s%s%s\n' "$DIM" "$1" "$RESET"; }
busy() { printf '  %s...%s %s\n' "$DIM" "$RESET" "$1"; }

# Everything that needs administrator rights, or that a failed repair leaves
# behind, is collected here and printed as the closing section.
manual() { MANUAL+=("$1"); MANUAL_COUNT=$((MANUAL_COUNT + 1)); }

if command -v curl >/dev/null 2>&1; then
  DL="curl"
elif command -v wget >/dev/null 2>&1; then
  DL="wget"
else
  DL=""
fi

http_get() {
  case "$DL" in
    curl) curl -fsSL --max-time 30 "$1" ;;
    wget) wget -qO- --timeout=30 "$1" ;;
    *) return 1 ;;
  esac
}

http_get_file() {
  case "$DL" in
    curl)
      if [ -t 2 ]; then
        curl -fL --progress-bar --retry 2 --max-time 1800 -o "$2" "$1"
      else
        curl -fsSL --retry 2 --max-time 1800 -o "$2" "$1"
      fi ;;
    wget) wget -q --tries=3 --timeout=60 -O "$2" "$1" ;;
    *) return 1 ;;
  esac
}

http_ok() {
  case "$DL" in
    curl) curl -fsS --max-time 15 -o /dev/null "$1" ;;
    wget) wget -q --spider --timeout=15 "$1" ;;
    *) return 1 ;;
  esac
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" 2>/dev/null | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$1" 2>/dev/null | awk '{print $NF}'
  else
    return 1
  fi
}

printf '%s\n' "$BLUE$BOLD"
cat <<'BANNER'
  ___                 _              ___ _      _
 / _ \ _  _ __ _ _ _ | |___  _ ___  / __| |_  _| |__
| (_) | || / _` | '_|| / / || (_-< | (__| | || | '_ \
 \__\_\\_,_\__,_|_|  |_\_\\_,_/__/  \___|_|\_,_|_.__/
BANNER
printf '%s' "$RESET"
printf ' Quarkus LangChain4j workshop  %s(%s)%s\n' "$DIM" "$WORKSHOP" "$RESET"

# ---------------------------------------------------------------- Java
step "1/8  Java"

UNAME_S="$(uname -s 2>/dev/null || echo unknown)"

# 0 usable, 1 absent, 2 unparseable, 3 too old.
detect_java() {
  JAVA_BIN=""; JAVA_VER=""; JAVA_RAW=""
  if [ -n "${JAVA_HOME:-}" ] && [ -x "${JAVA_HOME}/bin/java" ]; then
    JAVA_BIN="${JAVA_HOME}/bin/java"
  elif command -v java >/dev/null 2>&1; then
    JAVA_BIN="$(command -v java)"
  fi
  [ -n "$JAVA_BIN" ] || return 1
  JAVA_RAW="$("$JAVA_BIN" -version 2>&1 | head -1)"
  JAVA_VER="$(printf '%s' "$JAVA_RAW" | sed -n 's/.*version "\([0-9][0-9]*\).*/\1/p')"
  [ -n "$JAVA_VER" ] || return 2
  [ "$JAVA_VER" -ge "$MIN_JAVA" ] || return 3
  return 0
}

java_home_of() {
  "$1" -XshowSettings:properties -version 2>&1 \
    | sed -n 's/^[[:space:]]*java\.home = //p' | head -1
}

adoptium_os() {
  case "$UNAME_S" in
    Darwin) printf 'mac' ;;
    Linux)  printf 'linux' ;;
    *) return 1 ;;
  esac
}

# A terminal running under Rosetta 2 reports x86_64 on an Apple Silicon Mac, so
# uname alone would hand an M-series attendee an Intel JDK: it runs, but every
# Quarkus build in the workshop pays the translation tax. proc_translated is the
# only reliable tell, and it exists solely on macOS.
adoptium_arch() {
  if [ "$(sysctl -n sysctl.proc_translated 2>/dev/null)" = "1" ]; then
    printf 'aarch64'
    return 0
  fi
  case "$(uname -m 2>/dev/null)" in
    x86_64|amd64)  printf 'x64' ;;
    aarch64|arm64) printf 'aarch64' ;;
    *) return 1 ;;
  esac
}

# The assets endpoint lists the installer before the archive, so pair every
# checksum with the name that follows it and keep the one for the .tar.gz.
adoptium_checksum() {
  http_get "${ADOPTIUM_API}/assets/latest/${MIN_JAVA}/hotspot?os=${1}&architecture=${2}&image_type=jdk" \
    | grep -oE '"(checksum|name)"[[:space:]]*:[[:space:]]*"[^"]+"' \
    | awk -F'"' '
        $2 == "checksum" { sum = $4 }
        $2 == "name" && $4 ~ /\.tar\.gz$/ && sum != "" { print sum; exit }
      '
}

managed_jdk_ok() {
  [ -x "${JDK_DIR}/bin/java" ] || return 1
  local v
  v="$("${JDK_DIR}/bin/java" -version 2>&1 | head -1 | sed -n 's/.*version "\([0-9][0-9]*\).*/\1/p')"
  [ -n "$v" ] && [ "$v" -ge "$MIN_JAVA" ]
}

JDK_MANUAL_NOTE="Install a JDK ${MIN_JAVA} yourself (no administrator needed)
Download the archive for your machine from https://adoptium.net/temurin/releases/?version=${MIN_JAVA}
Pick: JDK, hotspot, .tar.gz. Then, from the folder you downloaded it to:
> mkdir -p ${QC_HOME} && tar -xzf OpenJDK21U-jdk_*.tar.gz -C ${QC_HOME}
> mv ${QC_HOME}/jdk-21* ${JDK_DIR}
> export JAVA_HOME=${JDK_DIR} && export PATH=\$JAVA_HOME/bin:\$PATH
Why we could not do it for you: the download or the checksum check did not succeed on this machine."

install_temurin() {
  local os arch url expected actual tmp top src
  os="$(adoptium_os)" || { warn "Unsupported operating system for the automatic JDK install: ${UNAME_S}"; return 1; }
  arch="$(adoptium_arch)" || { warn "Unsupported CPU architecture for the automatic JDK install: $(uname -m)"; return 1; }
  [ -n "$DL" ] || { warn "Neither curl nor wget is available, cannot download the JDK."; return 1; }

  if ! command -v tar >/dev/null 2>&1; then
    warn "tar is not available, cannot unpack the JDK."
    return 1
  fi

  expected="$(adoptium_checksum "$os" "$arch")"
  if [ -z "$expected" ]; then
    warn "Could not read the expected SHA-256 from the Adoptium API. Not installing an unverified JDK."
    return 1
  fi

  tmp="$(mktemp -d "${TMPDIR:-/tmp}/quarkusclub.XXXXXX" 2>/dev/null)" || return 1
  url="${ADOPTIUM_API}/binary/latest/${MIN_JAVA}/ga/${os}/${arch}/jdk/hotspot/normal/eclipse"

  busy "downloading Eclipse Temurin ${MIN_JAVA} for ${os}/${arch} (around 200MB)"
  if ! http_get_file "$url" "${tmp}/jdk.tar.gz"; then
    warn "The JDK download failed. Check your connection or proxy."
    rm -rf "$tmp"; return 1
  fi

  actual="$(sha256_of "${tmp}/jdk.tar.gz")"
  if [ -z "$actual" ]; then
    warn "No SHA-256 tool found (sha256sum, shasum or openssl). Not installing an unverified JDK."
    rm -rf "$tmp"; return 1
  fi
  if [ "$actual" != "$expected" ]; then
    fail "The downloaded JDK does not match the SHA-256 published by Adoptium. Discarded."
    hint "expected ${expected}"
    hint "got      ${actual}"
    rm -rf "$tmp"; return 1
  fi
  ok "SHA-256 verified against the Adoptium API"

  if ! tar -xzf "${tmp}/jdk.tar.gz" -C "$tmp"; then
    warn "Could not unpack the JDK archive."
    rm -rf "$tmp"; return 1
  fi

  top="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d -name 'jdk*' | head -1)"
  if [ -z "$top" ]; then
    warn "The JDK archive did not contain the expected layout."
    rm -rf "$tmp"; return 1
  fi
  # macOS builds nest the real JAVA_HOME inside the bundle.
  if [ -x "${top}/Contents/Home/bin/java" ]; then
    src="${top}/Contents/Home"
  elif [ -x "${top}/bin/java" ]; then
    src="$top"
  else
    warn "The JDK archive did not contain bin/java."
    rm -rf "$tmp"; return 1
  fi

  mkdir -p "$QC_HOME" && rm -rf "$JDK_DIR" && mv "$src" "$JDK_DIR"
  local moved=$?
  rm -rf "$tmp"
  if [ $moved -ne 0 ] || ! managed_jdk_ok; then
    warn "The JDK was downloaded but could not be installed into ${JDK_DIR}."
    return 1
  fi
  return 0
}

java_shortfall() {
  case $JAVA_STATE in
    1) printf 'no Java on PATH' ;;
    2) printf "could not read a version from '%s'" "$JAVA_RAW" ;;
    3) printf 'Java %s is older than %s' "$JAVA_VER" "$MIN_JAVA" ;;
  esac
}

# Drops our block and any blank lines it left behind, so a re-run replaces the
# block instead of stacking a new one under the old.
remove_rc_block() {
  local rc_file="$1" tmp="$1.quarkusclub.tmp"
  awk '/^# >>> quarkusclub$/ { skip = 1 }
       !skip { keep[++n] = $0 }
       /^# <<< quarkusclub$/ { skip = 0 }
       END { while (n > 0 && keep[n] ~ /^[[:space:]]*$/) n--
             for (i = 1; i <= n; i++) print keep[i] }' "$rc_file" > "$tmp" 2>/dev/null \
    || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$rc_file" 2>/dev/null || { rm -f "$tmp"; return 1; }
}

# 0 written, 1 could not write, 2 shell not recognised.
persist_env() {
  local rc_file=""
  case "$(basename "${SHELL:-}")" in
    zsh)  rc_file="${HOME}/.zshrc" ;;
    bash) if [ "$UNAME_S" = "Darwin" ]; then rc_file="${HOME}/.bash_profile"; else rc_file="${HOME}/.bashrc"; fi ;;
    *) return 2 ;;
  esac

  if [ -f "$rc_file" ] && grep -q '^# >>> quarkusclub$' "$rc_file"; then
    remove_rc_block "$rc_file" || return 1
  fi
  touch "$rc_file" 2>/dev/null || return 1
  {
    printf '\n# >>> quarkusclub\n'
    printf '# Added by the Quarkus Club workshop preparation script. Safe to delete.\n'
    printf 'export JAVA_HOME="%s"\n' "$RESOLVED_JAVA_HOME"
    printf 'export PATH="$JAVA_HOME/bin:$PATH"\n'
    printf '# <<< quarkusclub\n'
  } >> "$rc_file" 2>/dev/null || return 1
  PERSISTED_RC="$rc_file"
  return 0
}

write_env_file() {
  local dir="$1"
  cat > "${dir}/env.sh" <<EOF
# Generated by the Quarkus Club workshop preparation script.
# Gives this terminal the JDK the workshop expects:
#
#   source ${dir}/env.sh
#
export JAVA_HOME="${RESOLVED_JAVA_HOME}"
export PATH="\$JAVA_HOME/bin:\$PATH"
EOF
}

RESOLVED_JAVA_HOME=""
PERSISTED_RC=""
JDK_MANAGED=0

detect_java
JAVA_STATE=$?
if [ $JAVA_STATE -eq 0 ]; then
  ok "Java ${JAVA_VER} at ${JAVA_BIN}"
else
  if managed_jdk_ok; then
    ok "$(java_shortfall), reusing the JDK a previous run installed at ${JDK_DIR}"
    JDK_INSTALLED=0
  else
    busy "$(java_shortfall), installing Eclipse Temurin ${MIN_JAVA} under your home directory"
    install_temurin
    JDK_INSTALLED=$?
  fi
  if [ $JDK_INSTALLED -eq 0 ]; then
    JDK_MANAGED=1
    export JAVA_HOME="$JDK_DIR"
    export PATH="${JDK_DIR}/bin:${PATH}"
    if detect_java; then
      ok "Java ${JAVA_VER} at ${JAVA_BIN}"
    else
      fail "The JDK at ${JDK_DIR} is not usable."
      manual "$JDK_MANUAL_NOTE"
    fi
  else
    fail "Java ${MIN_JAVA} is missing and the automatic install did not succeed."
    manual "$JDK_MANUAL_NOTE"
  fi
fi

if [ -n "${JAVA_BIN:-}" ] && [ -n "${JAVA_VER:-}" ] && [ "$JAVA_VER" -ge "$MIN_JAVA" ]; then
  if [ "$JDK_MANAGED" -eq 1 ]; then
    RESOLVED_JAVA_HOME="$JDK_DIR"
  else
    RESOLVED_JAVA_HOME="$(java_home_of "$JAVA_BIN")"
    [ -n "$RESOLVED_JAVA_HOME" ] || RESOLVED_JAVA_HOME="${JAVA_HOME:-}"
  fi
fi

PERSIST_MANUAL_NOTE="Point your shell at the JDK yourself (no administrator needed)
Add the equivalent of these two lines to your shell startup file:
> export JAVA_HOME=${RESOLVED_JAVA_HOME}
> export PATH=\$JAVA_HOME/bin:\$PATH
fish uses different syntax:
> set -Ux JAVA_HOME ${RESOLVED_JAVA_HOME}
> fish_add_path ${RESOLVED_JAVA_HOME}/bin
Why we could not do it for you: we will not guess at the syntax of a shell we
do not recognise, or write to a file we cannot write to."

if [ "$JDK_MANAGED" -eq 1 ] && [ -n "$RESOLVED_JAVA_HOME" ]; then
  if [ "$DO_PERSIST" -eq 0 ]; then
    hint "Shell rc left untouched (--no-persist-env)"
  else
    persist_env
    case $? in
      0) ok "JAVA_HOME persisted in ${PERSISTED_RC} (block marked '# >>> quarkusclub')" ;;
      2) warn "Shell '$(basename "${SHELL:-unknown}")' not recognised, JAVA_HOME was not persisted."
         manual "$PERSIST_MANUAL_NOTE" ;;
      *) warn "Could not write to your shell startup file. JAVA_HOME was not persisted."
         manual "$PERSIST_MANUAL_NOTE" ;;
    esac
  fi
elif [ -n "$RESOLVED_JAVA_HOME" ]; then
  hint "Your own JDK is already on PATH, so nothing was added to your shell startup file"
fi

# ---------------------------------------------------- Container runtime
# The end question comes first: can anything here run a container? Only when
# the answer is no do we walk the chain backwards to name the broken link.
step "2/8  Container runtime"
RUNTIME=""
for candidate in docker podman; do
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" info >/dev/null 2>&1; then
    RUNTIME="$candidate"
    ok "${candidate} is installed and running"
    break
  fi
done

DOCKER_INSTALL_NOTE_MAC="Docker Desktop for macOS  (needs administrator)
Download: https://www.docker.com/products/docker-desktop/
Open the .dmg, drag Docker into Applications, launch it once and wait until the
whale icon in the menu bar stops animating.
Why we cannot do it for you: the installer asks for your administrator password.
Needed from step 06 on, where Quarkus starts a pgvector container for you.
Steps 01 to 05 run fine without it."

DOCKER_INSTALL_NOTE_LINUX="Docker Engine or Podman  (needs administrator)
Docker Engine: follow https://docs.docker.com/engine/install/ for your distribution.
Podman:        follow https://podman.io/docs/installation
After installing Docker, let your user talk to it without sudo:
> sudo usermod -aG docker $(id -un 2>/dev/null || echo \$USER)
then log out and back in (a new terminal is not enough).
Why we cannot do it for you: installing packages and changing groups needs root.
Needed from step 06 on, where Quarkus starts a pgvector container for you.
Steps 01 to 05 run fine without it."

diagnose_runtime() {
  local have_docker=0 have_podman=0 daemon_state="unknown"
  command -v docker >/dev/null 2>&1 && have_docker=1
  command -v podman >/dev/null 2>&1 && have_podman=1

  if [ $have_docker -eq 0 ] && [ $have_podman -eq 0 ]; then
    fail "No container runtime installed. Steps 06 to 10 need Docker or Podman."
    hint "Steps 01 to 05 do not need one, so this is not fatal for the first half."
    if [ "$UNAME_S" = "Darwin" ]; then
      manual "$DOCKER_INSTALL_NOTE_MAC"
    else
      manual "$DOCKER_INSTALL_NOTE_LINUX"
    fi
    return
  fi

  if [ $have_docker -eq 1 ]; then
    if [ "$UNAME_S" = "Darwin" ]; then
      fail "Docker is installed but not running."
      manual "Start Docker Desktop
> open -a Docker
Wait until the whale icon in the menu bar stops animating, then run this script again.
Why we cannot do it for you: the script will not launch and babysit a desktop app for you."
      return
    fi

    if command -v systemctl >/dev/null 2>&1; then
      if systemctl is-active --quiet docker 2>/dev/null; then daemon_state="active"; else daemon_state="inactive"; fi
    fi

    if [ "$daemon_state" = "inactive" ] || { [ "$daemon_state" = "unknown" ] && [ ! -S /var/run/docker.sock ]; }; then
      fail "Docker is installed but the daemon is not running."
      manual "Start the Docker daemon  (needs administrator)
> sudo systemctl start docker
> sudo systemctl enable docker   # so it comes back after a reboot
Why we cannot do it for you: starting a system service needs root."
      return
    fi

    if ! id -nG 2>/dev/null | tr ' ' '\n' | grep -qx docker && [ ! -w /var/run/docker.sock ]; then
      fail "The Docker daemon is running but your user is not allowed to talk to it."
      manual "Add your user to the docker group  (needs administrator)
  sudo usermod -aG docker $(id -un 2>/dev/null || echo \$USER)
Then log out and back in. A new terminal is not enough, the group is applied at login.
Why we cannot do it for you: changing group membership needs root."
      return
    fi

    fail "Docker is installed and the daemon looks up, but 'docker info' failed."
    hint "Run 'docker info' by hand: the error it prints is the missing link."
    manual "Make 'docker info' work
Run it by hand and read the error:
> docker info
A common cause is a DOCKER_HOST or DOCKER_CONTEXT pointing at something that is gone:
> docker context ls
Why we cannot do it for you: the fix depends on the error, and it may need root."
    return
  fi

  # Podman only.
  if [ "$UNAME_S" = "Darwin" ]; then
    fail "Podman is installed but its virtual machine is not running."
    manual "Start the Podman machine  (no administrator needed)
> podman machine init   # only the first time
> podman machine start
Then run this script again."
  else
    fail "Podman is installed but 'podman info' failed."
    hint "Run 'podman info' by hand: the error it prints is the missing link."
    manual "Make 'podman info' work
Run it by hand and read the error:
> podman info
Why we cannot do it for you: the fix depends on the error, and it may need root."
  fi
}

[ -n "$RUNTIME" ] || diagnose_runtime

# ------------------------------------------------------------- Git
# Not required any more: the material can also arrive as a tarball. Git is
# still preferred, because it is what makes a later 'git pull' work.
step "3/8  Git"
HAVE_GIT=0
if command -v git >/dev/null 2>&1; then
  HAVE_GIT=1
  ok "git $(git --version | awk '{print $3}')"
else
  warn "git not found. The material will be downloaded as a tarball instead."
  manual "git  (optional, nice to have)
macOS, no administrator needed:
> xcode-select --install
Linux: install 'git' with your distribution's package manager (needs administrator).
Without git the material still arrives as a tarball, but you cannot 'git pull'
the updates we may publish before the workshop.
Why we cannot do it for you: installing a package needs root."
fi

# ------------------------------------------------------------- Disk
step "4/8  Disk space"
AVAIL_GB="$(df -Pk "$HOME" 2>/dev/null | awk 'NR==2 {printf "%d", $4/1024/1024}')"
if [ -z "$AVAIL_GB" ]; then
  warn "Could not determine free disk space"
elif [ "$AVAIL_GB" -lt "$MIN_DISK_GB" ]; then
  warn "Only ${AVAIL_GB}GB free in ${HOME}. Around ${MIN_DISK_GB}GB is recommended."
else
  ok "${AVAIL_GB}GB free in ${HOME}"
fi

# ---------------------------------------------------------- Network
step "5/8  Network"
probe() {
  if http_ok "$1"; then
    ok "$2 reachable"
  else
    warn "$2 unreachable ($1). Check proxy or firewall."
  fi
}
probe "https://repo1.maven.org/maven2/" "Maven Central"
probe "https://integrate.api.nvidia.com/v1/models" "NVIDIA NIM API"
probe "https://github.com" "GitHub"

# ------------------------------------------------- Workshop material
step "6/8  Workshop material"
WORKSHOP_DIR="${TARGET_DIR}/${WORKSHOP}"

MATERIAL_MANUAL_NOTE="Put the workshop material in place by hand
Open https://github.com/quarkusclub/workshops in a browser, use the green
'Code' button and 'Download ZIP', then unpack it so that this path exists:
> ${WORKSHOP_DIR}/mvnw
Why we could not do it for you: the download did not succeed, or ${TARGET_DIR}
already holds something we did not put there and we will not overwrite it."

fetch_tarball() {
  local tmp top
  [ -n "$DL" ] || { warn "Neither curl nor wget is available, cannot download the material."; return 1; }
  command -v tar >/dev/null 2>&1 || { warn "tar is not available, cannot unpack the material."; return 1; }

  tmp="$(mktemp -d "${TMPDIR:-/tmp}/quarkusclub.XXXXXX" 2>/dev/null)" || return 1
  busy "downloading the material as a tarball"
  if ! http_get_file "$REPO_TARBALL" "${tmp}/material.tar.gz"; then
    warn "Could not download ${REPO_TARBALL}"
    rm -rf "$tmp"; return 1
  fi
  if ! tar -xzf "${tmp}/material.tar.gz" -C "$tmp"; then
    warn "Could not unpack the material tarball."
    rm -rf "$tmp"; return 1
  fi
  top="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -1)"
  if [ -z "$top" ]; then
    warn "The material tarball did not contain the expected layout."
    rm -rf "$tmp"; return 1
  fi

  rm -rf "$TARGET_DIR"
  mkdir -p "$(dirname "$TARGET_DIR")"
  if ! mv "$top" "$TARGET_DIR"; then
    warn "Could not move the material into ${TARGET_DIR}"
    rm -rf "$tmp"; return 1
  fi
  rm -rf "$tmp"
  : > "${TARGET_DIR}/${TARBALL_MARKER}"
  [ -f "${WORKSHOP_DIR}/mvnw" ] && chmod +x "${WORKSHOP_DIR}/mvnw" 2>/dev/null
  return 0
}

if [ "$HAVE_GIT" -eq 1 ] && [ -d "${TARGET_DIR}/.git" ]; then
  if git -C "$TARGET_DIR" pull --ff-only >/dev/null 2>&1; then
    ok "Updated ${TARGET_DIR}"
  else
    warn "${TARGET_DIR} exists but could not fast-forward. Leaving it untouched."
  fi
elif [ -f "${TARGET_DIR}/${TARBALL_MARKER}" ] && [ -x "${WORKSHOP_DIR}/mvnw" ]; then
  # Ours, complete, and possibly holding work in progress: refreshing it would
  # overwrite whatever the attendee changed.
  ok "Material already in ${TARGET_DIR} (downloaded by an earlier run)"
  hint "Delete that folder and run this script again for a fresh copy"
elif [ -e "$TARGET_DIR" ] && [ ! -f "${TARGET_DIR}/${TARBALL_MARKER}" ]; then
  warn "${TARGET_DIR} exists and was not created by this script. Leaving it untouched."
elif [ "$HAVE_GIT" -eq 1 ] && [ ! -e "$TARGET_DIR" ] \
     && git clone --depth 1 "$REPO_URL" "$TARGET_DIR" >/dev/null 2>&1; then
  ok "Cloned into ${TARGET_DIR}"
elif fetch_tarball; then
  ok "Downloaded into ${TARGET_DIR} (tarball)"
  [ "$HAVE_GIT" -eq 1 ] || hint "Install git later to pick up updates with 'git pull'"
else
  fail "Could not fetch the workshop material."
fi

# A clone can succeed and still be empty (unpublished repo), so verify the payload.
MATERIAL_OK=0
if [ -x "${WORKSHOP_DIR}/mvnw" ] && [ -d "${WORKSHOP_DIR}/section-1" ]; then
  MATERIAL_OK=1
else
  fail "No workshop material found at ${WORKSHOP_DIR}"
  manual "$MATERIAL_MANUAL_NOTE"
fi

if [ -n "$RESOLVED_JAVA_HOME" ]; then
  ENV_DIR="$QC_HOME"
  [ "$MATERIAL_OK" -eq 1 ] && ENV_DIR="$TARGET_DIR"
  if mkdir -p "$ENV_DIR" 2>/dev/null && write_env_file "$ENV_DIR"; then
    ok "Wrote ${ENV_DIR}/env.sh"
    hint "source ${ENV_DIR}/env.sh gives any terminal the right JAVA_HOME"
  else
    warn "Could not write env.sh"
  fi
fi

# --------------------------------------------------- Warm the caches
step "7/8  Warming caches"
if [ "$DO_IMAGES" -eq 1 ] && [ -n "$RUNTIME" ]; then
  busy "pulling ${PGVECTOR_IMAGE} (this is the big one)"
  if "$RUNTIME" pull "$PGVECTOR_IMAGE" >/dev/null 2>&1; then
    ok "Image ${PGVECTOR_IMAGE} is local"
  else
    warn "Could not pull ${PGVECTOR_IMAGE}. Retry on a better connection."
  fi
else
  hint "Image pull skipped"
fi

if [ "$DO_BUILD" -eq 1 ] && [ -d "$WORKSHOP_DIR" ] && [ -x "${WORKSHOP_DIR}/mvnw" ]; then
  busy "downloading Quarkus dependencies, several minutes on first run"
  if (cd "$WORKSHOP_DIR" && ./mvnw -B -q clean verify) >/dev/null 2>&1; then
    ok "Maven cache warm, all step projects compile"
  else
    warn "The warm-up build did not finish cleanly. Run it by hand to see why:"
    hint "cd ${WORKSHOP_DIR} && ./mvnw clean verify"
    manual "Finish the dependency warm-up yourself (no administrator needed)
> cd ${WORKSHOP_DIR}
> ./mvnw clean verify
Getting this to pass before the workshop means the room's wifi only has to carry
the model calls, not a few hundred megabytes of Quarkus dependencies.
Why we could not do it for you: the build failed here and the error needs a human."
  fi
else
  hint "Build skipped"
fi


# ---------------------------------------------------------- Health check
# Independently verifies the END STATE. The checks above describe what the
# script found and did; this one answers a single question: is this machine
# ready to run the workshop right now?
step "8/8  Health check"

HEALTH_PASS=0
HEALTH_FAIL=0

health() {
  local label="$1" detail="$2"; shift 2
  if "$@" >/dev/null 2>&1; then
    printf '  %s✓%s %-34s %s%s%s\n' "$GREEN" "$RESET" "$label" "$DIM" "$detail" "$RESET"
    HEALTH_PASS=$((HEALTH_PASS + 1))
  else
    printf '  %s✗%s %-34s %s%s%s\n' "$RED" "$RESET" "$label" "$DIM" "$detail" "$RESET"
    HEALTH_FAIL=$((HEALTH_FAIL + 1))
  fi
}

working_runtime() {
  local c
  for c in docker podman; do
    if command -v "$c" >/dev/null 2>&1 && "$c" info >/dev/null 2>&1; then
      printf '%s' "$c"; return 0
    fi
  done
  return 1
}

check_java() {
  local exe="" v
  if [ -n "${JAVA_HOME:-}" ] && [ -x "${JAVA_HOME}/bin/java" ]; then
    exe="${JAVA_HOME}/bin/java"
  elif command -v java >/dev/null 2>&1; then
    exe="$(command -v java)"
  fi
  [ -n "$exe" ] || return 1
  v="$("$exe" -version 2>&1 | head -1 | sed -n 's/.*version "\([0-9][0-9]*\).*/\1/p')"
  [ -n "$v" ] && [ "$v" -ge "$MIN_JAVA" ]
}
check_runtime()   { working_runtime; }
check_image()     { local r; r="$(working_runtime)" && "$r" image inspect "$PGVECTOR_IMAGE"; }
check_material()  { [ -x "${WORKSHOP_DIR}/mvnw" ] && [ -d "${WORKSHOP_DIR}/section-1/step-01" ]; }
check_mvncache()  { [ -d "${HOME}/.m2/repository/io/quarkus" ]; }
check_nvidia()    { http_ok https://integrate.api.nvidia.com/v1/models; }

health "JDK ${MIN_JAVA} or newer"        "required to build every step" check_java
health "Container runtime running"       "pgvector Dev Service, step 06+" check_runtime
health "Image ${PGVECTOR_IMAGE}"         "pulled locally" check_image
health "Workshop material on disk"       "${WORKSHOP_DIR}" check_material
health "Quarkus dependencies cached"     "~/.m2/repository/io/quarkus" check_mvncache
health "NVIDIA API reachable"            "integrate.api.nvidia.com" check_nvidia

# The key is created live during step 00, so its absence is expected beforehand.
if [ -n "${NVIDIA_API_KEY:-}" ]; then
  printf '  %s✓%s %-34s %s%s%s\n' "$GREEN" "$RESET" "NVIDIA_API_KEY is set" "$DIM" "already exported" "$RESET"
else
  printf '  %s·%s %-34s %s%s%s\n' "$BLUE" "$RESET" "NVIDIA_API_KEY not set yet" "$DIM" "expected: you create it in step 00" "$RESET"
fi

# -------------------------------------------------------------- Verdict
printf '\n%s%s%s\n' "$BOLD" "────────────────────────────────────────────────────────" "$RESET"
if [ "$HEALTH_FAIL" -eq 0 ]; then
  printf '%s%s  READY%s  %d/%d health checks passed. This machine can run the workshop.\n' \
    "$BOLD" "$GREEN" "$RESET" "$HEALTH_PASS" "$((HEALTH_PASS + HEALTH_FAIL))"
else
  printf '%s%s  NOT READY%s  %d of %d health checks failed.\n' \
    "$BOLD" "$RED" "$RESET" "$HEALTH_FAIL" "$((HEALTH_PASS + HEALTH_FAIL))"
  printf '  Fix the items marked %s✗%s above and run this script again.\n' "$RED" "$RESET"
fi

# ------------------------------------------------ What is left for you
printf '\n%s%s%s\n' "$BOLD" "────────────────────────────────────────────────────────" "$RESET"
printf '%s  WHAT YOU STILL HAVE TO DO YOURSELF%s\n\n' "$BOLD" "$RESET"
if [ "$MANUAL_COUNT" -eq 0 ]; then
  printf '  %sNothing.%s This script installed or verified everything the workshop needs.\n' "$GREEN" "$RESET"
else
  printf '  %sThis script never asks for administrator rights, so these are yours:%s\n\n' "$DIM" "$RESET"
  MANUAL_INDEX=1
  for entry in "${MANUAL[@]}"; do
    FIRST_LINE=1
    while IFS= read -r line; do
      if [ "$FIRST_LINE" -eq 1 ]; then
        printf '  %s%d) %s%s\n' "$BOLD" "$MANUAL_INDEX" "$line" "$RESET"
        FIRST_LINE=0
      elif [ "${line#> }" != "$line" ]; then
        printf '       %s%s%s%s\n' "$BOLD" "$CYAN" "${line#> }" "$RESET"
      else
        printf '     %s\n' "$line"
      fi
    done <<< "$entry"
    MANUAL_INDEX=$((MANUAL_INDEX + 1))
    printf '\n'
  done
fi

if [ "$WARN_COUNT" -gt 0 ]; then
  printf '  %sWarnings (not blocking):%s\n' "$YELLOW" "$RESET"
  for w in "${WARNINGS[@]}"; do printf '    %s!%s %s\n' "$YELLOW" "$RESET" "$w"; done
fi

printf '\n  %sNext:%s create your free NVIDIA API key during the workshop (step 00).\n' "$BOLD" "$RESET"
printf '  %sGuide:%s https://quarkusclub.github.io/workshops/langchain4j/\n\n' "$BOLD" "$RESET"

[ "$HEALTH_FAIL" -eq 0 ] || exit 1
exit 0

}
