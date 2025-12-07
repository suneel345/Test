Here’s a clean pattern you can use:

One central “infra / CI-CD” account (where Jenkins + archive bucket live).

Multiple spoke accounts: dev, dev2, qa, prod (each already has CUR S3 or you’ll add later).

CDK:

A central stack in the infra account that:

Imports the existing archive bucket.

Creates a Jenkins STS role that can:

Assume cross-account roles in each spoke account.

Write ZIP archives into the existing S3 bucket (per account, per date).



A spoke stack that you deploy in each account (dev/dev2/qa/prod) that:

Creates a cross-account role trusted by the infra Jenkins role.

Allows read access on that account’s CUR S3 bucket.




You’ll then use STS AssumeRole from Jenkins to pull CUR files and push ZIPs into the central archive bucket like:

2025/<account-id>/2025_12_06.zip


---

1. CDK Project Structure (TypeScript)

cdk-billing-sync/
├─ bin/
│  └─ billing-app.ts
├─ lib/
│  ├─ central-infra-stack.ts
│  └─ spoke-billing-role-stack.ts
├─ package.json
├─ tsconfig.json
└─ cdk.json


---

2. bin/billing-app.ts

This wires one central stack and N spoke stacks.
You can control which ones to deploy via profiles / cdk deploy commands.

#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { CentralInfraStack } from '../lib/central-infra-stack';
import { SpokeBillingRoleStack } from '../lib/spoke-billing-role-stack';

const app = new cdk.App();

// === Edit these to your real values ===
const region = 'ap-south-1';

const centralAccountId = '111111111111'; // infra / CI-CD account
const archiveBucketName = 'my-existing-billing-archive-bucket';

const devAccountId  = '222222222222';
const dev2AccountId = '333333333333';
const qaAccountId   = '444444444444';
const prodAccountId = '555555555555';

const spokeAccounts = [devAccountId, dev2AccountId, qaAccountId, prodAccountId];

// Central stack (deploy with infra profile)
const central = new CentralInfraStack(app, 'BillingCentralStack', {
  env: { account: centralAccountId, region },
    billingArchiveBucketName: archiveBucketName,
      spokeAccountIds: spokeAccounts,
        jenkinsRoleName: 'JenkinsBillingSyncRole',
        });

        // Spoke stacks (deploy each with its own profile/account)
        new SpokeBillingRoleStack(app, 'BillingDevStack', {
          env: { account: devAccountId, region },
            centralAccountId,
              centralJenkinsRoleName: central.jenkinsRoleName,
                curBucketArn: 'arn:aws:s3:::dev-cur-bucket', // change per account
                });

                new SpokeBillingRoleStack(app, 'BillingDev2Stack', {
                  env: { account: dev2AccountId, region },
                    centralAccountId,
                      centralJenkinsRoleName: central.jenkinsRoleName,
                        curBucketArn: 'arn:aws:s3:::dev2-cur-bucket',
                        });

                        new SpokeBillingRoleStack(app, 'BillingQaStack', {
                          env: { account: qaAccountId, region },
                            centralAccountId,
                              centralJenkinsRoleName: central.jenkinsRoleName,
                                curBucketArn: 'arn:aws:s3:::qa-cur-bucket',
                                });

                                new SpokeBillingRoleStack(app, 'BillingProdStack', {
                                  env: { account: prodAccountId, region },
                                    centralAccountId,
                                      centralJenkinsRoleName: central.jenkinsRoleName,
                                        curBucketArn: 'arn:aws:s3:::prod-cur-bucket',
                                        });


                                        ---

                                        3. Central Stack – lib/central-infra-stack.ts

                                        Imports existing bucket.

                                        Creates JenkinsBillingSyncRole.

                                        Grants:

                                        Put/List on archive bucket.

                                        sts:AssumeRole on each spoke’s role BillingCurReadRole.



                                        import * as cdk from 'aws-cdk-lib';
                                        import { Construct } from 'constructs';
                                        import * as s3 from 'aws-cdk-lib/aws-s3';
                                        import * as iam from 'aws-cdk-lib/aws-iam';

                                        export interface CentralInfraStackProps extends cdk.StackProps {
                                          billingArchiveBucketName: string;
                                            spokeAccountIds: string[];
                                              jenkinsRoleName: string;
                                              }

                                              export class CentralInfraStack extends cdk.Stack {
                                                public readonly jenkinsRoleName: string;

                                                  constructor(scope: Construct, id: string, props: CentralInfraStackProps) {
                                                      super(scope, id, props);

                                                          this.jenkinsRoleName = props.jenkinsRoleName;

                                                              // Import existing archive bucket (already created)
                                                                  const archiveBucket = s3.Bucket.fromBucketName(
                                                                        this,
                                                                              'BillingArchiveBucket',
                                                                                    props.billingArchiveBucketName,
                                                                                        );

                                                                                            // Role Jenkins will use to do billing sync
                                                                                                const jenkinsRole = new iam.Role(this, 'JenkinsBillingSyncRole', {
                                                                                                      roleName: props.jenkinsRoleName,
                                                                                                            // You can tighten this to ArnPrincipal of your Jenkins EC2 / user
                                                                                                                  assumedBy: new iam.AccountPrincipal(this.account), // any principal in this account can assume
                                                                                                                        description: 'Role used by Jenkins in infra account to sync billing CUR from all accounts',
                                                                                                                            });

                                                                                                                                // Jenkins can write ZIPs to archive bucket
                                                                                                                                    archiveBucket.grantReadWrite(jenkinsRole);

                                                                                                                                        // Jenkins can assume the CUR read role in each spoke account
                                                                                                                                            jenkinsRole.addToPolicy(
                                                                                                                                                  new iam.PolicyStatement({
                                                                                                                                                          actions: ['sts:AssumeRole'],
                                                                                                                                                                  resources: props.spokeAccountIds.map(
                                                                                                                                                                            (acc) => `arn:aws:iam::${acc}:role/BillingCurReadRole`,
                                                                                                                                                                                    ),
                                                                                                                                                                                          }),
                                                                                                                                                                                              );
                                                                                                                                                                                                }
                                                                                                                                                                                                }


                                                                                                                                                                                                ---

                                                                                                                                                                                                4. Spoke Stack – lib/spoke-billing-role-stack.ts

                                                                                                                                                                                                Each spoke account (dev/dev2/qa/prod) gets:

                                                                                                                                                                                                A role BillingCurReadRole.

                                                                                                                                                                                                Trusted only by central JenkinsBillingSyncRole.

                                                                                                                                                                                                Permission to read CUR bucket in that account.


                                                                                                                                                                                                import * as cdk from 'aws-cdk-lib';
                                                                                                                                                                                                import { Construct } from 'constructs';
                                                                                                                                                                                                import * as iam from 'aws-cdk-lib/aws-iam';

                                                                                                                                                                                                export interface SpokeBillingRoleStackProps extends cdk.StackProps {
                                                                                                                                                                                                  centralAccountId: string;
                                                                                                                                                                                                    centralJenkinsRoleName: string;
                                                                                                                                                                                                      curBucketArn: string; // e.g. arn:aws:s3:::dev-cur-bucket
                                                                                                                                                                                                      }

                                                                                                                                                                                                      export class SpokeBillingRoleStack extends cdk.Stack {
                                                                                                                                                                                                        constructor(scope: Construct, id: string, props: SpokeBillingRoleStackProps) {
                                                                                                                                                                                                            super(scope, id, props);

                                                                                                                                                                                                                const curBucketArn = props.curBucketArn;
                                                                                                                                                                                                                    const curObjectsArn = `${curBucketArn}/*`;

                                                                                                                                                                                                                        // Trust central Jenkins role only
                                                                                                                                                                                                                            const centralJenkinsRoleArn = `arn:aws:iam::${props.centralAccountId}:role/${props.centralJenkinsRoleName}`;

                                                                                                                                                                                                                                const billingCurReadRole = new iam.Role(this, 'BillingCurReadRole', {
                                                                                                                                                                                                                                      roleName: 'BillingCurReadRole',
                                                                                                                                                                                                                                            assumedBy: new iam.ArnPrincipal(centralJenkinsRoleArn),
                                                                                                                                                                                                                                                  description: 'Role that allows infra Jenkins to read this account CUR S3 bucket',
                                                                                                                                                                                                                                                      });

                                                                                                                                                                                                                                                          // Allow read access to CUR S3 bucket in this account
                                                                                                                                                                                                                                                              billingCurReadRole.addToPolicy(
                                                                                                                                                                                                                                                                    new iam.PolicyStatement({
                                                                                                                                                                                                                                                                            actions: ['s3:GetObject', 's3:ListBucket'],
                                                                                                                                                                                                                                                                                    resources: [curBucketArn, curObjectsArn],
                                                                                                                                                                                                                                                                                          }),
                                                                                                                                                                                                                                                                                              );
                                                                                                                                                                                                                                                                                                }
                                                                                                                                                                                                                                                                                                }


                                                                                                                                                                                                                                                                                                ---

                                                                                                                                                                                                                                                                                                5. How Jenkins Uses STS (High-level)

                                                                                                                                                                                                                                                                                                In your Jenkins pipeline (running in the infra account):

                                                                                                                                                                                                                                                                                                1. Use the infra credentials (or assume JenkinsBillingSyncRole first if needed).


                                                                                                                                                                                                                                                                                                2. For each account (dev/dev2/qa/prod):

                                                                                                                                                                                                                                                                                                ACCOUNT_ID=222222222222
                                                                                                                                                                                                                                                                                                ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/BillingCurReadRole"

                                                                                                                                                                                                                                                                                                CREDS=$(aws sts assume-role \
                                                                                                                                                                                                                                                                                                  --role-arn "$ROLE_ARN" \
                                                                                                                                                                                                                                                                                                    --role-session-name "billing-sync-$ACCOUNT_ID" \
                                                                                                                                                                                                                                                                                                      --query 'Credentials' \
                                                                                                                                                                                                                                                                                                        --output json)

                                                                                                                                                                                                                                                                                                        export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | jq -r '.AccessKeyId')
                                                                                                                                                                                                                                                                                                        export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | jq -r '.SecretAccessKey')
                                                                                                                                                                                                                                                                                                        export AWS_SESSION_TOKEN=$(echo "$CREDS" | jq -r '.SessionToken')

                                                                                                                                                                                                                                                                                                        # Now copy CUR files from that account’s CUR bucket, zip them,
                                                                                                                                                                                                                                                                                                        # and upload to central archive bucket as:
                                                                                                                                                                                                                                                                                                        #   s3://my-existing-billing-archive-bucket/2025/$ACCOUNT_ID/2025_12_06.zip


                                                                                                                                                                                                                                                                                                        3. The date-based ZIP naming (2025_12_06.zip) and archive structure
                                                                                                                                                                                                                                                                                                        year/account-id/year_month_day.zip is implemented in your script, e.g. Python or Bash:

                                                                                                                                                                                                                                                                                                        TODAY=$(date +%Y_%m_%d)
                                                                                                                                                                                                                                                                                                        YEAR=$(date +%Y)

                                                                                                                                                                                                                                                                                                        ZIP_NAME="${TODAY}.zip"
                                                                                                                                                                                                                                                                                                        LOCAL_DIR="cur-$ACCOUNT_ID"
                                                                                                                                                                                                                                                                                                        ARCHIVE_KEY="${YEAR}/${ACCOUNT_ID}/${ZIP_NAME}"

                                                                                                                                                                                                                                                                                                        # (1) download latest CUR objects to $LOCAL_DIR
                                                                                                                                                                                                                                                                                                        # (2) zip them
                                                                                                                                                                                                                                                                                                        # (3) upload to central archive bucket
                                                                                                                                                                                                                                                                                                        aws s3 cp "$ZIP_NAME" "s3://my-existing-billing-archive-bucket/$ARCHIVE_KEY"



                                                                                                                                                                                                                                                                                                        You can extend the script to also pull “previous report” and bundle both in the same ZIP or two different ZIPs – CDK doesn’t need to change for that logic.


                                                                                                                                                                                                                                                                                                        ---

                                                                                                                                                                                                                                                                                                        6. Deploying with Profiles (example)

                                                                                                                                                                                                                                                                                                        In cdk.json you might use:

                                                                                                                                                                                                                                                                                                        {
                                                                                                                                                                                                                                                                                                          "app": "npx ts-node bin/billing-app.ts"
                                                                                                                                                                                                                                                                                                          }

                                                                                                                                                                                                                                                                                                          Then:

                                                                                                                                                                                                                                                                                                          # Central (infra) account
                                                                                                                                                                                                                                                                                                          cdk deploy BillingCentralStack --profile infra-profile

                                                                                                                                                                                                                                                                                                          # Spoke accounts
                                                                                                                                                                                                                                                                                                          cdk deploy BillingDevStack   --profile dev-profile
                                                                                                                                                                                                                                                                                                          cdk deploy BillingDev2Stack  --profile dev2-profile
                                                                                                                                                                                                                                                                                                          cdk deploy BillingQaStack    --profile qa-profile
                                                                                                                                                                                                                                                                                                          cdk deploy BillingProdStack  --profile prod-profile


                                                                                                                                                                                                                                                                                                          ---

                                                                                                                                                                                                                                                                                                          If you want, next step I can also give you a small Python script (ready for GitHub) that:

                                                                                                                                                                                                                                                                                                          Assumes each BillingCurReadRole.

                                                                                                                                                                                                                                                                                                          Finds the latest CUR & previous CUR.

                                                                                                                                                                                                                                                                                                          Creates the ZIP in the exact 2025/account-id/2025_12_06.zip pattern and uploads to the reused archive bucket.