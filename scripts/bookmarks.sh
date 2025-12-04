#!/bin/bash

###############################################################################
# Bookmarks Setup Script
###############################################################################
#
# This script loads bookmarks from configs/bookmarks.json into available browsers.
#
# Supported Browsers:
#   - Safari: Automatically imports bookmarks using safari-bookmarks-cli
#   - Chrome: Automatically imports bookmarks by modifying Bookmarks file
#   - Brave: Automatically imports bookmarks by modifying Bookmarks file
#   - Arc: Shows instructions to use browser's import feature
#   - Dia: Shows instructions to use browser's import feature
#
# Requirements:
#   - jq: Required for parsing JSON (install via: brew install jq)
#   - Full Disk Access: Required for Safari bookmarks (checked in setup.sh)
#   - Python 3 or mise: Required for Safari bookmarks (safari-bookmarks-cli)
#
# Usage:
#   ./scripts/bookmarks.sh
#
# Configuration:
#   Bookmarks are defined in configs/bookmarks.json with the following format:
#   {
#     "bookmarks": [
#       {
#         "name": "Bookmark Name",
#         "url": "https://example.com"
#       }
#     ]
#   }
#
# Notes:
#   - Duplicate bookmarks (by URL) are automatically skipped
#   - Existing bookmarks are backed up before modification
#   - Safari bookmarks require Full Disk Access (prompted in setup.sh)
#   - Arc and Dia require manual import using their built-in features
#
###############################################################################

set -e

source ./scripts/utils.sh

BOOKMARKS_CONFIG="configs/bookmarks.json"

# Check if bookmarks config exists
if [ ! -f "$BOOKMARKS_CONFIG" ]; then
  print_error "Bookmarks config file not found at $BOOKMARKS_CONFIG"
  exit 1
fi

step "Checking Full Disk Access..."
check_full_disk_access

step "Loading bookmarks into available browsers..."

# Function to check if a browser is installed
is_browser_installed() {
  local browser="$1"
  case "$browser" in
    safari)
      [ -d "/Applications/Safari.app" ]
      ;;
    chrome)
      [ -d "/Applications/Google Chrome.app" ]
      ;;
    arc)
      [ -d "/Applications/Arc.app" ]
      ;;
    dia)
      [ -d "/Applications/Dia.app" ]
      ;;
    brave)
      [ -d "/Applications/Brave Browser.app" ]
      ;;
    *)
      return 1
      ;;
  esac
}

# Function to add bookmarks to Chrome-based browsers (Chrome, Arc, Brave, Dia)
add_bookmarks_to_chrome_based() {
  local browser_name="$1"
  local bookmarks_file="$2"
  local profile_dir="$3"
  
  if [ ! -d "$profile_dir" ]; then
    print_warning "$browser_name profile directory not found. Creating it..."
    mkdir -p "$profile_dir"
  fi
  
  # Backup existing bookmarks if they exist
  if [ -f "$bookmarks_file" ]; then
    local backup_file="${bookmarks_file}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$bookmarks_file" "$backup_file"
    print_success_muted "Backed up existing bookmarks to $(basename "$backup_file")"
  fi
  
  # Read bookmarks from config
  if ! command -v jq &>/dev/null; then
    print_error "jq is required to parse bookmarks. Please install it: brew install jq"
    return 1
  fi
  
  # Create or update bookmarks file
  if [ ! -f "$bookmarks_file" ]; then
    # Create new bookmarks file structure
    cat > "$bookmarks_file" << 'EOF'
{
  "version": 1,
  "checksum": "",
  "roots": {
    "bookmark_bar": {
      "children": [],
      "type": "folder",
      "id": 1,
      "name": "Bookmarks Bar"
    },
    "other": {
      "children": [],
      "type": "folder",
      "id": 2,
      "name": "Other Bookmarks"
    },
    "synced": {
      "children": [],
      "type": "folder",
      "id": 3,
      "name": "Mobile Bookmarks"
    }
  }
}
EOF
  fi
  
  # Get existing bookmarks and extract their URLs (normalized for comparison)
  local existing_bookmarks=$(jq -r '.roots.bookmark_bar.children // []' "$bookmarks_file")
  
  # Create a function to normalize URLs for comparison (lowercase, remove trailing slash)
  # We'll use jq to normalize URLs when comparing
  local existing_urls=$(echo "$existing_bookmarks" | jq -r '.[] | select(.type == "url") | .url | ascii_downcase | rtrimstr("/")' | sort -u)
  
  # Extract bookmarks from config and add only non-duplicates to the bookmark bar
  local bookmark_id=4
  local bookmarks_to_add="[]"
  local skipped=0
  local added=0
  
  # Get the highest existing ID to avoid conflicts
  local max_id=$(echo "$existing_bookmarks" | jq '[.[] | .id // 0] | max // 0')
  if [ "$max_id" -gt 0 ]; then
    bookmark_id=$((max_id + 1))
  fi
  
  while IFS= read -r line; do
    local name=$(echo "$line" | jq -r '.name')
    local url=$(echo "$line" | jq -r '.url')
    
    if [ "$name" != "null" ] && [ "$url" != "null" ]; then
      # Normalize URL for comparison (lowercase, remove trailing slash)
      local normalized_url=$(echo "$url" | tr '[:upper:]' '[:lower:]' | sed 's|/$||')
      
      # Check if this URL already exists (case-insensitive, ignoring trailing slash)
      # existing_urls is already normalized from line 142
      local is_duplicate=false
      if [ -n "$existing_urls" ]; then
        if echo "$existing_urls" | grep -qFx "$normalized_url"; then
          is_duplicate=true
        fi
      fi
      
      if [ "$is_duplicate" = false ]; then
        local bookmark_entry=$(jq -n \
          --arg name "$name" \
          --arg url "$url" \
          --argjson id "$bookmark_id" \
          '{type: "url", name: $name, url: $url, id: $id}')
        
        bookmarks_to_add=$(echo "$bookmarks_to_add" | jq --argjson entry "$bookmark_entry" '. + [$entry]')
        bookmark_id=$((bookmark_id + 1))
        added=$((added + 1))
        # Add to existing_urls to avoid duplicates within the same batch
        existing_urls="$existing_urls"$'\n'"$normalized_url"
      else
        skipped=$((skipped + 1))
      fi
    fi
  done < <(jq -c '.bookmarks[]' "$BOOKMARKS_CONFIG")
  
  # Merge new bookmarks with existing ones
  local merged_bookmarks=$(echo "$existing_bookmarks" | jq --argjson new "$bookmarks_to_add" '. + $new')
  
  # Update the bookmarks file
  jq --argjson children "$merged_bookmarks" '.roots.bookmark_bar.children = $children' "$bookmarks_file" > "${bookmarks_file}.tmp"
  mv "${bookmarks_file}.tmp" "$bookmarks_file"
  
  if [ $added -gt 0 ]; then
    print_success "Added $added bookmark(s) to $browser_name"
    if [ $skipped -gt 0 ]; then
      print_muted "Skipped $skipped bookmark(s) (already exist)"
    fi
  else
    if [ $skipped -gt 0 ]; then
      print_success_muted "All $skipped bookmark(s) already exist in $browser_name"
    else
      print_warning "No bookmarks were processed for $browser_name"
    fi
  fi
}

# Function to add bookmarks to Safari using safari-bookmarks-cli
add_bookmarks_to_safari() {
  local safari_bookmarks="$HOME/Library/Safari/Bookmarks.plist"
  
  if [ ! -f "$safari_bookmarks" ]; then
    print_warning "Safari Bookmarks.plist not found. Safari may need to be opened at least once."
    return 1
  fi
  
  # Check if mise is available for temporary installation
  local use_mise=false
  local temp_install=false
  
  if command -v mise &>/dev/null; then
    use_mise=true
    # Check if safari-bookmarks-cli is already available via mise
    if ! mise exec python -- safari-bookmarks --version >/dev/null 2>&1; then
      print_muted "Temporarily installing safari-bookmarks-cli with mise..."
      # Use mise's Python to install the package temporarily
      if ! mise exec python -- pip install safari-bookmarks-cli >/dev/null 2>&1; then
        print_warning "Failed to install safari-bookmarks-cli with mise. Falling back to system Python."
        use_mise=false
      else
        temp_install=true
        # Verify it's accessible via mise exec
        if ! mise exec python -- safari-bookmarks --version >/dev/null 2>&1; then
          print_warning "safari-bookmarks-cli installed but not accessible. Falling back to system Python."
          use_mise=false
          temp_install=false
        fi
      fi
    fi
  fi
  
  # Fallback to system Python if mise is not available or failed
  if [ "$use_mise" = false ]; then
    if ! command -v safari-bookmarks &>/dev/null; then
      if command -v pip3 &>/dev/null; then
      print_muted "Installing safari-bookmarks-cli with system Python..."
      pip3 install --user safari-bookmarks-cli >/dev/null 2>&1
      # Add user's local bin to PATH if not already there (for macOS)
      local python_version=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))' 2>/dev/null || echo "3.11")
      local user_bin="$HOME/Library/Python/$python_version/bin"
      if [ -d "$user_bin" ] && [[ ":$PATH:" != *":$user_bin:"* ]]; then
        export PATH="$user_bin:$PATH"
      fi
      # Also check common locations
      if [ -d "$HOME/.local/bin" ] && [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        export PATH="$HOME/.local/bin:$PATH"
      fi
      temp_install=true
      else
        print_error "Neither mise nor pip3 is available. Please install Python 3 or mise first."
        return 1
      fi
    fi
  fi
  
  # Verify installation succeeded
  if [ "$use_mise" = true ]; then
    if ! mise exec python -- safari-bookmarks --version >/dev/null 2>&1; then
      print_error "Failed to install safari-bookmarks-cli with mise. Please install manually: pip3 install safari-bookmarks-cli"
      return 1
    fi
  elif ! command -v safari-bookmarks &>/dev/null; then
    print_error "Failed to install safari-bookmarks-cli. Please install manually: pip3 install safari-bookmarks-cli"
    return 1
  fi
  
  # Get existing bookmarks to check for duplicates
  # safari-bookmarks list outputs in format: "Title - URL" or just "URL"
  local existing_urls=""
  local list_output=""
  local list_error=""
  
  if [ "$use_mise" = true ]; then
    list_output=$(mise exec python -- safari-bookmarks list "BookmarksBar" 2>&1 || true)
  else
    list_output=$(safari-bookmarks list "BookmarksBar" 2>&1 || true)
  fi
  
  # Check if the command failed (ignore permission errors - will fail silently)
  if echo "$list_output" | grep -qiE "(error|not found|does not exist)"; then
    print_muted "BookmarksBar folder may not exist yet, will create it when adding bookmarks"
    existing_urls=""
  else
    # Extract URLs from the list output (handles both "Title - URL" and "URL" formats)
    if [ -n "$list_output" ]; then
      existing_urls=$(echo "$list_output" | grep -oE 'https?://[^[:space:]]+' || echo "")
    fi
  fi
  
  # If we couldn't get existing URLs, we'll try to add all bookmarks anyway
  # (the CLI will handle duplicates gracefully)
  local skip_duplicate_check=false
  if [ -z "$existing_urls" ] && [ -z "$list_output" ]; then
    print_muted "Could not retrieve existing bookmarks list, will attempt to add all (duplicates will be skipped)"
    skip_duplicate_check=true
  fi
  
  # Process each bookmark from config
  local count=0
  local skipped=0
  while IFS= read -r line; do
    local name=$(echo "$line" | jq -r '.name')
    local url=$(echo "$line" | jq -r '.url')
    
    if [ "$name" != "null" ] && [ "$url" != "null" ]; then
      # Check if bookmark already exists (unless we're skipping duplicate check)
      local should_add=true
      if [ "$skip_duplicate_check" = false ]; then
        # Normalize URL for comparison (remove trailing slashes, etc.)
        local normalized_url=$(echo "$url" | sed 's|/$||')
        
        # Check if bookmark already exists (case-insensitive, handle trailing slashes)
        local exists=""
        if [ -n "$existing_urls" ]; then
          exists=$(echo "$existing_urls" | grep -iE "^${normalized_url}/*$" || true)
        fi
        
        if [ -n "$exists" ]; then
          should_add=false
        fi
      fi
      
      if [ "$should_add" = true ]; then
        # Add bookmark to BookmarksBar using safari-bookmarks-cli
        local add_success=false
        local add_error=""
        
        if [ "$use_mise" = true ]; then
          add_error=$(mise exec python -- safari-bookmarks add --title "$name" --url "$url" "BookmarksBar" 2>&1)
          if [ $? -eq 0 ]; then
            add_success=true
            count=$((count + 1))
            # Add to existing_urls to avoid duplicates in the same run
            existing_urls="$existing_urls"$'\n'"$url"
          fi
        else
          add_error=$(safari-bookmarks add --title "$name" --url "$url" "BookmarksBar" 2>&1)
          if [ $? -eq 0 ]; then
            add_success=true
            count=$((count + 1))
            # Add to existing_urls to avoid duplicates in the same run
            existing_urls="$existing_urls"$'\n'"$url"
          fi
        fi
        
        if [ "$add_success" = false ]; then
          # Check for specific error types (ignore permission errors - will fail silently)
          if echo "$add_error" | grep -qiE "(already exists|duplicate)"; then
            # It's a duplicate, count as skipped
            skipped=$((skipped + 1))
          else
            # Other error
            if [ $count -eq 0 ]; then
              # Only show detailed error on first failure
              print_warning "Failed to add bookmark: $name ($url)"
              print_muted "Error: $(echo "$add_error" | head -3 | tr '\n' ' ')"
            fi
          fi
        fi
      else
        skipped=$((skipped + 1))
      fi
    fi
  done < <(jq -c '.bookmarks[]' "$BOOKMARKS_CONFIG")
  
  if [ $count -gt 0 ]; then
    print_success "Added $count bookmark(s) to Safari"
    if [ $skipped -gt 0 ]; then
      print_muted "Skipped $skipped bookmark(s) (already exist)"
    fi
    print_muted "Safari will automatically reload the bookmarks"
  else
    if [ $skipped -gt 0 ]; then
      print_success_muted "All $skipped bookmark(s) already exist in Safari"
    else
      print_warning "No bookmarks were processed. Please check your bookmarks.json file."
    fi
  fi
  
  # Clean up temporary installation if we installed it
  if [ "$temp_install" = true ]; then
    print_muted "Removing temporary safari-bookmarks-cli installation..."
    if [ "$use_mise" = true ]; then
      mise exec python -- pip uninstall -y safari-bookmarks-cli >/dev/null 2>&1 || true
    else
      pip3 uninstall -y safari-bookmarks-cli >/dev/null 2>&1 || true
    fi
  fi
}

# Process each browser
browsers_processed=0

# Safari
if is_browser_installed "safari"; then
  print_muted "Processing Safari..."
  if add_bookmarks_to_safari; then
    browsers_processed=$((browsers_processed + 1))
  fi
fi

# Chrome
if is_browser_installed "chrome"; then
  print_muted "Processing Chrome..."
  add_bookmarks_to_chrome_based "Chrome" \
    "$HOME/Library/Application Support/Google/Chrome/Default/Bookmarks" \
    "$HOME/Library/Application Support/Google/Chrome/Default"
  browsers_processed=$((browsers_processed + 1))
fi

# Arc
if is_browser_installed "arc"; then
  print_muted "Arc detected..."
  print_in_cyan "  To import bookmarks into Arc, use the browser's import feature:\n"
  print_in_white "  1. Open Arc\n"
  print_in_white "  2. Go to Settings → Import\n"
  print_in_white "  3. Select Chrome or Safari to import bookmarks\n"
  echo ""
fi

# Dia
if is_browser_installed "dia"; then
  print_muted "Dia detected..."
  print_in_cyan "  To import bookmarks into Dia, use the browser's import feature:\n"
  print_in_white "  1. Open Dia\n"
  print_in_white "  2. Go to Settings → Import\n"
  print_in_white "  3. Select Chrome or Safari to import bookmarks\n"
  echo ""
fi

# Brave
if is_browser_installed "brave"; then
  print_muted "Processing Brave Browser..."
  add_bookmarks_to_chrome_based "Brave Browser" \
    "$HOME/Library/Application Support/BraveSoftware/Brave-Browser/Default/Bookmarks" \
    "$HOME/Library/Application Support/BraveSoftware/Brave-Browser/Default"
  browsers_processed=$((browsers_processed + 1))
fi

if [ $browsers_processed -eq 0 ]; then
  print_warning "No supported browsers found. Please install at least one of: Safari, Chrome, Arc, Dia, or Brave Browser"
else
  echo ""
  print_success "Bookmarks loaded into $browsers_processed browser(s)!"
  print_muted "You may need to restart your browsers for changes to take effect."
fi

