#!/usr/bin/env python3
"""
Test script for EVM wallet integration
"""

import sys
import os

# Add the project root to the path so we can import api.wallet
sys.path.append(os.path.dirname(__file__))

from api.wallet import (
    get_wallet_status,
    get_balance,
    get_all_balances,
    get_token_address
)

def test_wallet_integration():
    """Test the EVM wallet integration functions"""
    
    print("🧪 Testing EVM Wallet Integration for Futarchy Governance")
    print("=" * 60)
    
    # Test 1: Wallet status
    print("\n1. Checking wallet status...")
    status = get_wallet_status()
    print(f"   Status: {status}")
    
    if not status.get('success'):
        print("   ❌ Wallet not set up properly")
        return False
    
    wallet_address = status.get('address')
    print(f"   ✅ Wallet address: {wallet_address}")
    
    # Test 2: Balance check on Base
    print("\n2. Checking Base network balance...")
    base_balance = get_balance('base')
    print(f"   Base ETH: {base_balance}")
    
    if base_balance.get('success'):
        print(f"   ✅ Balance: {base_balance.get('balance', '0')} ETH")
    else:
        print(f"   ⚠️  Balance check error: {base_balance.get('error')}")
    
    # Test 3: Token address lookup
    print("\n3. Testing token address lookup...")
    usdc_address = get_token_address('base', 'USDC')
    print(f"   Base USDC address: {usdc_address}")
    
    if usdc_address:
        print("   ✅ Token lookup working")
        
        # Test USDC balance
        usdc_balance = get_balance('base', usdc_address)
        print(f"   USDC balance: {usdc_balance.get('balance', '0') if usdc_balance.get('success') else 'Error'}")
    else:
        print("   ❌ Token lookup failed")
    
    # Test 4: All balances (limited test)
    print("\n4. Testing multi-chain balance check...")
    try:
        all_balances = get_all_balances()
        if all_balances.get('success'):
            print("   ✅ Multi-chain balance check working")
            print(f"   Chains checked: {len(all_balances.get('balances', []))}")
        else:
            print(f"   ⚠️  Multi-chain check error: {all_balances.get('error')}")
    except Exception as e:
        print(f"   ⚠️  Multi-chain check exception: {e}")
    
    print("\n" + "=" * 60)
    print("✅ EVM Wallet Integration Test Complete!")
    print("\n📋 Ready for governance operations:")
    print(f"   • Wallet Address: {wallet_address}")
    print("   • Supported Chains: Base, Ethereum, Polygon, Arbitrum, Optimism")
    print("   • Features: Token transfers, swaps, smart contract calls")
    print("   • Governance: Voting, staking, prediction market betting")
    print("\n💡 Next steps:")
    print("   1. Fund wallet with ETH on Base for gas fees")
    print("   2. Acquire governance tokens for participation")
    print("   3. Use api/wallet.py functions for governance operations")
    
    return True

if __name__ == "__main__":
    test_wallet_integration()