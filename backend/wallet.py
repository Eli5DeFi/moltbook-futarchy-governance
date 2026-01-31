"""
EVM Wallet API Endpoints for Moltbook Futarchy Governance

Provides wallet functionality for governance participants including:
- Balance checking across multiple chains
- Token transfers and governance token management  
- Smart contract interactions for voting and staking
- Integration with prediction markets
"""

import os
import json
import subprocess
from datetime import datetime
from typing import Dict, Any, Optional

def run_wallet_command(command_args: list) -> Dict[str, Any]:
    """
    Execute EVM wallet command and return JSON result
    
    Args:
        command_args: List of command arguments to pass to wallet
        
    Returns:
        Dictionary containing command result or error
    """
    try:
        # Get skill directory
        skill_dir = os.path.join(os.path.dirname(__file__), '..', 'skills', 'evm-wallet')
        
        # Build full command
        cmd = ['node'] + [os.path.join(skill_dir, 'src', command_args[0])] + command_args[1:] + ['--json']
        
        # Execute command
        result = subprocess.run(cmd, cwd=skill_dir, capture_output=True, text=True, timeout=30)
        
        if result.returncode == 0:
            return json.loads(result.stdout)
        else:
            return {
                "success": False,
                "error": result.stderr or result.stdout,
                "command": " ".join(cmd)
            }
            
    except subprocess.TimeoutExpired:
        return {"success": False, "error": "Wallet command timeout"}
    except json.JSONDecodeError:
        return {"success": False, "error": "Invalid JSON response from wallet"}
    except Exception as e:
        return {"success": False, "error": str(e)}

def get_wallet_status() -> Dict[str, Any]:
    """Get wallet setup status and address"""
    try:
        wallet_file = os.path.expanduser('~/.evm-wallet.json')
        
        if not os.path.exists(wallet_file):
            return {
                "success": False,
                "message": "Wallet not found. Run setup first.",
                "setup_required": True
            }
        
        # Try to get wallet address from balance check
        result = run_wallet_command(['balance.js', 'base'])
        
        if result.get('success'):
            return {
                "success": True,
                "address": result.get('address'),
                "setup_complete": True,
                "chains": ["base", "ethereum", "polygon", "arbitrum", "optimism"]
            }
        else:
            return {
                "success": False,
                "error": result.get('error', 'Unknown error'),
                "setup_required": True
            }
            
    except Exception as e:
        return {"success": False, "error": str(e)}

def setup_wallet() -> Dict[str, Any]:
    """Initialize new wallet"""
    return run_wallet_command(['setup.js'])

def get_balance(chain: str = 'base', token_address: Optional[str] = None) -> Dict[str, Any]:
    """
    Get token balance for specific chain
    
    Args:
        chain: Blockchain network (base, ethereum, polygon, arbitrum, optimism)
        token_address: Optional ERC20 token contract address
        
    Returns:
        Balance information
    """
    if token_address:
        return run_wallet_command(['balance.js', chain, token_address])
    else:
        return run_wallet_command(['balance.js', chain])

def get_all_balances() -> Dict[str, Any]:
    """Get balances across all supported chains"""
    return run_wallet_command(['balance.js', '--all'])

def send_token(chain: str, to_address: str, amount: str, token_address: Optional[str] = None, confirm: bool = False) -> Dict[str, Any]:
    """
    Send ETH or ERC20 token
    
    Args:
        chain: Target blockchain
        to_address: Recipient address
        amount: Amount to send (in token units)
        token_address: Optional ERC20 token address (None for native ETH)
        confirm: Whether to execute (True) or just estimate (False)
        
    Returns:
        Transaction result or estimation
    """
    cmd_args = ['transfer.js', chain, to_address, amount]
    
    if token_address:
        cmd_args.append(token_address)
    
    if confirm:
        cmd_args.append('--yes')
    
    return run_wallet_command(cmd_args)

def swap_tokens(chain: str, from_token: str, to_token: str, amount: str, confirm: bool = False, slippage: float = 0.5) -> Dict[str, Any]:
    """
    Swap tokens via DEX aggregator
    
    Args:
        chain: Blockchain network
        from_token: Source token (use 'eth' for native token or contract address)
        to_token: Destination token (use 'eth' for native token or contract address)
        amount: Amount to swap
        confirm: Whether to execute (True) or get quote (False)
        slippage: Maximum slippage percentage
        
    Returns:
        Swap result or quote
    """
    cmd_args = ['swap.js', chain, from_token, to_token, amount, f'--slippage={slippage}']
    
    if not confirm:
        cmd_args.append('--quote-only')
    else:
        cmd_args.append('--yes')
    
    return run_wallet_command(cmd_args)

def call_contract(chain: str, contract_address: str, function_signature: str, *args, confirm: bool = False) -> Dict[str, Any]:
    """
    Call smart contract function
    
    Args:
        chain: Blockchain network
        contract_address: Contract address
        function_signature: Function signature (e.g., "vote(uint256,bool)")
        *args: Function arguments
        confirm: Whether to execute write operations
        
    Returns:
        Contract call result
    """
    cmd_args = ['contract.js', chain, contract_address, function_signature] + list(args)
    
    if confirm:
        cmd_args.append('--yes')
    
    return run_wallet_command(cmd_args)

# Governance-specific functions

def vote_on_proposal(proposal_id: int, vote: bool, chain: str = 'base', governance_contract: str = None) -> Dict[str, Any]:
    """
    Vote on governance proposal
    
    Args:
        proposal_id: ID of the proposal to vote on
        vote: True for YES, False for NO
        chain: Blockchain network
        governance_contract: Governance contract address
        
    Returns:
        Voting transaction result
    """
    if not governance_contract:
        return {"success": False, "error": "Governance contract address required"}
    
    return call_contract(
        chain, 
        governance_contract, 
        "vote(uint256,bool)", 
        str(proposal_id), 
        "true" if vote else "false",
        confirm=True
    )

def stake_tokens(amount: str, chain: str = 'base', staking_contract: str = None) -> Dict[str, Any]:
    """
    Stake governance tokens
    
    Args:
        amount: Amount to stake
        chain: Blockchain network  
        staking_contract: Staking contract address
        
    Returns:
        Staking transaction result
    """
    if not staking_contract:
        return {"success": False, "error": "Staking contract address required"}
    
    return call_contract(
        chain,
        staking_contract,
        "stake(uint256)",
        amount,
        confirm=True
    )

def get_governance_balance(chain: str = 'base', governance_token: str = None) -> Dict[str, Any]:
    """
    Get governance token balance
    
    Args:
        chain: Blockchain network
        governance_token: Governance token contract address
        
    Returns:
        Governance token balance
    """
    if not governance_token:
        return {"success": False, "error": "Governance token address required"}
    
    return get_balance(chain, governance_token)

def place_prediction_bet(proposal_id: int, position: bool, amount: str, chain: str = 'base', governance_contract: str = None) -> Dict[str, Any]:
    """
    Place bet in prediction market
    
    Args:
        proposal_id: Proposal ID
        position: True for YES outcome, False for NO
        amount: Amount to bet
        chain: Blockchain network
        governance_contract: Governance contract address
        
    Returns:
        Betting transaction result
    """
    if not governance_contract:
        return {"success": False, "error": "Governance contract address required"}
    
    return call_contract(
        chain,
        governance_contract,
        "placeBet(uint256,bool,uint256)",
        str(proposal_id),
        "true" if position else "false", 
        amount,
        confirm=True
    )

# Common token addresses for each chain
COMMON_TOKENS = {
    "base": {
        "USDC": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
        "WETH": "0x4200000000000000000000000000000000000006"
    },
    "ethereum": {
        "USDC": "0xA0b86a33E6441b8a46a59DE4c4C5E8F5a6a7A8d0", 
        "WETH": "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
    }
}

def get_token_address(chain: str, symbol: str) -> Optional[str]:
    """Get token contract address by symbol"""
    return COMMON_TOKENS.get(chain, {}).get(symbol.upper())

# Example usage functions for governance integration

def example_governance_flow():
    """Example of typical governance participation flow"""
    
    # 1. Check wallet status
    status = get_wallet_status()
    if not status.get('success'):
        print("Setting up wallet...")
        setup_result = setup_wallet()
        if not setup_result.get('success'):
            return {"error": "Wallet setup failed"}
    
    # 2. Check governance token balance
    gov_token = "0xGOVERNANCE_TOKEN_ADDRESS"  # Replace with actual address
    balance = get_governance_balance('base', gov_token)
    print(f"Governance token balance: {balance}")
    
    # 3. Vote on proposal
    proposal_id = 1
    vote_result = vote_on_proposal(proposal_id, True, 'base', "0xGOVERNANCE_CONTRACT")
    print(f"Vote result: {vote_result}")
    
    # 4. Place prediction market bet
    bet_result = place_prediction_bet(proposal_id, True, "100", 'base', "0xGOVERNANCE_CONTRACT")
    print(f"Bet result: {bet_result}")
    
    return {"success": True, "actions_completed": ["setup", "balance_check", "vote", "bet"]}

if __name__ == "__main__":
    # Test wallet functionality
    print("Testing wallet integration...")
    print(example_governance_flow())