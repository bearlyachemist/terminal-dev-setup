#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status

LOGFILE="$HOME/setup_log.txt"
exec > >(awk '{print strftime("[%Y-%m-%d %H:%M:%S]"), $0}' | tee -a "$LOGFILE") 2>&1

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
    if ! brew list "$1" &>/dev/null; then
        echo "Installing $1..."
        install_with_retry "brew install $1"
    else
        echo "$1 is already installed, skipping."
    fi
}

# Install required packages
BREW_PACKAGES=(
    python uv go rust node docker npm minio mosquitto postgres sqlite 
    ripgrep neovim navi bat zoxide exa fzf tmux watchexec git2gpt chatgpt-cli 
    apache-airflow pyenv julia gcc zig git gh ffmpeg cmake nmap netcat tcpdump 
    wireshark duf entr exiftool fdupes hyperfine just jq procs rsync speedtest-cli 
    rclone httpie lazygit ngrok asciinema traceroute netstat lazydocker 
    zsh-syntax-highlighting zsh-autosuggestions copilot-cli 1password-cli 
    pgcli mycli awscli google-cloud-sdk warp-cli fnm powerlevel10k
)

echo "Installing Homebrew packages in parallel..."
printf "%s\n" "${BREW_PACKAGES[@]}" | xargs -n1 -P4 brew install

# Install required npm packages
NPM_PACKAGES=(
    typescript react svelte next express tauri
    nodemon concurrently dotenv rimraf cross-env http-server prettier 
    eslint husky lint-staged tailwindcss postcss sass styled-components 
    axios node-fetch graphql apollo-server cors mongoose sequelize pg 
    sqlite3 redis bcrypt jsonwebtoken passport helmet socket.io ws mqtt 
    jest mocha chai supertest cypress commander yargs chalk figlet ora 
    webpack vite parcel pm2 @tensorflow/tfjs-node brain.js natural 
    uuid moment date-fns lodash underscore rxjs
)

echo "Installing npm packages in parallel..."
for package in "${NPM_PACKAGES[@]}"; do
    (npm install -g "$package") &
done
wait

# Install Python packages in parallel
PYTHON_PACKAGES=(
    polars pandas numpy matplotlib scipy scikit-learn flask pyqt6 rich 
    scrapy seaborn ray statsmodels fire requests httpx beautifulsoup4 
    lxml websockets dask plotly xgboost lightgbm torch pyspark modin 
    vaex pyarrow typer click loguru tqdm pytest pdb flake8 mypy black 
    pyjwt cryptography paramiko joblib cython numba boto3 certifi 
    virtualenv urllib3
)

echo "Installing Python packages in parallel..."
printf "%s\n" "${PYTHON_PACKAGES[@]}" | xargs -n1 -P4 pip install

# Install top Rust crates
RUST_CRATES=(
    serde thiserror clap rand tokio log anyhow base64 regex itertools chrono
    libc once_cell tracing lazy_static futures tempfile bitflags url toml
    bytes uuid env_logger hex http rayon hyper rusttls nom colored dirs
    walkdir insta fake indexmap serde_json ryu 
)

echo "Installing Rust crates..."
for crate in "${RUST_CRATES[@]}"; do
    (cargo install "$crate") &
done
wait

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
append_if_missing "[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh"

# Set Powerlevel10k theme
if [ ! -d "$HOME/.config/powerlevel10k" ]; then
    echo "Setting up Powerlevel10k..."
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
    append_if_missing "ZSH_THEME=powerlevel10k/powerlevel10k"
fi

chmod 644 "$HOME/.zshrc"

echo "Setup complete! Restart your terminal to apply changes."
