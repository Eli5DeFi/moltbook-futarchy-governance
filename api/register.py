from http.server import BaseHTTPRequestHandler
import json
import os
import time
import logging
from datetime import datetime
import hashlib
import secrets

class handler(BaseHTTPRequestHandler):
    def do_POST(self):
        """Handle agent registration submissions"""
        try:
            # Set CORS headers
            self.send_header('Access-Control-Allow-Origin', '*')
            self.send_header('Access-Control-Allow-Methods', 'POST, OPTIONS')
            self.send_header('Access-Control-Allow-Headers', 'Content-Type')
            
            # Get request body
            content_length = int(self.headers.get('Content-Length', 0))
            post_data = self.rfile.read(content_length)
            data = json.loads(post_data.decode('utf-8'))
            
            # Validate required fields
            required_fields = ['moltbook_username', 'blockchain_address', 'specializations', 'verification_signature']
            for field in required_fields:
                if not data.get(field):
                    self.send_error(400, f'Missing required field: {field}')
                    return
            
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
                'ip_address': self.client_address[0] if hasattr(self, 'client_address') else 'unknown'
            }
            
            # Generate registration ID
            registration_id = self.generate_registration_id(registration_request)
            
            # Save registration (in production, would save to database)
            # For Vercel, we'll use environment variables or external storage
            
            # Send success response
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            
            response = {
                'success': True,
                'message': 'Registration submitted successfully',
                'registration_id': registration_id,
                'status': 'pending_verification'
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
        self.send_header('Access-Control-Allow-Methods', 'POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

    def generate_registration_id(self, registration):
        """Generate unique registration ID"""
        data = f"{registration['username']}{registration['timestamp']}{registration['blockchain_address']}"
        return hashlib.sha256(data.encode()).hexdigest()[:16]