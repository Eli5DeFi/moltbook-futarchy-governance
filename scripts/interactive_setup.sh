#!/bin/bash

# Interactive Setup Script for Moltbook Futarchy Governance System
# Makes deployment as easy as possible for new users

set -e

echo "🏛️ Welcome to Moltbook Futarchy Governance System Setup!"
echo "======================================================"
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running on macOS or Linux
if [[ "$OSTYPE" == "darwin"* ]]; then
    PLATFORM="macOS"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    PLATFORM="Linux"
else
    echo -e "${RED}❌ Unsupported platform: $OSTYPE${NC}"
    exit 1
fi

echo -e "${BLUE}🔍 Detected platform: $PLATFORM${NC}"
echo ""

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install dependencies on macOS
install_macos_deps() {
    echo -e "${YELLOW}📦 Installing dependencies for macOS...${NC}"
    
    # Check for Homebrew
    if ! command_exists brew; then
        echo -e "${BLUE}Installing Homebrew...${NC}"
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    
    # Install Python if not present
    if ! command_exists python3; then
        echo -e "${BLUE}Installing Python 3...${NC}"
        brew install python@3.11
    fi
    
    # Install Node.js if not present
    if ! command_exists node; then
        echo -e "${BLUE}Installing Node.js...${NC}"
        brew install node
    fi
    
    # Install Foundry if not present
    if ! command_exists forge; then
        echo -e "${BLUE}Installing Foundry...${NC}"
        curl -L https://foundry.paradigm.xyz | bash
        source ~/.bashrc || source ~/.zshrc || true
        foundryup
    fi
}

# Function to install dependencies on Linux
install_linux_deps() {
    echo -e "${YELLOW}📦 Installing dependencies for Linux...${NC}"
    
    # Update package list
    sudo apt update
    
    # Install Python if not present
    if ! command_exists python3; then
        echo -e "${BLUE}Installing Python 3...${NC}"
        sudo apt install -y python3 python3-pip python3-venv
    fi
    
    # Install Node.js if not present
    if ! command_exists node; then
        echo -e "${BLUE}Installing Node.js...${NC}"
        curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
        sudo apt-get install -y nodejs
    fi
    
    # Install Foundry if not present
    if ! command_exists forge; then
        echo -e "${BLUE}Installing Foundry...${NC}"
        curl -L https://foundry.paradigm.xyz | bash
        source ~/.bashrc
        foundryup
    fi
    
    # Install git if not present
    if ! command_exists git; then
        echo -e "${BLUE}Installing Git...${NC}"
        sudo apt install -y git
    fi
}

# Check and install dependencies
echo -e "${YELLOW}🔧 Checking dependencies...${NC}"

if [[ "$PLATFORM" == "macOS" ]]; then
    install_macos_deps
elif [[ "$PLATFORM" == "Linux" ]]; then
    install_linux_deps
fi

echo ""
echo -e "${GREEN}✅ All dependencies installed!${NC}"
echo ""

# Install Python packages
echo -e "${YELLOW}🐍 Installing Python packages...${NC}"

# Create virtual environment if it doesn't exist
if [[ ! -d "venv" ]]; then
    python3 -m venv venv
fi

source venv/bin/activate

# Install required Python packages
pip install --upgrade pip
pip install web3 aiohttp requests python-dotenv solcx eth-account

echo -e "${GREEN}✅ Python packages installed!${NC}"
echo ""

# Setup environment file
echo -e "${YELLOW}⚙️ Setting up environment configuration...${NC}"

if [[ ! -f ".env" ]]; then
    cat > .env << 'EOF'
# Blockchain Configuration
WEB3_URL=http://localhost:8545
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
CHAIN_ID=31337

# Moltbook API Configuration (update with your credentials)
MOLTBOOK_API_URL=https://api.moltbook.com
MOLTBOOK_API_KEY=your-api-key-here
MOLTBOOK_USERNAME=governance-bot

# Bankr Integration (update with your credentials)
BANKR_API_URL=https://api.bankr.com
BANKR_API_KEY=your-bankr-api-key
EOF
    
    echo -e "${GREEN}✅ Environment file created: .env${NC}"
    echo -e "${BLUE}📝 Please edit .env with your API credentials${NC}"
else
    echo -e "${BLUE}ℹ️ Environment file already exists${NC}"
fi

echo ""

# Start local blockchain
echo -e "${YELLOW}🔗 Do you want to start a local blockchain? (y/n):${NC}"
read -r start_blockchain

if [[ $start_blockchain =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}🚀 Starting Anvil (local blockchain)...${NC}"
    echo -e "${YELLOW}Note: This will run in the background. Use 'pkill anvil' to stop it.${NC}"
    
    # Start Anvil in background
    nohup anvil --host 0.0.0.0 --port 8545 --chain-id 31337 > anvil.log 2>&1 &
    
    # Wait a moment for Anvil to start
    sleep 3
    
    # Check if Anvil is running
    if curl -s -X POST -H "Content-Type: application/json" \
       --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
       http://localhost:8545 > /dev/null; then
        echo -e "${GREEN}✅ Local blockchain started successfully!${NC}"
        echo -e "${BLUE}📍 RPC URL: http://localhost:8545${NC}"
        echo -e "${BLUE}📍 Chain ID: 31337${NC}"
    else
        echo -e "${RED}❌ Failed to start local blockchain${NC}"
        echo -e "${YELLOW}💡 You can manually start it with: anvil --host 0.0.0.0 --port 8545 --chain-id 31337${NC}"
    fi
else
    echo -e "${BLUE}ℹ️ Skipping local blockchain setup${NC}"
    echo -e "${YELLOW}💡 Make sure to update WEB3_URL in .env for your blockchain provider${NC}"
fi

echo ""

# Deploy contracts
echo -e "${YELLOW}🚀 Do you want to deploy the governance contracts? (y/n):${NC}"
read -r deploy_contracts

if [[ $deploy_contracts =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}📝 Deploying governance system contracts...${NC}"
    
    # Make sure we're in the virtual environment
    source venv/bin/activate
    
    # Run deployment
    if python scripts/deploy_governance.py; then
        echo -e "${GREEN}✅ Contracts deployed successfully!${NC}"
        echo -e "${BLUE}📄 Deployment details saved to: deployment.json${NC}"
    else
        echo -e "${RED}❌ Contract deployment failed${NC}"
        echo -e "${YELLOW}💡 Check the logs above for error details${NC}"
    fi
else
    echo -e "${BLUE}ℹ️ Skipping contract deployment${NC}"
    echo -e "${YELLOW}💡 You can deploy later with: python scripts/deploy_governance.py${NC}"
fi

echo ""

# Setup GitHub integration
echo -e "${YELLOW}🐙 Do you want to set up GitHub integration? (y/n):${NC}"
read -r setup_github

if [[ $setup_github =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}📝 Setting up GitHub integration...${NC}"
    
    # Check if git is configured
    if ! git config user.name > /dev/null 2>&1; then
        echo -e "${YELLOW}⚙️ Git not configured. Let's set it up:${NC}"
        echo -n "Enter your name: "
        read -r git_name
        echo -n "Enter your email: "
        read -r git_email
        
        git config --global user.name "$git_name"
        git config --global user.email "$git_email"
    fi
    
    # Check if GitHub CLI is installed
    if command_exists gh; then
        echo -e "${GREEN}✅ GitHub CLI found${NC}"
        
        # Check if authenticated
        if gh auth status > /dev/null 2>&1; then
            echo -e "${GREEN}✅ GitHub CLI authenticated${NC}"
        else
            echo -e "${YELLOW}🔐 Authenticating with GitHub...${NC}"
            gh auth login
        fi
    else
        echo -e "${YELLOW}📦 Installing GitHub CLI...${NC}"
        if [[ "$PLATFORM" == "macOS" ]]; then
            brew install gh
        elif [[ "$PLATFORM" == "Linux" ]]; then
            curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
            sudo apt update
            sudo apt install gh
        fi
        
        echo -e "${YELLOW}🔐 Authenticating with GitHub...${NC}"
        gh auth login
    fi
    
    echo -e "${GREEN}✅ GitHub integration ready!${NC}"
else
    echo -e "${BLUE}ℹ️ Skipping GitHub integration${NC}"
fi

echo ""

# Start evolution engine
echo -e "${YELLOW}🧬 Do you want to start the evolution engine? (y/n):${NC}"
read -r start_evolution

if [[ $start_evolution =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}🧬 Starting autonomous evolution engine...${NC}"
    
    # Make evolution script executable
    chmod +x scripts/evolution_engine.py
    
    # Run first evolution cycle
    source venv/bin/activate
    python scripts/evolution_engine.py --analyze
    
    echo -e "${GREEN}✅ Evolution engine initialized!${NC}"
    echo -e "${BLUE}🔄 The system will now evolve every 6 hours automatically${NC}"
else
    echo -e "${BLUE}ℹ️ Skipping evolution engine startup${NC}"
    echo -e "${YELLOW}💡 You can start it later with: python scripts/evolution_engine.py${NC}"
fi

echo ""

# Open dashboard
echo -e "${YELLOW}📊 Do you want to open the governance dashboard? (y/n):${NC}"
read -r open_dashboard

if [[ $open_dashboard =~ ^[Yy]$ ]]; then
    if [[ -f "dashboard.html" ]]; then
        echo -e "${BLUE}🌐 Opening governance dashboard...${NC}"
        
        if [[ "$PLATFORM" == "macOS" ]]; then
            open dashboard.html
        elif [[ "$PLATFORM" == "Linux" ]]; then
            if command_exists xdg-open; then
                xdg-open dashboard.html
            else
                echo -e "${YELLOW}💡 Open dashboard.html in your browser manually${NC}"
            fi
        fi
    else
        echo -e "${BLUE}📊 Creating governance dashboard...${NC}"
        python scripts/evolution_engine.py --analyze
        
        if [[ "$PLATFORM" == "macOS" ]]; then
            open dashboard.html
        elif [[ "$PLATFORM" == "Linux" ]]; then
            if command_exists xdg-open; then
                xdg-open dashboard.html
            fi
        fi
    fi
fi

echo ""

# Setup complete
echo -e "${GREEN}🎉 Setup Complete!${NC}"
echo "========================================"
echo ""
echo -e "${BLUE}📋 Next Steps:${NC}"
echo -e "1. ${YELLOW}Edit .env${NC} with your API credentials"
echo -e "2. ${YELLOW}Review deployment.json${NC} for contract addresses"
echo -e "3. ${YELLOW}Open dashboard.html${NC} to monitor governance"
echo -e "4. ${YELLOW}Read QUICKSTART.md${NC} for usage examples"
echo -e "5. ${YELLOW}Check README.md${NC} for full documentation"
echo ""
echo -e "${BLUE}🔧 Useful Commands:${NC}"
echo -e "• Start blockchain: ${YELLOW}anvil --host 0.0.0.0 --port 8545 --chain-id 31337${NC}"
echo -e "• Deploy contracts: ${YELLOW}python scripts/deploy_governance.py${NC}"
echo -e "• Run evolution: ${YELLOW}python scripts/evolution_engine.py${NC}"
echo -e "• Start Moltbook integration: ${YELLOW}python scripts/moltbook_integration.py${NC}"
echo ""
echo -e "${GREEN}🏛️ Welcome to autonomous AI governance!${NC}"
echo -e "${BLUE}🚀 Your system will evolve automatically every 6 hours${NC}"
echo ""