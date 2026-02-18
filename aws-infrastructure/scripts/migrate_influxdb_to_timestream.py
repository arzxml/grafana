#!/usr/bin/env python3
"""
Migration script to move data from InfluxDB export to Amazon Timestream
"""
import argparse
import zipfile
import csv
import io
import sys
import os
from datetime import datetime
import boto3
from botocore.exceptions import ClientError
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)


def parse_csv_to_timestream_records(csv_content, measurement_name):
    """
    Parse CSV content and convert to Timestream records
    
    Args:
        csv_content: String content of CSV file
        measurement_name: Name of the measurement
    
    Returns:
        List of Timestream record dictionaries
    """
    records = []
    csv_reader = csv.DictReader(io.StringIO(csv_content))
    
    for row in csv_reader:
        # Extract timestamp
        time_str = row.pop('time', None)
        if not time_str:
            logging.warning(f"Skipping row without time: {row}")
            continue
        
        # Convert timestamp to epoch milliseconds
        try:
            dt = datetime.fromisoformat(time_str.replace('Z', '+00:00'))
            time_ms = int(dt.timestamp() * 1000)
        except Exception as e:
            logging.warning(f"Failed to parse timestamp {time_str}: {e}")
            continue
        
        # Create dimensions from tags and measurement
        dimensions = [{'Name': 'measurement', 'Value': measurement_name}]
        
        # Separate tags and fields
        fields = {}
        for key, value in row.items():
            if key.startswith('tag_') or key in ['measurement', 'User_ID']:
                # This is a tag/dimension
                dimensions.append({'Name': key, 'Value': str(value)})
            elif value:  # Only add non-empty fields
                fields[key] = value
        
        # Create a record for each field
        for field_name, field_value in fields.items():
            # Determine value type
            try:
                # Try to parse as number
                if '.' in str(field_value):
                    float_val = float(field_value)
                    measure_value = str(float_val)
                    measure_type = 'DOUBLE'
                else:
                    int_val = int(field_value)
                    measure_value = str(int_val)
                    measure_type = 'BIGINT'
            except (ValueError, TypeError):
                # It's a string
                measure_value = str(field_value)
                measure_type = 'VARCHAR'
            
            record = {
                'Dimensions': dimensions,
                'MeasureName': field_name,
                'MeasureValue': measure_value,
                'MeasureValueType': measure_type,
                'Time': str(time_ms),
                'TimeUnit': 'MILLISECONDS'
            }
            records.append(record)
    
    return records


def write_records_to_timestream(client, database, table, records, batch_size=100):
    """
    Write records to Timestream in batches
    
    Args:
        client: Boto3 Timestream write client
        database: Database name
        table: Table name
        records: List of records to write
        batch_size: Number of records per batch (max 100)
    
    Returns:
        Tuple of (successful_count, failed_count)
    """
    successful = 0
    failed = 0
    
    for i in range(0, len(records), batch_size):
        batch = records[i:i + batch_size]
        
        try:
            response = client.write_records(
                DatabaseName=database,
                TableName=table,
                Records=batch
            )
            successful += len(batch)
            
            if i % 1000 == 0:
                logging.info(f"Progress: {successful} records written")
                
        except ClientError as e:
            error_code = e.response.get('Error', {}).get('Code', 'Unknown')
            
            if error_code == 'RejectedRecordsException':
                # Some records were rejected
                rejected = e.response.get('RejectedRecords', [])
                failed += len(rejected)
                successful += len(batch) - len(rejected)
                
                for rejected_record in rejected[:5]:  # Log first 5 rejections
                    logging.warning(f"Record rejected: {rejected_record.get('Reason')}")
            else:
                logging.error(f"Error writing batch: {e}")
                failed += len(batch)
    
    return successful, failed


def migrate_influxdb_to_timestream(zip_file_path, database, table, region='us-east-1'):
    """
    Main migration function
    
    Args:
        zip_file_path: Path to the InfluxDB export ZIP file
        database: Timestream database name
        table: Timestream table name
        region: AWS region
    """
    # Initialize Timestream client
    client = boto3.client('timestream-write', region_name=region)
    
    logging.info(f"Starting migration from {zip_file_path}")
    logging.info(f"Target: {database}.{table} in {region}")
    
    total_records = 0
    total_successful = 0
    total_failed = 0
    
    # Open and process the ZIP file
    with zipfile.ZipFile(zip_file_path, 'r') as zip_ref:
        csv_files = [f for f in zip_ref.namelist() if f.endswith('.csv')]
        
        logging.info(f"Found {len(csv_files)} CSV files in ZIP")
        
        for csv_file in csv_files:
            measurement_name = csv_file.replace('.csv', '')
            logging.info(f"\nProcessing measurement: {measurement_name}")
            
            # Read CSV content
            with zip_ref.open(csv_file) as f:
                csv_content = f.read().decode('utf-8')
            
            # Convert to Timestream records
            records = parse_csv_to_timestream_records(csv_content, measurement_name)
            logging.info(f"Parsed {len(records)} records from {csv_file}")
            
            if records:
                # Write to Timestream
                successful, failed = write_records_to_timestream(
                    client, database, table, records
                )
                
                total_records += len(records)
                total_successful += successful
                total_failed += failed
                
                logging.info(f"✓ {measurement_name}: {successful} successful, {failed} failed")
    
    # Final summary
    logging.info("\n" + "="*50)
    logging.info("Migration Summary")
    logging.info("="*50)
    logging.info(f"Total records: {total_records}")
    logging.info(f"Successful: {total_successful}")
    logging.info(f"Failed: {total_failed}")
    logging.info(f"Success rate: {(total_successful/total_records*100):.2f}%")
    logging.info("="*50)
    
    return total_successful, total_failed


if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description='Migrate InfluxDB export data to Amazon Timestream'
    )
    parser.add_argument(
        '--zip-file',
        required=True,
        help='Path to InfluxDB export ZIP file'
    )
    parser.add_argument(
        '--database',
        default='GarminStats',
        help='Timestream database name (default: GarminStats)'
    )
    parser.add_argument(
        '--table',
        default='GarminMetrics',
        help='Timestream table name (default: GarminMetrics)'
    )
    parser.add_argument(
        '--region',
        default=os.getenv('AWS_REGION', 'us-east-1'),
        help='AWS region (default: from AWS_REGION env or us-east-1)'
    )
    
    args = parser.parse_args()
    
    # Validate ZIP file exists
    if not os.path.exists(args.zip_file):
        logging.error(f"ZIP file not found: {args.zip_file}")
        sys.exit(1)
    
    try:
        successful, failed = migrate_influxdb_to_timestream(
            args.zip_file,
            args.database,
            args.table,
            args.region
        )
        
        if failed > 0:
            logging.warning(f"Migration completed with {failed} failures")
            sys.exit(1)
        else:
            logging.info("Migration completed successfully!")
            sys.exit(0)
            
    except Exception as e:
        logging.error(f"Migration failed: {e}")
        sys.exit(1)
