#!/usr/bin/env python3
"""
Moltbook Governance Integration Script
Connects the Futarchy governance system with Moltbook platform
"""

import asyncio
import json
import time
import logging
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple
import aiohttp
import requests
from web3 import Web3
from eth_account import Account
from dataclasses import dataclass

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@dataclass
class GovernanceConfig:
    """Configuration for the governance system"""
    web3_url: str
    private_key: str
    contract_addresses: Dict[str, str]
    moltbook_api_url: str
    moltbook_api_key: str
    moltbook_username: str

@dataclass
class ProposalMetrics:
    """Metrics for evaluating proposal outcomes"""
    proposal_id: int
    title: str
    start_time: datetime
    end_time: Optional[datetime]
    total_stakes: float
    participant_count: int
    yes_votes: float
    no_votes: float
    actual_outcome: Optional[float]
    success_metrics: List[str]

class MoltbookAPI:
    """Interface to Moltbook platform"""
    
    def __init__(self, api_url: str, api_key: str, username: str):
        self.api_url = api_url.rstrip('/')
        self.api_key = api_key
        self.username = username
        self.session = None

    async def __aenter__(self):
        self.session = aiohttp.ClientSession(
            headers={'Authorization': f'Bearer {self.api_key}'}
        )
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        if self.session:
            await self.session.close()

    async def get_agent_karma(self, username: str) -> Dict:
        """Fetch agent karma and reputation from Moltbook"""
        try:
            async with self.session.get(f"{self.api_url}/agents/{username}/reputation") as resp:
                if resp.status == 200:
                    return await resp.json()
                else:
                    logger.error(f"Failed to fetch karma for {username}: {resp.status}")
                    return {}
        except Exception as e:
            logger.error(f"Error fetching karma: {e}")
            return {}

    async def post_governance_update(self, content: str, proposal_id: int) -> bool:
        """Post governance update to Moltbook"""
        try:
            payload = {
                "content": content,
                "type": "governance_update",
                "metadata": {
                    "proposal_id": proposal_id,
                    "timestamp": datetime.utcnow().isoformat()
                }
            }
            
            async with self.session.post(f"{self.api_url}/posts", json=payload) as resp:
                return resp.status in [200, 201]
        except Exception as e:
            logger.error(f"Error posting update: {e}")
            return False

    async def get_agent_activity(self, username: str, days: int = 30) -> Dict:
        """Get recent activity metrics for an agent"""
        try:
            end_date = datetime.utcnow()
            start_date = end_date - timedelta(days=days)
            
            async with self.session.get(
                f"{self.api_url}/agents/{username}/activity",
                params={
                    'start': start_date.isoformat(),
                    'end': end_date.isoformat()
                }
            ) as resp:
                if resp.status == 200:
                    return await resp.json()
                return {}
        except Exception as e:
            logger.error(f"Error fetching activity: {e}")
            return {}

    async def notify_agents(self, agent_list: List[str], message: str, proposal_id: int) -> int:
        """Send notifications to a list of agents"""
        success_count = 0
        
        for agent in agent_list:
            try:
                payload = {
                    "recipient": agent,
                    "message": message,
                    "type": "governance_notification",
                    "proposal_id": proposal_id
                }
                
                async with self.session.post(f"{self.api_url}/notifications", json=payload) as resp:
                    if resp.status in [200, 201]:
                        success_count += 1
                        
            except Exception as e:
                logger.error(f"Error notifying {agent}: {e}")
                
        return success_count

class GovernanceOrchestrator:
    """Main orchestrator for the Moltbook governance system"""
    
    def __init__(self, config: GovernanceConfig):
        self.config = config
        self.web3 = Web3(Web3.HTTPProvider(config.web3_url))
        self.account = Account.from_key(config.private_key)
        self.contracts = {}
        self.moltbook = None
        self.running = False
        
        # Load contract ABIs (simplified for demo)
        self.load_contracts()

    def load_contracts(self):
        """Load smart contract interfaces"""
        # In production, load actual ABIs
        # For now, we'll create simplified interfaces
        
        governance_abi = [
            {"name": "getProposal", "type": "function", "inputs": [{"name": "id", "type": "uint256"}]},
            {"name": "proposals", "type": "function", "inputs": [{"name": "", "type": "uint256"}]},
            {"name": "createProposal", "type": "function"},
            {"name": "reportOutcome", "type": "function"}
        ]
        
        self.contracts['governance'] = self.web3.eth.contract(
            address=self.config.contract_addresses['governance'],
            abi=governance_abi
        )

    async def start_monitoring(self):
        """Start the governance monitoring loop"""
        self.running = True
        logger.info("Starting Moltbook governance monitoring...")
        
        async with MoltbookAPI(
            self.config.moltbook_api_url,
            self.config.moltbook_api_key,
            self.config.moltbook_username
        ) as moltbook:
            self.moltbook = moltbook
            
            while self.running:
                try:
                    await self.monitoring_cycle()
                    await asyncio.sleep(300)  # 5 minute cycles
                except Exception as e:
                    logger.error(f"Error in monitoring cycle: {e}")
                    await asyncio.sleep(60)  # Shorter wait on error

    async def monitoring_cycle(self):
        """Execute one monitoring cycle"""
        logger.info("Executing governance monitoring cycle...")
        
        # 1. Update reputation data from Moltbook
        await self.update_reputation_data()
        
        # 2. Check for active proposals
        await self.check_active_proposals()
        
        # 3. Measure outcomes for completed proposals
        await self.measure_proposal_outcomes()
        
        # 4. Update governance metrics
        await self.update_governance_metrics()
        
        # 5. Post community updates
        await self.post_community_updates()

    async def update_reputation_data(self):
        """Update reputation oracle with latest Moltbook data"""
        logger.info("Updating reputation data...")
        
        # Get list of verified agents (would come from contract)
        verified_agents = await self.get_verified_agents()
        
        for agent_address, moltbook_username in verified_agents:
            try:
                # Fetch latest karma and activity
                karma_data = await self.moltbook.get_agent_karma(moltbook_username)
                activity_data = await self.moltbook.get_agent_activity(moltbook_username)
                
                if karma_data:
                    # Update reputation oracle contract
                    await self.update_agent_reputation(
                        agent_address,
                        karma_data.get('karma', 0),
                        karma_data.get('posts', 0),
                        activity_data.get('interactions', 0),
                        karma_data.get('quality_score', 0)
                    )
                    
            except Exception as e:
                logger.error(f"Error updating reputation for {moltbook_username}: {e}")

    async def check_active_proposals(self):
        """Check and manage active proposals"""
        logger.info("Checking active proposals...")
        
        # Get active proposals from governance contract
        active_proposals = await self.get_active_proposals()
        
        for proposal in active_proposals:
            proposal_id = proposal['id']
            deadline = proposal['deadline']
            
            # Check if voting is ending soon (within 24 hours)
            if deadline - time.time() < 86400:  # 24 hours
                await self.send_voting_reminders(proposal_id)
            
            # Check if proposal is ready for execution
            if time.time() > deadline and not proposal['executed']:
                await self.queue_proposal_execution(proposal_id)

    async def measure_proposal_outcomes(self):
        """Measure and report outcomes for completed proposals"""
        logger.info("Measuring proposal outcomes...")
        
        # Get proposals pending outcome measurement
        pending_proposals = await self.get_pending_outcome_proposals()
        
        for proposal in pending_proposals:
            try:
                outcome = await self.measure_proposal_success(proposal)
                if outcome is not None:
                    await self.report_proposal_outcome(proposal['id'], outcome)
                    
            except Exception as e:
                logger.error(f"Error measuring outcome for proposal {proposal['id']}: {e}")

    async def measure_proposal_success(self, proposal: Dict) -> Optional[float]:
        """Measure the success of a completed proposal"""
        proposal_id = proposal['id']
        deliverables = proposal.get('deliverables', {})
        
        success_score = 0.0
        total_metrics = 0
        
        # Check repository deliverables
        if 'repository' in deliverables:
            repo_success = await self.check_repository_deliverable(
                deliverables['repository'],
                deliverables.get('milestones', [])
            )
            success_score += repo_success
            total_metrics += 1

        # Check demo/product deliverables
        if 'demoLink' in deliverables:
            demo_success = await self.check_demo_deliverable(deliverables['demoLink'])
            success_score += demo_success
            total_metrics += 1

        # Check community impact metrics
        community_impact = await self.measure_community_impact(proposal_id)
        success_score += community_impact
        total_metrics += 1

        return success_score / total_metrics if total_metrics > 0 else None

    async def check_repository_deliverable(self, repo_url: str, milestones: List[int]) -> float:
        """Check if repository deliverables are completed"""
        try:
            # Simple check: verify repo exists and has recent commits
            # In production, this would be more sophisticated
            
            # Parse GitHub URL
            if 'github.com' in repo_url:
                parts = repo_url.rstrip('/').split('/')
                if len(parts) >= 2:
                    owner, repo = parts[-2], parts[-1]
                    
                    # Check repository activity
                    api_url = f"https://api.github.com/repos/{owner}/{repo}"
                    async with aiohttp.ClientSession() as session:
                        async with session.get(api_url) as resp:
                            if resp.status == 200:
                                data = await resp.json()
                                
                                # Check if recently updated
                                updated = datetime.fromisoformat(data['updated_at'].replace('Z', '+00:00'))
                                days_since_update = (datetime.now(updated.tzinfo) - updated).days
                                
                                if days_since_update < 7:  # Updated within a week
                                    return 1.0
                                elif days_since_update < 30:  # Updated within a month
                                    return 0.7
                                else:
                                    return 0.3
            
            return 0.5  # Default score if can't verify
            
        except Exception as e:
            logger.error(f"Error checking repository: {e}")
            return 0.0

    async def check_demo_deliverable(self, demo_url: str) -> float:
        """Check if demo is accessible and functional"""
        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(demo_url) as resp:
                    if resp.status == 200:
                        return 1.0
                    elif resp.status in [404, 500, 502, 503]:
                        return 0.0
                    else:
                        return 0.5
        except Exception:
            return 0.0

    async def measure_community_impact(self, proposal_id: int) -> float:
        """Measure community engagement and impact"""
        try:
            # Check Moltbook for posts/discussions about this proposal
            # This is a simplified metric
            
            # In production, would analyze:
            # - Number of community posts referencing the proposal
            # - Engagement metrics (likes, comments, shares)
            # - Adoption metrics if it's a feature/tool
            
            return 0.7  # Placeholder
            
        except Exception as e:
            logger.error(f"Error measuring community impact: {e}")
            return 0.5

    async def update_governance_metrics(self):
        """Calculate and update overall governance metrics"""
        logger.info("Updating governance metrics...")
        
        try:
            # Calculate metrics from historical data
            metrics = await self.calculate_governance_metrics()
            
            # Update the Evolution Engine contract
            await self.update_evolution_metrics(
                metrics['proposal_quality'],
                metrics['participation_rate'],
                metrics['outcome_accuracy'],
                metrics['product_delivery'],
                metrics['time_to_execution'],
                metrics['staking_efficiency']
            )
            
        except Exception as e:
            logger.error(f"Error updating governance metrics: {e}")

    async def calculate_governance_metrics(self) -> Dict[str, float]:
        """Calculate current governance performance metrics"""
        # Get historical data from contracts
        total_proposals = 10  # Placeholder - would get from contract
        successful_proposals = 7  # Placeholder
        total_participants = 50  # Placeholder
        eligible_voters = 100  # Placeholder
        
        return {
            'proposal_quality': (successful_proposals / total_proposals * 100) if total_proposals > 0 else 0,
            'participation_rate': (total_participants / eligible_voters * 100) if eligible_voters > 0 else 0,
            'outcome_accuracy': 75,  # Placeholder - prediction vs reality accuracy
            'product_delivery': 80,  # Placeholder - % of proposals delivering products
            'time_to_execution': 10 * 24 * 3600,  # 10 days in seconds
            'staking_efficiency': 85  # Placeholder - reward distribution effectiveness
        }

    async def post_community_updates(self):
        """Post governance updates to the Moltbook community"""
        try:
            # Get recent governance activity
            recent_activity = await self.get_recent_governance_activity()
            
            if recent_activity:
                update_content = self.format_governance_update(recent_activity)
                await self.moltbook.post_governance_update(update_content, 0)
                
        except Exception as e:
            logger.error(f"Error posting community updates: {e}")

    def format_governance_update(self, activity: Dict) -> str:
        """Format governance activity into a community update"""
        update = "🏛️ **Governance Update**\n\n"
        
        if activity.get('new_proposals'):
            update += f"📝 {len(activity['new_proposals'])} new proposals this period\n"
        
        if activity.get('completed_proposals'):
            update += f"✅ {len(activity['completed_proposals'])} proposals completed\n"
        
        if activity.get('metrics'):
            metrics = activity['metrics']
            update += f"📊 Current metrics:\n"
            update += f"  • Proposal success rate: {metrics.get('success_rate', 0):.1f}%\n"
            update += f"  • Participation rate: {metrics.get('participation', 0):.1f}%\n"
            update += f"  • Prediction accuracy: {metrics.get('accuracy', 0):.1f}%\n"
        
        update += "\n🔗 Participate in governance: [link to governance interface]"
        
        return update

    # Placeholder methods for contract interactions
    async def get_verified_agents(self) -> List[Tuple[str, str]]:
        """Get list of verified agents from reputation oracle"""
        # In production, would call reputation oracle contract
        return [
            ("0x742d35Cc6634C0532925a3b8D8BaD69C0A12C5e8", "agent1"),
            ("0x8ba1f109551bD432803012645Hac136c8Bda7d37", "agent2")
        ]

    async def update_agent_reputation(self, address: str, karma: int, posts: int, interactions: int, quality: int):
        """Update agent reputation in the oracle contract"""
        # Would call the reputation oracle's updateMoltbookData function
        pass

    async def get_active_proposals(self) -> List[Dict]:
        """Get active proposals from governance contract"""
        # Would call governance contract
        return []

    async def get_pending_outcome_proposals(self) -> List[Dict]:
        """Get proposals pending outcome measurement"""
        # Would call governance contract
        return []

    async def report_proposal_outcome(self, proposal_id: int, outcome: float):
        """Report measured outcome to governance contract"""
        # Would call reputation oracle's reportOutcome function
        pass

    async def update_evolution_metrics(self, quality: float, participation: float, accuracy: float, 
                                     delivery: float, execution_time: float, efficiency: float):
        """Update evolution engine with latest metrics"""
        # Would call evolution engine's updateMetrics function
        pass

    async def get_recent_governance_activity(self) -> Dict:
        """Get recent governance activity for community updates"""
        return {
            'new_proposals': [],
            'completed_proposals': [],
            'metrics': {
                'success_rate': 75.0,
                'participation': 60.0,
                'accuracy': 68.0
            }
        }

    async def send_voting_reminders(self, proposal_id: int):
        """Send voting reminders to eligible agents"""
        # Get eligible voters who haven't voted yet
        # Send notifications via Moltbook
        pass

    async def queue_proposal_execution(self, proposal_id: int):
        """Queue a proposal for execution"""
        # Call governance contract to execute proposal
        pass

    def stop_monitoring(self):
        """Stop the monitoring loop"""
        self.running = False

# Configuration and main execution
async def main():
    """Main execution function"""
    config = GovernanceConfig(
        web3_url="http://localhost:8545",  # Local Anvil instance
        private_key="0x...",  # Private key for transactions
        contract_addresses={
            "governance": "0x...",
            "reputation": "0x...", 
            "bankr": "0x...",
            "evolution": "0x..."
        },
        moltbook_api_url="https://api.moltbook.com",
        moltbook_api_key="your-api-key",
        moltbook_username="governance-bot"
    )
    
    orchestrator = GovernanceOrchestrator(config)
    
    try:
        await orchestrator.start_monitoring()
    except KeyboardInterrupt:
        logger.info("Stopping governance monitoring...")
        orchestrator.stop_monitoring()

if __name__ == "__main__":
    asyncio.run(main())