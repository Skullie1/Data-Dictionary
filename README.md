# Salesforce DX Project: Next Steps

Deploy manifest from repo <a href="https://githubsfdeploy.herokuapp.com">
  <img alt="Deploy to Salesforce"
       src="https://raw.githubusercontent.com/afawcett/githubsfdeploy/master/deploy.png">
</a>

<!--
=============================================================================
KEEP YOUR EXISTING SALESFORCE INSTALL BUTTON MARKUP DIRECTLY BELOW THIS COMMENT.

The installation instructions in this README treat that button as the primary
deployment method.

If you maintain separate Production and Sandbox package links, place both
buttons here.
=============================================================================
-->


<div align="center">

# Data Dictionary Health Scan

### Understand field population, documentation, governance, and technical metadata across Salesforce.

<p>
    <strong>Lightning Web Component</strong>
    &nbsp;•&nbsp;
    <strong>Apex</strong>
    &nbsp;•&nbsp;
    <strong>User-Mode Security</strong>
    &nbsp;•&nbsp;
    <strong>CSV Export</strong>
</p>

<p>
    A practical Salesforce data-dictionary and field-health auditing tool
    designed to help administrators make informed cleanup, documentation,
    and governance decisions.
</p>

</div>

---

## Quick Start

<table>
    <tr>
        <td align="center" width="33%">
            <strong>1. Install</strong><br><br>
            Use the Salesforce install button at the top of this README.
        </td>
        <td align="center" width="33%">
            <strong>2. Assign Access</strong><br><br>
            Assign the <code>Data_Dictionary_App</code> permission set.
        </td>
        <td align="center" width="33%">
            <strong>3. Launch</strong><br><br>
            Open the <code>Data_Dictionary</code> custom tab.
        </td>
    </tr>
</table>

> [!TIP]
> The install button is the recommended deployment method for administrators and end users. Source deployment instructions are also included for developers and contributors.

---

## Table of Contents

- [Overview](#overview)
- [What the Tool Provides](#what-the-tool-provides)
- [How the Audit Works](#how-the-audit-works)
- [Included Salesforce Components](#included-salesforce-components)
- [Installation](#installation)
- [Post-Installation Setup](#post-installation-setup)
- [Security and Access](#security-and-access)
- [Using the Tool](#using-the-tool)
- [Configuration JSON](#configuration-json)
- [Understanding the Results](#understanding-the-results)
- [Audit Rollups](#audit-rollups)
- [Large-Org Considerations](#large-org-considerations)
- [Known Limitations](#known-limitations)
- [Screenshots](#screenshots)
- [Demo Video](#demo-video)
- [Troubleshooting](#troubleshooting)
- [License](#license)

---

# Overview

Data Dictionary Health Scan helps Salesforce administrators, architects, analysts, and governance teams understand how fields are configured and populated across an org.

The tool combines field population analysis with documentation, governance, history-tracking, and technical metadata in one searchable interface.

It can help answer questions such as:

- Which fields contain data?
- Which fields appear unused?
- Which fields have very low population?
- Which fields are missing descriptions?
- Which fields are missing inline help text?
- Which fields have field history tracking enabled?
- Which fields have governance classifications?
- Which fields are formulas, lookups, external IDs, unique fields, or required fields?
- Which objects and fields are accessible to the user running the audit?
- Which fields should be reviewed before cleanup, migration, or redesign?

> [!IMPORTANT]
> Audit results reflect the access of the user running the tool. Object permissions, field-level security, sharing rules, and record visibility directly affect the results.

---

# What the Tool Provides

<table>
    <tr>
        <td width="50%" valign="top">
            <h3>Object Selection</h3>
            <ul>
                <li>Search by object label or API name.</li>
                <li>Filter standard, custom, or selected objects.</li>
                <li>Select individual objects with checkboxes.</li>
                <li>Select all objects matching the current filter.</li>
                <li>Preselect objects through JSON configuration.</li>
            </ul>
        </td>
        <td width="50%" valign="top">
            <h3>Population Analysis</h3>
            <ul>
                <li>Count records visible to the running user.</li>
                <li>Count populated values for supported fields.</li>
                <li>Calculate field population percentages.</li>
                <li>Identify fields with no data.</li>
                <li>Identify fields below a configurable threshold.</li>
            </ul>
        </td>
    </tr>
    <tr>
        <td width="50%" valign="top">
            <h3>Metadata Health</h3>
            <ul>
                <li>Field descriptions</li>
                <li>Inline help text</li>
                <li>Field history tracking</li>
                <li>Formula and required status</li>
                <li>External ID and uniqueness settings</li>
                <li>Relationship and picklist metadata</li>
            </ul>
        </td>
        <td width="50%" valign="top">
            <h3>Governance</h3>
            <ul>
                <li>Field Usage</li>
                <li>Data Sensitivity Level</li>
                <li>Compliance Categorization</li>
                <li>Governance-completeness rollups</li>
                <li>Documentation-health scoring</li>
            </ul>
        </td>
    </tr>
    <tr>
        <td width="50%" valign="top">
            <h3>Results Interface</h3>
            <ul>
                <li>Search and filter results.</li>
                <li>Sort the complete result set.</li>
                <li>Use pagination or infinite scrolling.</li>
                <li>Display full or trimmed column sets.</li>
                <li>Review detailed rollup explanations.</li>
            </ul>
        </td>
        <td width="50%" valign="top">
            <h3>Actions and Export</h3>
            <ul>
                <li>Open fields directly in Lightning Setup.</li>
                <li>Edit eligible unpackaged custom fields.</li>
                <li>Export full or trimmed CSV files.</li>
                <li>Protect exported values from spreadsheet formulas.</li>
                <li>Apply runtime JSON configuration.</li>
            </ul>
        </td>
    </tr>
</table>

---

# How the Audit Works

## Initial Object Inventory

When the component loads, it reads Salesforce schema metadata and prepares the object-selection table.

This initial step is affected primarily by:

- The number of installed Salesforce products
- The number of managed packages
- The number of standard and custom objects
- The number of fields
- The running user’s object and field access

The initial inventory does **not** scan business-record data.

## Object Audit

When the user selects **Run Audit**, each selected object is evaluated sequentially.

Each object runs in a separate Apex transaction, providing a fresh set of governor limits for every object.

For each selected object, the tool:

1. Counts records visible to the running user.
2. Loads accessible field metadata.
3. Builds the field inventory.
4. Identifies fields eligible for population analysis.
5. Groups supported fields into aggregate queries.
6. Calculates populated-record counts and population percentages.
7. Scores documentation and governance metadata.
8. Returns the results to the Lightning Web Component.
9. Updates the rollups and results table.

## Checkbox Fields

Checkbox fields remain part of the data dictionary and metadata audit, but their TRUE/FALSE value distribution is intentionally excluded from population analysis.

For checkbox fields:

- Metadata is displayed.
- The field remains in the results table.
- The field is included in CSV exports.
- No TRUE/FALSE distribution query is executed.
- Usage Method displays `Excluded by design`.
- Usage Status displays `Not applicable`.
- The field does not increase the No Data, Low Usage, or Not Evaluated rollups.

This approach:

- Reduces SOQL query usage.
- Improves performance on objects with many checkbox fields.
- Avoids treating `FALSE` as equivalent to an empty value.
- Keeps the tool focused on practical field-population analysis.

---

# Included Salesforce Components

The solution uses the following metadata API names:

| Metadata Type | API Name | Purpose |
|---|---|---|
| Apex Class | `DataDictionaryController` | Loads object metadata and performs field audits. |
| Apex Test Class | `DataDictionaryControllerTest` | Tests controller behavior, security, counting, scoring, and exclusions. |
| Lightning Web Component | `dataDictionaryAudit` | Provides configuration, object selection, rollups, results, links, and export. |
| Custom Tab | `Data_Dictionary` | Exposes the Lightning Web Component as a standalone Salesforce tab. |
| Permission Set | `Data_Dictionary_App` | Grants Apex-class access and custom-tab visibility. |

## Expected Source Structure

```text
force-app/
└── main/
    └── default/
        ├── classes/
        │   ├── DataDictionaryController.cls
        │   ├── DataDictionaryController.cls-meta.xml
        │   ├── DataDictionaryControllerTest.cls
        │   └── DataDictionaryControllerTest.cls-meta.xml
        │
        ├── lwc/
        │   └── dataDictionaryAudit/
        │       ├── dataDictionaryAudit.html
        │       ├── dataDictionaryAudit.js
        │       └── dataDictionaryAudit.js-meta.xml
        │
        ├── permissionsets/
        │   └── Data_Dictionary_App.permissionset-meta.xml
        │
        └── tabs/
            └── Data_Dictionary.tab-meta.xml
```

---

# Installation

## Recommended: One-Click Package Installation

Use the Salesforce install button at the top of this README.

### Installation Steps

1. Select the install button.
2. Sign in to the Salesforce org where the tool should be installed.
3. Review the package details.
4. Choose the installation-access option appropriate for the org.
5. Complete the installation.
6. Wait for Salesforce to confirm that the package was installed.
7. Continue with the [Post-Installation Setup](#post-installation-setup).

For an initial validation, limiting package access and then assigning the included permission set is generally the safest approach.

> [!NOTE]
> If separate Production and Sandbox package URLs are maintained, provide a separate install button for each environment at the top of this README.

## Maintaining the Install Button

When a new package version is released:

1. Promote or publish the new package version.
2. Update the install button to reference the new package-version URL.
3. Test the button in a sandbox or test org.
4. Confirm that the package includes all required metadata.
5. Confirm that the permission set and custom tab are available after installation.

## Post-Install Checklist

- [ ] Package installation completed successfully.
- [ ] `Data_Dictionary_App` permission set assigned.
- [ ] `Data_Dictionary` tab visible to the user.
- [ ] `DataDictionaryControllerTest` verified in the target org.
- [ ] Tool opened successfully from the App Launcher.
- [ ] A small test audit completed successfully.
- [ ] Field Setup links tested with an appropriately permissioned user.
- [ ] CSV export tested.

---

## Alternative: Source Deployment

Source deployment is intended for developers, contributors, and organizations that do not use the installable package.

<details>
<summary><strong>View source-deployment instructions</strong></summary>

### Prerequisites

Confirm that:

- Lightning Experience is enabled.
- The deploying user can deploy Apex classes.
- The deploying user can deploy Lightning Web Components.
- The deploying user can deploy permission sets.
- The deploying user can deploy custom tabs.
- All source files are present in the expected project folders.

### Deploy from Salesforce Extensions for Visual Studio Code

1. Open the Salesforce DX project.
2. Confirm that the target org is authorized.
3. Locate the metadata under `force-app/main/default`.
4. Select the relevant folders or deployment manifest.
5. Use the Salesforce deployment action to deploy the source.
6. Review the deployment result.
7. Resolve any deployment errors.
8. Run `DataDictionaryControllerTest`.
9. Confirm that all tests pass.
10. Continue with the post-installation steps.

### Example Deployment Manifest

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types>
        <members>DataDictionaryController</members>
        <members>DataDictionaryControllerTest</members>
        <name>ApexClass</name>
    </types>

    <types>
        <members>Data_Dictionary</members>
        <name>CustomTab</name>
    </types>

    <types>
        <members>dataDictionaryAudit</members>
        <name>LightningComponentBundle</name>
    </types>

    <types>
        <members>Data_Dictionary_App</members>
        <name>PermissionSet</name>
    </types>

    <version>67.0</version>
</Package>
```

Use the API version configured for the project if it differs from the example.

</details>

---

# Post-Installation Setup

## Assign the Permission Set

The permission set API name is:

```text
Data_Dictionary_App
```

To assign it:

1. Open **Setup**.
2. Search for **Permission Sets**.
3. Open the permission set with API name `Data_Dictionary_App`.
4. Select **Manage Assignments**.
5. Select **Add Assignments**.
6. Select the users who should access the tool.
7. Complete the assignment.

The permission set grants:

- Access to `DataDictionaryController`
- Visibility to the `Data_Dictionary` custom tab

The permission set does **not** grant unrestricted access to:

- Salesforce records
- Salesforce objects
- Salesforce fields
- Setup
- Metadata administration
- Modify All Data

## Open the Custom Tab

The custom-tab API name is:

```text
Data_Dictionary
```

After assigning the permission set:

1. Open the **App Launcher**.
2. Select **View All**.
3. Search for the Data Dictionary tab.
4. Open the tab.

The displayed tab label is controlled by the custom-tab metadata and can differ from the API name.

## Add the Tab to a Lightning App

To add the tab to a specific Lightning application:

1. Open **Setup**.
2. Search for **App Manager**.
3. Locate the desired Lightning application.
4. Select **Edit**.
5. Open **Navigation Items**.
6. Add the Data Dictionary custom tab.
7. Save the application.
8. Refresh or reopen the application.

---

# Security and Access

The tool respects the access of the user running the audit.

<table>
    <tr>
        <th>Access Area</th>
        <th>Effect on the Audit</th>
    </tr>
    <tr>
        <td><strong>Object Permissions</strong></td>
        <td>Determine which objects appear and can be audited.</td>
    </tr>
    <tr>
        <td><strong>Field-Level Security</strong></td>
        <td>Determines which fields are included in the field inventory.</td>
    </tr>
    <tr>
        <td><strong>Record Sharing</strong></td>
        <td>Determines which records contribute to population counts.</td>
    </tr>
    <tr>
        <td><strong>Apex-Class Access</strong></td>
        <td>Provided by the <code>Data_Dictionary_App</code> permission set.</td>
    </tr>
    <tr>
        <td><strong>Setup Permissions</strong></td>
        <td>Determine whether the user can view or edit field metadata.</td>
    </tr>
</table>

## Organization-Wide Audits

For consistent organization-wide results, use a dedicated audit user with appropriate:

- Object access
- Field access
- Record visibility
- Setup access, when field editing is required

> [!WARNING]
> Two users with different sharing or field-level access can receive different audit results for the same object.

---

# Using the Tool

## 1. Open the Data Dictionary Tab

Open the custom tab deployed as:

```text
Data_Dictionary
```

The component initially displays a schema-loading message while it prepares the object inventory.

---

## 2. Configure the Audit

When the component is opened through the custom tab, the **Runtime Configuration** section is available near the top of the page.

Available actions include:

### Edit JSON

Opens the multiline JSON editor.

### Load Template

Loads a starter configuration for:

- Sales Cloud
- Service Cloud

The template is not applied until the user selects **Apply Configuration**.

### Format JSON

Validates the JSON and formats it with readable indentation.

### Apply Configuration

Applies the runtime JSON, reloads the object inventory, and clears existing audit results.

### Reset to Component Configuration

Removes the runtime override and restores the component’s original configuration.

> [!NOTE]
> Runtime changes apply only to the current component session. They are not written back to Lightning App Builder or Salesforce metadata.

---

## 3. Select Objects

Use the object-selection table to define the audit scope.

### Search Objects

Searches across:

- Object label
- Object API name
- Object type

### Object Filter

Available options include:

- All objects
- Standard objects
- Custom objects
- Selected objects

### Bulk Actions

- **Select All Matching**
- **Clear Matching**
- **Clear All**

### Table Checkboxes

Use row checkboxes to select individual objects.

The header checkbox selects or clears all currently displayed objects.

Selections hidden by a search or filter remain selected.

---

## 4. Run the Audit

After selecting one or more objects, select:

```text
Run Audit
```

The progress area displays:

- The object currently being evaluated
- The number of completed objects
- The total number of selected objects
- Overall completion percentage

---

## 5. Stop a Large Audit

While an audit is running, select:

```text
Stop After Current Object
```

The current object is allowed to finish.

Results from completed objects are retained.

Objects that have not started are skipped.

---

## 6. Review Audit Rollups

The Audit Rollups panel updates as objects complete.

Each tile includes a Salesforce help-text icon that explains:

- What the tile counts
- Which fields are included
- Which fields are excluded
- Which denominator is used
- How the percentage is calculated

The rollup panel scrolls independently so it does not increase the height of the object-selection table.

---

## 7. Filter the Results

### Audited Object

Displays results for:

- One completed object
- All completed objects

### Search Fields

Searches across:

- Object label
- Object API name
- Field label
- Field API name
- Field type
- Description
- Help text
- Governance values
- Metadata status
- Usage status
- Notes

### Metadata Issues Only

Displays fields whose metadata audit status is not complete.

### Usage Issues Only

Displays population-eligible fields with one of the following statuses:

- No Data
- Low Usage
- Not Evaluated

Checkbox fields are not included because their population status is `Not applicable`.

---

## 8. Sort the Results

Select a sortable column heading to sort the results.

Sorting is applied to the complete filtered result set before pagination or infinite-scroll windowing.

Sorting is not limited to the currently visible page.

---

## 9. Use Pagination or Infinite Scrolling

### Pagination

Pagination provides:

- First
- Previous
- Current-page indicator
- Next
- Last
- Configurable rows per page

### Infinite Scroll

Infinite Scroll loads additional rows as the user reaches the end of the current result window.

The batch-size control determines how many rows are loaded at a time.

---

## 10. Trim the Result Columns

Enable:

```text
Trim Columns
```

Trimmed mode keeps the primary population, documentation, and governance information while hiding additional technical columns.

Trimmed mode affects:

- The results table
- The CSV export

---

## 11. Open a Field in Lightning Setup

The **Field Label** column acts as the field Setup link.

Depending on the field:

- Eligible unpackaged custom fields can open the Lightning edit page.
- Standard fields open the Lightning view page.
- Managed-package fields open the Lightning view page.
- Person Account fields generally open the Lightning view page.
- Restricted or non-editable fields open the Lightning view page.

A field opening in view mode does not mean the audit failed.

---

## 12. Export Results

Select:

```text
Export Full CSV
```

or:

```text
Export Trimmed CSV
```

The export includes:

- Every row matching the current filters
- The complete sorted result set
- All matching rows, not only the current page
- Protection against spreadsheet formula interpretation

---

# Configuration JSON

The component uses one JSON configuration object.

## Default Configuration

An empty object loads all eligible readable objects without preselecting them:

```json
{}
```

## Basic Example

```json
{
  "objectApiNames": [
    "Account",
    "Contact",
    "Opportunity",
    "Case"
  ],
  "includeStandardObjects": true,
  "includeCustomObjects": true,
  "includeSystemObjects": false,
  "lowUsageThresholdPercent": 5
}
```

## Configuration Properties

| Property | Type | Description |
|---|---|---|
| `objectApiNames` | Array of strings | Object API names initially selected when the inventory loads. |
| `includeStandardObjects` | Boolean | Includes eligible standard objects in the object selector. |
| `includeCustomObjects` | Boolean | Includes eligible custom objects in the object selector. |
| `includeSystemObjects` | Boolean | Includes technical and system-like objects normally hidden from the selector. |
| `lowUsageThresholdPercent` | Number | Population percentage below which a populated field is classified as Low Usage. |

> [!NOTE]
> `objectApiNames` controls the initial selection. It does not act as a strict allowlist. Users can select other eligible objects from the table.

<details>
<summary><strong>Sales Cloud example</strong></summary>

```json
{
  "objectApiNames": [
    "Account",
    "Contact",
    "Lead",
    "Opportunity",
    "OpportunityLineItem",
    "Product2",
    "Pricebook2",
    "PricebookEntry",
    "Campaign",
    "CampaignMember",
    "Quote",
    "QuoteLineItem",
    "Contract",
    "Order",
    "OrderItem",
    "Task",
    "Event"
  ],
  "includeStandardObjects": true,
  "includeCustomObjects": true,
  "includeSystemObjects": false,
  "lowUsageThresholdPercent": 5
}
```

</details>

<details>
<summary><strong>Service Cloud example</strong></summary>

```json
{
  "objectApiNames": [
    "Account",
    "Contact",
    "Case",
    "CaseComment",
    "CaseContactRole",
    "CaseTeamMember",
    "EmailMessage",
    "Asset",
    "Product2",
    "Contract",
    "ServiceContract",
    "Entitlement",
    "EntitlementContact",
    "CaseMilestone",
    "MilestoneType",
    "WorkOrder",
    "WorkOrderLineItem",
    "Task",
    "Event"
  ],
  "includeStandardObjects": true,
  "includeCustomObjects": true,
  "includeSystemObjects": false,
  "lowUsageThresholdPercent": 5
}
```

</details>

Some objects depend on optional Salesforce features. If an object is unavailable, the tool displays a warning and continues loading the remaining eligible objects.

---

# Understanding the Results

## Population Analysis Applicable

Indicates whether a field participates in population analysis.

A field is eligible when:

- The running user can access the field.
- The field is not a checkbox.
- Salesforce supports `COUNT(field)` for the field type.

## Populated Records

The number of visible records where the field contains a value.

For checkbox fields, this value is blank because checkbox-value distribution is excluded.

## Population Percentage

Calculated as:

```text
Populated Records ÷ Total Visible Records × 100
```

## Usage Status

| Status | Meaning |
|---|---|
| `Used` | The field contains data and meets or exceeds the low-usage threshold. |
| `Low usage` | The field contains data but is below the configured threshold. |
| `No data` | The object has records, but the field is unpopulated on all visible records. |
| `Object has no records` | The object contains no records visible to the running user. |
| `Not evaluated` | The field was eligible, but the aggregate count did not complete. |
| `Not applicable` | Population analysis was intentionally excluded for the field. |

---

# Audit Rollups

Every rollup tile includes detailed help text in the interface.

## Scope

- Objects Audited
- Fields Audited
- Population Eligible
- Checkbox Fields
- Other Not Applicable

## Documentation

- Fully Documented
- Missing Description
- Missing Help Text

## Governance

- History Tracked
- Field Usage Set
- Sensitivity Set
- Compliance Set
- Governance Complete

## Technical Metadata

- Custom Fields
- Required Fields
- Formula Fields
- External IDs
- Unique Fields
- Picklist Fields
- Relationship Fields

## Population Analysis

- No Data
- Below Threshold Usage
- Not Evaluated

Checkbox and other Not Applicable fields are excluded from population-analysis rollups.

---

# Large-Org Considerations

The tool does not retrieve every business record into Apex or the browser.

Population analysis uses aggregate queries and returns one result row per field.

Performance still depends on:

- Number of selected objects
- Number of fields per object
- Number of accessible records
- Sharing-rule complexity
- Installed packages
- Salesforce database aggregation performance

## Recommended Approach for Large Audits

1. Start with a small set of representative objects.
2. Test the largest objects individually.
3. Keep the browser page open while the audit runs.
4. Use **Stop After Current Object** when needed.
5. Review warnings and Not Evaluated results.
6. Expand the object scope after confirming acceptable performance.

Removing checkbox-value evaluation significantly reduces query usage, but performance can still vary across Salesforce orgs.

---

# Known Limitations

- Population counts reflect records visible to the running user.
- Fields hidden by field-level security are excluded.
- Checkbox TRUE/FALSE distribution is not evaluated.
- Some field types do not support population analysis.
- Some governance metadata can display `Unavailable`.
- Runtime JSON changes are not saved to Salesforce metadata.
- Audit results are not persisted after the component session ends.
- The audit is not currently scheduled or background-persisted.
- The browser page must remain open while the audit runs.
- Field Setup links require separate Setup permissions.
- Managed-package and standard fields can open in view mode instead of edit mode.

---

# Screenshots

Replace the placeholders below after the interface is finalized.

<table>
    <tr>
        <td align="center" width="50%">
            <strong>Initial Loading Experience</strong><br><br>
            <img width="1439" height="364" alt="image" src="https://github.com/user-attachments/assets/b8907fa0-f9b0-4a95-8352-2989f56e725b" />
        </td>
        <td align="center" width="50%">
            <strong>Runtime Configuration</strong><br><br>
            <img width="1404" height="688" alt="Screenshot 2026-07-28 at 9 02 36 AM" src="https://github.com/user-attachments/assets/9d478068-2e5b-4541-9f91-5129825f3bc8" />
        </td>
    </tr>
    <tr>
        <td align="center" width="50%">
            <strong>Object Selection</strong><br><br>
            <img width="1409" height="617" alt="Screenshot 2026-07-28 at 9 03 49 AM" src="https://github.com/user-attachments/assets/27770929-38b7-4801-b9b5-306df79319b0" />
        </td>
        <td align="center" width="50%">
            <strong>Audit Progress</strong><br><br>
          <img width="1453" height="257" alt="Screenshot 2026-07-28 at 9 05 01 AM" src="https://github.com/user-attachments/assets/84d01d17-5ba5-4687-b5fd-a42798e2d11f" />
        </td>
    </tr>
    <tr>
        <td align="center" width="50%">
            <strong>Audit Rollups</strong><br><br>
          <img width="514" height="410" alt="Screenshot 2026-07-28 at 9 06 28 AM" src="https://github.com/user-attachments/assets/e12228cb-dffd-409c-ba70-b2ddb4f62b4b" />
        </td>
        <td align="center" width="50%">
            <strong>Field Results</strong><br><br>
          <img width="1410" height="463" alt="Screenshot 2026-07-28 at 9 07 04 AM" src="https://github.com/user-attachments/assets/501481d1-c2ed-4209-a8a4-356a193e1459" />
        </td>
    </tr>
</table>

After adding the images, replace the placeholders with markup such as:

---

# Demo Video





---

# Troubleshooting

<details>
<summary><strong>The install button does not open a valid package</strong></summary>

- Confirm that the button references the current package-version URL.
- Confirm that the package version has been promoted or made installable.
- Confirm that the link is appropriate for the target environment.
- Update the button after publishing a new package version.
- Test the link in a separate Salesforce org.

</details>

<details>
<summary><strong>The custom tab is not visible</strong></summary>

Confirm that:

- `Data_Dictionary` was installed or deployed.
- `Data_Dictionary_App` is assigned to the user.
- The tab is available through the App Launcher.
- The tab was added to the desired Lightning app navigation.
- The user refreshed or reopened the Lightning application.

</details>

<details>
<summary><strong>The user receives an Apex access error</strong></summary>

Confirm that:

- `DataDictionaryController` is installed.
- `Data_Dictionary_App` grants access to the controller.
- The permission set is assigned to the user.

</details>

<details>
<summary><strong>The object list is empty</strong></summary>

Confirm that the user has access to at least one:

- Accessible object
- Queryable object
- Object with an accessible Id field

Also review the JSON configuration filters.

</details>

<details>
<summary><strong>A configured object produces a warning</strong></summary>

The object might:

- Not exist in the org
- Depend on an optional Salesforce feature
- Be hidden from the user
- Be non-queryable
- Be excluded by the current configuration

The remaining eligible objects can still load.

</details>

<details>
<summary><strong>Metadata displays Unavailable</strong></summary>

The running user may not have access to the required `FieldDefinition` metadata.

Population analysis can still complete even when governance metadata is unavailable.

</details>

<details>
<summary><strong>A checkbox displays Not Applicable</strong></summary>

This is expected.

Checkboxes are included in metadata auditing but excluded from TRUE/FALSE distribution analysis.

</details>

<details>
<summary><strong>A field displays Not Evaluated</strong></summary>

The field was eligible for population analysis, but its aggregate count did not complete.

Review the field note and audit warnings for additional details.

</details>

<details>
<summary><strong>A field opens in view mode</strong></summary>

Direct editing is limited to eligible unpackaged custom fields.

Standard, managed-package, Person Account, and restricted fields can open in Lightning view mode.

</details>

<details>
<summary><strong>Results differ between users</strong></summary>

This is expected when users have different:

- Object permissions
- Field permissions
- Sharing access
- Record visibility

Use a dedicated audit user for consistent organization-wide results.

</details>

---

# License

Add the selected project license here.

<!--
Example:

MIT License

Copyright (c) YEAR OWNER
-->
## Read All About It

- [Salesforce Extensions Documentation](https://developer.salesforce.com/tools/vscode/)
- [Salesforce CLI Setup Guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_setup.meta/sfdx_setup/sfdx_setup_intro.htm)
- [Salesforce DX Developer Guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_intro.htm)
- [Salesforce CLI Command Reference](https://developer.salesforce.com/docs/atlas.en-us.sfdx_cli_reference.meta/sfdx_cli_reference/cli_reference.htm)
