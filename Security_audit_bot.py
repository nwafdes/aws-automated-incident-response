import json
import boto3
import urllib3
import os  # <--- For Environment Variables

def lambda_handler(event, context):
    # 1. Initialize Clients
    s3 = boto3.client('s3')
    http = urllib3.PoolManager()
    
    # 2. Securely get the Webhook URL from Environment Variables
    # (If this fails, check your Lambda Configuration -> Environment variables)
    webhook_url = os.environ.get('N8N_WEBHOOK_URL')

    if not webhook_url:
        return {"error": "N8N_WEBHOOK_URL not set in environment variables."}

    # 3. Parse the Event (The Trigger)
    try:
        # Extract details from the CloudTrail event
        detail = event['detail']
        source_user = detail['userIdentity']['type']
        source_ip = detail['sourceIPAddress']
        bucket_name = detail['requestParameters']['bucketName']
        
        # Determine the current status
        versioning = s3.get_bucket_versioning(Bucket=bucket_name)
        status = versioning.get("Status")

        # 4. Check Compliance (The Logic)
        if status == "Enabled":
            return f"[SAFE] Bucket {bucket_name} is compliant."

        # 5. Auto-Remediate (The Action)
        print(f"[RISK] Bucket {bucket_name} unversioned. Enabling now...")
        
        s3.put_bucket_versioning(
            Bucket=bucket_name,
            VersioningConfiguration={'Status': 'Enabled'}
        )

        # 6. Notify via ChatOps (The Alert)
        message = (
            f"🚨 SECURITY INCIDENT AUTO-RESOLVED 🚨\n"
            f"• Target: {bucket_name}\n"
            f"• User: {source_user}\n"
            f"• IP: {source_ip}\n"
            f"• Action: Versioning enabled by SecurityBot."
        )

        payload = {"message": message}
        
        response = http.request(
            'POST',
            webhook_url,
            body=json.dumps(payload).encode('utf-8'),
            headers={'Content-Type': 'application/json'}
        )
        
        return {
            "status": "Remediation Successful",
            "webhook_status": response.status
        }

    except Exception as e:
        print(f"Error: {str(e)}")
        return {"error": str(e)}
