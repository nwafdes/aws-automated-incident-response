# AWS Self-Healing S3 Sentinel 🛡️☁️

![AWS](https://img.shields.io/badge/AWS-EventBridge-orange)
![Python](https://img.shields.io/badge/Python-3.x-blue)
![Security](https://img.shields.io/badge/Security-Automated-red)
![ChatOps](https://img.shields.io/badge/ChatOps-Enabled-green)

## 📋 Overview
A serverless, event-driven security platform that automatically detects and remediates insecure AWS S3 buckets in real-time.

By leveraging **AWS EventBridge** and **Lambda**, this system eliminates the "window of exposure" that exists with traditional periodic scans. It detects unversioned buckets within seconds of creation, enables versioning to protect against ransomware/accidental deletion, and instantly notifies the SOC team via **ChatOps** (n8n Webhook).

## 🏗️ Architecture

[INSERT YOUR ARCHITECTURE DIAGRAM IMAGE HERE]
*(Recommended: Use Excalidraw or draw.io to show: User -> CloudTrail -> EventBridge -> Lambda -> n8n)*

**The Workflow:**
1.  **Trigger:** A user creates an S3 Bucket (via Console, CLI, or Terraform).
2.  **Detection:** CloudTrail captures the API call; **EventBridge** matches the `CreateBucket` event.
3.  **Response:** The **Lambda Function** (Python) parses the event to identify the creator and bucket name.
4.  **Remediation:** The function checks if Versioning is enabled. If not, it **automatically enables it**.
5.  **Alerting:** A JSON payload is sent to an **n8n Webhook**, which dispatches a formatted alert to Slack/Telegram/Teams.

## 🚀 Key Features

* **Real-Time Compliance:** <2 second response time from bucket creation to remediation.
* **Infrastructure as Code (IaC) Ready:** Designed to work alongside Terraform/CloudFormation deployments.
* **ChatOps Integration:** Replaces noisy emails with actionable, rich-text Instant Messages.
* **Cost Efficient:** 100% Serverless (Free Tier eligible). Runs only when events occur.

## 🛠️ Tech Stack

* **Cloud:** AWS (Lambda, S3, EventBridge, IAM)
* **Language:** Python 3 (Boto3, Urllib3)
* **Automation:** n8n (Workflow Automation)
* **Security:** IAM Least Privilege Policies

## 💻 Setup & Installation

### Prerequisites
* AWS Account with CloudTrail enabled.
* n8n Instance (Cloud or Self-Hosted).

### 1. Deploy the Lambda Function
* Create a Python 3.x Lambda function.
* Paste the code from `lambda_function.py`.
* **Environment Variables:**
    * `N8N_WEBHOOK_URL`: Your n8n webhook endpoint.

### 2. Configure IAM Permissions
Attach a policy allowing:
* `s3:GetBucketVersioning`
* `s3:PutBucketVersioning`
* `s3:ListBuckets` (optional for auditing)

### 3. Set Up EventBridge Rule
* **Source:** `aws.s3`
* **Event Type:** `AWS API Call via CloudTrail`
* **Specific Operation:** `CreateBucket`
* **Target:** Your Lambda Function

## 📸 Proof of Concept

### 1. The Attack (Creating an Insecure Bucket)
!["create-bucket.png"]

### 2. The Auto-Remediation (Logs)
![cloudwatch-logs.png]

### 3. The Alert (ChatOps)
![telegram-message.png]

## 🔮 Future Improvements
* Add auto-remediation for **Public Access Block** (S3).
* Integrate with **Jira** to create audit tickets automatically.
* Migrate deployment to **Terraform** for full automation.
