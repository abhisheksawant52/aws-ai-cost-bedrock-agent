# AWS Cost AI Reporter with Bedrock Agent (Fully Automated with Terraform)

This project automatically:

-   Creates & prepares an **Amazon Bedrock Agent** from code\
-   Creates an **Agent Alias**\
-   Deploys a **Lambda function** that:
    -   Fetches AWS monthly cost data from **Cost Explorer**
    -   Sends the data to the **Bedrock Agent**
    -   Generates an AI-written cost summary
    -   Emails the report using **SES**
-   Schedules the Lambda to run monthly using **EventBridge**
-   All resources are created and managed using **Terraform**

------------------------------------------------------------------------

## 🚀 Features

-   100% automated Bedrock Agent creation (**no console clicks
    required**)
-   AI-generated cost summary email delivered via SES
-   Lambda dynamically calls:
    -   Cost Explorer
    -   Bedrock Agent Runtime
    -   SES
-   Highly customizable (schedule, email formatting, cost dimensions,
    etc.)
-   Works in **us-east-1**, where Bedrock Agents are fully supported

------------------------------------------------------------------------

## 📁 Folder Structure

    aws-ai-cost-bedrock-agent/
     ├── main.tf
     ├── variables.tf
     ├── iam_bedrock_agent.tf
     ├── bedrock_agent_bootstrap.tf
     ├── iam_lambda.tf
     ├── ses.tf
     ├── lambda.tf
     ├── eventbridge.tf
     ├── lambda_function.py
     └── terraform.tfvars

------------------------------------------------------------------------

## ⚙️ Prerequisites

Before running Terraform:

### 1. Install required tools

-   Terraform ≥ 1.5
-   AWS CLI v2
-   bash (Git Bash on Windows works)
-   IAM permissions allowing:
    -   Bedrock Agent creation (`bedrock-agent:*`)
    -   IAM role creation
    -   SES identity creation
    -   Lambda deployment
    -   EventBridge creation

### 2. Enable Cost Explorer in your AWS Billing Console

If not enabled, Lambda will fail with:

    AccessDeniedException: User not enabled for cost explorer access

### 3. SES must be verified

In **SES sandbox**, both `FROM` and `TO` emails must be verified.

------------------------------------------------------------------------

## 🏗️ Step-by-Step Setup

### 1. Clone or download the project folder

Place the folder anywhere on your system.

### 2. Edit `terraform.tfvars`

Example:

``` hcl
aws_region = "us-east-1"

cost_email_from = "your-email@company.com"
cost_email_to   = "your-email@company.com"

# Initial dummy values; they will be replaced after bootstrap prints real IDs
bedrock_agent_id       = "DUMMY"
bedrock_agent_alias_id = "DUMMY"

schedule_expression = "cron(0 7 1 * ? *)"
```

### 3. Run Terraform for the first time

``` bash
terraform init
terraform apply
```

This will:

-   Create the IAM role for the agent\
-   Create the Bedrock agent\
-   Prepare the agent\
-   Create the agent alias\
-   Print the following in your terminal:

```{=html}
<!-- -->
```
    ==== BEDROCK AGENT INFO (copy into terraform.tfvars) ====
    BEDROCK_AGENT_ID=XXXXXXXXXX
    BEDROCK_AGENT_ALIAS_ID=YYYYYYYYYY
    =========================================================

### 4. Update `terraform.tfvars` with the real Agent IDs

Example:

``` hcl
bedrock_agent_id       = "4JCEIL1NSZ"
bedrock_agent_alias_id = "WMBZHGQHZG"
```

### 5. Run Terraform again

``` bash
terraform apply
```

This deploys:

-   Lambda (wired to Bedrock Agent)
-   SES email identity
-   EventBridge schedule

------------------------------------------------------------------------

## 📬 Triggering the Email

### Option A --- Lambda Console (manual)

1.  Open Lambda → your function
2.  Click **Test**
3.  Use payload `{}`

### Option B --- AWS CLI

``` bash
aws lambda invoke \
 --function-name aws-ai-cost-bedrock-agent-reporter \
 --payload '{}' \
 output.json
```

### Option C --- Scheduled run

Your `schedule_expression` controls when the report runs.

Example:

-   Monthly at 07:00 UTC:

```{=html}
<!-- -->
```
    cron(0 7 1 * ? *)

------------------------------------------------------------------------

## 🧪 Testing

Check **CloudWatch Logs** to confirm:

-   Bedrock Agent invocation works
-   Cost Explorer returns data
-   SES sends email

If SES is still in sandbox, email will only deliver to verified
addresses.

------------------------------------------------------------------------

## 🔧 Customization

You can easily modify:

-   Cost breakdown (daily, hourly, tags, linked accounts)
-   Bedrock Agent instructions
-   Email formatting (HTML, attachments)
-   Trigger schedule (daily, weekly, monthly)
-   Support for CUR (Cost & Usage Report) instead of Cost Explorer

If you want enhancements, ask and I'll generate the code.

------------------------------------------------------------------------

## 🧹 Cleanup

To destroy all resources:

``` bash
terraform destroy
```

This removes:

-   Bedrock agent + alias
-   Lambda
-   IAM roles
-   SES identity
-   EventBridge rule

------------------------------------------------------------------------

## 🙌 Support

If you want:

-   HTML email formatting\
-   API Gateway trigger\
-   Slack / Teams integration\
-   Multi-account cost aggregation\
-   Adding cost forecasts or anomalies

Just ask --- I can generate the Terraform + Lambda code for you.

------------------------------------------------------------------------

Happy Automating!\
**AI-Powered AWS Cost Reporting with Bedrock 🤖💸**
