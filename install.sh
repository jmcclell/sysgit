#!/bin/bash
#
# Installs sysgit
#
# Requirements:
# - instance of Bash executable at /bin/bash
# - instance of git in $PATH (discoverable with `command -v`)
#
# Tested on macOS (Monterey) and Linux (Debian-based)

#                       #
# --- Setup Options --- #
#                       #

set -e # Fail on any non-zero exit status
set -u # Fail for referencing non-declared vars
set -o pipefail # Don't silently swallow errors in pipelines

#                              #
# --- Setup Error Handling --- #
#                              #

# Aborts with error message and exits with status 1
abort() {
  printf "%s\n" "$@" >&2
  exit 1
}

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

usage() {
  cat << EOF # remove the space between << and EOF, this is due to web plugin issue
Usage: $(basename "${BASH_SOURCE[0]}") [-h] [--non-interactive] [--config-repo url] [--config-repo-branch branch] [--home path] [--workspace path] [--executable-path path] [ -- all bootstrap args]

SysGit installation script.

Available options:

-h, --help            Print this help and exit
-v, --verbose         Enable verbose output
--interactive         Enable interactive mode
--config-repo         The URL to the git repository used as the canonical storage for your system configuration files
--config-repo-branch  The name of the configrepo git branch to clone [Default: master]
--home                Where to clone the configuration repo [Default: $HOME/.sysgit]
--workspace           The path to the location you wish sysgit to manage [Default: $HOME]
--executable-path     The path to install the sysgit executable script [Default: /usr/local/bin]

Argument parsing stops when `--` is encountered as a lone argument. All arguments past that point are collected and passed to the bootstrap script during installation.

EOF
  exit
}

parse_params() {
  while :; do
    case "${1-}" in
    -h | --help) usage ;;
    -v | --verbose) set -x ;;
    --non-interactive) export NONINTERACTIVE=1 ;;
    --config-repo)
      SYSGIT_CONFIG_REPO="${2-}"
      shift
      ;;
    --config-repo-branch)
      SYSGIT_CONFIG_REPO_BRANCH="${2-}"
      shift
      ;;
    --home)
      SYSGIT_HOME="${2-}"
      shift
      ;;
    --workspace)
      SYSGIT_WORKSPACE="${2-}"
      shift
      ;;
    --executable-path)
      SYSGIT_EXECUTABLE_PATH="${2-}"
      shift
      ;;
    --) shift; break 2 ;; # Stop arg parsing after --
    -?*) die "Unknown option: $1" ;;
    *) break ;;
    esac
    shift
  done

  if [[ -n "$@" ]]; then
    SYSGIT_BOOTSTRAP_ARGS=("$@")
  fi

  return 0
}

parse_params "$@"

#                            #
# --- Initial Pre-Checks --- #
#                            #

# Fail fast with a concise message when not using bash
# Single brackets are needed here for POSIX compatibility
if [ -z "${BASH_VERSION:-}" ]
then
  abort "Bash is required to interpret this script."
fi

# Check if script is run in POSIX mode
if [ -n "${POSIXLY_CORRECT+1}" ]
then
  abort 'Bash must not run in POSIX mode. Please unset POSIXLY_CORRECT and try again.'
fi

# Check OS compatibility
OS="$(uname)"
if [[ "${OS}" == "Linux" ]]; then
  IS_LINUX=1
elif [[ "${OS}" != "Darwin" ]]; then
  abort "sysgit is only supported on macOS and Linux."
fi

# Check if git is installed
if ! command -v git >/dev/null 2>&1; then
    abort "git is required to install sysgit!"
fi

# Check if both `INTERACTIVE` and `NONINTERACTIVE` are set
if [[ -n "${INTERACTIVE-}" && -n "${NONINTERACTIVE-}" ]]
then
  abort 'Both `$INTERACTIVE` and `$NONINTERACTIVE` are set. Please unset at least one variable and try again.'
fi

#                                  #
# --- Define String Formatters --- #
#                                  #

if [[ -t 1 ]]
then
  tty_escape() { printf "\033[%sm" "$1"; }
else
  tty_escape() { :; }
fi

tty_mkbold() { tty_escape "1;$1"; }
tty_underline="$(tty_escape "4;39")"
tty_blue="$(tty_mkbold 34)"
tty_red="$(tty_mkbold 31)"
tty_green="$(tty_mkbold 32)"
tty_yellow="$(tty_mkbold 33)"
tty_bold="$(tty_mkbold 39)"
tty_reset="$(tty_escape 0)"

shell_join() {
  local arg
  printf "%s" "$1"
  shift
  for arg in "$@"
  do
    printf " "
    printf "%s" "${arg// /\ }"
  done
}

chomp() {
  printf "%s" "${1/"$'\n'"/}"
}

info() {
  printf "${tty_blue}>>${tty_bold} %s${tty_reset}\n" "$(shell_join "$@")"
}

warn() {
  printf "${tty_yellow}Warning${tty_reset}: %s\n" "$(chomp "$1")"
}

err() {
  printf "${tty_red}Error${tty_reset}: %s\n" "$(chomp "$1")"
}

#                                               #
# --- Define Additional Non-Critical Checks --- #
#                                               #

# Check if script is run non-interactively (e.g. CI)
# If it is run non-interactively we should not prompt for passwords.
# Always use single-quoted strings with `exp` expressions
# shellcheck disable=SC2016
if [[ -z "${NONINTERACTIVE-}" ]]; then
  if [[ ! -t 0 ]]; then
    if [[ -z "${INTERACTIVE-}" ]]; then
      warn 'Running in non-interactive mode because `stdin` is not a TTY.'
      NONINTERACTIVE=1
    else
      warn 'Running in interactive mode despite `stdin` not being a TTY because `$INTERACTIVE` is set.'
    fi
  fi
else
  info 'Running in non-interactive mode because `$NONINTERACTIVE` is set.'
fi

#                                     #
# --- Define User Input Functions --- #
#                                     #

getc() {
  local save_state
  save_state="$(/bin/stty -g)"
  /bin/stty raw -echo
  IFS='' read -r -n 1 -d '' "$@"
  /bin/stty "${save_state}"
}

prompt_user() {
  if [[ -z ${NONINTERACTIVE-} ]]; then
    local c
    local prompt="${1}"
    if [[ -z $prompt ]]; then
      abort "prompt_user requires a prompt argument."
    fi
    echo "${tty_bold}${prompt} "
    getc c
    if [[ "${c}" != "y" && "${c}" != "Y" ]]; then
      return 1
    fi
  fi
}

check_run_command() {
  local promptMsg="${1}"
  if [[ -z ${promptMsg} ]]; then
      abort "check_run_command requires promptMsg argument"
  fi
  if [[ -z ${3} ]]; then
    local promptMsgSub=""
    local cmd="${2}"
  else
    local promptMsgSub="${2}"
    local cmd="${3}"
  fi
  if [[ -z ${cmd} ]]; then
      abort "check_run_command requires cmd argument"
  fi

  info "${promptMsg}"
  info "${tty_reset}${promptMsgSub}"
  info "Command to run:"
  info "    ${tty_reset}${cmd}"
  echo
  if prompt_user "Run command now? [Y/n]:"; then
    info "Running command..."
    eval "${cmd}"
    return $?
  else
    err "Installation cancelled. Exiting."
    return 1
  fi
}

#                               #
# --- Start of Installation --- #
#                               #

# Figure out what repository we're using for configuration
config_repo_url=${1:-${SYSGIT_CONFIG_REPO:-}}
config_repo_branch=${2:-${SYSGIT_CONFIG_REPO_BRANCH:-"master"}}

if [[ -z "${config_repo_url}" ]]; then
  if [[ -z "${NONINTERACTIVE:-}" ]]; then
      #config_repo_input=($(ask_user "Which configuration repository do you want to use?"))
      read -a config_repo_input -p "Configuration repository URL: "
      config_repo_url=${config_repo_input[0]:-${config_repo_url}}
      config_repo_branch=${config_repo_input[1]:-${config_repo_branch}}
      if [[ -z "${config_repo_url}" ]]; then
          abort "No configuration repository specified"
      fi
  else
      abort "No configuration repository specified"
  fi
fi

# Check if sysgit already exists
SYSGIT_HOME=${SYSGIT_HOME:-"${HOME}/.sysgit"}
SYSGIT_WORKSPACE=${SYSGIT_WORKSPACE:-"${HOME}"}

if [[ -a "${SYSGIT_HOME}" ]]; then
    check_run_command "Pre-existing sysgit installation found" "Do you wish to move it to a safe place to continue?" "mv '${SYSGIT_HOME}' '${SYSGIT_HOME}.backup_$(date +%s)'"
fi

if [[ ! -d "${SYSGIT_WORKSPACE}" ]]; then
    check_run_command "Workspace ${SYSGIT_WORKSPACE} does not exist." "Do you wish to create it?" "mkdir -p '${SYSGIT_WORKSPACE}'"
fi

# Clone repository
check_run_command "Cloning configuration repository" "Do you want to clone branch ${config_repo_branch} of ${config_repo_url} to bare repo ${SYSGIT_HOME}?" "git clone --bare -b ${config_repo_branch} ${config_repo_url} ${SYSGIT_HOME}"

# Create sysgit function for use within this script
sysgit() {
  $(command -v git) --git-dir="${SYSGIT_HOME}/" --work-tree="${SYSGIT_WORKSPACE}" $@
}

# Ensure the local repo is configured to ignore untracked files
sysgit config --local status.showUntrackedFiles no

set +e
backup_file_list=$(sysgit checkout 2>&1 | grep "^\t" | sed -e "s/^\t//")
set -e

if [[ ! -z "${backup_file_list}" ]]; then
    backup_dir="${SYSGIT_WORKSPACE}/sysgit_existing_config_backup.$(date +%s)"
    backup_file_list_formatted="$(echo "${tty_reset}${backup_file_list}" | sed -e "s/^/\t- /")"
    check_run_command "Workspace has conflicting config changes." $'Backup the conflicting files?\n'"${backup_file_list_formatted}" "
    IFS=\$'\n'
    mkdir \"$backup_dir\"
    for fname in \$backup_file_list; do
      mkdir -p \$(dirname \"$backup_dir/\$fname\")
      mv \"${SYSGIT_WORKSPACE}/\$fname\" \"$backup_dir/\$fname\"
    done"
fi

info "Copying new configuration files"
# Actually do the checkout of config files into the workspace
sysgit checkout

# Install sysgit script to $HOME/.local/bin
set +e
read -r -d '' sysgit_script <<"EOF"
#!/bin/bash
\$(command -v git) --git-dir="${SYSGIT_HOME}/" --work-tree="${SYSGIT_WORKSPACE}" \$@
EOF
set -e

SYSGIT_EXECUTABLE_PATH="${SYSGIT_EXECUTABLE_PATH:-"${HOME}//bin"}"
sysgit_executable="${SYSGIT_EXECUTABLE_PATH}/sysgit"

info "Installing sysgit executable"
if [[ -f "${sysgit_executable}" ]]; then
  check_run_command "Pre-existing sysgit executable found at ${sysgit_executable}" "Overwrite?" "echo \"${sysgit_script}\" > \"${sysgit_executable}\""
else
  check_run_command "No sysgit executable found" "Create?" "mkdir -p \"${SYSGIT_EXECUTABLE_PATH}\"; echo \"${sysgit_script}\" > \"${sysgit_executable}\""
fi

# Ensure the sysgit command is executable
chmod +x "${sysgit_executable}"

# TODO: Just run a single script found in ~/.config/sysgit/bootstrap.sh and provide a way to pass args to it which will let us move this idea/concept of
#       modules out of this script and provides ultimate flexibility. We don't need to add that kind of rigidness here.

# Run bootstrap script if present
bootstrap_file="${SYSGIT_WORKSPACE}/.config/sysgit/bootstrap.sh"

bootstrap_args="${SYSGIT_BOOTSTRAP_ARGS:-""}"

if [[ -f "$bootstrap_file" ]]; then
  check_run_command "Bootstrap file found at ${bootstrap_file}" "Execute it?" "/bin/bash \"${bootstrap_file}\" ${bootstrap_args}"
fi

info "Installation complete."
info "NOTE: ${tty_reset}It is recommended that you add ${SYSGIT_EXECUTABLE_PATH} to your \$PATH for ease of use"
