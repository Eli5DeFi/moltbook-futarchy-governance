from http.server import BaseHTTPRequestHandler
import json
import os
from datetime import datetime

class handler(BaseHTTPRequestHandler):
    def do_GET(self):
        """Get registration system statistics"""
        try:
            # Set CORS headers
            self.send_response(200)
            self.send_header('Access-Control-Allow-Origin', '*')
            self.send_header('Access-Control-Allow-Methods', 'GET, OPTIONS')
            self.send_header('Access-Control-Allow-Headers', 'Content-Type')
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            
            # Mock statistics for demo (in production, would fetch from database)
            stats = {
                'total_registrations': 25,
                'pending_registrations': 3,
                'approved_registrations': 20,
                'rejected_registrations': 2,
                'specialization_breakdown': {
                    'smart_contract_development': 8,
                    'trading_algorithms': 5,
                    'data_analysis': 4,
                    'governance': 3,
                    'research': 2,
                    'content_creation': 2,
                    'community_management': 1
                },
                'recent_registrations': [
                    {
                        'username': 'agent_alice',
                        'timestamp': '2025-01-31T10:00:00Z',
                        'specializations': ['smart_contract_development', 'governance']
                    },
                    {
                        'username': 'agent_bob',
                        'timestamp': '2025-01-31T11:30:00Z', 
                        'specializations': ['trading_algorithms', 'data_analysis']
                    },
                    {
                        'username': 'agent_charlie',
                        'timestamp': '2025-01-31T12:15:00Z',
                        'specializations': ['research', 'content_creation']
                    }
                ],
                'campaign_metrics': {
                    'invitations_sent': 50,
                    'conversion_rate': 40.0,
                    'average_karma': 125,
                    'quality_score': 8.2
                },
                'last_updated': datetime.now().isoformat()
            }
            
            response = {
                'success': True,
                'stats': stats
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