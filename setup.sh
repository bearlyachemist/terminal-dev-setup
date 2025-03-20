#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status

LOGFILE="$HOME/setup_log.txt"
exec > >(while read line; do echo "$(date '+[%Y-%m-%d %H:%M:%S]') $line"; done | tee -a "$LOGFILE") 2>&1

# Check Internet Connection
if ! ping -c 1 google.com &>/dev/null; then
    echo "No internet connection detected. Please check your network and try again."
    exit 1
fi

# Install Xcode Command Line Tools
if ! xcode-select -p &>/dev/null; then
    echo "Installing Xcode Command Line Tools..."
    xcode-select --install
fi

# Install Homebrew if not installed
if ! command -v brew &>/dev/null; then
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

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
BREW_PACKAGES=(
    python uv go rust node docker npm minio mosquitto postgresql sqlite 
    ripgrep neovim navi bat zoxide fzf tmux watchexec chatgpt vips
    pyenv julia gcc zig git gh ffmpeg cmake nmap netcat tcpdump libtool autoconf
    wireshark duf entr exiftool fdupes hyperfine just jq procs rsync speedtest-cli 
    rclone httpie lazygit ngrok asciinema lazydocker zsh-syntax-highlighting 
    zsh-autosuggestions copilot 1password-cli pgcli mycli awscli 
    google-cloud-sdk cloudflare-warp fnm abseil powerlevel10k
)

echo "Installing Homebrew packages..."
for package in "${BREW_PACKAGES[@]}"; do
    install_brew_package "$package"
done

export CXXFLAGS="-I$(brew --prefix abseil)/include"

# Install required npm packages
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

# Install top Rust crates
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
wait

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


# Clone kickstart.nvim configuration
if [ ! -d "${XDG_CONFIG_HOME:-$HOME/.config}/nvim" ]; then
    echo "Cloning kickstart.nvim..."
    git clone https://github.com/bearlyachemist/kickstart.nvim.git "${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
else
    echo "kickstart.nvim already exists, skipping..."
fi


append_if_missing() {
    local file="$1"
    local line="$2"
    grep -qxF "$line" "$file" || echo "$line" >> "$file"
}

append_if_missing "$HOME/.zshrc" "eval \"\$(zoxide init zsh)\""
append_if_missing "$HOME/.zshrc" "autoload -Uz compinit && compinit -d ~/.zcompdump"
append_if_missing "$HOME/.zshrc" "setopt correct"
append_if_missing "$HOME/.zshrc" "setopt correctall"
append_if_missing "$HOME/.zshrc" "setopt autocd"
append_if_missing "$HOME/.zshrc" "HISTSIZE=100000"
append_if_missing "$HOME/.zshrc" "SAVEHIST=100000"
append_if_missing "$HOME/.zshrc" "setopt inc_append_history"
append_if_missing "$HOME/.zshrc" "setopt share_history"
append_if_missing "$HOME/.zshrc" "setopt hist_ignore_all_dups"
append_if_missing "$HOME/.zshrc" "setopt hist_ignore_space"
append_if_missing "$HOME/.zshrc" "setopt hist_reduce_blanks"
append_if_missing "$HOME/.zshrc" "zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'"
append_if_missing "$HOME/.zshrc" "zstyle ':completion:*' menu select"
append_if_missing "$HOME/.zshrc" "source \$(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
append_if_missing "$HOME/.zshrc" "source \$(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
append_if_missing "$HOME/.zshrc" "eval \"\$(fnm env --use-on-cd)\""

# Add Aliases
ALIASES=(
    "alias ..='cd ..'"
    "alias ...='cd ../..'"
    "alias ....='cd ../../..'"
    "alias ~='cd ~'"
    "alias home='cd ~'"
    "alias dl='cd ~/Downloads'"
    "alias dt='cd ~/Desktop'"
    "alias l='exa -lah'"
    "alias ll='exa -lAh --color=auto'"
    "alias ls='exa --color=auto'"
    "alias tree='exa --tree --color=always'"
    "alias g='git'"
    "alias ga='git add'"
    "alias gc='git commit -m'"
    "alias gp='git push'"
    "alias gl='git log --oneline --graph --decorate'"
    "alias gs='git status -sb'"
    "alias gd='git diff'"
    "alias speed='speedtest-cli --simple'"
    "alias myip='curl ifconfig.me'"
    "alias cpu='lscpu'"
    "alias mem='free -h'"
    "alias reload='source ~/.zshrc'"
)
for alias in "${ALIASES[@]}"; do
    append_if_missing "$HOME/.zshrc" "$alias"
done

# Ensure Go and Rust binaries are in PATH
append_if_missing "$HOME/.zshrc" "export PATH=\$(go env GOPATH)/bin:\$PATH"
append_if_missing "$HOME/.zshrc" "export PATH=\"\$HOME/.cargo/bin:\$PATH\""

# Ensure Pyenv is initialized
append_if_missing "$HOME/.zshrc" "export PYENV_ROOT=\"\$HOME/.pyenv\""
append_if_missing "$HOME/.zshrc" "export PATH=\"\$PYENV_ROOT/bin:\$PATH\""
append_if_missing "$HOME/.zshrc" "eval \"\$(pyenv init --path)\""

if [ ! -d "$HOME/.config/powerlevel10k" ]; then
    echo "Setting up Powerlevel10k..."
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
    append_if_missing "ZSH_THEME=powerlevel10k/powerlevel10k"
fi

# Set Powerlevel10k theme
append_if_missing "$HOME/.zshrc" "ZSH_TEME=“powerlevel10k/powerlevel10k”"
append_if_missing "$HOME/.zshrc" "[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh"

chmod 644 "$HOME/.zshrc"

echo "Setup complete! Restart your terminal to apply changes."

append_if_missing() {
    local file="$1"
    local line="$2"
    grep -qxF "$line" "$file" || echo "$line" >> "$file"
}

append_if_missing "$HOME/.zshrc" "ZSH_TEME=“powerlevel10k/powerlevel10k”"
append_if_missing "$HOME/.zshrc" "source /opt/homebrew/Cellar/powerlevel10k/1.20.0/share/powerlevel10k/powerlevel10k.zsh-theme"
append_if_missing "$HOME/.zshrc" "[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh"
