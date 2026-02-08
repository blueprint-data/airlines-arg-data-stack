#!/bin/bash
set -e

echo "🚀 Setting up airlines-arg-data-stack Extraction local development environment"

# Function to check Python version
check_python_version() {
    local version=$1
    if ! command -v python3 &> /dev/null; then
        echo "❌ Python 3 is not installed. Please install Python $version or higher"
        exit 1
    fi
    
    local current_version=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:3])))')
    if [ "$(printf '%s\n' "$version" "$current_version" | sort -V | head -n1)" != "$version" ]; then
        echo "❌ Python $version or higher is required (you have $current_version)"
        exit 1
    fi
}

# Check Python version
MIN_PYTHON_VERSION="3.11.0"
echo "🐍 Checking Python version..."
check_python_version $MIN_PYTHON_VERSION

# Create virtual environment
VENV_DIR="venv"
echo "🔧 Creating virtual environment: $VENV_DIR"

if [ -d "$VENV_DIR" ]; then
    echo "♻️  Removing existing virtual environment..."
    rm -rf "$VENV_DIR"
fi

python3 -m venv "$VENV_DIR"
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
    source "$VENV_DIR/Scripts/activate"
else
    source "$VENV_DIR/bin/activate"
fi

# Upgrade pip
echo "⬆️  Upgrading pip..."
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
    python -m pip install --upgrade pip
else
    pip install --upgrade pip
fi

# Install uv
echo "⚡ Installing uv..."
pip install uv

# Install Meltano and dependencies from pyproject.toml
echo "🎵 Installing Meltano and dependencies..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
uv pip install -e "$REPO_ROOT[extraction]"

# Initialize Meltano if not already done
if [ ! -d ".meltano" ]; then
    echo "🎼 Initializing Meltano project..."
    meltano install
fi

# Ensure compatibility for target-bigquery plugin imports.
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
    TARGET_BQ_PY=".meltano/loaders/target-bigquery/venv/Scripts/python.exe"
else
    TARGET_BQ_PY=".meltano/loaders/target-bigquery/venv/bin/python"
fi

if [ -x "$TARGET_BQ_PY" ]; then
    echo "🧩 Pinning setuptools for target-bigquery compatibility..."
    uv pip install --python "$TARGET_BQ_PY" "setuptools<81"
fi

echo ""
echo "✅ Setup complete!"
echo ""
echo "📋 Next steps:"
echo "1. Configure your environment variables:"
echo "   Edit .env with your credentials"
echo ""
echo "2. Activate the virtual environment:"
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
    echo "   source venv/Scripts/activate"
else
    echo "   source venv/bin/activate"
fi
echo ""
echo "3. Configure your extractors and loaders in meltano.yml"
echo ""
echo "4. Test local extraction:"
echo "   meltano run <tap-name> <loader-name>"
