# Bill Split - Target Org Deployment Runbook

This runbook provides complete, step-by-step instructions for deploying the **Bill Split** application to a fresh Salesforce target org (Developer Edition, Sandbox, Scratch Org, or Production).

---

## 1. Prerequisites and Org Requirements

Before initiating deployment, verify that the target Salesforce org and local environment meet all criteria:

### Required Tools
| Tool | Minimum Version | Check Command |
|---|---|---|
| **Salesforce CLI (`sf`)** | `@salesforce/cli` v2.x+ | `sf version` |
| **Node.js** | v18.x or v20.x LTS | `node -v` |
| **npm** | v9.x+ | `npm -v` |
| **Git** | v2.30+ | `git --version` |

### Target Org Licenses & Editions
- **Salesforce Edition**: Developer Edition, Enterprise, Unlimited, or Scratch Org with `Communities` enabled.
- **User Licenses**:
  - `Salesforce` (for Staff and System Administrators).
  - `Customer Community Plus` (required for external property owners accessing the portal with Apex managed sharing).

---

## 2. Pre-Deployment Configuration (Manual Org Setup)

Complete the following steps in the target org **before** running metadata deployments:

### Step 2.1: Enable Digital Experiences (Communities)
> **CRITICAL**: If your target org does not have Digital Experiences enabled, deployments containing `networks/`, `sites/`, or `digitalExperienceConfigs/` will fail immediately.

1. Navigate to **Setup > Feature Settings > Digital Experiences > Settings**.
2. Check **Enable Digital Experiences**.
3. Select a unique domain name suffix (if prompted) and click **Save**.

### Step 2.2: Verify External Sharing Defaults
1. Navigate to **Setup > Security > Sharing Settings**.
2. Click **Edit** under **Organization-Wide Defaults**.
3. Confirm that **External Access** for `Account` and `Contact` is set to **Private** (or Controlled by Parent).
4. Save and allow the recalculation to finish. (The `Property__c` object is deployed with Private OWD, and child objects inherit via master-detail).

### Step 2.3: Configure Portal Account Owner Role
Customer Community Plus users cannot be owned by an internal Salesforce user with no Role assigned.
1. Navigate to **Setup > Users > Users**.
2. Open the administrator or system user who will own Portal Accounts/Contacts.
3. Verify that a **Role** (e.g., `CEO`, `Bill Split Admin`, or any standard role) is assigned.

### Step 2.4: Email Deliverability & Org-Wide Address
1. Navigate to **Setup > Email > Deliverability**.
2. Set **Access level** to **All email** (critical for Sandboxes and Scratch Orgs where default is often *System email only*).
3. Navigate to **Setup > Email > Organization-Wide Addresses**.
4. Add an address (e.g. `billing@yourdomain.com`), set Purpose to **User and System Selection**, and click **Save**.
5. Verify the address via the verification email sent to that inbox.

---

## 3. Local Preparation & Authentication

### Step 3.1: Install Dependencies
From the repository root:
```bash
npm install
```

### Step 3.2: Authenticate Target Org
Authorize your target org and assign it an alias:

**For a Sandbox / Dev / Production Org:**
```bash
# Log in via browser (use test.salesforce.com for Sandboxes)
sf org login web --alias billsplit-target --instance-url https://login.salesforce.com --set-default
```

**For a Scratch Org (from Dev Hub):**
```bash
# Authorize Dev Hub if not already authenticated
sf org login web --alias devhub --set-default-dev-hub

# Create scratch org (duration 30 days)
sf org create scratch --definition-file config/project-scratch-def.json --alias billsplit-scratch --duration-days 30 --set-default
```

---

## 4. Metadata Deployment

### Option A: Standard Full Deployment (Manifest-Based, Recommended)
Deploying via the project manifest `manifest/package.xml` ensures that core objects, classes, triggers, and components deploy in an ordered, validated sequence:

```bash
# 1. Validate without applying changes (Check-Only)
sf project deploy validate \
  --target-org billsplit-target \
  --manifest manifest/package.xml \
  --test-level RunLocalTests \
  --wait 30 \
  --verbose

# 2. Deploy metadata
sf project deploy start \
  --target-org billsplit-target \
  --manifest manifest/package.xml \
  --test-level RunLocalTests \
  --wait 30 \
  --verbose
```

> **Note on Quick Deploy**: If validation passes in a production org, note the `Job ID` from the validation output and execute a quick deploy within 10 days:
> ```bash
> sf project deploy quick --target-org billsplit-target --job-id <JOB_ID> --wait 30
> ```

### Option B: Deploying Specific Test Classes
If unrelated managed package or legacy tests fail in the target org:
```bash
sf project deploy start \
  --target-org billsplit-target \
  --manifest manifest/package.xml \
  --test-level RunSpecifiedTests \
  --tests BillSplitCalculatorTest \
  --tests BillSplitControllerSendTest \
  --tests BillSplitControllerTest \
  --tests BillSplitEmailBuilderTest \
  --tests BillSplitNotificationServiceTest \
  --tests BillSplitServiceTest \
  --tests BillSplitTriggerTest \
  --tests OwnerPortalControllerTest \
  --tests OwnershipSharingServiceTest \
  --tests PropertySetupControllerTest \
  --wait 30
```

---

## 5. Experience Cloud / Portal Recovery & Isolation

### Common Failure Points
Experience Cloud metadata often fails in new target orgs due to org-specific references:
1. `sites/Owner_Portal.site-meta.xml`: Contains hardcoded scratch org usernames in `<siteAdmin>` and `<siteGuestRecordDefaultOwner>`.
2. `networks/Owner Portal.network-meta.xml`: Contains an org-specific `<emailSenderAddress>` and profile references.
3. `profiles/Bill Split Owner Portal.profile-meta.xml`: Fails if `Customer Community Plus` user license is absent.
4. `digitalExperienceConfigs/Owner_Portal1.digitalExperienceConfig-meta.xml`: Fails if Digital Experiences is not enabled.

### Safe Metadata Exclusion (Without Deleting Files)
If deployment fails on any Experience Cloud artifact, **do not delete source files**. Follow this non-destructive isolation procedure:

1. **Add Temporary Exclusions to `.forceignore`**:
   Append the following lines to your local `.forceignore`:
   ```
   # Temporary Experience Cloud exclusion
   force-app/main/default/digitalExperienceConfigs/**
   force-app/main/default/networks/**
   force-app/main/default/sites/**
   force-app/main/default/profiles/Bill Split Owner Portal.profile-meta.xml
   ```

2. **Retry Core Application Deployment**:
   ```bash
   sf project deploy start \
     --target-org billsplit-target \
     --manifest manifest/package.xml \
     --test-level RunSpecifiedTests \
     --tests BillSplitCalculatorTest \
     --tests BillSplitServiceTest \
     --tests BillSplitTriggerTest \
     --tests PropertySetupControllerTest \
     --wait 30
   ```

3. **Configure the Experience Cloud Site Manually in the Target Org**:
   - **Step 1**: Go to **Setup > Feature Settings > Digital Experiences > All Sites > New**.
   - **Step 2**: Select the **Build Your Own (LWR)** template.
   - **Step 3**: Name the site **Owner Portal**, set the URL path to `owners`, and click **Create**.
   - **Step 4**: Open **Experience Builder** > Select **Pages > Home**. Remove placeholder content and drag the custom **billSplitOwnerPortal** component into the layout.
   - **Step 5**: Click **Publish**.
   - **Step 6**: Go to **Workspaces > Administration > Members**. Under *Select Profiles*, add **Customer Community Plus User** (and `Bill Split Owner Portal` if deployed).
   - **Step 7**: Go to **Administration > Settings** and click **Activate**.

4. **Sync / Retrieve Site Metadata (Optional)**:
   Once the site is created and active, retrieve the org-specific configuration:
   ```bash
   sf project retrieve start \
     --target-org billsplit-target \
     --metadata "Network:Owner Portal" \
     --metadata "CustomSite:Owner_Portal"
   ```
   Then remove the temporary exclusions from `.forceignore`.

---

## 6. Post-Deployment Setup & Activation

### Step 6.1: Assign Permission Sets
Assign administrator and staff permissions to your deployment/admin user:
```bash
sf org assign permset \
  --name Bill_Split_Admin \
  --name Bill_Split_UI_Access \
  --target-org billsplit-target
```

For general staff members, assign the permission set group:
```bash
sf org assign permset-license --name Bill_Split_Staff_Group --target-org billsplit-target
```

### Step 6.2: Activate Lightning Record Pages
1. Navigate to **Setup > Object Manager > Utility Bill (`Utility_Bill__c`) > Lightning Record Pages**.
2. Select **Utility Bill Record Page**.
3. Click **Activation... > Assign as Org Default > Desktop > Save**.

### Step 6.3: Configure Custom Metadata (`Bill_Split_Setting__mdt`)
1. Navigate to **Setup > Custom Code > Custom Metadata Types**.
2. Click **Manage Records** next to **Bill Split Setting**.
3. Edit the **Default** record:
   - **Org Wide Email Name**: Enter the exact display name of the verified Org-Wide Email Address created in Section 2.4.
   - **Email Footer**: Confirm or customize the reply guidance.
   - **Max Units Per Property**: Default is `2`.
   - **Reading Date Tolerance Days**: Default is `14`.
4. Click **Save**.

### Step 6.4: Schedule Nightly Owner Access Sync Batch
Execute the following script to schedule the nightly Apex batch (`OwnershipSharingBatch`) that maintains `Property__Share` records:
```bash
sf apex run --file scripts/promote/05-post-deploy-prod.apex --target-org billsplit-target
```

---

## 7. Post-Deployment Smoke Tests & Verification

Verify operational health by running the automated demo seed script and validating the calculations:

### Smoke Test 1: Seed Demo Data
```bash
sf apex run --file scripts/apex/seed-data.apex --target-org billsplit-target
```
*Expected Output*: Creates Demo Household Account, Alex & Sam Contacts, 12 Banksia St Property, Unit A & Unit B, Water Utility Account, SUB-0001 Meter, Baseline reading (1240 kL), Utility Bill DEMO-0001 (120 kL, $480.00), and Bill Close reading (1278 kL).

### Smoke Test 2: Calculate Bill Split
```bash
sf apex run --file scripts/apex/calculate-demo.apex --target-org billsplit-target
```
*Expected Output*:
- Unit B (submetered, 38 kL): **$163.00** ($133.00 usage + $30.00 supply).
- Unit A (residual, 82 kL): **$317.00** ($287.00 usage + $30.00 supply).
- Bill status changes from `Draft` to `Calculated`, with `Allocation_Variance__c` = 0.00.

### Smoke Test 3: Lightning App Verification
1. Open the target org:
   ```bash
   sf org open --target-org billsplit-target
   ```
2. In App Launcher, select **Bill Split**.
3. Verify that the **Property Setup** tab loads the wizard correctly.
4. Open the demo bill **DEMO-0001**:
   - Check that the **billSplitWorkbench** displays the submeter readings (1240 opening, 1278 closing).
   - Verify the calculated allocations table.
   - Check that the **Send** button opens the send preview modal.

### Smoke Test 4: Portal User Verification (If Customer Community Plus enabled)
1. Edit `scripts/apex/create-portal-user.apex` with an email address you control.
2. Run:
   ```bash
   sf apex run --file scripts/apex/create-portal-user.apex --target-org billsplit-target
   ```
3. Query the created share:
   ```bash
   sf data query --query "SELECT ParentId, UserOrGroupId, RowCause, AccessLevel FROM Property__Share WHERE RowCause = 'Owner_Access__c'" --target-org billsplit-target
   ```
4. Log into the Owner Portal and confirm that the property and bill split are visible.

---

## 8. Troubleshooting Matrix

| Issue | Cause | Resolution |
|---|---|---|
| `Unknown user permission: Customer Community Plus` | Target org lacks Community user licenses or Digital Experiences is disabled. | Enable Digital Experiences in Setup, or temporarily exclude `Bill Split Owner Portal.profile-meta.xml` via `.forceignore`. |
| `siteAdmin: User not found` | `sites/Owner_Portal.site-meta.xml` contains a username from another org. | Replace `<siteAdmin>` and `<siteGuestRecordDefaultOwner>` with your active admin username, or configure site manually. |
| `Cannot create user: account owner needs a role` | Internal user owning the Portal Account has no Role. | Assign a UserRole to the Account owner user in **Setup > Users**. |
| `SINGLE_EMAIL_LIMIT_EXCEEDED` or emails not received | Email deliverability is disabled or daily limits reached. | Set **Setup > Deliverability** to **All Email**, and verify Org-Wide Email Address. |
| `No opening reading found for meter` | Meter lacks a Baseline reading. | Insert a Baseline `Meter_Reading__c` with a date preceding the bill close reading date. |
| Leaflet map / Nominatim search fails | CSP Trusted Site missing or blocked by network. | Confirm `Nominatim_OSM` and `OSM_Tiles` exist under **Setup > CSP Trusted Sites**. Fall back to manual address entry if external API is blocked. |
