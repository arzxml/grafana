"""
Wrapper for Garmin Connect that uses Secrets Manager for token storage.
Replaces file-based token storage with AWS Secrets Manager.
"""
import logging
import tempfile
import os
import shutil
from garminconnect import Garmin
from token_manager import SecretsManagerTokenStore


class GarminWithSecretsManager(Garmin):
    """
    Extended Garmin class that uses AWS Secrets Manager for OAuth token storage.
    """
    
    def __init__(self, email=None, password=None, is_cn=False, prompt_mfa=None, 
                 mfa_callback=None, return_on_mfa=False, secrets_manager_token_name=None,
                 aws_region='us-east-1'):
        """
        Initialize Garmin client with Secrets Manager token storage.
        
        Args:
            secrets_manager_token_name: Name of the secret in Secrets Manager for OAuth tokens
            aws_region: AWS region for Secrets Manager
            Other args: Same as parent Garmin class
        """
        super().__init__(email, password, is_cn, prompt_mfa, mfa_callback, return_on_mfa)
        self.token_store = SecretsManagerTokenStore(
            secret_name=secrets_manager_token_name or 'garmin-exporter/oauth-tokens',
            region_name=aws_region
        )
        self._temp_token_dir = None
    
    def login(self, tokenstore=None):
        """
        Login to Garmin Connect using tokens from Secrets Manager.
        
        Args:
            tokenstore: Ignored (for compatibility with parent class)
        
        Returns:
            Authentication result from parent class
        """
        # Load tokens from Secrets Manager to a temporary directory
        tokens = self.token_store.load_tokens()
        
        if tokens:
            # Create temporary directory for tokens
            self._temp_token_dir = tempfile.mkdtemp(prefix='garmin_tokens_')
            
            # Write tokens as files (garth expects directory structure)
            try:
                # Garth stores tokens as individual files in the directory
                # We need to recreate this structure
                for filename, content in tokens.items():
                    filepath = os.path.join(self._temp_token_dir, filename)
                    with open(filepath, 'w') as f:
                        f.write(content if isinstance(content, str) else str(content))
                
                logging.info(f"Loaded tokens from Secrets Manager to temp dir: {self._temp_token_dir}")
                
                # Call parent login with temp directory
                result = super().login(self._temp_token_dir)
                
                # Clean up temp directory
                self._cleanup_temp_dir()
                
                return result
                
            except Exception as e:
                self._cleanup_temp_dir()
                raise e
        else:
            # No tokens found, will need to login with credentials
            logging.warning("No OAuth tokens found in Secrets Manager, credential login required")
            raise FileNotFoundError("No stored tokens found")
    
    def save_tokens(self):
        """
        Save OAuth tokens from garth to Secrets Manager.
        """
        # Dump tokens to temporary directory
        self._temp_token_dir = tempfile.mkdtemp(prefix='garmin_tokens_')
        
        try:
            # Have garth dump tokens to temp directory
            self.garth.dump(self._temp_token_dir)
            
            # Read all token files from the directory
            tokens = {}
            for filename in os.listdir(self._temp_token_dir):
                filepath = os.path.join(self._temp_token_dir, filename)
                if os.path.isfile(filepath):
                    with open(filepath, 'r') as f:
                        tokens[filename] = f.read()
            
            # Save to Secrets Manager
            self.token_store.save_tokens(tokens)
            logging.info("OAuth tokens saved to Secrets Manager")
            
            # Clean up temp directory
            self._cleanup_temp_dir()
            
        except Exception as e:
            self._cleanup_temp_dir()
            raise e
    
    def _cleanup_temp_dir(self):
        """Clean up temporary token directory."""
        if self._temp_token_dir and os.path.exists(self._temp_token_dir):
            shutil.rmtree(self._temp_token_dir)
            self._temp_token_dir = None
    
    def __del__(self):
        """Cleanup on object destruction."""
        self._cleanup_temp_dir()
