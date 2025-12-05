#!/bin/bash

set -e

source ./scripts/utils.sh

# Check if git is installed
if ! command -v git &>/dev/null; then
  print_error "Git is not installed. Please install Git first."
  exit 1
fi

print_muted "Setting up Git configuration..."

# Check if gitconfig template exists
if [ ! -f "configs/git/gitconfig" ]; then
  print_error "No gitconfig found in configs/git/gitconfig. Please create one first."
  exit 1
fi

# Flag to track if gitconfig was set up
gitconfig_setup=false

# Setup gitconfig if it doesn't exist or user agrees to override
if [ ! -f "$HOME/.gitconfig" ]; then
  print_muted "Copying gitconfig from configs/git/gitconfig..."
  cp configs/git/gitconfig ~/.gitconfig
  print_success_muted "Copied gitconfig file"
  gitconfig_setup=true
elif files_are_identical "$HOME/.gitconfig" "configs/git/gitconfig"; then
  print_success_muted "Git configuration already up to date"
  gitconfig_setup=true
elif confirm_override "$HOME/.gitconfig" "configs/git/gitconfig" ".gitconfig file"; then
  print_muted "Copying gitconfig from configs/git/gitconfig..."
  cp configs/git/gitconfig ~/.gitconfig
  print_success_muted "Copied gitconfig file"
  gitconfig_setup=true
else
  print_success_muted "Git configuration skipped."
fi

# Prompt for Git user information only if gitconfig is set up
if [ "$gitconfig_setup" = true ]; then
  print_muted "Setting up Git user information..."

  read -p "Enter your Git display name: " git_name
  git config --global user.name "$git_name"
  print_success_muted "Git name set to: $git_name"

  read -p "Enter your Git email: " git_email
  git config --global user.email "$git_email"
  print_success_muted "Git email set to: $git_email"

else
  print_success_muted "Git user information already set."
fi

step "Setting up GitHub authentication..."
# Check if gh CLI is installed
if ! command -v gh &>/dev/null; then
  print_error "GitHub CLI (gh) is not installed. Please install it first."
  print_muted "Install with: brew install gh"
  exit 1
fi

# Check if already authenticated
if gh auth status &>/dev/null; then
  print_success_muted "GitHub authentication already configured"
  # Check if git protocol is set to SSH
  if gh config get git_protocol 2>/dev/null | grep -q "ssh"; then
    print_success_muted "Git protocol already set to SSH"
  else
    print_muted "Setting git protocol to SSH..."
    gh config set git_protocol ssh
    gh auth setup-git
    print_success_muted "Git protocol set to SSH"
  fi
else
  # Authenticate with GitHub using SSH protocol
  print_muted "Authenticating with GitHub using SSH protocol..."
  print_muted "This will automatically detect or create an SSH key and upload it to GitHub."
  echo ""
  
  if gh auth login --git-protocol ssh; then
    print_success_muted "GitHub authentication completed successfully"
  else
    print_error "GitHub authentication failed. Please try again."
    exit 1
  fi
fi

print_success "Git setup completed!"