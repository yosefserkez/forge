#!/bin/bash

set -e

source ./scripts/utils.sh

# Check if AWS CLI is installed
if ! command -v aws &>/dev/null; then
  print_error "AWS CLI is not installed. Please install AWS CLI first."
  exit 1
fi

print_muted "Setting up AWS configuration..."

# Check if AWS config template exists
if [ ! -f "configs/aws/config" ]; then
  print_error "No AWS config found in configs/aws/config. Please create one first."
  exit 1
fi

# Create .aws directory if it doesn't exist
aws_dir="$HOME/.aws"
if [ ! -d "$aws_dir" ]; then
  mkdir -p "$aws_dir"
  chmod 700 "$aws_dir"
  print_success_muted "Created .aws directory"
fi

# Flag to track if AWS config was set up
aws_config_setup=false

# Setup AWS config if it doesn't exist or user agrees to override
if [ ! -f "$aws_dir/config" ]; then
  print_muted "Copying AWS config from configs/aws/config..."
  cp configs/aws/config "$aws_dir/config"
  chmod 600 "$aws_dir/config"
  print_success_muted "Copied AWS config file"
  aws_config_setup=true
elif files_are_identical "$aws_dir/config" "configs/aws/config"; then
  print_success_muted "AWS configuration already up to date"
  aws_config_setup=true
elif confirm_override "$aws_dir/config" "configs/aws/config" "AWS config file"; then
  print_muted "Copying AWS config from configs/aws/config..."
  cp configs/aws/config "$aws_dir/config"
  chmod 600 "$aws_dir/config"
  print_success_muted "Copied AWS config file"
  aws_config_setup=true
else
  print_success_muted "AWS configuration skipped."
fi

# Run AWS configure to set up credentials
if [ "$aws_config_setup" = true ]; then
  print_muted "Setting up AWS credentials..."
  print_muted "You will be prompted to enter your AWS Access Key ID, Secret Access Key, and other settings."
  echo ""
  print_in_cyan "  1. Login to your AWS account at https://us-west-1.signin.aws.amazon.com \n"
  print_in_cyan "  2. Create a new access key: Click on your username in the top right corner and select 'Security Credentials' \n"
  print_in_cyan "  3. Click on 'Create access key'  \n"
  print_in_cyan "  4. Copy and enter your AWS Access Key ID and Secret Access Key in the prompts \n"
  echo ""
    
  # We should change this to use aws login but I haven't figured out how to get it to work yet (getting 400 errors).
  aws configure  
  print_success "AWS setup completed!"
else
  print_success_muted "AWS setup completed (configuration skipped)."
fi

