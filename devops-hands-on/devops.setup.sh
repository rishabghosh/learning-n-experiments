#!/usr/bin/env bash
#
# devops.setup.sh
# ----------------
# Installs and configures everything needed for the 7-day hands-on plan in
# learning-plan.md (AWS, Terraform, Kubernetes, Helm) on macOS.
#
# Safe to re-run: every step checks whether the tool is already installed first.
#
# Usage:
#   chmod +x devops.setup.sh
#   ./devops.setup.sh
#

set -euo pipefail

# Homebrew 7+ asks "Do you want to proceed? [y/n]" before every install.
# Turn that off so the script runs from start to finish without stopping.
export HOMEBREW_NO_ASK=1

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()  { printf "\n\033[1;34m==> %s\033[0m\n" "$*"; }
ok()    { printf "    \033[1;32m✔\033[0m %s\n" "$*"; }
warn()  { printf "    \033[1;33m!\033[0m %s\n" "$*"; }

# Install a Homebrew formula only if it isn't already installed.
brew_install() {
  local formula="$1"
  if brew list --formula "$formula" &>/dev/null; then
    ok "$formula already installed"
  else
    brew install "$formula"
    ok "$formula installed"
  fi
}

# Install a Homebrew cask (GUI app / binary package) only if missing.
cask_install() {
  local cask="$1"
  if brew list --cask "$cask" &>/dev/null; then
    ok "$cask already installed"
  else
    brew install --cask "$cask"
    ok "$cask installed"
  fi
}

LEARNING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZSHRC="$HOME/.zshrc"
MARKER_START="# >>> devops-learning setup >>>"
MARKER_END="# <<< devops-learning setup <<<"

# ---------------------------------------------------------------------------
# 0. Pre-flight checks
# ---------------------------------------------------------------------------
info "Checking platform"

# This script uses Homebrew and macOS app bundles, so it only supports macOS.
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script supports macOS only." >&2
  exit 1
fi
ok "macOS $(sw_vers -productVersion) on $(uname -m)"

# Xcode Command Line Tools provide git, make and compilers. Homebrew needs
# them, and some tools build native pieces during install.
if ! xcode-select -p &>/dev/null; then
  warn "Xcode Command Line Tools missing. Starting installer..."
  xcode-select --install || true
  echo "Re-run this script after the Command Line Tools finish installing." >&2
  exit 1
fi
ok "Xcode Command Line Tools present"

# ---------------------------------------------------------------------------
# 1. Homebrew
# ---------------------------------------------------------------------------
# Homebrew is the package manager on macOS. Every other tool below is
# installed and kept up to date through it (`brew upgrade`).
info "Homebrew"
if ! command -v brew &>/dev/null; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
# Apple Silicon installs to /opt/homebrew and Intel to /usr/local. Load
# whichever is present so `brew` works for the rest of this script.
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi
brew update
ok "Homebrew $(brew --version | head -1 | awk '{print $2}')"

# ---------------------------------------------------------------------------
# 2. Core CLI utilities
# ---------------------------------------------------------------------------
info "Core utilities"

# git: version control. Every day's code goes into a repo, which becomes
# your portfolio by Day 7.
brew_install git

# jq: parses JSON on the command line. The AWS CLI and `kubectl -o json`
# both output JSON, e.g. `aws ec2 describe-instances | jq '.Reservations[].Instances[].InstanceId'`.
brew_install jq

# yq: like jq, but for YAML. Kubernetes manifests and Helm values files are
# YAML, so this is handy for reading and editing them.
brew_install yq

# hey: a tiny HTTP load generator. Used on Day 7 to send traffic at the app
# so you can watch the Horizontal Pod Autoscaler add pods.
brew_install hey

# ---------------------------------------------------------------------------
# 3. AWS tooling (Days 1-2, 7)
# ---------------------------------------------------------------------------
info "AWS tooling"

# awscli (v2): the official AWS command line. Used to run commands against
# your account, to supply the credentials Terraform uses, and to set up
# kubectl for EKS (`aws eks update-kubeconfig`).
brew_install awscli

# session-manager-plugin: lets `aws ssm start-session` open a shell on EC2
# with no SSH keys and no port 22 open. Day 1 uses this.
cask_install session-manager-plugin

# ---------------------------------------------------------------------------
# 4. Terraform tooling (Days 3-4, 7)
# ---------------------------------------------------------------------------
info "Terraform tooling"

# terraform: the Infrastructure-as-Code tool. It comes from HashiCorp's own
# tap because the Homebrew core formula is frozen at 1.5.x after the licence
# change. The tap keeps you on current releases.
brew tap hashicorp/tap
# Homebrew 7+ won't load formulae from third-party taps until you trust them.
# Trust only the terraform formula, not the whole hashicorp tap.
brew trust --formula hashicorp/tap/terraform
if brew list --formula hashicorp/tap/terraform &>/dev/null; then
  ok "terraform already installed"
else
  # Remove the old core formula first if it's installed, to avoid binary conflicts.
  brew list --formula terraform &>/dev/null && brew uninstall terraform || true
  brew install hashicorp/tap/terraform
  ok "terraform installed"
fi

# tflint: a Terraform linter. It catches mistakes `terraform validate` misses,
# such as invalid instance types, deprecated syntax and unused variables.
# Homebrew no longer packages it, so download the official release from
# GitHub, check it against the published checksum, and install to ~/.local/bin.
# It's a nice-to-have, so a failure here only prints a warning.
install_tflint() {
  local arch tag tmp zip
  arch="$(uname -m)"; [[ "$arch" == "x86_64" ]] && arch="amd64"
  tag="$(curl -fsSL https://api.github.com/repos/terraform-linters/tflint/releases/latest | jq -r .tag_name)" || return 1
  [[ -n "$tag" && "$tag" != "null" ]] || return 1
  zip="tflint_darwin_${arch}.zip"
  tmp="$(mktemp -d)"
  # Each step must succeed before the next one runs. A checksum mismatch
  # stops the function before anything is unzipped.
  curl -fsSL -o "$tmp/$zip"          "https://github.com/terraform-linters/tflint/releases/download/${tag}/${zip}" &&
  curl -fsSL -o "$tmp/checksums.txt" "https://github.com/terraform-linters/tflint/releases/download/${tag}/checksums.txt" &&
  (cd "$tmp" && grep " ${zip}\$" checksums.txt | shasum -a 256 -c -) >/dev/null &&
  mkdir -p "$HOME/.local/bin" &&
  unzip -oq "$tmp/$zip" tflint -d "$HOME/.local/bin" &&
  chmod +x "$HOME/.local/bin/tflint"
  local rc=$?
  rm -rf "$tmp"
  return $rc
}
if command -v tflint &>/dev/null || [[ -x "$HOME/.local/bin/tflint" ]]; then
  ok "tflint already installed"
elif install_tflint; then
  ok "tflint installed to ~/.local/bin"
else
  warn "tflint install failed (optional, skipping)"
fi
export PATH="$HOME/.local/bin:$PATH"

# ---------------------------------------------------------------------------
# 5. Containers & Kubernetes tooling (Days 5-7)
# ---------------------------------------------------------------------------
info "Container & Kubernetes tooling"

# Docker Desktop: the container runtime. kind runs Kubernetes nodes as
# Docker containers, and on Day 7 you build the app image and push it to ECR.
if [[ -d "/Applications/Docker.app" ]] || command -v docker &>/dev/null; then
  ok "Docker already installed"
else
  # The cask was renamed from `docker` to `docker-desktop`. Try the new name first.
  brew install --cask docker-desktop || brew install --cask docker
  ok "Docker Desktop installed"
fi

# kubectl: the Kubernetes CLI. You use it all through Days 5-7 to deploy,
# inspect, debug and scale workloads. The formula is named kubernetes-cli.
brew_install kubernetes-cli

# kind (Kubernetes IN Docker): runs a real Kubernetes cluster locally inside
# Docker. It's free, so you can practise Days 5-6 without paying for EKS.
brew_install kind

# helm: the Kubernetes package manager. Day 6 is about writing charts, and
# Day 7 uses Helm to install the AWS Load Balancer Controller and your app.
brew_install helm

# k9s: a terminal UI for Kubernetes. It makes browsing pods, logs and
# events much faster than typing kubectl commands while you're learning.
brew_install k9s

# kubectx + kubens: switch cluster context (kind ↔ EKS) and default namespace
# with one short command. You'll go back and forth between kind and EKS on Day 7.
brew_install kubectx

# ---------------------------------------------------------------------------
# 6. Shell configuration (~/.zshrc)
# ---------------------------------------------------------------------------
# Adds aliases, tab completion and Terraform's plugin cache. The block sits
# between markers so a re-run replaces it instead of adding a duplicate.
info "Configuring zsh ($ZSHRC)"
touch "$ZSHRC"

# Remove any previous version of our block.
if grep -q "$MARKER_START" "$ZSHRC"; then
  sed -i '' "/$MARKER_START/,/$MARKER_END/d" "$ZSHRC"
fi

cat >> "$ZSHRC" <<EOF
$MARKER_START
# ~/.local/bin holds tools installed outside Homebrew (tflint).
export PATH="\$HOME/.local/bin:\$PATH"

# Tab completion needs compinit loaded before the tool completions below.
autoload -Uz compinit && compinit -i

# kubectl / helm / kind completion: tab-complete resource names, flags and
# pod names, which saves a lot of typing and typos.
command -v kubectl >/dev/null && source <(kubectl completion zsh)
command -v helm    >/dev/null && source <(helm completion zsh)
command -v kind    >/dev/null && source <(kind completion zsh)

# AWS CLI completion: tab-complete services and subcommands.
command -v aws_completer >/dev/null && complete -C "\$(command -v aws_completer)" aws

# Terraform completion: tab-complete subcommands.
autoload -U +X bashcompinit && bashcompinit
command -v terraform >/dev/null && complete -o nospace -C "\$(command -v terraform)" terraform

# Short aliases. 'k' is the universal kubectl shorthand, and completion is wired to it too.
alias k=kubectl
compdef k=kubectl 2>/dev/null
alias tf=terraform
alias kgp='kubectl get pods'
alias kga='kubectl get all'
alias kev='kubectl get events --sort-by=.lastTimestamp'

# Terraform plugin cache: providers (the AWS provider is ~500MB) are
# downloaded once and reused by every project, instead of once per folder.
export TF_PLUGIN_CACHE_DIR="\$HOME/.terraform.d/plugin-cache"

# Default AWS region, so you don't have to pass --region every time.
# Change it to the region closest to you.
export AWS_DEFAULT_REGION="\${AWS_DEFAULT_REGION:-ap-south-1}"

# Don't send AWS CLI output to a pager (less). Output stays in the terminal and pipes cleanly to jq.
export AWS_PAGER=""
$MARKER_END
EOF
ok "zsh config block written"

# The plugin cache directory has to exist, or Terraform ignores the setting.
mkdir -p "$HOME/.terraform.d/plugin-cache"
ok "Terraform plugin cache: ~/.terraform.d/plugin-cache"

# ---------------------------------------------------------------------------
# 7. Helm repositories (Days 6-7)
# ---------------------------------------------------------------------------
# Register the chart repos the plan uses, so `helm install` works straight away.
info "Helm repositories"
# bitnami: well-written community charts (redis, postgres). Day 6 practice.
helm repo add bitnami https://charts.bitnami.com/bitnami --force-update >/dev/null
# eks: official AWS charts, including the AWS Load Balancer Controller. Day 7.
helm repo add eks https://aws.github.io/eks-charts --force-update >/dev/null
# ingress-nginx: the ingress controller for the local kind cluster. Day 5.
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx --force-update >/dev/null
# metrics-server: provides CPU/memory metrics so the HPA can autoscale. Day 7.
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ --force-update >/dev/null
helm repo update >/dev/null
ok "bitnami, eks, ingress-nginx, metrics-server added"

# ---------------------------------------------------------------------------
# 8. Workspace folders
# ---------------------------------------------------------------------------
# One folder per topic, matching the plan, so each day's work has a home.
info "Workspace folders in $LEARNING_DIR"
mkdir -p "$LEARNING_DIR"/{aws,terraform,k8s,helm,capstone}
ok "aws/ terraform/ k8s/ helm/ capstone/"

# Start a git repo so each day's progress can be committed.
# The repo ships with a full .gitignore (Terraform state, credentials,
# kubeconfigs, Helm packages and so on), so we only run `git init` here.
if [[ ! -d "$LEARNING_DIR/.git" ]]; then
  git -C "$LEARNING_DIR" init -q -b main
  ok "git repo initialised (branch: main)"
else
  ok "git repo already exists"
fi
if [[ -f "$LEARNING_DIR/.gitignore" ]]; then
  ok ".gitignore present"
else
  warn ".gitignore missing. Restore it before committing, so state files and secrets stay out of git."
fi

# ---------------------------------------------------------------------------
# 9. Docker daemon
# ---------------------------------------------------------------------------
# kind needs a running Docker daemon. Start Docker Desktop if it isn't running.
info "Docker daemon"
if docker info &>/dev/null; then
  ok "Docker is running"
else
  open -a Docker 2>/dev/null || true
  warn "Docker Desktop is starting. Accept its first-run prompts, then wait for the whale icon to go steady."
fi

# ---------------------------------------------------------------------------
# 10. AWS credentials check
# ---------------------------------------------------------------------------
# The script never asks for or stores credentials. It only checks whether
# you have already configured them.
info "AWS credentials"
if aws sts get-caller-identity &>/dev/null; then
  ok "Authenticated as: $(aws sts get-caller-identity --query Arn --output text)"
else
  warn "No AWS credentials found. Configure them yourself with ONE of:"
  echo "        aws configure sso     # recommended: IAM Identity Center, short-lived credentials"
  echo "        aws configure         # IAM user access key (never use root account keys)"
  warn "Also set an AWS Budget alarm (\$10) in the Billing console before Day 1."
fi

# ---------------------------------------------------------------------------
# 11. Summary
# ---------------------------------------------------------------------------
info "Installed versions"
printf "    %-12s %s\n" "aws"       "$(aws --version 2>&1 | awk '{print $1}')"
printf "    %-12s %s\n" "terraform" "$(terraform version | head -1)"
printf "    %-12s %s\n" "tflint"    "$({ tflint --version 2>/dev/null || echo 'not installed'; } | head -1)"
printf "    %-12s %s\n" "kubectl"   "$(kubectl version --client 2>/dev/null | head -1)"
printf "    %-12s %s\n" "kind"      "$(kind version)"
printf "    %-12s %s\n" "helm"      "$(helm version --short)"
printf "    %-12s %s\n" "k9s"       "$(k9s version --short 2>/dev/null | head -1)"
printf "    %-12s %s\n" "docker"    "$(docker --version 2>/dev/null || echo 'installed – start Docker Desktop')"
printf "    %-12s %s\n" "jq"        "$(jq --version)"

cat <<'EOF'

✅ Setup complete.

Next steps:
  1. Reload your shell:            exec zsh
  2. Configure AWS (if not done):  aws configure sso
  3. Make sure Docker is running, then test kind:
       kind create cluster --name learn
       kubectl get nodes
       kind delete cluster --name learn
  4. Open learning-plan.md and start Day 1.
EOF
