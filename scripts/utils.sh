#!/usr/bin/env bash

set -e

###############################################################################
# VARIABLES
###############################################################################

reset="\033[0m"
highlight="\033[41m\033[97m"
dot="\033[31m▸ $reset"
dim="\033[2m"
blue="\e[34m"
green="\e[32m"
yellow="\e[33m"
tag_green="\e[30;42m"
tag_blue="\e[30;46m"
bold=$(tput bold)
normal=$(tput sgr0)
underline="\e[37;4m"
indent="   "

# Get full directory name of this script
cwd="$(cd "$(dirname "$0")" && pwd)"

DOTFILES_ROOT=$HOME/.dotfiles

###############################################################################
# Utility Functions
###############################################################################
_print_in_color() {
  printf "%b" \
    "$(tput setaf "$2" 2>/dev/null)" \
    "$1" \
    "$(tput sgr0 2>/dev/null)"
}

_print_error_stream() {
  while read -r line; do
    print_in_red "     ↳ ERROR: $line\n"
  done
}

_show_spinner() {

  local -r FRAMES='/-\|\\'

  # shellcheck disable=SC2034
  local -r NUMBER_OR_FRAMES=${#FRAMES}

  local -r CMDS="$2"
  local -r MSG="$3"
  local -r PID="$1"

  local i=0
  local frameText=""

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  # Note: In order for the Travis CI site to display
  # things correctly, it needs special treatment, hence,
  # the "is Travis CI?" checks.

  if [ "$TRAVIS" != "true" ]; then

    # Provide more space so that the text hopefully
    # doesn't reach the bottom line of the terminal window.
    #
    # This is a workaround for escape sequences not tracking
    # the buffer position (accounting for scrolling).
    #
    # See also: https://unix.stackexchange.com/a/278888

    printf "\n\n\n"
    tput cuu 3

    tput sc

  fi

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  # Display spinner while the commands are being executed.

  while kill -0 "$PID" &>/dev/null; do

    frameText=" [${FRAMES:i++%NUMBER_OR_FRAMES:1}] $MSG"

    # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    # Print frame text.

    if [ "$TRAVIS" != "true" ]; then
      printf "%s\n" "$frameText"
    else
      printf "%s" "$frameText"
    fi

    sleep 0.2

    # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    # Clear frame text.

    if [ "$TRAVIS" != "true" ]; then
      tput rc
    else
      printf "\r"
    fi

  done

}

_kill_all_subprocesses() {

  local i=""

  for i in $(jobs -p); do
    kill "$i"
    wait "$i" &>/dev/null
  done

}

_set_trap() {

  trap -p "$1" | grep "$2" &>/dev/null ||
    trap '$2' "$1"

}

_link_file() {
  local src=$1 dst=$2

  local overwrite= backup= skip=
  local action=

  if [ -f "$dst" -o -d "$dst" -o -L "$dst" ]; then

    if [ "$overwrite_all" == "false" ] && [ "$backup_all" == "false" ] && [ "$skip_all" == "false" ]; then

      local currentSrc="$(readlink $dst)"

      if [ "$currentSrc" == "$src" ]; then

        skip=true

      else

        printf "\r   ${yellow}!${reset} File already exists: $dst ($(basename "$src")), what do you want to do?\n     [s]kip, [S]kip all, [o]verwrite, [O]verwrite all, [b]ackup, [B]ackup all? "
        read -n 1 action

        case "$action" in
        o)
          overwrite=true
          ;;
        O)
          overwrite_all=true
          ;;
        b)
          backup=true
          ;;
        B)
          backup_all=true
          ;;
        s)
          skip=true
          ;;
        S)
          skip_all=true
          ;;
        *)
          ;;
        esac

      fi

    fi

    overwrite=${overwrite:-$overwrite_all}
    backup=${backup:-$backup_all}
    skip=${skip:-$skip_all}

    if [ "$overwrite" == "true" ]; then
      rm -rf "$dst"
      print_in_green "\n      ✓ deleted $dst"
    fi

    if [ "$backup" == "true" ]; then
      mv "$dst" "${dst}.backup"
      print_in_green "\n      ✓ moved $dst to ${dst}.backup"
    fi

    if [ "$skip" == "true" ]; then
      printf "\n  ${dim}    ✓ $src already linked. Skipped.${reset}"
    fi
  fi

  if [ "$skip" != "true" ]; then # "false" or empty
    ln -s "$1" "$2"
    print_in_green "\n      ✓ linked $1 to $2"
  fi
}

###############################################################################
# Print Functions
###############################################################################

print_in_red() {
  _print_in_color "$1" 1
}

print_in_green() {
  _print_in_color "$1" 2
}

print_in_yellow() {
  _print_in_color "$1" 3
}

print_in_blue() {
  _print_in_color "$1" 4
}

print_in_purple() {
  _print_in_color "$1" 5
}

print_in_cyan() {
  _print_in_color "$1" 6
}

print_in_white() {
  _print_in_color "$1" 7
}

print_result() {

  if [ "$1" -eq 0 ]; then
    print_success "$2"
  else
    print_error "$2"
  fi

  return "$1"

}

print_question() {
  print_in_yellow "  [?] $1\n"
}

print_success() {
  print_in_green "  [✓] $1\n"
}

print_success_muted() {
  printf "  ${dim}[✓] $1${reset}\n" "$@"
}

print_muted() {
  printf "  ${dim}$1${reset}\n" "$@"
}

print_warning() {
  print_in_yellow "  [!] $1\n"
}

print_error() {
  print_in_red "  [𝘅] $1 $2\n"
}

###############################################################################
# Meta Checks
###############################################################################

check_bash_version() {
  if ((BASH_VERSINFO[0] < 3)); then
    print_error "Sorry, you need at least bash-3.0 to run this script."
    exit 1
  fi
}

get_os() {

  local os=""
  local kernelName=""

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  kernelName="$(uname -s)"

  if [ "$kernelName" == "Darwin" ]; then
    os="macOS"
  elif [ "$kernelName" == "Linux" ] && [ -e "/etc/lsb-release" ]; then
    os="ubuntu"
  else
    os="$kernelName"
  fi

  printf "%s" "$os"

}

get_os_version() {

  local os=""
  local version=""

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  os="$(get_os)"

  if [ "$os" == "macOS" ]; then
    version="$(sw_vers -productVersion)"
  elif [ "$os" == "ubuntu" ]; then
    version="$(lsb_release -d | cut -f2 | cut -d' ' -f2)"
  fi

  printf "%s" "$version"

}

check_internet_connection() {
  if [ ping -q -w1 -c1 google.com ] &>/dev/null; then
    print_error "Please check your internet connection"
    exit 0
  else
    print_success "Internet connection"
  fi
}

###############################################################################
# Execution
###############################################################################

execute() {

  local -r CMDS="$1"
  local -r MSG="${2:-$1}"
  local -r TMP_FILE="$(mktemp /tmp/XXXXX)"

  local exitCode=0
  local cmdsPID=""

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  # If the current process is ended,
  # also end all its subprocesses.

  _set_trap "EXIT" "_kill_all_subprocesses"

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  # Execute commands in background

  eval "$CMDS" \
    &>/dev/null \
    2>"$TMP_FILE" &

  cmdsPID=$!

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  # Show a spinner if the commands
  # require more time to complete.

  _show_spinner "$cmdsPID" "$CMDS" "$MSG"

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  # Wait for the commands to no longer be executing
  # in the background, and then get their exit code.

  wait "$cmdsPID" &>/dev/null
  exitCode=$?

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  # Print output based on what happened.

  print_result $exitCode "$MSG"

  if [ $exitCode -ne 0 ]; then
    _print_error_stream <"$TMP_FILE"
  fi

  rm -rf "$TMP_FILE"

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  return $exitCode

}

mkd() {
  if [ -n "$1" ]; then
    if [ -e "$1" ]; then
      if [ ! -d "$1" ]; then
        print_error "$1 - a file with the same name already exists!"
      else
        printf "     ${dim}✓ $1 already exists. Skipped.${reset}\n"
      fi
    else
      execute "mkdir -p $1" "$1"
    fi
  fi
}

symlink_dotfiles() {
  local overwrite_all=false backup_all=false skip_all=false

  for src in $(find -H "$DOTFILES_ROOT" -maxdepth 2 -name '*.symlink' -not -path '*.git*'); do
    dst="$HOME/.$(basename "${src%.*}")"
    _link_file "$src" "$dst"
  done
}

###############################################################################
# Prompts
###############################################################################
ask_for_sudo() {

  # Ask for the administrator password upfront.

  sudo -v &>/dev/null

  # Update existing `sudo` time stamp
  # until this script has finished.
  #
  # https://gist.github.com/cowboy/3118588

  # Keep-alive: update existing `sudo` time stamp until script has finished
  while true; do
    sudo -n true
    sleep 60
    kill -0 "$$" || exit
  done 2>/dev/null &

  print_success "Password cached"

}

ask_for_github_org() {
  if [ -z "$GITHUB_ORG" ]; then
    echo ""
    print_question "Enter your GitHub organization name (e.g. 'yosefserkez'):"
    read -r GITHUB_ORG </dev/tty
    if [ -z "$GITHUB_ORG" ]; then
      print_error "GitHub organization name cannot be empty"
      exit 1
    fi
    export GITHUB_ORG
    print_success "GitHub organization set to: $GITHUB_ORG"
  else
    print_success_muted "GitHub organization already set to: $GITHUB_ORG"
  fi
}

ask() {
  # https://djm.me/ask
  local prompt default reply

  while true; do

    if [ "${2:-}" = "Y" ]; then
      prompt="Y/n"
      default=Y
    elif [ "${2:-}" = "N" ]; then
      prompt="y/N"
      default=N
    else
      prompt="y/n"
      default=
    fi

    # Ask the question (not using "read -p" as it uses stderr not stdout)
    echo -n "  [?] $1 [$prompt] "

    # Read the answer (use /dev/tty in case stdin is redirected from somewhere else)
    read reply </dev/tty

    # Default?
    if [ -z "$reply" ]; then
      reply=$default
    fi

    # Check if the reply is valid
    case "$reply" in
    Y* | y*) return 0 ;;
    N* | n*) return 1 ;;
    esac

  done
}

show_file_diff() {
  local file_path="$1"
  local config_file="$2"
  
  if [ -f "$file_path" ] && [ -f "$config_file" ]; then
    print_in_blue "      📋 Showing diff between existing and new config:"
    echo -e "   ${dim}┌─────────────────────────────────────────────────────${reset}"
    if command -v diff &>/dev/null; then
      diff "$file_path" "$config_file" || true
    else
      echo "   ${dim}diff command not available${reset}"
    fi
    echo -e "   ${dim}└─────────────────────────────────────────────────────${reset}"
  fi
}

files_are_identical() {
  local file_path="$1"
  local config_file="$2"
  
  if [ -f "$file_path" ] && [ -f "$config_file" ]; then
    if command -v diff &>/dev/null; then
      diff "$file_path" "$config_file" >/dev/null 2>&1
      return $?
    else
      # Fallback: compare file sizes and content if diff is not available
      if [ "$(wc -c < "$file_path")" = "$(wc -c < "$config_file")" ]; then
        cmp "$file_path" "$config_file" >/dev/null 2>&1
        return $?
      else
        return 1
      fi
    fi
  else
    return 1
  fi
}

confirm_override() {
  local file_path="$1"
  local config_file="$2"
  local description="${3:-file}"
  
  if [ -f "$file_path" ]; then
    print_warning "⚠️  $description already exists at $file_path"
    
    # Show diff if both files exist
    show_file_diff "$file_path" "$config_file"
    
    if ask "Would you like to override it?" Y; then
      return 0
    else
      return 1
    fi
  else
    return 0
  fi
}

###############################################################################
#
###############################################################################

# return 1 if global command line program installed, else 0
cli_is_installed() {
  # set to 1 initially
  local return_=1
  # set to 0 if not found
  type $1 >/dev/null 2>&1 || { local return_=0; }
  # return value
  echo "$return_"
}

###############################################################################
# Text Formatting
###############################################################################

print_attribute() {
  local name="$1"
  local value="$2"
  printf "   ${blue}✦  ${reset}"
  print_in_cyan "$name: "
  print_in_white "$value\n"
}

title() {
  local fmt="$1"
  shift
  printf "\n✦  ${bold}$fmt${normal}\n└─────────────────────────────────────────────────────○\n" "$@"
}

echo_install() {
  local fmt="$1"
  shift
  printf "  [↓] $fmt " "$@"
}

todo() {
  local fmt="$1"
  shift
  printf "  [ ] $fmt\n" "$@"
}

inform() {
  local fmt="$1"
  shift
  printf "   ✦  $fmt\n" "$@"
}

announce() {
  local fmt="$1"
  shift
  printf "○───✦ $fmt\n" "$@"
}

step() {
  printf "\n ${dot}$@${reset}\n"
}

label_blue() {
  printf "\e[30;46m $1 \033[0m\e[34m $2 \033[0m\n"
}

label_green() {
  printf "\e[30;42m $1 \e[0m\e[32m $2 \033[0m\n"
}

###############################################################################
# Full Disk Access Functions
###############################################################################

check_full_disk_access() {
  # Test if we can access a protected file (Safari bookmarks is a good test)
  # On macOS 10.14+, accessing certain files in ~/Library requires Full Disk Access
  local test_file="$HOME/Library/Safari/Bookmarks.plist"
  
  # Try to read the file (this requires Full Disk Access on macOS 10.14+)
  if [ -f "$test_file" ]; then
    # File exists, try to read it - this will fail with permission error if Full Disk Access is not enabled
    local error_output=$(cat "$test_file" 2>&1)
    if [ $? -ne 0 ]; then
      # Check if it's a permission error
      if echo "$error_output" | grep -qiE "(Operation not permitted|denied)"; then
        if ! prompt_full_disk_access; then
          print_error "Full Disk Access is required for modifying Safari bookmarks. Exiting."
          exit 1
        fi
        # Test again after user enables it
        if ! cat "$test_file" >/dev/null 2>&1; then
          print_error "Full Disk Access is still not enabled. Please restart your terminal and try again."
          exit 1
        fi
      else
        print_error "Failed to access Safari bookmarks file"
        exit 1
      fi
    fi
  fi
  # If file doesn't exist or we can read it, we're good
  print_success "Full Disk Access"
}

prompt_full_disk_access() {
  # Detect which terminal is being used
  local terminal_app="Terminal"
  local terminal_path="/System/Applications/Utilities/Terminal.app"
  
  if [ -n "$ITERM_SESSION_ID" ]; then
    terminal_app="iTerm"
    terminal_path="/Applications/iTerm.app"
  elif [ -n "$VSCODE_INJECTION" ] || [ -n "$VSCODE_PID" ]; then
    terminal_app="Code"
    terminal_path="/Applications/Visual Studio Code.app"
  fi
  
  print_error "Full Disk Access is required for this setup"
  echo ""
  print_in_cyan "Opening System Settings to Full Disk Access..."
  echo ""
  
  # Detect macOS version and open appropriate settings
  local macos_version=$(sw_vers -productVersion | cut -d. -f1)
  
  # Try to open System Settings/Preferences to Full Disk Access
  if [ "$macos_version" -ge 14 ]; then
    # macOS Sonoma (14+) - Use newer System Settings URL
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles" 2>/dev/null || \
    open -b com.apple.systempreferences
  elif [ "$macos_version" -eq 13 ]; then
    # macOS Ventura (13) - Use System Settings
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles" 2>/dev/null || \
    open -b com.apple.systempreferences
  else
    # macOS Monterey (12) and earlier - Use System Preferences
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles" 2>/dev/null || \
    open "/System/Library/PreferencePanes/Security.prefPane" 2>/dev/null || \
    open -b com.apple.systempreferences
  fi
  
  # Give it a moment to open
  sleep 1
  
  echo ""
  print_in_white "Please follow these steps:"
  echo ""
  print_in_white "1. In System Settings, scroll down to 'Full Disk Access'"
  print_in_white "2. Click the lock icon (🔒) and enter your password"
  print_in_white "3. Enable the toggle for:"
  print_in_yellow "   → $terminal_app"
  echo ""
  print_in_white "4. If $terminal_app is not in the list, click the '+' button to add it"
  print_in_white "   and navigate to: $terminal_path"
  echo ""
  
  if ask "Have you enabled Full Disk Access for $terminal_app?" N; then
    print_muted "Please restart your terminal for the changes to take effect."
    if ask "Have you restarted your terminal?" N; then
      # Test again after restart
      if check_full_disk_access; then
        print_success "Full Disk Access is now enabled!"
        return 0
      else
        print_warning "Full Disk Access still doesn't appear to be working. Please verify it's enabled and try again."
        return 1
      fi
    else
      print_warning "You must restart your terminal for Full Disk Access to work."
      return 1
    fi
  else
    print_warning "Full Disk Access is required to continue. Please enable it and run this script again."
    return 1
  fi
}