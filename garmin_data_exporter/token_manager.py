"""
Token Manager for Garmin Connect OAuth tokens.
Stores tokens in AWS Secrets Manager instead of filesystem (EFS).
"""
import json
import logging
import boto3
from botocore.exceptions import ClientError
from typing import Optional, Dict, Any


class SecretsManagerTokenStore:
    """
    Stores Garmin OAuth tokens in AWS Secrets Manager.
    Provides a drop-in replacement for file-based token storage.
    """
    
    def __init__(self, secret_name: str, region_name: str = 'us-east-1'):
        """
        Initialize the Secrets Manager token store.
        
        Args:
            secret_name: Name of the secret in Secrets Manager (e.g., 'garmin-exporter/oauth-tokens')
            region_name: AWS region where the secret is stored
        """
        self.secret_name = secret_name
        self.region_name = region_name
        self.client = boto3.client('secretsmanager', region_name=region_name)
        logging.info(f"Initialized SecretsManagerTokenStore for secret: {secret_name}")
    
    def save_tokens(self, tokens: Dict[str, Any]) -> None:
        """
        Save OAuth tokens to Secrets Manager.
        
        Args:
            tokens: Dictionary containing OAuth tokens
        """
        try:
            secret_value = json.dumps(tokens)
            
            try:
                # Try to update existing secret
                self.client.update_secret(
                    SecretId=self.secret_name,
                    SecretString=secret_value
                )
                logging.info(f"Updated OAuth tokens in Secrets Manager: {self.secret_name}")
            except self.client.exceptions.ResourceNotFoundException:
                # Secret doesn't exist, create it
                self.client.create_secret(
                    Name=self.secret_name,
                    Description='Garmin Connect OAuth tokens',
                    SecretString=secret_value
                )
                logging.info(f"Created new OAuth token secret in Secrets Manager: {self.secret_name}")
                
        except ClientError as e:
            logging.error(f"Failed to save tokens to Secrets Manager: {e}")
            raise
    
    def load_tokens(self) -> Optional[Dict[str, Any]]:
        """
        Load OAuth tokens from Secrets Manager.
        
        Returns:
            Dictionary containing OAuth tokens, or None if not found
        """
        try:
            response = self.client.get_secret_value(SecretId=self.secret_name)
            secret_value = response['SecretString']
            tokens = json.loads(secret_value)
            logging.info(f"Loaded OAuth tokens from Secrets Manager: {self.secret_name}")
            return tokens
            
        except self.client.exceptions.ResourceNotFoundException:
            logging.warning(f"OAuth token secret not found in Secrets Manager: {self.secret_name}")
            return None
        except ClientError as e:
            logging.error(f"Failed to load tokens from Secrets Manager: {e}")
            raise
    
    def delete_tokens(self) -> None:
        """
        Delete OAuth tokens from Secrets Manager.
        """
        try:
            self.client.delete_secret(
                SecretId=self.secret_name,
                ForceDeleteWithoutRecovery=True
            )
            logging.info(f"Deleted OAuth tokens from Secrets Manager: {self.secret_name}")
        except self.client.exceptions.ResourceNotFoundException:
            logging.warning(f"OAuth token secret not found (already deleted): {self.secret_name}")
        except ClientError as e:
            logging.error(f"Failed to delete tokens from Secrets Manager: {e}")
            raise
