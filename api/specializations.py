from http.server import BaseHTTPRequestHandler
import json

class handler(BaseHTTPRequestHandler):
    def do_GET(self):
        """Get available specialization categories"""
        try:
            # Set CORS headers
            self.send_response(200)
            self.send_header('Access-Control-Allow-Origin', '*')
            self.send_header('Access-Control-Allow-Methods', 'GET, OPTIONS')
            self.send_header('Access-Control-Allow-Headers', 'Content-Type')
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            
            # Specialization categories with descriptions
            specializations_data = [
                {
                    'id': 'smart_contract_development',
                    'name': 'Smart Contract Development',
                    'description': 'Building and auditing smart contracts'
                },
                {
                    'id': 'trading_algorithms',
                    'name': 'Trading Algorithms', 
                    'description': 'Automated trading and market analysis'
                },
                {
                    'id': 'data_analysis',
                    'name': 'Data Analysis',
                    'description': 'Data science and analytics'
                },
                {
                    'id': 'content_creation',
                    'name': 'Content Creation',
                    'description': 'Writing, media, and content production'
                },
                {
                    'id': 'community_management',
                    'name': 'Community Management',
                    'description': 'Building and moderating communities'
                },
                {
                    'id': 'research',
                    'name': 'Research',
                    'description': 'Academic and applied research'
                },
                {
                    'id': 'governance',
                    'name': 'Governance',
                    'description': 'Organizational governance and coordination'
                },
                {
                    'id': 'economic_modeling',
                    'name': 'Economic Modeling',
                    'description': 'Economic systems and tokenomics'
                },
                {
                    'id': 'security_auditing',
                    'name': 'Security Auditing',
                    'description': 'Security analysis and penetration testing'
                },
                {
                    'id': 'user_experience',
                    'name': 'User Experience',
                    'description': 'UI/UX design and user research'
                },
                {
                    'id': 'prediction_markets',
                    'name': 'Prediction Markets',
                    'description': 'Prediction market design and analysis'
                },
                {
                    'id': 'reputation_systems',
                    'name': 'Reputation Systems',
                    'description': 'Identity and reputation mechanisms'
                },
                {
                    'id': 'autonomous_systems',
                    'name': 'Autonomous Systems',
                    'description': 'AI and automation systems'
                },
                {
                    'id': 'blockchain_integration',
                    'name': 'Blockchain Integration',
                    'description': 'Blockchain infrastructure and integration'
                }
            ]
            
            response = {
                'success': True,
                'specializations': specializations_data
            }
            
            self.wfile.write(json.dumps(response).encode())
            
        except Exception as e:
            self.send_response(500)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            
            error_response = {
                'success': False,
                'error': 'Internal server error'
            }
            
            self.wfile.write(json.dumps(error_response).encode())

    def do_OPTIONS(self):
        """Handle preflight requests"""
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()