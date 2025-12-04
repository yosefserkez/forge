#!/bin/bash

set -e

ascii_art='
 ███████╗  ██████╗   ██████╗   ████████╗  ███████╗
 ██╔════╝ ██╔═══██╗  ██╔══██╗  ██╔═════╝  ██╔════╝
 █████╗   ██║   ██║  ██████╔╝  ██║  ███╗  █████╗  
 ██╔══╝   ██║   ██║  ██╔══██╗  ██║   ██║  ██╔══╝  
 ██║      ╚██████╔╝  ██║  ██║  ╚██████╔╝  ███████╗
 ╚═╝       ╚═════╝   ╚═╝  ╚═╝   ╚═════╝   ╚══════╝
'

# Define the color gradient (shades of blue)
colors=(
  '\033[38;5;18m'  # Dark Blue
  '\033[38;5;19m'  # Deep Blue
  '\033[38;5;20m'  # Medium Blue
  '\033[38;5;21m'  # Blue
  '\033[38;5;27m'  # Bright Blue
  '\033[38;5;33m'  # Light Blue
  '\033[38;5;39m'  # Sky Blue
)

# Print each line with color
i=0
echo "$ascii_art" | while IFS= read -r line; do
  color_index=$((i % ${#colors[@]}))
  echo -e "${colors[color_index]}${line}\033[0m"
  i=$((i + 1))
done