#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status

LOGFILE="$HOME/setup_log.txt"
CHEATSHEET="$HOME/dev_environment_cheatsheet.md"
exec > >(while read line; do echo "$(date '+[%Y-%m-%d %H:%M:%S]') $line"; done | tee -a "$LOGFILE") 2>&1

# Cleanup function for failed installations
cleanup() {
  echo "Installation interrupted. Cleaning up..."
  # Cleanup code here
  exit 1
}
trap cleanup INT TERM

# Create backup of existing configuration files
backup_configs() {
  local timestamp=$(date +%Y%m%d%H%M%S)
  [ -f "$HOME/.zshrc" ] && cp "$HOME/.zshrc" "$HOME/.zshrc.backup-$timestamp"
  [ -f "$HOME/.tmux.conf" ] && cp "$HOME/.tmux.conf" "$HOME/.tmux.conf.backup-$timestamp"
  [ -f "$HOME/.gitconfig" ] && cp "$HOME/.gitconfig" "$HOME/.gitconfig.backup-$timestamp"
  echo "Created backups of existing configuration files with timestamp: $timestamp"
}

# System detection
SYSTEM_ARCH=$(uname -m)
if [[ "$SYSTEM_ARCH" == "arm64" ]]; then
  echo "Running on Apple Silicon (ARM64)"
  IS_ARM=true
else
  echo "Running on Intel architecture"
  IS_ARM=false
fi

# Check Internet Connection
check_internet() {
  if ! ping -c 1 google.com &>/dev/null; then
    echo "No internet connection detected. Please check your network and try again."
    exit 1
  fi
  echo "Internet connection confirmed."
}

# Install Xcode Command Line Tools
install_xcode_tools() {
  if ! xcode-select -p &>/dev/null; then
    echo "Installing Xcode Command Line Tools..."
    xcode-select --install
    echo "Please wait for Xcode Command Line Tools to finish installing, then press any key to continue..."
    read -n 1
  else
    echo "Xcode Command Line Tools already installed."
  fi
}

# Create GitHub directory in home folder
setup_github_dir() {
  GITHUB_DIR="$HOME/github"
  if [ ! -d "$GITHUB_DIR" ]; then
    echo "Creating GitHub directory at $GITHUB_DIR..."
    mkdir -p "$GITHUB_DIR"
    echo "GitHub directory created successfully."
  else
    echo "GitHub directory already exists at $GITHUB_DIR, skipping..."
  fi
}

# Install Homebrew if not installed
install_homebrew() {
  if ! command -v brew &>/dev/null; then
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # Add homebrew to PATH based on architecture
    if [[ "$IS_ARM" == true ]]; then
      echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> $HOME/.zprofile
      eval "$(/opt/homebrew/bin/brew shellenv)"
    else
      echo 'eval "$(/usr/local/bin/brew shellenv)"' >> $HOME/.zprofile
      eval "$(/usr/local/bin/brew shellenv)"
    fi
  else
    echo "Homebrew already installed."
  fi
}

# Performance optimization for Homebrew
optimize_homebrew() {
  # Update Homebrew first
  brew update
  
  # Add parallel downloads for Homebrew
  export HOMEBREW_NO_AUTO_UPDATE=1
  export HOMEBREW_NO_INSTALL_CLEANUP=1
  export HOMEBREW_INSTALL_BADGE="🍺"
  export HOMEBREW_CASK_OPTS="--no-quarantine"
  
  # Increase parallelism for formula building
  if [ "$IS_ARM" = true ]; then
    PARALLEL_JOBS=$(sysctl -n hw.ncpu)
    echo "export HOMEBREW_MAKE_JOBS=$PARALLEL_JOBS" >> $HOME/.zprofile
  fi
}

install_with_retry() {
  local cmd="$1"
  local retries=3
  local count=0

  until $cmd; do
    count=$((count + 1))
    if [ "$count" -ge "$retries" ]; then
      echo "Failed to install after $retries attempts: $cmd"
      return 1
    fi
    echo "Retrying ($count/$retries)..."
    sleep 2
  done
}

install_brew_package() {
  local package="$1"
  local retries=3
  local count=0

  while [ "$count" -lt "$retries" ]; do
    if brew list "$package" &>/dev/null; then
      echo "$package is already installed, skipping."
      return 0
    fi

    echo "Installing $package (attempt $((count + 1))/$retries)..."
    if brew install "$package"; then
      echo "Successfully installed $package."
      return 0
    else
      # Check if the error message is about an existing app, and skip it
      if brew install "$package" 2>&1 | grep -q "It seems there is already an App at"; then
        echo "Package $package already installed (App already exists), skipping."
        return 0
      fi

      echo "Failed to install $package, retrying..."
      count=$((count + 1))
      sleep 1
    fi
  done

  echo "ERROR: Failed to install $package after $retries attempts." | tee -a "$LOGFILE"
  return 0
}

# Install required packages
install_brew_packages() {
  # Install GNU parallel for faster package installation
  install_brew_package "parallel"
  
  BREW_PACKAGES=(
    python uv go rust node npm minio mosquitto postgresql sqlite 
    ripgrep neovim navi bat zoxide fzf tmux watchexec chatgpt vips
    pyenv julia gcc zig git gh ffmpeg cmake nmap netcat tcpdump libtool autoconf
    wireshark duf entr exiftool fdupes hyperfine just jq procs rsync speedtest-cli 
    rclone httpie lazygit ngrok asciinema lazydocker zsh-syntax-highlighting 
    zsh-autosuggestions copilot 1password-cli pgcli mycli awscli 
    google-cloud-sdk cloudflare-warp fnm abseil powerlevel10k pv
    starship atuin git-delta lsd direnv gpg gnupg pinentry-mac
    bun htop tldr kubernetes-cli terraform ansible docker-compose
  )

  echo "Installing Homebrew packages..."
  
  # Use parallel for package installation if available
  if command -v parallel &>/dev/null; then
    # Export the install function to be used with parallel
    export -f install_brew_package
    echo "${BREW_PACKAGES[@]}" | parallel -j 4 install_brew_package
  else
    for package in "${BREW_PACKAGES[@]}"; do
      install_brew_package "$package"
    done
  fi
  
  export CXXFLAGS="-I$(brew --prefix abseil)/include"
}

# Install VS Code if requested
install_vscode() {
  if ! command -v code &>/dev/null; then
    echo "Installing Visual Studio Code..."
    brew install --cask visual-studio-code
    
    # Install popular VS Code extensions
    VS_CODE_EXTENSIONS=(
      "ms-vscode.cpptools"
      "ms-python.python"
      "esbenp.prettier-vscode"
      "dbaeumer.vscode-eslint"
      "ritwickdey.LiveServer"
      "GitHub.copilot"
      "ms-azuretools.vscode-docker"
      "ms-vscode-remote.remote-containers"
      "ms-vsliveshare.vsliveshare"
      "redhat.vscode-yaml"
      "rust-lang.rust-analyzer"
    )
    
    for extension in "${VS_CODE_EXTENSIONS[@]}"; do
      echo "Installing VS Code extension: $extension"
      code --install-extension "$extension" || echo "Failed to install VS Code extension: $extension" | tee -a "$LOGFILE"
    done
  else
    echo "Visual Studio Code already installed, skipping..."
  fi
}

# Install Docker and Docker-related tools
install_docker() {
  if ! command -v docker &>/dev/null; then
    echo "Installing Docker..."
    brew install --cask docker
    
    # Install Docker Compose if not already through Docker Desktop
    if ! command -v docker-compose &>/dev/null; then
      brew install docker-compose
    fi
    
    echo "Docker installed. You'll need to open Docker Desktop manually to complete the installation."
  else
    echo "Docker already installed, skipping."
  fi
}

# Install npm packages
install_npm_packages() {
  NPM_PACKAGES=(
    typescript react svelte next express tauri
    nodemon concurrently dotenv rimraf cross-env http-server prettier 
    eslint husky lint-staged tailwindcss postcss sass styled-components 
    axios node-fetch graphql apollo-server cors mongoose sequelize pg 
    sqlite3 redis bcrypt jsonwebtoken passport helmet socket.io ws mqtt 
    jest mocha chai supertest cypress commander yargs chalk figlet ora 
    webpack vite parcel pm2 @tensorflow/tfjs-node natural uuid moment 
    date-fns lodash underscore rxjs
  )

  echo "Installing npm packages..."
  install_npm_package() {
    local package="$1"
    if npm list -g "$package" &>/dev/null; then
      echo "$package is already installed, skipping."
    else
      echo "Installing $package..."
      npm install -g "$package" || echo "ERROR: Failed to install $package" | tee -a "$LOGFILE"
    fi
  }

  for package in "${NPM_PACKAGES[@]}"; do
    install_npm_package "$package"
  done
}

# Set up Python environment
setup_python() {
  # Create a global virtual environment if it doesn't already exist
  VENV_DIR="$HOME/.global_venv"

  if [ ! -d "$VENV_DIR" ]; then
    echo "Creating a global virtual environment..."
    python3 -m venv "$VENV_DIR"
  else
    echo "Global virtual environment already exists."
  fi

  # Activate the global virtual environment
  source "$VENV_DIR/bin/activate"

  # Upgrade pip in the virtual environment
  pip install --upgrade pip

  # Install Python packages in parallel
  PYTHON_PACKAGES=(
    polars pandas numpy matplotlib scipy scikit-learn flask 
    pyqt6 rich scrapy seaborn statsmodels fire requests httpx beautifulsoup4 
    lxml websockets dask plotly xgboost lightgbm torch pyspark modin 
    pyarrow typer click loguru tqdm pytest flake8 mypy black 
    pyjwt cryptography paramiko joblib cython numba boto3 certifi 
    virtualenv urllib3 openpyxl
  )

  # Install Python packages globally
  install_python_package() {
    local package="$1"
    local retries=3
    local count=0

    while [ "$count" -lt "$retries" ]; do
      echo "Installing $package (attempt $((count + 1))/$retries)..."
      if pip install "$package" --upgrade --no-cache-dir; then
        echo "Successfully installed $package."
        return 0
      else
        echo "Failed to install $package, retrying..."
        count=$((count + 1))
        sleep 1
      fi
    done

    echo "ERROR: Failed to install $package after $retries attempts." | tee -a "$LOGFILE"
    return 0
  }

  for package in "${PYTHON_PACKAGES[@]}"; do
    install_python_package "$package"
  done
}

# Install Rust crates
install_rust_crates() {
  RUST_CRATES=(
    exa 
  )

  echo "Installing Rust crates..."
  install_rust_crate() {
    local crate="$1"
    if cargo install --list | grep -q "$crate"; then
      echo "$crate is already installed, skipping."
    else
      echo "Installing $crate..."
      cargo install "$crate" || echo "ERROR: Failed to install $crate" | tee -a "$LOGFILE"
    fi
  }

  for crate in "${RUST_CRATES[@]}"; do
    install_rust_crate "$crate"
  done
}

# Install Go packages
install_go_packages() {
  # Install a Go package with retry logic
  install_go_package() {
    local go_package="$1"
    local retries=3
    local count=0

    while [ "$count" -lt "$retries" ]; do
      echo "Installing $go_package (attempt $((count + 1))/$retries)..."
      if go install "$go_package"; then
        echo "Successfully installed $go_package."
        return 0
      else
        echo "Failed to install $go_package, retrying..."
        count=$((count + 1))
        sleep 5
      fi
    done

    echo "ERROR: Failed to install $go_package after $retries attempts." | tee -a "$LOGFILE"
    return 1
  }

  # Declare Go packages array
  GO_PACKAGES=(
    "github.com/chand1012/git2gpt@latest"
  )
  
  for package in "${GO_PACKAGES[@]}"; do
    install_go_package "$package"
  done
}

# Configure git properly
configure_git() {
  # Only prompt if git isn't configured yet
  if ! git config --global user.name >/dev/null 2>&1; then
    read -p "Enter your Git name: " git_name
    git config --global user.name "$git_name"
  else
    echo "Git user.name already configured: $(git config --global user.name)"
  fi
  
  if ! git config --global user.email >/dev/null 2>&1; then
    read -p "Enter your Git email: " git_email
    git config --global user.email "$git_email"
  else
    echo "Git user.email already configured: $(git config --global user.email)"
  fi
  
  # Set better git defaults
  git config --global init.defaultBranch main
  git config --global pull.rebase true
  git config --global core.editor "nvim"
  git config --global core.autocrlf input
  git config --global push.autoSetupRemote true
  
  # Configure git delta for better diffs
  git config --global core.pager "delta"
  git config --global interactive.diffFilter "delta --color-only"
  git config --global delta.navigate true
  git config --global delta.side-by-side true
  git config --global delta.line-numbers true
}

# Install Oh My Zsh
install_ohmyzsh() {
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "Installing Oh My Zsh..."
    # Using the -y flag to automatically accept and not hang on the prompt
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    echo "Oh My Zsh installed successfully."
  else
    echo "Oh My Zsh is already installed, skipping..."
  fi
}

# Configure ZSH with plugins and options
configure_zsh() {
  # Backup existing zshrc if it exists
  if [ -f "$HOME/.zshrc" ]; then
    cp "$HOME/.zshrc" "$HOME/.zshrc.backup-$(date +%Y%m%d%H%M%S)"
  fi
  
  # Create a new .zshrc with better defaults
  cat << 'EOF' > "$HOME/.zshrc"
# Path to your oh-my-zsh installation
export ZSH="$HOME/.oh-my-zsh"

# Set powerlevel10k theme
ZSH_THEME="powerlevel10k/powerlevel10k"

# Enable powerlevel10k instant prompt
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Enable plugins
plugins=(
  git
  zsh-autosuggestions
  zsh-syntax-highlighting
  docker
  docker-compose
  npm
  node
  python
  pip
  golang
  rust
  fzf
  tmux
  gh
)

source $ZSH/oh-my-zsh.sh

# Configure zoxide
eval "$(zoxide init zsh)"

# Configure starship prompt (if not using p10k)
# eval "$(starship init zsh)"

# Configure direnv
eval "$(direnv hook zsh)"

# Configure atuin shell history
eval "$(atuin init zsh)"

# Add aliases
alias ls="lsd"
alias ll="lsd -la"
alias cat="bat"
alias vim="nvim"
alias python="python3"
alias pip="pip3"
alias k="kubectl"
alias tf="terraform"

# FZF integration
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# Source p10k config file
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
EOF

  # Setup p10k configuration
  if [ ! -f "$HOME/.p10k.zsh" ]; then
    curl -fsSL -o "$HOME/.p10k.zsh" https://raw.githubusercontent.com/romkatv/powerlevel10k/master/config/p10k-lean.zsh
  fi

  echo "ZSH configuration created at ~/.zshrc with powerlevel10k theme"
}

# Install Oh My Tmux
install_ohmytmux() {
  if [ ! -d "$HOME/.tmux" ]; then
    echo "Installing Oh My Tmux from your fork..."
    git clone https://github.com/bearlyachemist/.tmux.git "$HOME/.tmux"
    
    # Create config directory if it doesn't exist
    mkdir -p "$HOME/.config/tmux"
    
    # Create symlinks instead of copying
    ln -sf "$HOME/.tmux/.tmux.conf" "$HOME/.tmux.conf"
    ln -sf "$HOME/.tmux/.tmux.conf" "$HOME/.config/tmux/tmux.conf"
    ln -sf "$HOME/.tmux/.tmux.conf.local" "$HOME/.tmux.conf.local"
    ln -sf "$HOME/.tmux/.tmux.conf.local" "$HOME/.config/tmux/tmux.conf.local"
    
    echo "Oh My Tmux installed successfully with symlinks to ~/.config/tmux/."
  else
    echo "Oh My Tmux directory already exists, updating instead..."
    cd "$HOME/.tmux"
    git pull
    
    # Ensure symlinks exist even for updates
    mkdir -p "$HOME/.config/tmux"
    ln -sf "$HOME/.tmux/.tmux.conf" "$HOME/.tmux.conf"
    ln -sf "$HOME/.tmux/.tmux.conf" "$HOME/.config/tmux/tmux.conf"
    ln -sf "$HOME/.tmux/.tmux.conf.local" "$HOME/.tmux.conf.local"
    ln -sf "$HOME/.tmux/.tmux.conf.local" "$HOME/.config/tmux/tmux.conf.local"
    
    cd - > /dev/null
  fi
}

# Clone kickstart.nvim configuration
setup_neovim() {
  CONFIG_NVIM_DIR="$HOME/.config/nvim"
  REPO_DIR="$HOME/github/kickstart.nvim"
  
  mkdir -p "$HOME/.config"
  
  if [ ! -d "$REPO_DIR" ]; then
    echo "Cloning kickstart.nvim to ~/github directory..."
    mkdir -p "$HOME/github"
    git clone https://github.com/bearlyachemist/kickstart.nvim.git "$REPO_DIR"
  else
    echo "kickstart.nvim repository already exists, updating instead..."
    cd "$REPO_DIR"
    git pull
    cd - > /dev/null
  fi
  
  # Create symlink to config directory
  if [ -d "$CONFIG_NVIM_DIR" ] && [ ! -L "$CONFIG_NVIM_DIR" ]; then
    echo "Backing up existing nvim config directory..."
    mv "$CONFIG_NVIM_DIR" "$CONFIG_NVIM_DIR.backup-$(date +%Y%m%d%H%M%S)"
  fi
  
  # Remove existing symlink if it exists but points to the wrong location
  if [ -L "$CONFIG_NVIM_DIR" ] && [ "$(readlink "$CONFIG_NVIM_DIR")" != "$REPO_DIR" ]; then
    rm "$CONFIG_NVIM_DIR"
  fi
  
  # Create symlink if it doesn't exist
  if [ ! -e "$CONFIG_NVIM_DIR" ]; then
    echo "Creating symlink from $REPO_DIR to $CONFIG_NVIM_DIR"
    ln -sf "$REPO_DIR" "$CONFIG_NVIM_DIR"
  fi
  
  echo "Neovim configuration set up with symlink from ~/github/kickstart.nvim to ~/.config/nvim"
}

# Set up SSH key for GitHub
setup_ssh_key() {
  SSH_DIR="$HOME/.ssh"
  GITHUB_KEY="$SSH_DIR/github_ed25519"
  
  # Create SSH directory if it doesn't exist
  if [ ! -d "$SSH_DIR" ]; then
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"
  fi
  
  # Check if GitHub key already exists
  if [ -f "$GITHUB_KEY" ]; then
    echo "GitHub SSH key already exists at $GITHUB_KEY, skipping..."
    return 0
  fi
  
  echo "Setting up SSH key for GitHub..."
  
  # Ask for email
  read -p "Enter your GitHub email address: " github_email
  
  # Generate SSH key
  ssh-keygen -t ed25519 -C "$github_email" -f "$GITHUB_KEY" -N ""
  
  # Configure SSH config
  if [ ! -f "$SSH_DIR/config" ]; then
    touch "$SSH_DIR/config"
    chmod 600 "$SSH_DIR/config"
  fi
  
  # Add GitHub configuration to SSH config
  if ! grep -q "Host github.com" "$SSH_DIR/config"; then
    cat << EOF >> "$SSH_DIR/config"
Host github.com
    IdentityFile $GITHUB_KEY
    User git
EOF
  fi
  
  # Start ssh-agent and add key
  eval "$(ssh-agent -s)"
  ssh-add "$GITHUB_KEY"
  
  # Display the public key for copying to GitHub
  echo "Your SSH public key is:"
  cat "$GITHUB_KEY.pub"
  echo ""
  echo "Copy this key to your GitHub account at https://github.com/settings/keys"
  echo "Press any key when you have added the key to GitHub..."
  read -n 1
}

# Add a summary report at the end
summary_report() {
  echo "============== INSTALLATION SUMMARY ==============="
  echo "Log file: $LOGFILE"
  echo "Cheatsheet: $CHEATSHEET"
  if [ -f "$LOGFILE" ]; then
    local errors=$(grep -c "ERROR:" "$LOGFILE")
    echo "Total errors: $errors"
    if [ "$errors" -gt 0 ]; then
      echo "Errors encountered during installation. See $LOGFILE for details."
    else
      echo "All installations completed successfully!"
    fi
  fi
  echo "=================================================="
}

# Main function to run everything in the right order
main() {
  echo "Starting developer environment setup..."
  
  # Create backups
  backup_configs
  
  # Check prerequisites
  check_internet
  install_xcode_tools
  setup_github_dir
  
  # Install and optimize package managers
  install_homebrew
  optimize_homebrew
  
  # Install tools and packages
  install_brew_packages
  install_vscode
  install_docker
  
  # Install and set up shells
  install_ohmyzsh
  install_ohmytmux
  
  # Configure development environment
  setup_neovim
  configure_git
  configure_zsh
  setup_ssh_key
  
  # Install language-specific packages
  setup_python
  install_npm_packages
  install_rust_crates
  install_go_packages
  
  # Create documentation
  create_cheatsheet
  
  # Show summary
  summary_report
  
  echo "Setup completed! You may need to restart your terminal for all changes to take effect."
}

# Run the main function
main
