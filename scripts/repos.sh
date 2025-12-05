#!/bin/bash

set -e

source ./scripts/utils.sh

# Combined checks for git and GitHub authentication
missing_requirements=()

# Check if git is installed
if ! command -v git &>/dev/null; then
  missing_requirements+=("git")
fi

# Check if GitHub CLI is installed
if ! command -v gh &>/dev/null; then
  missing_requirements+=("GitHub CLI (gh)")
else
  # Only check authentication if GitHub CLI is installed
  if ! gh auth status &>/dev/null 2>&1; then
    missing_requirements+=("GitHub authentication")
  fi
fi

# If any requirements are missing, show error and exit
if [ ${#missing_requirements[@]} -gt 0 ]; then
  print_error "Missing requirements:"
  for req in "${missing_requirements[@]}"; do
    echo "  - $req"
  done
  echo ""
  print_in_yellow "Please run: ./scripts/git.sh"
  print_in_yellow "Or install git, GitHub CLI, and run `gh auth login` manually."
  exit 1
fi

# Get GitHub organization from command line argument or environment variable
GITHUB_ORG="${1:-${GITHUB_ORG:-}}"

# If still not set, prompt the user
if [ -z "$GITHUB_ORG" ]; then
  echo ""
  print_question "Enter your GitHub organization name:"
  read -r GITHUB_ORG </dev/tty
  if [ -z "$GITHUB_ORG" ]; then
    print_error "GitHub organization name cannot be empty"
    exit 1
  fi
fi

print_muted "Setting up repositories..."
print_muted "Using GitHub organization: $GITHUB_ORG"

# Use a generic workspace directory name
workspace_dir="$HOME/$GITHUB_ORG"

# Create workspace directory if it doesn't exist
if [ ! -d "$workspace_dir" ]; then
  step "Creating workspace directory..."
  mkdir -p "$workspace_dir"
  print_success_muted "Created workspace directory at $workspace_dir"
fi

# Fetch repositories from GitHub organization
step "Fetching repositories from GitHub organization..."
set +e
all_repos=$(gh repo list "$GITHUB_ORG" --limit 1000 --json name --jq '.[].name' 2>&1)
fetch_exit_code=$?
set -e

if [ $fetch_exit_code -ne 0 ]; then
  print_error "Failed to fetch repositories from GitHub organization: $GITHUB_ORG"
  echo "$all_repos" | sed 's/^/     /'
  exit 1
fi

if [ -z "$all_repos" ]; then
  print_warning "No repositories found in organization: $GITHUB_ORG"
  exit 0
fi

# Convert to array
all_repos_array=()
while IFS= read -r line; do
  [ -n "$line" ] && all_repos_array+=("$line")
done <<< "$all_repos"

if [ ${#all_repos_array[@]} -eq 0 ]; then
  print_warning "No repositories found in organization: $GITHUB_ORG"
  exit 0
fi

# Interactive repository selection
selected_repos=()

if command -v fzf &>/dev/null; then
  # Use fzf for multi-select interface
  echo ""
  print_muted "Select repositories to clone (use Tab to select, Enter to confirm):"
  echo ""
  
  # Use fzf with multi-select
  selected_repos_string=$(printf '%s\n' "${all_repos_array[@]}" | fzf --multi --height=40% --border --prompt="Repositories: " --header="Select repositories to clone (Tab to toggle, Enter to confirm)")
  
  if [ -z "$selected_repos_string" ]; then
    print_warning "No repositories selected. Skipping repository setup."
    exit 0
  fi
  
  # Convert selected string to array
  selected_repos=()
  while IFS= read -r line; do
    [ -n "$line" ] && selected_repos+=("$line")
  done <<< "$selected_repos_string"
else
  # Fallback to simple bash menu
  echo ""
  print_muted "Available repositories:"
  echo ""
  
  # Display repositories with numbers
  declare -A repo_map
  index=1
  for repo in "${all_repos_array[@]}"; do
    repo_map[$index]="$repo"
    # Check if already cloned
    if [ -d "$workspace_dir/$repo" ]; then
      printf "  ${dim}[$index]${reset} $repo ${dim}(already exists)${reset}\n"
    else
      printf "  [$index] $repo\n"
    fi
    ((index++))
  done
  
  echo ""
  print_question "Enter repository numbers to clone (comma-separated, e.g., 1,3,5) or 'all' for all repositories:"
  read -r selection </dev/tty
  
  if [ -z "$selection" ]; then
    print_warning "No repositories selected. Skipping repository setup."
    exit 0
  fi
  
  if [ "$selection" = "all" ]; then
    selected_repos=("${all_repos_array[@]}")
  else
    # Parse comma-separated numbers
    IFS=',' read -ra numbers <<< "$selection"
    for num in "${numbers[@]}"; do
      num=$(echo "$num" | tr -d '[:space:]')
      if [[ "$num" =~ ^[0-9]+$ ]] && [ -n "${repo_map[$num]:-}" ]; then
        selected_repos+=("${repo_map[$num]}")
      fi
    done
  fi
fi

if [ ${#selected_repos[@]} -eq 0 ]; then
  print_warning "No repositories selected. Skipping repository setup."
  exit 0
fi

echo ""
print_success "Selected ${#selected_repos[@]} repository/repositories to clone"
echo ""

repositories_without_access=()

for repository in "${selected_repos[@]}"; do
  repository=$(echo "$repository" | tr -d '[:space:]')
  if [ -z "$repository" ]; then
    continue
  fi
  
  if [ ! -d "$workspace_dir/$repository" ]; then
    step "Cloning $repository repository..."
    set +e
    clone_output=$(git clone "git@github.com:$GITHUB_ORG/$repository.git" "$workspace_dir/$repository" 2>&1)
    clone_exit_code=$?
    set -e
    
    if [ $clone_exit_code -eq 0 ]; then
      print_success_muted "$repository repository cloned into $workspace_dir/$repository"
    else
      if echo "$clone_output" | grep -qiE "(403|permission|access denied|authentication|not authorized|repository not found)"; then
        print_warning "No permission to clone $repository repository"
        repositories_without_access+=("$repository")
      else
        print_error "Failed to clone $repository repository"
        echo "$clone_output" | sed 's/^/     /'
      fi
    fi
  else
    print_success_muted "$repository repository already found at $workspace_dir/$repository"
  fi
done

if [ ${#repositories_without_access[@]} -gt 0 ]; then
  echo ""
  print_warning "You don't have access to the following repositories:"
  for repo in "${repositories_without_access[@]}"; do
    echo "  - $repo"
  done
  echo ""
  print_in_yellow "Please reach out to your manager for access to these repositories.\n"
fi

print_success "Repositories setup completed!"
