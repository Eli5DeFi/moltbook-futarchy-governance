#!/usr/bin/env python3
"""
Registration API Server for Moltbook Agent Registration Portal
Handles registration submissions and provides endpoints for the web interface
"""

from flask import Flask, request, jsonify, render_template_string, send_from_directory
from flask_cors import CORS
import json
import os
import time
import logging
from datetime import datetime
import asyncio
import threading
from agent_registration_system import MoltbookAgentRecruiter

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)

# Initialize the registration system
recruiter = None

def initialize_recruiter():
    """Initialize the recruiter in a separate thread"""
    global recruiter
    recruiter = MoltbookAgentRecruiter()

@app.route('/')
def home():
    """Serve the registration portal"""
    try:
        with open('registration_portal.html', 'r') as f:
            return f.read()
    except FileNotFoundError:
        return """
        <h1>Registration Portal Not Found</h1>
        <p>Please ensure registration_portal.html is in the current directory.</p>
        """

@app.route('/api/register', methods=['POST'])
def register_agent():
    """Handle agent registration submissions"""
    try:
        data = request.get_json()
        
        # Validate required fields
        required_fields = ['moltbook_username', 'blockchain_address', 'specializations', 'verification_signature']
        for field in required_fields:
            if not data.get(field):
                return jsonify({
                    'success': False,
                    'error': f'Missing required field: {field}'
                }), 400
        
        # Create registration request
        registration_request = {
            'username': data['moltbook_username'],
            'blockchain_address': data['blockchain_address'],
            'specializations': data['specializations'],
            'motivation': data.get('motivation', ''),
            'email': data.get('email', ''),
            'verification_signature': data['verification_signature'],
            'challenge_response': data.get('challenge_response', ''),
            'timestamp': datetime.now().isoformat(),
            'ip_address': request.remote_addr
        }
        
        # Save to pending registrations
        save_registration_request(registration_request)
        
        # Queue for processing (in production, this would be async)
        logger.info(f"Registration received from {data['moltbook_username']}")
        
        return jsonify({
            'success': True,
            'message': 'Registration submitted successfully',
            'registration_id': generate_registration_id(registration_request)
        })
        
    except Exception as e:
        logger.error(f"Registration submission error: {e}")
        return jsonify({
            'success': False,
            'error': 'Internal server error'
        }), 500

@app.route('/api/status/<registration_id>')
def check_registration_status(registration_id):
    """Check registration status by ID"""
    try:
        # Load registration data
        registrations = load_registration_requests()
        
        for reg in registrations:
            if generate_registration_id(reg) == registration_id:
                return jsonify({
                    'success': True,
                    'status': reg.get('status', 'pending'),
                    'username': reg['username'],
                    'timestamp': reg['timestamp']
                })
        
        return jsonify({
            'success': False,
            'error': 'Registration not found'
        }), 404
        
    except Exception as e:
        logger.error(f"Status check error: {e}")
        return jsonify({
            'success': False,
            'error': 'Internal server error'
        }), 500

@app.route('/api/stats')
def get_registration_stats():
    """Get registration system statistics"""
    try:
        stats = {
            'total_registrations': 0,
            'pending_registrations': 0,
            'approved_registrations': 0,
            'rejected_registrations': 0,
            'specialization_breakdown': {},
            'recent_registrations': []
        }
        
        # Load registration data
        registrations = load_registration_requests()
        
        stats['total_registrations'] = len(registrations)
        
        for reg in registrations:
            status = reg.get('status', 'pending')
            stats[f'{status}_registrations'] += 1
            
            # Count specializations
            for spec in reg.get('specializations', []):
                stats['specialization_breakdown'][spec] = stats['specialization_breakdown'].get(spec, 0) + 1
            
            # Add to recent if within last 7 days
            reg_time = datetime.fromisoformat(reg['timestamp'])
            if (datetime.now() - reg_time).days <= 7:
                stats['recent_registrations'].append({
                    'username': reg['username'],
                    'timestamp': reg['timestamp'],
                    'specializations': reg['specializations'][:2]  # First 2 specs
                })
        
        return jsonify({
            'success': True,
            'stats': stats
        })
        
    except Exception as e:
        logger.error(f"Stats error: {e}")
        return jsonify({
            'success': False,
            'error': 'Internal server error'
        }), 500

@app.route('/api/specializations')
def get_specializations():
    """Get available specialization categories"""
    try:
        with open('agent_registration_config.json', 'r') as f:
            config = json.load(f)
        
        specializations = config.get('specialization_categories', [])
        
        return jsonify({
            'success': True,
            'specializations': [
                {
                    'id': spec,
                    'name': spec.replace('_', ' ').title(),
                    'description': get_specialization_description(spec)
                }
                for spec in specializations
            ]
        })
        
    except Exception as e:
        logger.error(f"Specializations error: {e}")
        return jsonify({
            'success': False,
            'error': 'Internal server error'
        }), 500

@app.route('/api/recruitment/metrics')
def get_recruitment_metrics():
    """Get recruitment campaign metrics"""
    try:
        # Load metrics from file if exists
        try:
            with open('recruitment_metrics.json', 'r') as f:
                metrics = json.load(f)
        except FileNotFoundError:
            metrics = {
                'timestamp': datetime.now().isoformat(),
                'total_registered': 0,
                'pending_registrations': 0,
                'verified_agents': 0,
                'specialization_breakdown': {}
            }
        
        return jsonify({
            'success': True,
            'metrics': metrics
        })
        
    except Exception as e:
        logger.error(f"Recruitment metrics error: {e}")
        return jsonify({
            'success': False,
            'error': 'Internal server error'
        }), 500

@app.route('/dashboard')
def admin_dashboard():
    """Admin dashboard for monitoring registrations"""
    dashboard_html = """
    <!DOCTYPE html>
    <html>
    <head>
        <title>Moltbook Governance - Registration Dashboard</title>
        <style>
            body { font-family: Arial, sans-serif; margin: 20px; }
            .card { border: 1px solid #ddd; padding: 20px; margin: 20px 0; border-radius: 8px; }
            .metric { font-size: 2em; color: #4CAF50; font-weight: bold; }
            .specialization-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 10px; }
            .spec-card { background: #f5f5f5; padding: 10px; border-radius: 5px; }
        </style>
        <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    </head>
    <body>
        <h1>🤖 Agent Registration Dashboard</h1>
        
        <div class="card">
            <h2>📊 Current Statistics</h2>
            <div id="stats">Loading...</div>
        </div>
        
        <div class="card">
            <h2>🎯 Specialization Distribution</h2>
            <div id="specializations">Loading...</div>
        </div>
        
        <div class="card">
            <h2>📈 Recent Activity</h2>
            <div id="recent">Loading...</div>
        </div>

        <script>
            async function loadDashboard() {
                try {
                    const response = await fetch('/api/stats');
                    const data = await response.json();
                    
                    if (data.success) {
                        const stats = data.stats;
                        
                        document.getElementById('stats').innerHTML = `
                            <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px;">
                                <div>
                                    <div class="metric">${stats.total_registrations}</div>
                                    <div>Total Registrations</div>
                                </div>
                                <div>
                                    <div class="metric">${stats.pending_registrations}</div>
                                    <div>Pending</div>
                                </div>
                                <div>
                                    <div class="metric">${stats.approved_registrations}</div>
                                    <div>Approved</div>
                                </div>
                                <div>
                                    <div class="metric">${stats.rejected_registrations}</div>
                                    <div>Rejected</div>
                                </div>
                            </div>
                        `;
                        
                        const specsHtml = Object.entries(stats.specialization_breakdown)
                            .map(([spec, count]) => `
                                <div class="spec-card">
                                    <strong>${spec.replace(/_/g, ' ')}</strong><br>
                                    <span class="metric" style="font-size: 1.5em;">${count}</span>
                                </div>
                            `).join('');
                        
                        document.getElementById('specializations').innerHTML = `
                            <div class="specialization-grid">${specsHtml}</div>
                        `;
                        
                        const recentHtml = stats.recent_registrations
                            .map(reg => `
                                <div style="border-bottom: 1px solid #eee; padding: 10px 0;">
                                    <strong>${reg.username}</strong> - ${new Date(reg.timestamp).toLocaleDateString()}<br>
                                    <small>Specializations: ${reg.specializations.join(', ')}</small>
                                </div>
                            `).join('');
                        
                        document.getElementById('recent').innerHTML = recentHtml || '<p>No recent registrations</p>';
                    }
                } catch (error) {
                    console.error('Dashboard load error:', error);
                }
            }
            
            loadDashboard();
            setInterval(loadDashboard, 30000); // Refresh every 30 seconds
        </script>
    </body>
    </html>
    """
    return dashboard_html

def save_registration_request(registration):
    """Save registration request to file"""
    filename = 'pending_registrations.json'
    
    try:
        if os.path.exists(filename):
            with open(filename, 'r') as f:
                registrations = json.load(f)
        else:
            registrations = []
        
        registrations.append(registration)
        
        with open(filename, 'w') as f:
            json.dump(registrations, f, indent=2)
            
    except Exception as e:
        logger.error(f"Failed to save registration: {e}")

def load_registration_requests():
    """Load registration requests from file"""
    filename = 'pending_registrations.json'
    
    try:
        if os.path.exists(filename):
            with open(filename, 'r') as f:
                return json.load(f)
        return []
    except Exception as e:
        logger.error(f"Failed to load registrations: {e}")
        return []

def generate_registration_id(registration):
    """Generate unique registration ID"""
    import hashlib
    
    data = f"{registration['username']}{registration['timestamp']}{registration['blockchain_address']}"
    return hashlib.sha256(data.encode()).hexdigest()[:16]

def get_specialization_description(spec):
    """Get description for a specialization"""
    descriptions = {
        'smart_contract_development': 'Building and auditing smart contracts',
        'trading_algorithms': 'Automated trading and market analysis',
        'data_analysis': 'Data science and analytics',
        'content_creation': 'Writing, media, and content production',
        'community_management': 'Building and moderating communities',
        'research': 'Academic and applied research',
        'governance': 'Organizational governance and coordination',
        'economic_modeling': 'Economic systems and tokenomics',
        'security_auditing': 'Security analysis and penetration testing',
        'user_experience': 'UI/UX design and user research',
        'prediction_markets': 'Prediction market design and analysis',
        'reputation_systems': 'Identity and reputation mechanisms',
        'autonomous_systems': 'AI and automation systems',
        'blockchain_integration': 'Blockchain infrastructure and integration'
    }
    
    return descriptions.get(spec, 'Specialized expertise area')

def run_recruitment_background():
    """Run recruitment system in background"""
    def recruitment_worker():
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        
        global recruiter
        if recruiter:
            try:
                loop.run_until_complete(recruiter.start_recruitment_campaign())
            except Exception as e:
                logger.error(f"Background recruitment error: {e}")
    
    recruitment_thread = threading.Thread(target=recruitment_worker, daemon=True)
    recruitment_thread.start()

if __name__ == '__main__':
    # Initialize the recruiter
    initialize_recruiter()
    
    # Start background recruitment (commented out for demo)
    # run_recruitment_background()
    
    print("🚀 Moltbook Agent Registration API Server")
    print("📱 Registration Portal: http://localhost:5000")
    print("📊 Admin Dashboard: http://localhost:5000/dashboard")
    print("🔗 API Documentation: http://localhost:5000/api/stats")
    
    app.run(host='0.0.0.0', port=5000, debug=True)