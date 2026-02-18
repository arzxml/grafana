"""
Timestream adapter for Garmin Data Exporter
This module provides compatibility layer to use Amazon Timestream instead of InfluxDB
"""
import os
import logging
from datetime import datetime, timezone
from typing import List, Dict, Any
import boto3
from botocore.exceptions import ClientError


class TimestreamAdapter:
    """Adapter to write data to Amazon Timestream with InfluxDB-compatible interface"""
    
    def __init__(self, database_name: str, table_name: str, region: str = None):
        """
        Initialize Timestream client
        
        Args:
            database_name: Timestream database name
            table_name: Timestream table name
            region: AWS region (defaults to environment variable or 'us-east-1')
        """
        self.database_name = database_name
        self.table_name = table_name
        self.region = region or os.getenv('AWS_REGION', 'us-east-1')
        
        self.write_client = boto3.client('timestream-write', region_name=self.region)
        self.query_client = boto3.client('timestream-query', region_name=self.region)
        
        logging.info(f"Initialized Timestream adapter for database={database_name}, table={table_name}")
    
    def write_points(self, points: List[Dict[str, Any]]) -> None:
        """
        Write data points to Timestream (InfluxDB-compatible interface)
        
        Args:
            points: List of data points in InfluxDB format:
                {
                    'measurement': 'measurement_name',
                    'tags': {'tag1': 'value1'},
                    'fields': {'field1': value1},
                    'time': datetime_or_string
                }
        """
        if not points:
            return
        
        # Convert InfluxDB format to Timestream format
        records = []
        current_time = self._get_current_time_ms()
        
        for point in points:
            measurement = point.get('measurement', 'unknown')
            tags = point.get('tags', {})
            fields = point.get('fields', {})
            timestamp = point.get('time')
            
            # Convert timestamp to epoch milliseconds
            time_ms = self._convert_timestamp(timestamp) if timestamp else current_time
            
            # Create dimensions from tags
            dimensions = [
                {'Name': 'measurement', 'Value': measurement}
            ]
            for tag_key, tag_value in tags.items():
                dimensions.append({
                    'Name': str(tag_key),
                    'Value': str(tag_value)
                })
            
            # Create a record for each field
            for field_name, field_value in fields.items():
                measure_value, measure_value_type = self._convert_field_value(field_value)
                
                record = {
                    'Dimensions': dimensions,
                    'MeasureName': field_name,
                    'MeasureValue': measure_value,
                    'MeasureValueType': measure_value_type,
                    'Time': str(time_ms),
                    'TimeUnit': 'MILLISECONDS'
                }
                records.append(record)
        
        # Write records in batches (Timestream allows max 100 records per request)
        batch_size = 100
        for i in range(0, len(records), batch_size):
            batch = records[i:i + batch_size]
            try:
                self.write_client.write_records(
                    DatabaseName=self.database_name,
                    TableName=self.table_name,
                    Records=batch
                )
                logging.debug(f"Wrote {len(batch)} records to Timestream")
            except ClientError as e:
                error_code = e.response.get('Error', {}).get('Code', 'Unknown')
                if error_code == 'RejectedRecordsException':
                    logging.warning(f"Some records were rejected: {e}")
                else:
                    logging.error(f"Error writing to Timestream: {e}")
                    raise
    
    def query(self, query_string: str, language: str = 'influxql') -> 'QueryResult':
        """
        Query Timestream database (limited InfluxDB compatibility)
        
        Args:
            query_string: Query string (InfluxQL or SQL)
            language: Query language ('influxql' is converted to SQL)
        
        Returns:
            QueryResult object
        """
        # Convert InfluxQL to Timestream SQL if needed
        if language == 'influxql':
            sql_query = self._convert_influxql_to_sql(query_string)
        else:
            sql_query = query_string
        
        try:
            response = self.query_client.query(QueryString=sql_query)
            return QueryResult(response)
        except ClientError as e:
            logging.error(f"Error querying Timestream: {e}")
            raise
    
    def switch_database(self, database_name: str) -> None:
        """Switch to a different database (for InfluxDB compatibility)"""
        self.database_name = database_name
        logging.info(f"Switched to database: {database_name}")
    
    def _get_current_time_ms(self) -> int:
        """Get current time in epoch milliseconds"""
        return int(datetime.now(timezone.utc).timestamp() * 1000)
    
    def _convert_timestamp(self, timestamp) -> int:
        """Convert various timestamp formats to epoch milliseconds"""
        if isinstance(timestamp, str):
            # Parse ISO format timestamp
            dt = datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
            return int(dt.timestamp() * 1000)
        elif isinstance(timestamp, datetime):
            return int(timestamp.timestamp() * 1000)
        elif isinstance(timestamp, (int, float)):
            # Assume it's already in milliseconds or seconds
            if timestamp > 1e12:  # Likely milliseconds
                return int(timestamp)
            else:  # Likely seconds
                return int(timestamp * 1000)
        else:
            return self._get_current_time_ms()
    
    def _convert_field_value(self, value) -> tuple:
        """
        Convert field value to Timestream format
        
        Returns:
            Tuple of (value_string, value_type)
        """
        if isinstance(value, bool):
            return (str(value).lower(), 'BOOLEAN')
        elif isinstance(value, int):
            return (str(value), 'BIGINT')
        elif isinstance(value, float):
            return (str(value), 'DOUBLE')
        else:
            return (str(value), 'VARCHAR')
    
    def _convert_influxql_to_sql(self, influxql: str) -> str:
        """
        Convert basic InfluxQL queries to Timestream SQL
        This is a simplified converter for common queries
        """
        # Handle SHOW MEASUREMENTS
        if influxql.upper().startswith('SHOW MEASUREMENTS'):
            return f"""
                SELECT DISTINCT measurement
                FROM "{self.database_name}"."{self.table_name}"
            """
        
        # Handle SELECT with ORDER BY DESC LIMIT (for last sync time)
        if 'ORDER BY time DESC LIMIT' in influxql:
            # Extract measurement name and limit
            parts = influxql.split('FROM')
            if len(parts) >= 2:
                measurement_part = parts[1].split('ORDER BY')[0].strip()
                limit_part = influxql.split('LIMIT')[1].strip()
                
                return f"""
                    SELECT *
                    FROM "{self.database_name}"."{self.table_name}"
                    WHERE measurement = {measurement_part}
                    ORDER BY time DESC
                    LIMIT {limit_part}
                """
        
        # For other queries, return as-is (may need manual conversion)
        logging.warning(f"Query conversion not implemented for: {influxql}")
        return influxql


class QueryResult:
    """Wrapper for Timestream query results to provide InfluxDB-compatible interface"""
    
    def __init__(self, response: Dict[str, Any]):
        self.response = response
        self.rows = response.get('Rows', [])
        self.column_info = response.get('ColumnInfo', [])
    
    def get_points(self):
        """Get query results as points (generator)"""
        for row in self.rows:
            point = {}
            for i, column in enumerate(self.column_info):
                col_name = column['Name']
                col_value = row['Data'][i].get('ScalarValue', '')
                point[col_name] = col_value
            yield point
    
    def to_pylist(self) -> List[Dict[str, Any]]:
        """Convert results to list of dictionaries"""
        return list(self.get_points())


def create_timestream_client():
    """
    Factory function to create Timestream client
    
    Returns:
        TimestreamAdapter instance configured from environment variables
    """
    database = os.getenv('TIMESTREAM_DATABASE', 'GarminStats')
    table = os.getenv('TIMESTREAM_TABLE', 'GarminMetrics')
    region = os.getenv('AWS_REGION', 'us-east-1')
    
    return TimestreamAdapter(database, table, region)
