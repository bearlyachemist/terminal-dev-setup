#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status

LOGFILE="$HOME/setup_log.txt"
CHEATSHEET="$HOME/dev_environment_cheatsheet.md"
exec > >(while read line; do echo "$(date '+[%Y-%m-%d %H:%M:%S]') $line"; done | tee -a "$LOGFILE") 2>&1

SKIP_BREW=false
SKIP_PYTHON=false
SKIP_NODE=false
ORIGINAL_ARGS="$@"
echo "Original arguments: $ORIGINAL_ARGS"

# Try a more direct approach to set the flag
for arg in "$@"; do
  if [ "$arg" = "--skip-brew" ]; then
    echo "Found --skip-brew argument"
    export SKIP_BREW=true
  fi
done
# Parse command line arguments FIRST, before any function definitions or executions
while [[ $# -gt 0 ]]; do
  case $1 in
    --skip-brew)
      SKIP_BREW=true
      shift
      ;;
    --skip-python)
      SKIP_PYTHON=true
      shift
      ;;
    --skip-node)
      SKIP_NODE=true
      shift
      ;;
    --help)
      echo "Usage: setup.sh [OPTIONS]"
      echo "Options:"
      echo "  --skip-brew      Skip Homebrew installation and related packages"
      echo "  --skip-python    Skip Python setup and package installation"
      echo "  --skip-node      Skip Node.js and npm package installation"
      echo "  --help           Display this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for available options"
      exit 1
      ;;
  esac
done

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
    mkdir -p "$GITHUB_DIR" 2>/dev/null || true
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
      # Add to both .zprofile and .zshrc for maximum compatibility
      echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> $HOME/.zprofile
      echo 'export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"' >> $HOME/.zshrc
      eval "$(/opt/homebrew/bin/brew shellenv)"
    else
      # Add to both .zprofile and .zshrc for maximum compatibility
      echo 'eval "$(/usr/local/bin/brew shellenv)"' >> $HOME/.zprofile
      echo 'export PATH="/usr/local/bin:/usr/local/sbin:$PATH"' >> $HOME/.zshrc
      eval "$(/usr/local/bin/brew shellenv)"
    fi
    
    # Source both profile files to apply changes immediately
    if [[ -f "$HOME/.zprofile" ]]; then
      source "$HOME/.zprofile"
    fi
    
    if [[ -f "$HOME/.zshrc" ]]; then
      source "$HOME/.zshrc"
    fi
    
    # Verify Homebrew installation
    if command -v brew &>/dev/null; then
      echo "Homebrew installation verified."
    else
      echo "Homebrew installation could not be verified. PATH may not be set correctly."
      echo "Current PATH: $PATH"
      
      # Try a direct execution as a fallback
      if [[ "$IS_ARM" == true ]] && [[ -f "/opt/homebrew/bin/brew" ]]; then
        echo "Attempting to use direct path to brew..."
        /opt/homebrew/bin/brew --version
        # Add direct path to PATH as a last resort
        export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
      elif [[ -f "/usr/local/bin/brew" ]]; then
        echo "Attempting to use direct path to brew..."
        /usr/local/bin/brew --version
        # Add direct path to PATH as a last resort
        export PATH="/usr/local/bin:/usr/local/sbin:$PATH"
      else
        echo "ERROR: Could not find brew executable. Installation may have failed."
        return 1
      fi
    fi
  else
    echo "Homebrew already installed."
  fi
}

# Performance optimization for Homebrew
optimize_homebrew() {

  fix_homebrew_permissions
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

# Fix Homebrew permissions
fix_homebrew_permissions() {

  if command -v brew &>/dev/null; then
    BREW_PREFIX=$(brew --prefix 2>/dev/null || echo "/opt/homebrew")
  else
    # Default paths based on architecture
    if [[ "$IS_ARM" == true ]]; then
      BREW_PREFIX="/opt/homebrew"
    else
      BREW_PREFIX="/usr/local"
    fi
  fi
  
  echo "Checking Homebrew permissions for $BREW_PREFIX..."
  if [ ! -w "$BREW_PREFIX" ]; then
    echo "Warning: $BREW_PREFIX is not writable. Fixing permissions..."
    sudo chown -R $(whoami):admin "$BREW_PREFIX"
    sudo chmod -R 755 "$BREW_PREFIX"
    echo "Permissions fixed for $BREW_PREFIX"
  else
    echo "Homebrew permissions look good."
  fi
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
  
  # Programming Languages & Runtime Environments
  BREW_LANG_PACKAGES=(
    python
    uv
    pyenv
    julia
    go
    rust
    node
    npm
    gcc
    zig
    llvm
    lua
    elixir
    erlang
    ocaml
  )

  # Databases & Data Storage
  BREW_DB_PACKAGES=(
    postgresql
    sqlite
    minio
  )

  # Development Tools & Utilities
  BREW_DEV_TOOLS=(
    git
    gh
    lazygit
    git-delta
    cmake
    ripgrep
    fzf
    watchexec
    ffmpeg
    libtool
    autoconf
    entr
    just
    jq
    procs
    httpie
    ngrok
    direnv
    starship
    atuin
    lsd
    duf
  )

  # Terminal & Shell Enhancements
  BREW_SHELL_TOOLS=(
    tmux
    neovim
    navi
    bat
    zoxide
    zsh-syntax-highlighting
    zsh-autosuggestions
    powerlevel10k
    pv
    htop
    tldr
  )

  # AI & Productivity Tools
  BREW_AI_TOOLS=(
    chatgpt
    copilot
    ollama
  )

  # Network & Security Tools
  BREW_NET_TOOLS=(
    nmap
    netcat
    tcpdump
    wireshark
    speedtest-cli
    rclone
    cloudflare-warp
    gpg
    gnupg
    pinentry-mac
  )

  # Cloud & DevOps Tools
  BREW_CLOUD_DEVOPS=(
    awscli
    google-cloud-sdk
    kubernetes-cli
    docker-compose
    lazydocker
    1password-cli
  )

  # Messaging & IoT
  BREW_MESSAGING=(
    mosquitto
  )

  # Scientific & Data Analysis
  BREW_SCIENTIFIC=(
    jupyterlab
  )

  # Image & Media Processing
  BREW_MEDIA=(
    exiftool
    fdupes
    asciinema
  )

  # Miscellaneous Utilities
  BREW_MISC=(
    hyperfine
    rsync
    fnm
    abseil
    graphqurl
  )

  BREW_FONTS=(
    font-jetbrains-mono-nerd-font
    font-fira-code-nerd-font
  )

  # Combine all package groups
  BREW_PACKAGES=(
    "${BREW_LANG_PACKAGES[@]}"
    "${BREW_DB_PACKAGES[@]}"
    "${BREW_DEV_TOOLS[@]}"
    "${BREW_SHELL_TOOLS[@]}"
    "${BREW_AI_TOOLS[@]}"
    "${BREW_NET_TOOLS[@]}"
    "${BREW_CLOUD_DEVOPS[@]}"
    "${BREW_DB_CLIENTS[@]}"
    "${BREW_MESSAGING[@]}"
    "${BREW_SCIENTIFIC[@]}"
    "${BREW_MEDIA[@]}"
    "${BREW_MISC[@]}"
    "${BREW_FONTS[@]}"
  )

  echo "Installing Homebrew packages..."
  
  # Use parallel for package installation if available
  if command -v parallel &>/dev/null; then
    # Export the install function to be used with parallel
    export -f install_brew_package
    printf "%s\n" "${BREW_PACKAGES[@]}" | parallel -j 4 install_brew_package
  else
    for package in "${BREW_PACKAGES[@]}"; do
      install_brew_package "$package"
    done
  fi
  
  export CXXFLAGS="-I$(brew --prefix abseil)/include"
}

install_zsh_plugins() {
  echo "Installing missing oh-my-zsh plugins and themes..."
  
  # Create custom plugins and themes directories if they don't exist
  mkdir -p "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins"
  mkdir -p "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes"
  
  # Install zsh-autosuggestions
  if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions" ]; then
    echo "Installing zsh-autosuggestions plugin..."
    git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
  else
    echo "zsh-autosuggestions already installed"
  fi
  
  # Install zsh-syntax-highlighting
  if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting" ]; then
    echo "Installing zsh-syntax-highlighting plugin..."
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
  else
    echo "zsh-syntax-highlighting already installed"
  fi
  
  # Install powerlevel10k theme
  if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k" ]; then
    echo "Installing powerlevel10k theme..."
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
  else
    echo "powerlevel10k already installed"
  fi
  
  echo "oh-my-zsh plugins and themes installed successfully"
}

# Install VS Code if requested
install_vscode() {
  if command -v code &>/dev/null || [ -d "/Applications/Visual Studio Code.app" ]; then
    echo "Visual Studio Code already installed, skipping installation..."
    
    # Add VS Code to PATH if it's not already there
    if ! command -v code &>/dev/null && [ -d "/Applications/Visual Studio Code.app" ]; then
      echo "VS Code found in Applications but 'code' command not in PATH. Adding command to PATH..."
      
      # Create symlink to VS Code in /usr/local/bin
      if [ ! -L "/usr/local/bin/code" ]; then
        # Create the bin directory if it doesn't exist
        if [ ! -d "/usr/local/bin" ]; then
          sudo mkdir -p /usr/local/bin
        fi
        
        # Add symlink to code command
        sudo ln -s "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" "/usr/local/bin/code"
        echo "Added 'code' command to PATH via symlink."
      fi
    fi
    
    # Install extensions if VS Code is now available
    if command -v code &>/dev/null; then
      echo "Installing VS Code extensions..."
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
      echo "VS Code command still not found in PATH after symlinking. You may need to restart your terminal."
    fi
  else
    echo "Installing Visual Studio Code..."
    
    # Use --no-quarantine to avoid Gatekeeper issues
    if ! brew install --cask --no-quarantine visual-studio-code; then
      echo "Warning: Failed to install VS Code via Homebrew. VS Code may already exist or installation failed."
    else
      echo "Visual Studio Code installed successfully."
    fi
    
    # Install extensions if VS Code is now available
    if command -v code &>/dev/null; then
      echo "Installing VS Code extensions..."
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
      echo "Adding 'code' command to PATH..."
      
      # Create symlink to VS Code in /usr/local/bin
      if [ -d "/Applications/Visual Studio Code.app" ] && [ ! -L "/usr/local/bin/code" ]; then
        # Create the bin directory if it doesn't exist
        if [ ! -d "/usr/local/bin" ]; then
          sudo mkdir -p /usr/local/bin
        fi
        
        # Add symlink to code command
        sudo ln -s "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" "/usr/local/bin/code"
        echo "Added 'code' command to PATH via symlink."
        
        # Now try to install extensions again
        if command -v code &>/dev/null; then
          echo "Installing VS Code extensions now that 'code' is in PATH..."
          for extension in "${VS_CODE_EXTENSIONS[@]}"; do
            echo "Installing VS Code extension: $extension"
            code --install-extension "$extension" || echo "Failed to install VS Code extension: $extension" | tee -a "$LOGFILE"
          done
        else
          echo "VS Code command still not found in PATH. You may need to restart your terminal before installing extensions."
        fi
      else
        echo "VS Code application not found after installation or symlinking failed."
      fi
    fi
  fi
}

# Install Docker and Docker-related tools
install_docker() {
  if command -v docker &>/dev/null || [ -d "/Applications/Docker.app" ]; then
    echo "Docker already installed, skipping."
  else
    echo "Installing Docker..."
    # Use --no-quarantine to avoid Gatekeeper issues
    if ! brew install --cask --no-quarantine docker; then
      echo "Warning: Failed to install Docker via Homebrew. Docker may already exist or installation failed."
    else
      echo "Docker installed. You'll need to open Docker Desktop manually to complete the installation."
    fi
    
    # Install Docker Compose if not already through Docker Desktop
    if ! command -v docker-compose &>/dev/null; then
      brew install docker-compose || echo "Failed to install docker-compose. Continuing anyway..."
    fi
  fi
}

# Install npm packages
install_npm_packages() {
  # Web Frameworks & Libraries
  NPM_WEB_FRAMEWORKS=(
    typescript
    react
    svelte
    next
    express
    tauri
    tailwindcss
    postcss
    sass
    styled-components
  )

  # Development Utilities
  NPM_DEV_UTILS=(
    nodemon
    concurrently
    dotenv
    rimraf
    cross-env
    http-server
    prettier
    eslint
    husky
    lint-staged
    webpack
    vite
    parcel
    pm2
  )

  # API & Data Libraries
  NPM_API_DATA=(
    axios
    node-fetch
    graphql
    apollo-server
    cors
    mongoose
    sequelize
    pg
    sqlite3
    redis
  )

  # Authentication & Security
  NPM_AUTH_SECURITY=(
    bcrypt
    jsonwebtoken
    passport
    helmet
  )

  # Communication & Networking
  NPM_COMMUNICATION=(
    socket.io
    ws
    mqtt
  )

  # Testing Tools
  NPM_TESTING=(
    jest
    mocha
    chai
    supertest
    cypress
  )

  # CLI & Terminal Tools
  NPM_CLI_TOOLS=(
    commander
    yargs
    chalk
    figlet
    ora
  )

  # Utilities & Helper Libraries
  NPM_UTILS=(
    uuid
    moment
    date-fns
    lodash
    underscore
    rxjs
  )

  # AI & Machine Learning
  NPM_AI_ML=(
    "@tensorflow/tfjs-node"
    "natural"
  )

  # Combine all npm package groups
  NPM_PACKAGES=(
    "${NPM_WEB_FRAMEWORKS[@]}"
    "${NPM_DEV_UTILS[@]}"
    "${NPM_API_DATA[@]}"
    "${NPM_AUTH_SECURITY[@]}"
    "${NPM_COMMUNICATION[@]}"
    "${NPM_TESTING[@]}"
    "${NPM_CLI_TOOLS[@]}"
    "${NPM_UTILS[@]}"
    "${NPM_AI_ML[@]}"
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
  echo "Upgrading pip..."
  pip install --upgrade pip || echo "Failed to upgrade pip, continuing anyway..."

  # Install a smaller, essential set of Python packages to reduce chances of errors
  ESSENTIAL_PACKAGES=(
    numpy
    pandas
    matplotlib
    requests
    pytest
    black
  )

  # Install Python packages only if they're not already installed
  install_python_package() {
    local package="$1"
    
    echo "Checking $package..."
    
    # Check if the package is already installed
    if pip list | grep -i "^$package " >/dev/null 2>&1; then
      echo "$package is already installed, skipping."
      return 0
    fi
    
    echo "Installing $package..."
    if pip install "$package" --no-cache-dir; then
      echo "Successfully installed $package."
    else
      echo "WARNING: Failed to install $package. Continuing..." | tee -a "$LOGFILE"
    fi
    return 0
  }

  echo "Installing essential Python packages..."
  for package in "${ESSENTIAL_PACKAGES[@]}"; do
    install_python_package "$package"
  done

  # Deactivate the virtual environment
  deactivate

  echo "Python environment setup completed with essential packages."
  echo "To install additional packages later, activate the environment with:"
  echo "source $VENV_DIR/bin/activate"
  echo "Then run: pip install <package_name>"
  
  echo "If you encounter permission issues, run:"
  echo "sudo chown -R $(whoami) $VENV_DIR"
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

# Set up global gitignore
setup_global_gitignore() {
  echo "Setting up global gitignore file..."
  
  cat << 'EOF' > "$HOME/.gitignore_global"
# macOS
.DS_Store
.AppleDouble
.LSOverride
._*

# Node
node_modules/
npm-debug.log
yarn-error.log
.pnp.*
.yarn/*
!.yarn/patches
!.yarn/plugins
!.yarn/releases
!.yarn/sdks
!.yarn/versions

# Python
__pycache__/
*.py[cod]
*$py.class
.pytest_cache/
.coverage
htmlcov/
.tox/
.nox/
.hypothesis/
.venv/
venv/
ENV/

# Editor directories and files
.idea/
.vscode/
*.sublime-project
*.sublime-workspace
*.swp
*.swo
*~

# Environment
.env
.env.local
.env.development.local
.env.test.local
.env.production.local

# Logs
logs
*.log
npm-debug.log*
yarn-debug.log*
yarn-error.log*

# Build directories
/dist
/build
/out
EOF

  # Configure git to use this global gitignore file
  git config --global core.excludesfile "$HOME/.gitignore_global"
  
  echo "Global gitignore set up at $HOME/.gitignore_global"
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

# configure_zsh() function with added aliases and functions
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

# =============================================================================
# Custom Aliases and Functions
# =============================================================================

# Navigation and file management
alias zz="z -"                          # Quick jump back
alias j="z"                             # Shorter z command
alias ..="cd .."                        # Go up one directory
alias ...="cd ../.."                    # Go up two directories
alias ls="lsd"                          # Use lsd instead of ls
alias ll="lsd -la"                      # List all files with details
alias lt="lsd --tree"                   # Show directory tree
alias cat="bat"                         # Use bat instead of cat

# Git shortcuts
alias g="git"
alias ga="git add"
alias gc="git commit -m"
alias gp="git push"
alias gl="git pull"
alias gs="git status"
alias gd="git diff"
alias gb="git branch"
alias gco="git checkout"
alias lg="lazygit"
alias gundo="git reset --soft HEAD~1"      # Undo last commit but keep changes
alias gamend="git commit --amend --no-edit" # Amend last commit without editing message
alias grb="git rebase -i"                  # Interactive rebase
alias gsave="git stash save"               # Stash changes with message
alias gpop="git stash pop"                 # Apply and remove stashed changes
alias gclean="git clean -fd"               # Remove untracked files and directories

# Development workflow
alias nv="nvim"
alias vi="nvim"
alias vim="nvim"
alias tm="tmux"
alias tnew="tmux new -s"
alias tattach="tmux attach -t"
alias tlist="tmux list-sessions"
alias tks="tmux kill-session -t"       # Kill specific tmux session
alias tka="tmux kill-server"           # Kill all tmux sessions
alias nvs="nvim -S Session.vim"        # Open neovim with session

# Terminal workflow enhancements
alias c="clear"
alias his="atuin search"               # Better history search with atuin
alias reload="source ~/.zshrc"         # Reload zsh config
alias zshrc="nvim ~/.zshrc"            # Edit zshrc
alias vimrc="nvim ~/.config/nvim/init.lua" # Edit neovim config
alias tmuxconf="nvim ~/.tmux.conf"     # Edit tmux config
alias gitconfig="nvim ~/.gitconfig"    # Edit git config

# Project navigation shortcuts
alias dev="cd ~/Development"           # Quick jump to dev folder
alias dots="cd ~/.dotfiles"            # Quick jump to dotfiles

# Python environment
alias py="python"
alias ipy="ipython"
alias jl="jupyter lab"
alias uvenv="uv venv"
alias uvact="source .venv/bin/activate"
alias pir="pip install -r requirements.txt"
alias pipup="pip install --upgrade pip"

# Docker and k8s
alias dk="docker"
alias dkps="docker ps"
alias dkc="docker-compose"
alias k="kubectl"
alias lzd="lazydocker"
alias dcu="docker-compose up -d"
alias dcd="docker-compose down"
alias dcl="docker-compose logs -f"

# Database
alias pg="pgcli"
alias pgstart="brew services start postgresql"
alias pgstop="brew services stop postgresql"

# Network tools
alias myip="curl ifconfig.me"
alias ping="ping -c 5"
alias ns="speedtest-cli"
alias http="httpie"

# Cloud and Terraform
alias tf="terraform"
alias aws="awscli"
alias gcp="gcloud"
alias tfi="terraform init"
alias tfp="terraform plan"
alias tfa="terraform apply"
alias tfd="terraform destroy"
alias tfo="terraform output"

# Just command shortcuts
alias j="just"                         # Shorter just command
alias jl="just --list"                 # List available just recipes

# Enhanced ripgrep and fuzzy finding
alias rg="rg --smart-case"             # Case-insensitive if pattern is lowercase
alias fz="fzf --preview 'bat --color=always {}'"  # File preview with fzf
alias rgz="rg --color=always --line-number . | fzf --ansi" # Ripgrep with fzf

# Process management
alias psa="procs"                      # Better process list with procs
alias psg="procs | grep"               # Search for process

# GitHub CLI shortcuts
alias ghi="gh issue"                   # GitHub issues
alias ghpr="gh pr"                     # GitHub pull requests

# JQ formatting shortcuts
alias jqp="jq '.'"                     # Pretty-print JSON
alias jqc="jq -c '.'"                  # Compact JSON

# Node.js version management with fnm
alias nv="fnm use"                     # Use specific Node.js version
alias nl="fnm list"                    # List installed Node.js versions

# Misc utils
alias h="history | grep"
alias duc="duf"                         # Check disk usage
alias path="echo $PATH | tr ':' '\n'"   # Display path in readable format
alias hf="hyperfine"                    # Benchmarking
alias serve="python -m http.server"     # Quick HTTP server
alias watch="watchexec -c"              # Clear screen between runs

# Ollama shortcuts
alias oll="ollama run"
alias ollls="ollama list"
alias ollrm="ollama rm"

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

# Quick directory creation and navigation
mkcd() { mkdir -p "$1" && cd "$1"; }

# Extract various archive formats
extract() {
  if [ -f $1 ]; then
    case $1 in
      *.tar.bz2)   tar xjf $1     ;;
      *.tar.gz)    tar xzf $1     ;;
      *.bz2)       bunzip2 $1     ;;
      *.rar)       unrar e $1     ;;
      *.gz)        gunzip $1      ;;
      *.tar)       tar xf $1      ;;
      *.tbz2)      tar xjf $1     ;;
      *.tgz)       tar xzf $1     ;;
      *.zip)       unzip $1       ;;
      *.Z)         uncompress $1  ;;
      *.7z)        7z x $1        ;;
      *)           echo "'$1' cannot be extracted" ;;
    esac
  else
    echo "'$1' is not a valid file"
  fi
}

# Git commit and push in one command
gitcp() {
  git add .
  git commit -m "$1"
  git push
}

# Create python venv and activate it
pvenv() {
  uv venv .venv
  source .venv/bin/activate
}

# Python virtual environment helpers
venv_create() {
  local env_name=${1:-.venv}
  uv venv "$env_name" && source "$env_name/bin/activate"
}

venv_activate() {
  local env_paths=(".venv" "venv" "env")
  for env_path in "${env_paths[@]}"; do
    if [ -d "$env_path" ]; then
      source "$env_path/bin/activate"
      echo "Activated $env_path"
      return 0
    fi
  done
  echo "No virtual environment found"
  return 1
}

# Search and replace in all files
gsed() {
  if [ "$#" -ne 2 ]; then
    echo "Usage: gsed 'search' 'replace'"
    return 1
  fi
  rg "$1" -l | xargs sed -i '' "s/$1/$2/g"
}

# Improved find and replace in project
freplace() {
  if [ "$#" -ne 2 ]; then
    echo "Usage: freplace 'search_pattern' 'replacement'"
    return 1
  fi
  
  local search="$1"
  local replace="$2"
  local files=$(rg -l "$search")
  
  if [ -z "$files" ]; then
    echo "No files contain the pattern: $search"
    return 0
  fi
  
  echo "Files to modify:"
  echo "$files" | sed 's/^/  /'
  echo -n "Proceed with replacement? [y/N] "
  read -r confirm
  
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    echo "$files" | xargs sed -i '' "s|$search|$replace|g"
    echo "Replacement complete."
  else
    echo "Operation cancelled."
  fi
}

# Create a new project directory with git init
newproject() {
  mkdir -p "$1" && cd "$1" || return
  git init
  echo "# $1" > README.md
  touch .gitignore
  echo "Project $1 initialized"
}

# Run command with notification when it completes
notify() {
  "$@"
  # Using a more cross-platform approach
  if command -v osascript &> /dev/null; then
    osascript -e "display notification \"Command completed: $*\" with title \"Terminal\""
  elif command -v notify-send &> /dev/null; then
    notify-send "Terminal" "Command completed: $*"
  else
    echo "\nCommand completed: $*"
  fi
}

# Quickly find and edit a file
fe() {
  local file
  file=$(fzf --preview 'bat --color=always {}')
  [ -n "$file" ] && nvim "$file"
}

# Git browse file on GitHub
gbrowse() {
  local file=${1:-$(git rev-parse --show-toplevel)/$(git rev-parse --show-prefix)}
  gh browse "$file"
}

# Start a clean tmux session with common layout
tdev() {
  local session=${1:-dev}
  tmux new-session -d -s "$session" -n "editor"
  tmux send-keys -t "$session:editor" "nvim" C-m
  tmux new-window -t "$session" -n "terminal"
  tmux new-window -t "$session" -n "server"
  tmux select-window -t "$session:editor"
  tmux attach-session -t "$session"
}

# Add this to your .zshrc or .bashrc file

# IDE-style tmux session setup
tmuxide() {
  local session=${1:-dev}
  local project_dir=${2:-.}
  
  # Check if session already exists
  if tmux has-session -t "$session" 2>/dev/null; then
    echo "Session '$session' already exists. Attaching..."
    tmux attach-session -t "$session"
    return
  fi
  
  # Create a new session with a code editor in the first window
  tmux new-session -d -s "$session" -n "editor" -c "$project_dir"
  
  # Set up the editor window with a main editor pane and a small terminal below
  tmux send-keys -t "$session:editor" "nvim ." C-m
  tmux split-window -v -t "$session:editor" -p 20 -c "$project_dir"
  
  # Create a terminal window for running commands, git, etc.
  tmux new-window -t "$session" -n "terminal" -c "$project_dir"
  
  # Split the terminal window horizontally for multiple command lines
  tmux split-window -h -t "$session:terminal" -c "$project_dir"
  
  # Create a server/output window
  tmux new-window -t "$session" -n "server" -c "$project_dir"
  
  # Create a window for git operations
  tmux new-window -t "$session" -n "git" -c "$project_dir"
  tmux send-keys -t "$session:git" "git status" C-m
  
  # Optional: Create a window for database operations if needed
  # tmux new-window -t "$session" -n "db" -c "$project_dir"
  
  # Select the editor window and the main editor pane
  tmux select-window -t "$session:editor"
  tmux select-pane -t 0
  
  # Attach to the session
  tmux attach-session -t "$session"
}

# More minimal version focused just on editing and terminal
tmuxmin() {
  local session=${1:-min}
  local project_dir=${2:-.}
  
  # Check if session already exists
  if tmux has-session -t "$session" 2>/dev/null; then
    tmux attach-session -t "$session"
    return
  fi
  
  # Create a new session with a split editor/terminal layout
  tmux new-session -d -s "$session" -n "dev" -c "$project_dir"
  
  # Main editor on left (70%)
  tmux send-keys -t "$session:dev" "nvim ." C-m
  
  # Terminal on right (30%)
  tmux split-window -h -p 30 -t "$session:dev" -c "$project_dir"
  
  # Select the editor pane
  tmux select-pane -t 0
  
  # Attach to the session
  tmux attach-session -t "$session"
}

# Docker cleanup
dclean() {
  docker system prune -f
  docker volume prune -f
}

# Run Ollama with specific system prompt
ollama_with_prompt() {
  local model=${1:-mistral}
  shift
  echo "Starting $model with custom prompt..."
  ollama run "$model" "You are a helpful AI assistant. System: $*"
}

# Ollama conversation with memory
ollama_chat() {
  local model=${1:-mistral}
  local chat_file="$HOME/.cache/ollama_chats/$(date +%Y%m%d_%H%M%S)_$model.txt"
  mkdir -p "$(dirname "$chat_file")"
  echo "Starting chat with $model (saved to $chat_file)"
  echo "Chat history will be saved to $chat_file"
  echo "====== Chat Start ======" > "$chat_file"
  while true; do
    echo -n "You: "
    read -r user_input
    if [ "$user_input" = "exit" ]; then
      break
    fi
    echo "You: $user_input" >> "$chat_file"
    echo "AI: " >> "$chat_file"
    echo "AI is thinking..."
    ollama run "$model" "$user_input" | tee -a "$chat_file"
    echo "" >> "$chat_file"
  done
}

# Create a temporary Python environment and install packages
pytmp() {
  local dir=$(mktemp -d)
  cd "$dir" || return
  uv venv .venv
  source .venv/bin/activate
  if [ $# -gt 0 ]; then
    uv pip install "$@"
  fi
  python
  deactivate
  cd - > /dev/null || return
  echo "Temporary environment at $dir"
}

# Quick SSH tunneling
tunnelme() {
  ssh -N -L "$1":localhost:"$1" "$2"  # Usage: tunnelme 8080 user@remote
}

# Kubernetes helpers
kns() { kubectl config set-context --current --namespace="$1"; }  # Switch namespace
kpods() { kubectl get pods -n "${1:-default}"; }                  # Get pods in namespace
klogs() { kubectl logs -f "$1" -n "${2:-default}"; }             # Follow logs for pod

# HTTP API testing
apitest() {
  http "$@" | jq
}

# AWS profile switch
awsp() {
  export AWS_PROFILE="$1"
  echo "AWS Profile set to $AWS_PROFILE"
}

# Directory backup
backup() {
  tar -czf "$(basename "$1")-$(date +%Y%m%d%H%M%S).tar.gz" "$1"
}

# Quick note taking
note() {
  local notes_dir="$HOME/notes"
  mkdir -p "$notes_dir"
  if [ $# -eq 0 ]; then
    nvim "$notes_dir/$(date +%Y-%m-%d).md"
  else
    echo "$(date +"%H:%M") $*" >> "$notes_dir/$(date +%Y-%m-%d).md"
  fi
}

# Quick HTTP file sharing
share_file() {
  local port=${2:-8000}
  python -m http.server "$port" --directory "$(dirname "$1")" &
  local pid=$!
  local filename=$(basename "$1")
  local ip=$(ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -n 1)
  echo "Sharing $filename at http://$ip:$port/$filename"
  echo "Press any key to stop sharing"
  read -r -n 1
  kill $pid
}

# Benchmark command execution time
benchmark() {
  hyperfine --warmup 3 "$@"
}

# Find large files/directories
bigfiles() {
  du -h -x -s -- ./* | sort -rh | head -n "${1:-20}"
}

# Database backups
pgdump() { pg_dump -F c -Z 9 -f "$1.pgdump" "$1"; }
pgrestore() { pg_restore -d "$1" "$2"; }

# The following are system-dependent and may need adjustment
# Clipboard operations - adapt for your system
if command -v pbcopy &> /dev/null; then
  # macOS
  alias clipboard="pbcopy"
  alias clipout="pbpaste"
elif command -v xclip &> /dev/null; then
  # Linux with X11
  alias clipboard="xclip -selection clipboard"
  alias clipout="xclip -selection clipboard -o"
elif command -v wl-copy &> /dev/null; then
  # Linux with Wayland
  alias clipboard="wl-copy"
  alias clipout="wl-paste"
fi

# FZF integration
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# Source p10k config file
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
EOF

  # Setup p10k configuration
  if [ ! -f "$HOME/.p10k.zsh" ]; then
    curl -fsSL -o "$HOME/.p10k.zsh" https://raw.githubusercontent.com/romkatv/powerlevel10k/master/config/p10k-lean.zsh
  fi

  echo "ZSH configuration created at ~/.zshrc with powerlevel10k theme and enhanced aliases"
}

# Install Oh My Tmux
install_ohmytmux() {
  local tmux_dir="$HOME/.tmux"
  local tmux_config="$HOME/.tmux.conf"
  
  echo "Setting up Oh My Tmux..."
  
  if [ -d "$tmux_dir" ]; then
    echo "Oh My Tmux directory already exists, checking if it's a Git repository..."
    
    # Check if it's a valid Git repository
    if (cd "$tmux_dir" && git rev-parse --is-inside-work-tree > /dev/null 2>&1); then
      echo "Updating existing Oh My Tmux installation..."
      (cd "$tmux_dir" && git pull) || echo "Failed to update Oh My Tmux, but continuing..."
    else
      echo "Directory exists but is not a Git repository. Backing up and reinstalling..."
      mv "$tmux_dir" "${tmux_dir}.bak.$(date +%s)"
      git clone https://github.com/gpakosz/.tmux.git "$tmux_dir"
    fi
  else
    echo "Cloning Oh My Tmux..."
    git clone https://github.com/gpakosz/.tmux.git "$tmux_dir"
  fi
  
  # Create symlink to the configuration
  if [ -f "$tmux_config" ]; then
    echo "Backing up existing .tmux.conf..."
    mv "$tmux_config" "${tmux_config}.bak.$(date +%s)"
  fi
  
  echo "Creating symlink to Oh My Tmux configuration..."
  ln -s -f "$tmux_dir/.tmux.conf" "$tmux_config"
  
  # Copy the local config if it doesn't exist
  if [ ! -f "$HOME/.tmux.conf.local" ]; then
    cp "$tmux_dir/.tmux.conf.local" "$HOME/"
  fi
  
  echo "Oh My Tmux setup completed."
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
  
  # Output prompt to stderr to ensure it's displayed
  echo -e "\nEnter your GitHub email address (or just press Enter to skip): " >&2
  # Read input with timeout
  read -t 30 github_email
  
  # If timeout or empty input, skip key generation
  if [ -z "$github_email" ]; then
    echo "No email provided or timeout reached. Skipping SSH key generation."
    return 0
  fi
  
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
  echo -e "\nYour SSH public key is:" >&2
  cat "$GITHUB_KEY.pub"
  echo -e "\nCopy this key to your GitHub account at https://github.com/settings/keys" >&2
  
  # Non-blocking key press with clear message
  echo -e "\nPress Enter to continue (or wait 10 seconds)..." >&2
  read -t 10
  return 0
}

# Create a cheatsheet with useful commands
create_cheatsheet() {
  cat << 'EOF' > "$CHEATSHEET"
# Dev Environment Cheatsheet

## Terminal & Shell

- `z <folder>` - Jump to frequently visited directories (zoxide)
- `atuin search` - Search shell history intelligently
- `<ctrl+r>` - Interactive shell history search
- `tmux new -s <name>` - Create new tmux session
- `tmux attach -t <name>` - Attach to existing tmux session
- `<prefix> c` - Create new tmux window
- `<prefix> ,` - Rename current tmux window
- `<prefix> |` - Split vertically
- `<prefix> -` - Split horizontally
- `<prefix> h/j/k/l` - Navigate tmux panes
- `ls -la` - List all files with details (aliased to `ll`)

## Git

- `git clone <repo>` - Clone repository
- `lazygit` - Terminal UI for git
- `gh repo create` - Create GitHub repository
- `gh pr create` - Create pull request
- `gh issue list` - List GitHub issues

## Neovim

- `:Telescope find_files` - Find files
- `:Telescope live_grep` - Search for text
- `:Telescope buffers` - Show open buffers
- `:LSP...` commands for language server features
- `:Mason` to manage language servers

## Docker

- `docker-compose up -d` - Start containers
- `lazydocker` - Terminal UI for Docker
- `docker ps` - List running containers
- `docker logs <container>` - View container logs

## Package Management

- `brew install <package>` - Install package with Homebrew
- `npm install <package>` - Install npm package
- `pip install <package>` - Install Python package
- `cargo install <crate>` - Install Rust crate

## Development Workflow

- `just <command>` - Run scripts from Justfile
- `watchexec <command>` - Run commands when files change
- `direnv allow` - Allow .envrc in directory
- `httpie <url>` - Better alternative to curl

## Productivity Tools

- `chatgpt` - Terminal ChatGPT interface
- `navi` - Interactive cheatsheet tool
- `tldr <command>` - Simplified help pages
EOF

  echo "Created development environment cheatsheet at $CHEATSHEET"
}

setup_tmux() {
  echo "Setting up custom tmux enhancements..."
  
  # 1. Update existing .tmux.conf.local to use C-a instead of C-b
  # Check if .tmux.conf.local exists
  if [ -f "$HOME/.tmux.conf.local" ]; then
    # Backup the current file
    cp "$HOME/.tmux.conf.local" "$HOME/.tmux.conf.local.backup-$(date +%Y%m%d%H%M%S)"
    
    # Check if tmux_conf_new_prefix is already set
    if grep -q "tmux_conf_new_prefix" "$HOME/.tmux.conf.local"; then
      # Update prefix to C-a
      sed -i '' 's/tmux_conf_new_prefix=.*/tmux_conf_new_prefix="C-a"/' "$HOME/.tmux.conf.local"
    else
      # Add the settings at the end of the file
      cat << 'EOF' >> "$HOME/.tmux.conf.local"

# Change prefix from C-b to C-a
tmux_conf_new_prefix="C-a"
tmux_conf_new_prefix_option="none"
EOF
    fi
    echo "Updated tmux prefix to C-a in .tmux.conf.local"
  else
    echo "Warning: .tmux.conf.local not found. Make sure oh-my-tmux is properly installed."
    return 1
  fi
  
  # 2. Create a custom layout script for development
  mkdir -p "$HOME/bin"
  
  cat << 'EOF' > "$HOME/bin/tmux-dev-layout"
#!/bin/bash

# Create a dev layout with 4 panes: editor, console, server, and monitor
SESSION_NAME=${1:-dev}
PROJECT_DIR=${2:-$(pwd)}

# Check if the session already exists
tmux has-session -t $SESSION_NAME 2>/dev/null

if [ $? != 0 ]; then
  # Create a new session with an editor window
  tmux new-session -d -s $SESSION_NAME -n "editor" -c "$PROJECT_DIR"
  tmux send-keys -t $SESSION_NAME:editor "nvim" C-m
  
  # Create a console window
  tmux new-window -t $SESSION_NAME -n "console" -c "$PROJECT_DIR"
  
  # Create a server window
  tmux new-window -t $SESSION_NAME -n "server" -c "$PROJECT_DIR"
  
  # Create a monitor window with split panes
  tmux new-window -t $SESSION_NAME -n "monitor" -c "$PROJECT_DIR"
  
  # Split monitor window into 4 panes - top left, top right, bottom left, bottom right
  tmux split-window -h -t $SESSION_NAME:monitor
  tmux split-window -v -t $SESSION_NAME:monitor.0
  tmux split-window -v -t $SESSION_NAME:monitor.1
  
  # Setup monitoring tools in each pane
  tmux send-keys -t $SESSION_NAME:monitor.0 "htop" C-m
  tmux send-keys -t $SESSION_NAME:monitor.1 "procs" C-m
  tmux send-keys -t $SESSION_NAME:monitor.2 "watch -n 5 'df -h'" C-m
  tmux send-keys -t $SESSION_NAME:monitor.3 "duf" C-m
  
  # Create a logs window
  tmux new-window -t $SESSION_NAME -n "logs" -c "$PROJECT_DIR"
  
  # Return to editor window
  tmux select-window -t $SESSION_NAME:editor
else
  echo "Session $SESSION_NAME already exists. Attaching..."
fi

# Attach to the session
tmux attach-session -t $SESSION_NAME
EOF
  
  chmod +x "$HOME/bin/tmux-dev-layout"
  
  # 3. Add a status bar enhancement script
  cat << 'EOF' > "$HOME/bin/tmux-status"
#!/bin/bash

# Display project info in tmux status bar
# Usage: tmux-status [project-name]

PROJECT_NAME=${1:-$(basename $(pwd))}
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

if [ -n "$GIT_BRANCH" ]; then
  tmux set -g status-right " #[fg=colour81]$PROJECT_NAME #[fg=yellow]($GIT_BRANCH) #[fg=white]| #[fg=cyan]%a %Y-%m-%d %H:%M"
else
  tmux set -g status-right " #[fg=colour81]$PROJECT_NAME #[fg=white]| #[fg=cyan]%a %Y-%m-%d %H:%M"
fi

# Adjust status bar length to accommodate the project name
tmux set -g status-right-length 100
EOF
  
  chmod +x "$HOME/bin/tmux-status"
  
  # 4. Create a script for session management
  cat << 'EOF' > "$HOME/bin/tmux-session"
#!/bin/bash

# Manage tmux sessions
# Usage: tmux-session [list|save|restore|kill]

ACTION=${1:-list}
SESSION_NAME=${2:-}

case "$ACTION" in
  list|ls)
    echo "Available sessions:"
    tmux list-sessions
    ;;
    
  save)
    if [ -z "$SESSION_NAME" ]; then
      echo "Error: Please provide a session name to save"
      exit 1
    fi
    
    # Save session layout using tmux-resurrect
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
      tmux send-keys -t "$SESSION_NAME" "C-a" "C-s" # Trigger save using C-a + C-s
      echo "Session $SESSION_NAME saved"
    else
      echo "Error: Session $SESSION_NAME not found"
      exit 1
    fi
    ;;
    
  restore)
    if [ -z "$SESSION_NAME" ]; then
      echo "Error: Please provide a session name to restore"
      exit 1
    fi
    
    # Restore session layout using tmux-resurrect
    tmux start-server
    tmux send-keys "C-a" "C-r" # Trigger restore using C-a + C-r
    echo "Session $SESSION_NAME restored"
    ;;
    
  kill)
    if [ -z "$SESSION_NAME" ]; then
      echo "Error: Please provide a session name to kill"
      exit 1
    fi
    
    tmux kill-session -t "$SESSION_NAME"
    echo "Session $SESSION_NAME killed"
    ;;
    
  *)
    echo "Usage: tmux-session [list|save|restore|kill] [session-name]"
    ;;
esac
EOF
  
  chmod +x "$HOME/bin/tmux-session"
  
  # 5. Create a quick-switch script
  cat << 'EOF' > "$HOME/bin/tmux-switch"
#!/bin/bash

# Quick switch between tmux sessions using fzf
# Usage: tmux-switch

# Check if we're already in tmux
if [ -z "$TMUX" ]; then
  # Not in tmux, use fzf to select and attach to a session
  SESSION=$(tmux list-sessions -F "#{session_name}" | fzf --reverse --header="Select tmux session")
  
  if [ -n "$SESSION" ]; then
    tmux attach-session -t "$SESSION"
  else
    echo "No session selected"
  fi
else
  # Already in tmux, use fzf to select and switch
  SESSION=$(tmux list-sessions -F "#{session_name}" | fzf --reverse --header="Switch to tmux session")
  
  if [ -n "$SESSION" ]; then
    tmux switch-client -t "$SESSION"
  fi
fi
EOF
  
  chmod +x "$HOME/bin/tmux-switch"
  
  # 6. Ensure the bin directory is in PATH by adding to .zshrc if needed
  if ! grep -q "export PATH=\"\$HOME/bin:\$PATH\"" "$HOME/.zshrc"; then
    echo '
# Add ~/bin to PATH
export PATH="$HOME/bin:$PATH"' >> "$HOME/.zshrc"
  fi
  
  # 7. Add aliases to .zshrc if they don't exist
  if ! grep -q "# Tmux custom aliases" "$HOME/.zshrc"; then
    cat << 'EOF' >> "$HOME/.zshrc"

# Tmux custom aliases
alias td="tmux-dev-layout"
alias ts="tmux-session"
alias tsw="tmux-switch"
alias tls="tmux list-sessions"
alias tks="tmux kill-session -t"
EOF
  fi
  
  # 8. Create a navi cheatsheet for these custom commands
  mkdir -p "$HOME/.local/share/navi/cheats/custom"
  
  cat << 'EOF' > "$HOME/.local/share/navi/cheats/custom/tmux-custom.cheat"
% tmux-custom

# Start a new development session with 4-pane layout
tmux-dev-layout [session-name] [project-directory]

# Show tmux session list
tmux-session list

# Save current tmux session with tmux-resurrect
tmux-session save <session-name>

# Restore tmux session with tmux-resurrect
tmux-session restore <session-name>

# Kill a tmux session
tmux-session kill <session-name>

# Quick switch between sessions using fzf
tmux-switch

# Set status bar with project info
tmux-status [project-name]

# Start default dev layout (alias)
td [session-name]

# Show session management options (alias)
ts [list|save|restore|kill] [session-name]

# Quick switch sessions (alias)
tsw
EOF
  
  echo "Custom tmux enhancements set up successfully"
  echo "You can now use the following commands:"
  echo "  - tmux-dev-layout [session-name] [project-dir] - Create a development layout with 4 panes"
  echo "  - tmux-session - Manage tmux sessions"
  echo "  - tmux-switch - Quick switch between sessions using fzf"
  echo "  - tmux-status [project-name] - Update status bar with project info"
}

setup_navi_cheatsheets() {
  echo "Setting up navi cheatsheets for your development tools..."
  
  # Make sure navi is installed
  if ! command -v navi &> /dev/null; then
    echo "navi is not installed. Installing navi..."
    brew install navi
  fi
  
  # Create a directory to store the cheatsheet repos if it doesn't exist
  NAVI_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/navi/cheats"
  echo "Setting up navi cheatsheets for your development tools..."
  
  # Make sure navi is installed
  if ! command -v navi &> /dev/null; then
    echo "navi is not installed. Installing navi..."
    brew install navi
  fi
  
  # Create a directory to store the cheatsheet repos if it doesn't exist
  NAVI_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/navi/cheats"
  mkdir -p "$NAVI_DIR"
  
  add_repo "denisidoro/cheats"
  add_repo "papanito/cheats"
  add_repo "prx2090/cheatsheets-for-navi"
  add_repo "infosecstreams/cheat.sheets"
  add_repo "isene/cheats"
  add_repo "https://github.com/isacikgoz/navi-tldr"
  
  # Force navi to update its cache
  echo "Refreshing navi cache..."
  navi --refresh
  
  # Install custom cheatsheets for specific tools not well-covered by repositories
  echo "Creating custom cheatsheets for specific tools..."
  
  # Create custom directory for your own cheatsheets
  CUSTOM_CHEATS="$NAVI_DIR/custom"
  mkdir -p "$CUSTOM_CHEATS"
  
  # Create cheatsheet for zoxide
  cat > "$CUSTOM_CHEATS/zoxide.cheat" << 'EOF'
% zoxide

# Jump to directory with highest score matching pattern
z <pattern>

# Jump to directory with interactive selection
zi <pattern>

# Add directory to zoxide database
zoxide add <path>

# Remove directory from zoxide database
zoxide remove <path>

# Initialize zoxide in current shell (fish)
zoxide init fish

# Initialize zoxide in current shell (bash)
zoxide init bash

# Initialize zoxide in current shell (zsh)
zoxide init zsh

# Show query and score of each match
zoxide query <pattern>

# Interactive directory selection
zoxide query -i <pattern>

# List all directories in database with scores
zoxide query --list

# Import directory entries from z or autojump
zoxide import <path>
EOF

  # Create cheatsheet for fzf
  cat > "$CUSTOM_CHEATS/fzf.cheat" << 'EOF'
% fzf

# Basic usage
fzf

# Search for files in current directory
find . -type f | fzf

# Search with preview
fzf --preview 'cat {}'

# Search for files and edit selected file
vim $(fzf)

# Search through command history
history | fzf

# Kill process
kill -9 $(ps aux | fzf | awk '{print $2}')

# Change directory
cd $(find . -type d | fzf)

# Find and open file
open $(find . -type f | fzf)

# Git checkout branch
git checkout $(git branch | fzf)

# Git commit browser
git log --oneline | fzf --preview 'git show --color=always {1}'

# Search through man pages
man -k . | fzf | awk '{print $1}' | xargs -r man

# Environment variable browser
env | fzf

# Interactive package installation (brew)
brew search | fzf | xargs -r brew install
EOF
  
  # Create cheatsheets for tools that might not be well covered
  cat > "$CUSTOM_CHEATS/brew.cheat" << 'EOF'
% brew, homebrew

# Update Homebrew and upgrade all packages
brew update && brew upgrade

# Install a package
brew install <package>

# Uninstall a package
brew uninstall <package>

# List all installed packages
brew list

# Search for available packages
brew search <query>

# Get information about a package
brew info <package>

# Check for problems
brew doctor

# Clean up old versions of packages
brew cleanup

# Pin a package (prevent from upgrading)
brew pin <package>

# Unpin a package
brew unpin <package>

# Add a third-party repository (tap)
brew tap <user/repo>

# Remove a third-party repository
brew untap <user/repo>

# List all tapped repositories
brew tap
EOF

  cat > "$CUSTOM_CHEATS/tmux.cheat" << 'EOF'
% tmux

# Start a new session
tmux new -s <session-name>

# Attach to an existing session
tmux attach -t <session-name>

# List all sessions
tmux ls

# Detach from session
Ctrl-b d

# Split pane horizontally
Ctrl-b "

# Split pane vertically
Ctrl-b %

# Switch to pane
Ctrl-b <arrow-key>

# Create a new window
Ctrl-b c

# Switch to next window
Ctrl-b n

# Switch to previous window
Ctrl-b p

# Switch to specific window by number
Ctrl-b <number>

# Rename current window
Ctrl-b ,

# Kill current pane
Ctrl-b x

# Kill current window
Ctrl-b &

# Kill tmux server and all sessions
tmux kill-server

# Enter copy mode
Ctrl-b [

# Start selection in copy mode
Space

# Copy selection in copy mode
Enter

# Paste from tmux buffer
Ctrl-b ]
EOF

  cat > "$CUSTOM_CHEATS/neovim.cheat" << 'EOF'
% neovim, nvim

# Open file
nvim <file>

# Open multiple files in separate tabs
nvim -p <file1> <file2>

# Open in read-only mode
nvim -R <file>

# Save current file
:w

# Save and quit
:wq

# Quit without saving
:q!

# Go to line number
:<line-number>

# Search forward for pattern
/<pattern>

# Search backward for pattern
?<pattern>

# Replace all occurrences of old with new
:%s/<old>/<new>/g

# Replace with confirmation
:%s/<old>/<new>/gc

# Split window horizontally
:split

# Split window vertically
:vsplit

# Switch between windows
Ctrl-w <arrow-key>

# Open terminal
:terminal

# Enter visual mode
v

# Enter visual line mode
V

# Enter visual block mode
Ctrl-v

# Install plugins (using vim-plug)
:PlugInstall
EOF

  # Force navi to reload all cheatsheets
  echo "Refreshing navi with custom cheatsheets..."
  navi --refresh
  
  echo "Testing cheatsheet availability..."
  echo "FZF cheatsheet entries: $(navi --query "fzf" --print | wc -l)"
  echo "Zoxide cheatsheet entries: $(navi --query "zoxide" --print | wc -l)"
  
  echo "Navi cheatsheets setup complete. Run 'navi' to search for commands."
}

setup_navi_aliases_cheatsheet() {
  echo "Setting up Navi cheatsheet with your custom aliases..."
  
  # Create a custom cheatsheet directory
  mkdir -p "$HOME/.local/share/navi/cheats/custom"
  
  # Create a cheatsheet specifically for your aliases and functions
  cat << 'EOF' > "$HOME/.local/share/navi/cheats/custom/aliases.cheat"
% zsh, aliases, navigation

# Quick jump back with zoxide
zz

# Jump to frequently visited directory
j <directory>

# Go up one directory
..

# Go up two directories
...

# List files with details using lsd
ll

# Show directory tree with lsd
lt

# Jump to development directory
dev

# Jump to dotfiles directory
dots

% git, aliases

# Check git status
gs

# Add all files
ga .

# Commit with message
gc "<message>"

# Push to remote
gp

# Pull from remote
gl

# Show git diff
gd

# List branches
gb

# Checkout branch
gco <branch>

# Launch lazygit
lg

# Undo last commit (keep changes)
gundo

# Amend last commit without changing message
gamend

# Interactive rebase
grb <branch-or-commit>

# Stash changes with message
gsave "<message>"

# Apply and remove stashed changes
gpop

# Remove untracked files and directories
gclean

# Git add, commit, and push in one command
gitcp "<commit-message>"

# Open file/repo in GitHub
gbrowse [file-path]

% development, aliases

# Open with Neovim
nv <file>

# Create new tmux session
tnew <session-name>

# Attach to tmux session
tattach <session-name>

# List tmux sessions
tlist

# Kill tmux session
tks <session-name>

# Kill all tmux sessions
tka

# Open Neovim with session
nvs

# Start a dev tmux session with predefined layout
tdev [session-name]

% python, aliases

# Run Python
py <script.py>

# Run IPython
ipy

# Start Jupyter Lab
jl

# Create virtual environment with uv
uvenv

# Activate virtual environment
uvact

# Install requirements file
pir

# Create and activate Python venv
pvenv

# Create Python venv with specific name and activate
venv_create [env-name]

# Find and activate existing Python venv
venv_activate

# Create temporary Python environment
pytmp [package1 package2...]

% docker, aliases

# Show Docker processes
dkps

# Run Docker Compose up in detached mode
dcu

# Run Docker Compose down
dcd

# Show Docker Compose logs
dcl

# Launch lazydocker
lzd

# Clean up Docker system
dclean

% database, aliases

# Start PostgreSQL interactive client
pg

# Start PostgreSQL service
pgstart

# Stop PostgreSQL service
pgstop

# Create compressed PostgreSQL dump
pgdump <database-name>

# Restore PostgreSQL database
pgrestore <database-name> <dump-file>

% network, aliases

# Show public IP address
myip

# Ping with 5 packets only
ping <host>

# Run speed test
ns

# HTTP client with syntax highlighting
http <url>

# HTTP API testing with JQ output
apitest <url>

# Quick SSH tunneling
tunnelme <local-port> <user@remote>

# Share file via HTTP
share_file <file-path> [port]

% terraform, aliases

# Initialize Terraform
tfi

# Plan Terraform changes
tfp

# Apply Terraform changes
tfa

# Destroy Terraform resources
tfd

# Show Terraform outputs
tfo

% kubernetes, aliases

# Switch Kubernetes namespace
kns <namespace>

# Get pods in namespace
kpods [namespace]

# Follow logs for pod
klogs <pod-name> [namespace]

% files, utils

# Create directory and cd into it
mkcd <directory>

# Extract archive of various formats
extract <archive-file>

# Show disk usage with better UI
duc

# Find large files/directories
bigfiles [count]

# Search and replace text in files (prompted)
freplace "<search-pattern>" "<replacement>"

# Quickly find and edit a file with fzf
fe

# Search with ripgrep and preview with fzf
rgz

# Create a new project with git init
newproject <project-name>

# Backup a directory to tar.gz
backup <directory>

# Take a quick note or open today's notes
note [text]

# Run command with notification when done
notify <command>

% ai, ollama

# Run Ollama model
oll <model>

# List Ollama models
ollls

# Remove Ollama model
ollrm <model>

# Start Ollama with custom system prompt
ollama_with_prompt <model> "<system-prompt>"

# Start Ollama chat with history saved
ollama_chat [model]

% benchmarking, performance

# Benchmark command execution time
benchmark "<command1>" ["<command2>" ...]

# Run hyperfine benchmarks
hf "<command1>" ["<command2>" ...]

% aws

# Switch AWS profile
awsp <profile-name>

% tmux, basics

# Start a new session
tmux new-session -s <session-name>

# Start a new session with window name
tmux new-session -s <session-name> -n <window-name>

# Start a new session detached
tmux new-session -d -s <session-name>

# Attach to an existing session
tmux attach-session -t <session-name>

# List all sessions
tmux list-sessions

# Kill a session
tmux kill-session -t <session-name>

# Kill all sessions except current
tmux kill-session -a

# Detach from current session
<C-a> d

# Rename current session
<C-a> $

% tmux, windows

# Create a new window
<C-a> c

# Rename current window
<C-a> ,

# List all windows
<C-a> w

# Next window
<C-a> n

# Previous window
<C-a> p

# Switch to window by number
<C-a> <number>

# Switch to last active window
<C-a> l

# Close current window
<C-a> &

# Split window horizontally
<C-a> -

# Split window vertically
<C-a> |

% tmux, panes

# Toggle between panes
<C-a> o

# Move to pane (by direction using vi keys)
<C-a> h  # left
<C-a> j  # down
<C-a> k  # up
<C-a> l  # right

# Switch to last active pane
<C-a> ;

# Show pane numbers
<C-a> q

# Kill current pane
<C-a> x

# Resize pane (by direction using vi keys with repeat)
<C-a> H  # left
<C-a> J  # down
<C-a> K  # up
<C-a> L  # right

# Toggle pane zoom/maximize
<C-a> z

# Convert pane to window
<C-a> !

# Rotate panes
<C-a> <C-o>

# Swap pane positions
<C-a> {  # swap with previous
<C-a> }  # swap with next

% tmux, copy-mode

# Enter copy mode
<C-a> [

# Start selection in copy mode (vi mode)
v

# Rectangle toggle in copy mode
r

# Copy selection in copy mode
y

# Paste copied text
<C-a> ]

# Search backward in copy mode
?

# Search forward in copy mode
/

# Next match in copy mode
n

# Previous match in copy mode
N

% tmux, custom-scripts

# Start a new development session with 4-pane layout
tmux-dev-layout [session-name] [project-directory]

# Show tmux session list
tmux-session list

# Save current tmux session with tmux-resurrect
tmux-session save <session-name>

# Restore tmux session with tmux-resurrect
tmux-session restore <session-name>

# Kill a tmux session
tmux-session kill <session-name>

# Quick switch between sessions using fzf
tmux-switch

# Set status bar with project info
tmux-status [project-name]

% tmux, oh-my-tmux

# Reload tmux configuration
<C-a> r

# Toggle mouse support
<C-a> m

# Toggle synchronize panes
<C-a> e

# Toggle status bar visibility
<C-a> t

# Swap current pane with the next one
<C-a> >

# Swap current pane with the previous one
<C-a> 

# Open a man page in new window
<C-a> /

# Enter copy mode and scroll one page up
<C-a> PageUp

# Toggle status left visibility
<C-a> u

# Toggle status right visibility
<C-a> U

% tmux, oh-my-zsh-aliases

# Create new tmux session
tnew <session-name>

# Attach to tmux session
tattach <session-name>

# List tmux sessions
tlist

# Kill tmux session
tks <session-name>

# Kill all tmux sessions
tka

# Start a dev tmux session with predefined layout (custom)
tdev [session-name]

# Open another terminal in the same directory
<C-a> T

% tmux, resurrect-plugin

# Save tmux environment
<C-a> <C-s>

# Restore tmux environment
<C-a> <C-r>

% tmux, advanced

# List all key bindings
tmux list-keys

# Show every session, window, pane, etc.
tmux info

# Show global session options
tmux show-options -g

# Set an option
tmux set-option -g <option-name> <option-value>

# Enter tmux command mode
<C-a> :

# Show clock
<C-a> t

# Switch between layouts
<C-a> <space>

# Set a window option
tmux set-window-option <option-name> <option-value>

# Choose session/window/pane from a list
<C-a> s  # sessions
<C-a> w  # windows
<C-a> q  # panes

# Join pane from another window
:join-pane -s <window>.<pane>

# Move pane to another window
:move-pane -t <window>.<pane>

% tmux, plugin-management

# Install plugins
<C-a> I

# Update plugins
<C-a> U

# Clean plugins
<C-a> alt-u

% tmux, monitoring

# Monitor for activity in a window
<C-a> M-a

# Monitor for silence in a window
<C-a> M-s

# Toggle activity notification
tmux set-window-option -g monitor-activity [on|off]

# Toggle window bell
tmux set-window-option -g monitor-bell [on|off]

% tmux, nested-sessions

# Send command to inner tmux (when nesting)
<C-a> <C-a>

# Toggle sending keys to all panes
:setw synchronize-panes [on|off]
EOF
  
  echo "Created Navi cheatsheet with your aliases at $HOME/.local/share/navi/cheats/custom/aliases.cheat"
}

setup_additional_tools() {

  setup_navi_cheatsheets || echo "Navi cheatsheets setup failed, continuing anyway..."
  setup_navi_aliases_cheatsheet || echo "Navi aliases cheatsheet setup failed, continuing anyway..."
  
}

# Main execution flow
# Call main function at the end of the script to execute everything
trap main EXIT

main() {
  echo "Starting development environment setup..."
  # Parse command line arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      --skip-brew)
        SKIP_BREW=true
        shift
        ;;
      --skip-python)
        SKIP_PYTHON=true
        shift
        ;;
      --skip-node)
        SKIP_NODE=true
        shift
        ;;
      --help)
        echo "Usage: setup.sh [OPTIONS]"
        echo "Options:"
        echo "  --skip-brew      Skip Homebrew installation and related packages"
        echo "  --skip-python    Skip Python setup and package installation"
        echo "  --skip-node      Skip Node.js and npm package installation"
        echo "  --help           Display this help message"
        exit 0
        ;;
      *)
        echo "Unknown option: $1"
        echo "Use --help for available options"
        exit 1
        ;;
    esac
  done
  
  # Step 1: Backup existing configs
  backup_configs
  
  # Step 2: Check internet connection
  check_internet
  
  # Step 3: Install Xcode Command Line Tools
  install_xcode_tools
  
  # Step 4: Setup GitHub directory
  setup_github_dir

  # Step 5-6: Install and configure Homebrew if not skipped
  if [ "$SKIP_BREW" = false ]; then
    # Step 5: Install and configure Homebrew
    install_homebrew
    optimize_homebrew
    
    # Step 6: Install packages from Homebrew
    install_brew_packages
  else
    echo "Skipping Homebrew installation and package setup (--skip-brew flag used)"
  fi
  
  # Step 7: Install Oh My Zsh first (should be before configuring zsh)
  install_ohmyzsh
  
  # Step 8: Configure ZSH with plugins and theme
  configure_zsh
  
  # Step 9: Install zsh plugins
  install_zsh_plugins || { echo "ZSH plugins installation failed, but continuing..."; }
  
  # Step 10: Install VS Code
  install_vscode || { echo "VS Code installation failed, but continuing with other installations..."; }
  
  # Step 11: Install Docker
  install_docker || { echo "Docker installation failed, but continuing with other installations..."; }
  
  # Step 12: Install npm packages
  if [ "$SKIP_NODE" = false ]; then
    install_npm_packages || { echo "Some npm packages failed to install, but continuing..."; }
  else
    echo "Skipping Node.js and npm packages installation (--skip-node flag used)"
  fi
  
  # Step 13: Install Python packages
  if [ "$SKIP_PYTHON" = false ]; then
    setup_python || { echo "Some Python packages failed to install, but continuing..."; }
  else
    echo "Skipping Python setup and package installation (--skip-python flag used)"
  fi
  
  # Step 14: Install Rust crates
  install_rust_crates || { echo "Some Rust crates failed to install, but continuing..."; }
  
  # Step 15: Install Go packages
  install_go_packages || { echo "Some Go packages failed to install, but continuing..."; }
  
  # Step 16: Configure Git
  configure_git || { echo "Git configuration failed, but continuing..."; }

  # Step 17: Set up global gitignore
  setup_global_gitignore || { echo "Global gitignore setup failed, but continuing..."; }
  
  # Step 18: Install Oh My Tmux
  install_ohmytmux || { echo "Oh My Tmux installation failed, but continuing..."; }
  
  # Step 19: Set up Neovim
  setup_neovim || { echo "Neovim setup failed, but continuing..."; }

  # Step 20: Set up Tmux
  setup_tmux || { echo "Tmux setup failed, but continuing..."; }

  # Step 21: Set up additional tools
  setup_additional_tools || { echo "Additional tools setup failed, but continuing..."; }
  
  # Step 22: Set up SSH key
  setup_ssh_key || { echo "SSH key setup failed, but continuing..."; }
  
  # Step 23: Create cheatsheet
  create_cheatsheet || { echo "Cheatsheet creation failed, but continuing..."; }
  
  echo "======================================================"
  echo "✅ Development environment setup completed successfully!"
  echo "📝 Check the cheatsheet at $CHEATSHEET"
  echo "📋 Check the log at $LOGFILE"
  echo "======================================================"
}

main "@"
