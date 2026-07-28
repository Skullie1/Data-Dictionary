import { LightningElement, api } from 'lwc';
import getBootstrap from '@salesforce/apex/DataDictionaryController.getBootstrap';
import auditObject from '@salesforce/apex/DataDictionaryController.auditObject';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

/*
 * Component-wide constants.
 */
const VIEW_ALL_OBJECTS = '__VIEW_ALL_OBJECTS__';
const DEFAULT_ROW_BATCH_SIZE = 50;
const MAX_CONFIGURATION_LENGTH = 50000;

const ROW_BATCH_OPTIONS = [
    { label: '25 rows', value: '25' },
    { label: '50 rows', value: '50' },
    { label: '100 rows', value: '100' },
    { label: '200 rows', value: '200' }
];

const OBJECT_TYPE_OPTIONS = [
    { label: 'All objects', value: 'all' },
    { label: 'Standard objects', value: 'standard' },
    { label: 'Custom objects', value: 'custom' },
    { label: 'Selected objects', value: 'selected' }
];

/*
 * Starter configurations available from the runtime JSON editor.
 */
const CONFIGURATION_TEMPLATES = Object.freeze({
    sales: {
        objectApiNames: [
            'Account',
            'Contact',
            'Lead',
            'Opportunity',
            'OpportunityLineItem',
            'Product2',
            'Pricebook2',
            'PricebookEntry',
            'Campaign',
            'CampaignMember',
            'Quote',
            'QuoteLineItem',
            'Contract',
            'Order',
            'OrderItem',
            'Task',
            'Event'
        ],
        includeStandardObjects: true,
        includeCustomObjects: true,
        includeSystemObjects: false,
        lowUsageThresholdPercent: 5
    },
    service: {
        objectApiNames: [
            'Account',
            'Contact',
            'Case',
            'CaseComment',
            'CaseContactRole',
            'CaseTeamMember',
            'EmailMessage',
            'Asset',
            'Product2',
            'Contract',
            'ServiceContract',
            'Entitlement',
            'EntitlementContact',
            'CaseMilestone',
            'MilestoneType',
            'WorkOrder',
            'WorkOrderLineItem',
            'Task',
            'Event'
        ],
        includeStandardObjects: true,
        includeCustomObjects: true,
        includeSystemObjects: false,
        lowUsageThresholdPercent: 5
    }
});

/*
 * Detailed explanations shown through lightning-helptext beside each
 * audit rollup tile.
 */
const ROLLUP_HELP_TEXT = Object.freeze({
    objects:
        'The number of selected objects whose audits completed and contributed results. Objects that failed or were not started are not included.',

    fields:
        'The total number of fields returned for completed object audits. Fields hidden from the running user by field-level security are not included.',

    'population-eligible':
        'Accessible non-checkbox fields that support COUNT(field) population analysis. These fields are included in No Data, Low Usage, and Not Evaluated calculations.',

    'checkbox-fields':
        'Checkbox fields included in the metadata audit. Their TRUE and FALSE value distribution is intentionally excluded from population analysis to reduce query usage and avoid misleading population percentages.',

    'other-not-applicable':
        'Non-checkbox fields included in the metadata audit but excluded from population analysis because Salesforce does not support COUNT(field) for their field type.',

    documented:
        'Fields that have both a field description and inline help text. The percentage uses only fields for which description metadata was available.',

    'missing-description':
        'Fields with readable description metadata where the field description is blank. Fields whose description metadata was unavailable are not counted as missing.',

    'missing-help':
        'Audited fields that do not have inline help text. Inline help text is read from normal field describe metadata.',

    'history-tracked':
        'Fields reported by FieldDefinition as enabled for field history tracking. The percentage uses only fields where history-tracking metadata was available.',

    'field-usage-set':
        'Fields with a populated Salesforce Field Usage value, such as Active or Deprecate Candidate. The percentage uses only fields where governance metadata was available.',

    'sensitivity-set':
        'Fields with a populated Data Sensitivity Level, such as Internal, Confidential, or Restricted. The percentage uses only fields where governance metadata was available.',

    'compliance-set':
        'Fields with at least one populated Compliance Categorization value. The percentage uses only fields where governance metadata was available.',

    'governance-complete':
        'Fields that have Field Usage, Data Sensitivity Level, and Compliance Categorization populated. All three values must be present for a field to count as complete.',

    custom:
        'Fields identified by Salesforce describe metadata as custom fields. Standard fields are not included in this count.',

    required:
        'Fields that must be supplied when creating a record because they are not nillable and are not satisfied by a default, formula, or auto-number value.',

    formula:
        'Fields whose values are calculated by Salesforce through a formula or other calculated-field behavior.',

    external:
        'Fields configured as External IDs. These fields can be used for integrations, upsert operations, and external record matching.',

    unique:
        'Fields configured with a uniqueness constraint. Salesforce prevents duplicate values for these fields according to the field configuration.',

    picklist:
        'Fields whose type is Picklist, Multi-Select Picklist, or Combobox. This count includes both standard and custom picklist-like fields.',

    relationship:
        'Fields that reference one or more Salesforce objects, including lookup, master-detail, owner, and polymorphic relationship fields.',

    'no-data':
        'Population-eligible fields with zero populated records on an object that contains records. Fields on completely empty objects use the Object has no records status and are not counted here.',

    'low-usage':
        'Population-eligible fields with at least one populated record but a population percentage below the configured low-usage threshold.',

    'not-evaluated':
        'Population-eligible fields whose aggregate count did not complete. This can occur because of query behavior, field-specific limitations, or the controller preserving its SOQL query reserve. Checkbox and Not Applicable fields are excluded.'
});

/*
 * Natural text comparison keeps values such as Field2 before Field10.
 */
const TEXT_COLLATOR = new Intl.Collator(undefined, {
    numeric: true,
    sensitivity: 'base'
});

/*
 * Explicit sort types prevent numbers and Booleans from sorting as text.
 */
const RESULT_SORT_TYPES = Object.freeze({
    totalRecords: 'number',
    populatedRecords: 'number',
    populationPercent: 'number',
    documentationScore: 'number',
    activePicklistValueCount: 'number',
    totalPicklistValueCount: 'number',
    length: 'number',
    precision: 'number',
    scale: 'number',
    populationAnalysisApplicable: 'boolean',
    checkboxField: 'boolean',
    hasDescription: 'boolean',
    hasHelpText: 'boolean',
    fieldHistoryTracked: 'boolean',
    historyTrackingAuditAvailable: 'boolean',
    descriptionAuditAvailable: 'boolean',
    customField: 'boolean',
    required: 'boolean',
    nillable: 'boolean',
    calculated: 'boolean',
    autoNumber: 'boolean',
    externalId: 'boolean',
    uniqueField: 'boolean',
    defaultedOnCreate: 'boolean',
    createable: 'boolean',
    updateable: 'boolean',
    filterable: 'boolean',
    groupable: 'boolean',
    sortable: 'boolean',
    aggregatable: 'boolean',
    restrictedPicklist: 'boolean',
    dependentPicklist: 'boolean'
});

const OBJECT_SORT_TYPES = Object.freeze({
    customObject: 'boolean'
});

/*
 * The Field Label URL column stores setupUrl but sorts by fieldLabel.
 */
const RESULT_SORT_FIELD_ALIASES = Object.freeze({
    setupUrl: 'fieldLabel'
});

/*
 * Creates the complete zero-value rollup state.
 */
function createEmptySummary() {
    return {
        objectCount: 0,
        fieldCount: 0,
        populationEligibleFields: 0,
        checkboxFields: 0,
        otherNotApplicableFields: 0,
        documented: 0,
        documentationEvaluated: 0,
        missingDescription: 0,
        descriptionEvaluated: 0,
        missingHelpText: 0,
        historyTracked: 0,
        historyEvaluated: 0,
        fieldUsageSet: 0,
        fieldUsageEvaluated: 0,
        sensitivitySet: 0,
        sensitivityEvaluated: 0,
        complianceSet: 0,
        complianceEvaluated: 0,
        governanceComplete: 0,
        governanceEvaluated: 0,
        customFields: 0,
        requiredFields: 0,
        formulaFields: 0,
        externalIdFields: 0,
        uniqueFields: 0,
        picklistFields: 0,
        relationshipFields: 0,
        noData: 0,
        lowUsage: 0,
        notEvaluated: 0
    };
}

/*
 * Shared datatable column factories.
 */
function textColumn(
    label,
    fieldName,
    width,
    wrapText,
    sortable
) {
    return {
        label,
        fieldName,
        type: 'text',
        sortable: sortable !== false,
        wrapText: wrapText === true,
        initialWidth: width || 150
    };
}

function booleanColumn(
    label,
    fieldName,
    width,
    sortable
) {
    return {
        label,
        fieldName,
        type: 'boolean',
        sortable: sortable !== false,
        initialWidth: width || 100
    };
}

function numberColumn(
    label,
    fieldName,
    width,
    decimalPlaces,
    sortable
) {
    const places = decimalPlaces || 0;

    return {
        label,
        fieldName,
        type: 'number',
        sortable: sortable !== false,
        initialWidth: width || 105,
        typeAttributes: {
            minimumFractionDigits: places,
            maximumFractionDigits: places
        }
    };
}

/*
 * Object selector columns.
 */
const OBJECT_SELECTION_COLUMNS = [
    textColumn(
        'Object Label',
        'objectLabel',
        220,
        true
    ),
    textColumn(
        'Object API Name',
        'value',
        220,
        false
    ),
    textColumn(
        'Type',
        'objectTypeLabel',
        100,
        false
    )
];

const FULL_OBJECT_COLUMN = textColumn(
    'Object',
    'objectDisplay',
    220,
    true
);

const TRIMMED_OBJECT_COLUMN = textColumn(
    'Object API Name',
    'objectApiName',
    180,
    false
);

/*
 * Field Label doubles as the Lightning Setup navigation link.
 */
const FIELD_LABEL_COLUMN = {
    label: 'Field Label',
    fieldName: 'setupUrl',
    type: 'url',
    sortable: true,
    wrapText: true,
    initialWidth: 220,
    typeAttributes: {
        label: {
            fieldName: 'fieldLabel'
        },
        target: '_blank',
        tooltip: {
            fieldName: 'setupActionTitle'
        }
    }
};

const FIELD_API_NAME_COLUMN = textColumn(
    'Field API Name',
    'fieldApiName',
    210,
    false
);

const FIELD_TYPE_COLUMN = textColumn(
    'Type',
    'fieldType',
    120,
    false
);

const HISTORY_TRACKED_COLUMN = textColumn(
    'History Tracked',
    'fieldHistoryTrackingStatus',
    145,
    false
);

const RECORD_COUNT_COLUMN = numberColumn(
    'Records',
    'totalRecords',
    105,
    0
);

const POPULATED_COUNT_COLUMN = numberColumn(
    'Populated Records',
    'populatedRecords',
    145,
    0
);

const POPULATION_PERCENT_COLUMN = numberColumn(
    'Population %',
    'populationPercent',
    125,
    2
);

const USAGE_STATUS_COLUMN = textColumn(
    'Usage Status',
    'usageStatus',
    135,
    false
);

const HAS_DESCRIPTION_COLUMN = booleanColumn(
    'Has Description',
    'hasDescription',
    135
);

const DESCRIPTION_COLUMN = textColumn(
    'Description',
    'description',
    300,
    true
);

const HAS_HELP_TEXT_COLUMN = booleanColumn(
    'Has Help Text',
    'hasHelpText',
    120
);

const HELP_TEXT_COLUMN = textColumn(
    'Help Text',
    'helpText',
    300,
    true
);

const FIELD_USAGE_COLUMN = textColumn(
    'Field Usage',
    'fieldUsage',
    165,
    true
);

const DATA_SENSITIVITY_COLUMN = textColumn(
    'Data Sensitivity Level',
    'dataSensitivityLevel',
    190,
    true
);

const COMPLIANCE_COLUMN = textColumn(
    'Compliance Categorization',
    'complianceCategorization',
    220,
    true
);

const DOCUMENTATION_SCORE_COLUMN = numberColumn(
    'Documentation %',
    'documentationScore',
    145,
    0
);

const METADATA_AUDIT_COLUMN = textColumn(
    'Metadata Audit Status',
    'metadataAuditStatus',
    220,
    true
);

const TECHNICAL_TABLE_COLUMNS = [
    booleanColumn(
        'Population Eligible',
        'populationAnalysisApplicable',
        145
    ),
    booleanColumn(
        'Checkbox',
        'checkboxField',
        95
    ),
    textColumn(
        'Usage Method',
        'usageMethod',
        155,
        true
    ),
    booleanColumn(
        'Required',
        'required',
        95
    ),
    booleanColumn(
        'Custom',
        'customField',
        90
    ),
    booleanColumn(
        'Formula',
        'calculated',
        90
    ),
    textColumn(
        'Formula Expression',
        'calculatedFormula',
        300,
        true
    ),
    booleanColumn(
        'External ID',
        'externalId',
        105
    ),
    booleanColumn(
        'Unique',
        'uniqueField',
        90
    ),
    booleanColumn(
        'Createable',
        'createable',
        105
    ),
    booleanColumn(
        'Updateable',
        'updateable',
        105
    ),
    booleanColumn(
        'Filterable',
        'filterable',
        100
    ),
    booleanColumn(
        'Groupable',
        'groupable',
        100
    ),
    booleanColumn(
        'Sortable',
        'sortable',
        90
    ),
    numberColumn(
        'Length',
        'length',
        90,
        0
    ),
    numberColumn(
        'Precision',
        'precision',
        95,
        0
    ),
    numberColumn(
        'Scale',
        'scale',
        80,
        0
    ),
    textColumn(
        'Reference To',
        'referenceTo',
        180,
        true
    ),
    numberColumn(
        'Active Picklist Values',
        'activePicklistValueCount',
        165,
        0
    ),
    textColumn(
        'Note',
        'note',
        320,
        true
    )
];

const FULL_TABLE_BODY_COLUMNS = [
    FIELD_LABEL_COLUMN,
    FIELD_API_NAME_COLUMN,
    FIELD_TYPE_COLUMN,
    HISTORY_TRACKED_COLUMN,
    RECORD_COUNT_COLUMN,
    POPULATED_COUNT_COLUMN,
    POPULATION_PERCENT_COLUMN,
    USAGE_STATUS_COLUMN,
    HAS_DESCRIPTION_COLUMN,
    DESCRIPTION_COLUMN,
    HAS_HELP_TEXT_COLUMN,
    HELP_TEXT_COLUMN,
    FIELD_USAGE_COLUMN,
    DATA_SENSITIVITY_COLUMN,
    COMPLIANCE_COLUMN,
    DOCUMENTATION_SCORE_COLUMN,
    METADATA_AUDIT_COLUMN
].concat(TECHNICAL_TABLE_COLUMNS);

/*
 * Trimmed mode omits the Has Description and Has Help Text Boolean columns
 * and all technical columns after Metadata Audit Status.
 */
const TRIMMED_TABLE_BODY_COLUMNS = [
    FIELD_LABEL_COLUMN,
    FIELD_API_NAME_COLUMN,
    FIELD_TYPE_COLUMN,
    HISTORY_TRACKED_COLUMN,
    RECORD_COUNT_COLUMN,
    POPULATED_COUNT_COLUMN,
    POPULATION_PERCENT_COLUMN,
    USAGE_STATUS_COLUMN,
    DESCRIPTION_COLUMN,
    HELP_TEXT_COLUMN,
    FIELD_USAGE_COLUMN,
    DATA_SENSITIVITY_COLUMN,
    COMPLIANCE_COLUMN,
    DOCUMENTATION_SCORE_COLUMN,
    METADATA_AUDIT_COLUMN
];

const FULL_TABLE_COLUMNS_SINGLE_OBJECT =
    FULL_TABLE_BODY_COLUMNS.slice();

const FULL_TABLE_COLUMNS_VIEW_ALL = [
    FULL_OBJECT_COLUMN
].concat(FULL_TABLE_BODY_COLUMNS);

const TRIMMED_TABLE_COLUMNS_SINGLE_OBJECT =
    TRIMMED_TABLE_BODY_COLUMNS.slice();

const TRIMMED_TABLE_COLUMNS_VIEW_ALL = [
    TRIMMED_OBJECT_COLUMN
].concat(TRIMMED_TABLE_BODY_COLUMNS);

const FULL_EXPORT_COLUMNS = [
    ['Object Label', 'objectLabel'],
    ['Object API Name', 'objectApiName'],
    ['Field Label', 'fieldLabel'],
    ['Field API Name', 'fieldApiName'],
    ['Field Type', 'fieldType'],
    [
        'Field History Tracked',
        'fieldHistoryTrackingStatus'
    ],
    ['Total Records', 'totalRecords'],
    ['Populated Records', 'populatedRecords'],
    ['Population Percent', 'populationPercent'],
    [
        'Population Analysis Applicable',
        'populationAnalysisApplicable'
    ],
    ['Checkbox Field', 'checkboxField'],
    ['Usage Method', 'usageMethod'],
    ['Usage Status', 'usageStatus'],
    ['Has Description', 'hasDescription'],
    ['Description', 'description'],
    ['Has Help Text', 'hasHelpText'],
    ['Help Text', 'helpText'],
    ['Field Usage', 'fieldUsage'],
    [
        'Data Sensitivity Level',
        'dataSensitivityLevel'
    ],
    [
        'Compliance Categorization',
        'complianceCategorization'
    ],
    ['Documentation Score', 'documentationScore'],
    ['Metadata Audit Status', 'metadataAuditStatus'],
    ['Setup Field Identifier', 'setupFieldId'],
    [
        'History Tracking Audit Available',
        'historyTrackingAuditAvailable'
    ],
    [
        'Description Audit Available',
        'descriptionAuditAvailable'
    ],
    ['Custom Field', 'customField'],
    ['Required', 'required'],
    ['Nillable', 'nillable'],
    ['Calculated', 'calculated'],
    ['Calculated Formula', 'calculatedFormula'],
    ['Auto Number', 'autoNumber'],
    ['External ID', 'externalId'],
    ['Unique', 'uniqueField'],
    ['Defaulted On Create', 'defaultedOnCreate'],
    ['Createable', 'createable'],
    ['Updateable', 'updateable'],
    ['Filterable', 'filterable'],
    ['Groupable', 'groupable'],
    ['Sortable', 'sortable'],
    ['Aggregatable', 'aggregatable'],
    ['Length', 'length'],
    ['Precision', 'precision'],
    ['Scale', 'scale'],
    ['Relationship Name', 'relationshipName'],
    ['Reference To', 'referenceTo'],
    [
        'Active Picklist Values',
        'activePicklistValueCount'
    ],
    [
        'Total Picklist Values',
        'totalPicklistValueCount'
    ],
    ['Restricted Picklist', 'restrictedPicklist'],
    ['Dependent Picklist', 'dependentPicklist'],
    ['Note', 'note']
];

const TRIMMED_EXPORT_COLUMNS = [
    ['Object API Name', 'objectApiName'],
    ['Field Label', 'fieldLabel'],
    ['Field API Name', 'fieldApiName'],
    ['Field Type', 'fieldType'],
    [
        'Field History Tracked',
        'fieldHistoryTrackingStatus'
    ],
    ['Total Records', 'totalRecords'],
    ['Populated Records', 'populatedRecords'],
    ['Population Percent', 'populationPercent'],
    ['Usage Status', 'usageStatus'],
    ['Description', 'description'],
    ['Help Text', 'helpText'],
    ['Field Usage', 'fieldUsage'],
    [
        'Data Sensitivity Level',
        'dataSensitivityLevel'
    ],
    [
        'Compliance Categorization',
        'complianceCategorization'
    ],
    ['Documentation Score', 'documentationScore'],
    ['Metadata Audit Status', 'metadataAuditStatus']
];

export default class DataDictionaryAudit extends LightningElement {
    _configurationJson = '{}';
    _showRuntimeConfigurationEditor = true;

    hasConnected = false;
    bootstrapRequestVersion = 0;
    shouldScrollResultsToTop = false;
    activeDownloadUrl;

    /*
     * Runtime JSON editor state.
     */
    runtimeConfigurationJson = null;
    configurationDraft = '{}';
    configurationEditorOpen = false;
    configurationError = '';
    configurationNotice = '';

    /*
     * Initial object inventory state.
     */
    initialLoadMessage =
        'Reading readable Salesforce object metadata and preparing the selector.';

    isLoadingObjects = false;

    /*
     * Object selection state.
     */
    objectSelectionColumns = OBJECT_SELECTION_COLUMNS;
    objectTypeOptions = OBJECT_TYPE_OPTIONS;
    objectRows = [];
    visibleObjectRows = [];
    selectedObjectApiNames = [];
    objectSearchTerm = '';
    objectTypeFilter = 'all';
    objectSortBy = 'objectLabel';
    objectSortDirection = 'asc';

    /*
     * Audit result state.
     */
    rowsByObjectApiName = {};
    auditedObjects = [];

    resultObjectFilterOptions = [
        {
            label: 'View All',
            value: VIEW_ALL_OBJECTS
        }
    ];

    selectedResultObjectApiName =
        VIEW_ALL_OBJECTS;

    resultObjectFilterManuallyChanged = false;
    filteredRows = [];
    displayedRows = [];

    /*
     * Result display state.
     */
    rowBatchOptions = ROW_BATCH_OPTIONS;
    rowBatchSize = DEFAULT_ROW_BATCH_SIZE;
    currentPage = 1;
    infiniteLoadedRowCount = 0;
    useInfiniteScroll = false;
    isLoadingMoreRows = false;
    resultSortBy = 'setupUrl';
    resultSortDirection = 'asc';
    searchTerm = '';
    showMetadataIssuesOnly = false;
    showUsageIssuesOnly = false;
    trimColumns = false;

    /*
     * Rollups and audit execution.
     */
    summaryByObjectApiName = {};
    summaryMetrics = createEmptySummary();
    bootstrapWarnings = [];
    auditWarnings = [];
    auditErrors = [];
    lowUsageThresholdPercent = 5;
    isRunning = false;
    cancelRequested = false;
    progressCurrent = 0;
    progressTotal = 0;
    currentObjectLabel = '';

    @api
    get configurationJson() {
        return this._configurationJson;
    }

    set configurationJson(value) {
        this._configurationJson =
            this.normalizeConfigurationText(
                value
            );

        if (!this.hasRuntimeConfigurationOverride) {
            this.configurationDraft =
                this.prettyPrintConfigurationText(
                    this._configurationJson
                );
        }

        if (
            this.hasConnected &&
            !this.hasRuntimeConfigurationOverride
        ) {
            this.loadBootstrap({
                resetResults: true
            });
        }
    }

    @api
    get showRuntimeConfigurationEditor() {
        return this._showRuntimeConfigurationEditor;
    }

    set showRuntimeConfigurationEditor(value) {
        this._showRuntimeConfigurationEditor =
            value !== false &&
            value !== 'false';
    }

    connectedCallback() {
        this.hasConnected = true;

        this.configurationDraft =
            this.prettyPrintConfigurationText(
                this.effectiveConfigurationJson
            );

        this.loadBootstrap({
            resetResults: true
        });
    }

    disconnectedCallback() {
        this.bootstrapRequestVersion += 1;

        if (this.activeDownloadUrl) {
            URL.revokeObjectURL(
                this.activeDownloadUrl
            );

            this.activeDownloadUrl =
                undefined;
        }
    }

    renderedCallback() {
        if (!this.shouldScrollResultsToTop) {
            return;
        }

        const datatable =
            this.refs
                ? this.refs.resultsTable
                : null;

        if (
            datatable &&
            typeof datatable.scrollToTop ===
                'function'
        ) {
            datatable.scrollToTop();
        }

        this.shouldScrollResultsToTop =
            false;
    }

    get hasRuntimeConfigurationOverride() {
        return this.runtimeConfigurationJson !==
            null;
    }

    get effectiveConfigurationJson() {
        const source =
            this.hasRuntimeConfigurationOverride
                ? this.runtimeConfigurationJson
                : this._configurationJson;

        return this.normalizeConfigurationText(
            source
        );
    }

    get configurationSourceLabel() {
        return this.hasRuntimeConfigurationOverride
            ? 'Runtime JSON active'
            : 'Component configuration';
    }

    get configurationSourceDetail() {
        if (this.hasRuntimeConfigurationOverride) {
            return (
                'This browser session is using the JSON below. ' +
                'Reset restores the component configuration.'
            );
        }

        if (this._configurationJson === '{}') {
            return (
                'Using the default configuration. Paste JSON to preselect ' +
                'objects and adjust the audit threshold.'
            );
        }

        return (
            'Using the JSON configured in Lightning App Builder. ' +
            'A runtime override changes only the current browser session.'
        );
    }

    get configurationToggleLabel() {
        return this.configurationEditorOpen
            ? 'Hide JSON Editor'
            : 'Edit JSON';
    }

    get configurationControlsDisabled() {
        return (
            this.isLoadingObjects ||
            this.isRunning
        );
    }

    get configurationApplyDisabled() {
        return (
            this.configurationControlsDisabled ||
            !this.configurationDraft.trim()
        );
    }

    get configurationResetDisabled() {
        return (
            this.configurationControlsDisabled ||
            !this.hasRuntimeConfigurationOverride
        );
    }

    get hasConfigurationError() {
        return this.configurationError.length >
            0;
    }

    get hasConfigurationNotice() {
        return this.configurationNotice.length >
            0;
    }

    get configurationCharacterCountText() {
        return (
            this.configurationDraft.length.toLocaleString() +
            ' of ' +
            MAX_CONFIGURATION_LENGTH.toLocaleString() +
            ' characters'
        );
    }

    get initialLoadDetail() {
        return (
            'This request reads schema metadata, not business records. ' +
            'Orgs with many managed packages, custom objects, or fields ' +
            'can take longer.'
        );
    }

    get visibleSelectedObjectApiNames() {
        const visibleKeys =
            new Set(
                this.visibleObjectRows.map(
                    (row) =>
                        row.value
                )
            );

        return this.selectedObjectApiNames.filter(
            (apiName) =>
                visibleKeys.has(
                    apiName
                )
        );
    }

    get disabledObjectRows() {
        return this.isRunning
            ? this.visibleObjectRows.map(
                (row) =>
                    row.value
            )
            : [];
    }

    get selectedObjectCountText() {
        return (
            this.selectedObjectApiNames.length +
            ' of ' +
            this.objectRows.length +
            ' objects selected'
        );
    }

    get visibleObjectCountText() {
        return (
            this.visibleObjectRows.length +
            ' of ' +
            this.objectRows.length +
            ' objects shown'
        );
    }

    get selectAllMatchingDisabled() {
        if (
            this.isRunning ||
            !this.visibleObjectRows.length
        ) {
            return true;
        }

        const selected =
            new Set(
                this.selectedObjectApiNames
            );

        return this.visibleObjectRows.every(
            (row) =>
                selected.has(
                    row.value
                )
        );
    }

    get clearMatchingDisabled() {
        if (
            this.isRunning ||
            !this.visibleObjectRows.length
        ) {
            return true;
        }

        const selected =
            new Set(
                this.selectedObjectApiNames
            );

        return !this.visibleObjectRows.some(
            (row) =>
                selected.has(
                    row.value
                )
        );
    }

    get clearAllSelectionDisabled() {
        return (
            this.isRunning ||
            !this.selectedObjectApiNames.length
        );
    }

    get auditedObjectCount() {
        return this.auditedObjects.length;
    }

    get singleVisibleObjectApiName() {
        if (
            this.selectedResultObjectApiName !==
            VIEW_ALL_OBJECTS
        ) {
            return this.selectedResultObjectApiName;
        }

        return this.auditedObjectCount === 1
            ? this.auditedObjects[0]
                .objectApiName
            : null;
    }

    get showObjectColumn() {
        return !this.singleVisibleObjectApiName;
    }

    get columns() {
        if (this.trimColumns) {
            return this.showObjectColumn
                ? TRIMMED_TABLE_COLUMNS_VIEW_ALL
                : TRIMMED_TABLE_COLUMNS_SINGLE_OBJECT;
        }

        return this.showObjectColumn
            ? FULL_TABLE_COLUMNS_VIEW_ALL
            : FULL_TABLE_COLUMNS_SINGLE_OBJECT;
    }

    get fieldDictionaryTitle() {
        const objectApiName =
            this.singleVisibleObjectApiName;

        if (!objectApiName) {
            return 'Field Dictionary - View All';
        }

        const objectResult =
            this.auditedObjects.find(
                (item) =>
                    item.objectApiName ===
                    objectApiName
            );

        return objectResult
            ? (
                'Field Dictionary - ' +
                objectResult.displayLabel
            )
            : (
                'Field Dictionary - ' +
                objectApiName
            );
    }

    get scopedFieldCount() {
        if (
            this.selectedResultObjectApiName ===
            VIEW_ALL_OBJECTS
        ) {
            return this.summaryMetrics.fieldCount;
        }

        const summary =
            this.summaryByObjectApiName[
                this.selectedResultObjectApiName
            ];

        return summary
            ? summary.fieldCount
            : 0;
    }

    get rowBatchSizeValue() {
        return String(
            this.rowBatchSize
        );
    }

    get rowBatchControlLabel() {
        return this.useInfiniteScroll
            ? 'Load batch size'
            : 'Rows per page';
    }

    get isPaginationMode() {
        return !this.useInfiniteScroll;
    }

    get isInfiniteScrollMode() {
        return this.useInfiniteScroll;
    }

    get totalPages() {
        return Math.max(
            1,
            Math.ceil(
                this.filteredRows.length /
                this.rowBatchSize
            )
        );
    }

    get previousPageDisabled() {
        return (
            this.currentPage <= 1 ||
            !this.filteredRows.length
        );
    }

    get nextPageDisabled() {
        return (
            this.currentPage >=
                this.totalPages ||
            !this.filteredRows.length
        );
    }

    get firstPageDisabled() {
        return this.previousPageDisabled;
    }

    get lastPageDisabled() {
        return this.nextPageDisabled;
    }

    get pageLabel() {
        return (
            'Page ' +
            this.currentPage +
            ' of ' +
            this.totalPages
        );
    }

    get rowNumberOffset() {
        return this.useInfiniteScroll
            ? 0
            : (
                this.currentPage -
                1
            ) *
            this.rowBatchSize;
    }

    get infiniteLoadingEnabled() {
        return (
            this.useInfiniteScroll &&
            this.displayedRows.length <
                this.filteredRows.length
        );
    }

    get infiniteScrollStatusText() {
        return (
            this.displayedRows.length +
            ' of ' +
            this.filteredRows.length +
            ' matching rows loaded'
        );
    }

    get resultCountText() {
        if (!this.filteredRows.length) {
            return (
                '0 matching fields; ' +
                this.scopedFieldCount +
                ' fields in scope'
            );
        }

        if (this.useInfiniteScroll) {
            return (
                this.displayedRows.length +
                ' of ' +
                this.filteredRows.length +
                ' matching fields loaded; ' +
                this.scopedFieldCount +
                ' fields in scope'
            );
        }

        const start =
            (
                this.currentPage -
                1
            ) *
            this.rowBatchSize +
            1;

        const end =
            Math.min(
                start +
                this.displayedRows.length -
                1,
                this.filteredRows.length
            );

        return (
            start +
            '-' +
            end +
            ' of ' +
            this.filteredRows.length +
            ' matching fields; ' +
            this.scopedFieldCount +
            ' fields in scope'
        );
    }

    get runDisabled() {
        return (
            this.isRunning ||
            !this.selectedObjectApiNames.length
        );
    }

    get clearResultsDisabled() {
        return (
            this.isRunning ||
            !this.summaryMetrics.fieldCount
        );
    }

    get exportDisabled() {
        return (
            this.isRunning ||
            !this.filteredRows.length
        );
    }

    get cancelDisabled() {
        return (
            !this.isRunning ||
            this.cancelRequested
        );
    }

    get exportButtonLabel() {
        return this.trimColumns
            ? 'Export Trimmed CSV'
            : 'Export Full CSV';
    }

    get hasRows() {
        return this.summaryMetrics.fieldCount >
            0;
    }

    get hasDisplayedRows() {
        return this.displayedRows.length >
            0;
    }

    get hasBootstrapWarnings() {
        return this.bootstrapWarnings.length >
            0;
    }

    get hasAuditWarnings() {
        return this.auditWarnings.length >
            0;
    }

    get hasAuditErrors() {
        return this.auditErrors.length >
            0;
    }

    get progressPercent() {
        return this.progressTotal
            ? Math.round(
                (
                    this.progressCurrent /
                    this.progressTotal
                ) *
                100
            )
            : 0;
    }

    get progressText() {
        if (this.cancelRequested) {
            return (
                'Stopping after the current object completes'
            );
        }

        return this.progressTotal
            ? (
                this.progressCurrent +
                ' of ' +
                this.progressTotal +
                ' objects completed'
            )
            : '';
    }

    /**
     * Groups rollups into scope, documentation, governance,
     * technical metadata, and population analysis.
     *
     * Every tile includes helpText for the standard Salesforce
     * lightning-helptext icon rendered by the HTML template.
     */
    get summaryGroups() {
        const summary =
            this.summaryMetrics;

        const fields =
            summary.fieldCount;

        const eligible =
            summary.populationEligibleFields;

        return [
            {
                key: 'scope',
                title: 'Scope',
                iconName: 'utility:summary',
                tiles: [
                    {
                        key: 'objects',
                        value: summary.objectCount,
                        label: 'Objects Audited',
                        detail:
                            fields +
                            ' fields analyzed',
                        helpText:
                            ROLLUP_HELP_TEXT.objects
                    },
                    {
                        key: 'fields',
                        value: fields,
                        label: 'Fields Audited',
                        detail:
                            summary.objectCount +
                            ' objects analyzed',
                        helpText:
                            ROLLUP_HELP_TEXT.fields
                    },
                    this.metricTile(
                        'population-eligible',
                        'Population Eligible',
                        eligible,
                        fields
                    ),
                    {
                        key: 'checkbox-fields',
                        value: summary.checkboxFields,
                        label: 'Checkbox Fields',
                        detail:
                            'Metadata only; value analysis excluded',
                        helpText:
                            ROLLUP_HELP_TEXT[
                                'checkbox-fields'
                            ]
                    },
                    this.metricTile(
                        'other-not-applicable',
                        'Other Not Applicable',
                        summary.otherNotApplicableFields,
                        fields
                    )
                ]
            },
            {
                key: 'documentation',
                title: 'Documentation',
                iconName: 'utility:knowledge_base',
                tiles: [
                    this.metricTile(
                        'documented',
                        'Fully Documented',
                        summary.documented,
                        summary.documentationEvaluated,
                        'evaluated fields',
                        'Documentation metadata unavailable'
                    ),
                    this.metricTile(
                        'missing-description',
                        'Missing Description',
                        summary.missingDescription,
                        summary.descriptionEvaluated,
                        'evaluated fields',
                        'Description metadata unavailable'
                    ),
                    this.metricTile(
                        'missing-help',
                        'Missing Help Text',
                        summary.missingHelpText,
                        fields
                    )
                ]
            },
            {
                key: 'governance',
                title: 'Governance',
                iconName: 'utility:shield',
                tiles: [
                    this.metricTile(
                        'history-tracked',
                        'History Tracked',
                        summary.historyTracked,
                        summary.historyEvaluated,
                        'evaluated fields',
                        'History metadata unavailable'
                    ),
                    this.metricTile(
                        'field-usage-set',
                        'Field Usage Set',
                        summary.fieldUsageSet,
                        summary.fieldUsageEvaluated,
                        'evaluated fields',
                        'Field Usage metadata unavailable'
                    ),
                    this.metricTile(
                        'sensitivity-set',
                        'Sensitivity Set',
                        summary.sensitivitySet,
                        summary.sensitivityEvaluated,
                        'evaluated fields',
                        'Sensitivity metadata unavailable'
                    ),
                    this.metricTile(
                        'compliance-set',
                        'Compliance Set',
                        summary.complianceSet,
                        summary.complianceEvaluated,
                        'evaluated fields',
                        'Compliance metadata unavailable'
                    ),
                    this.metricTile(
                        'governance-complete',
                        'Governance Complete',
                        summary.governanceComplete,
                        summary.governanceEvaluated,
                        'evaluated fields',
                        'Governance metadata unavailable'
                    )
                ]
            },
            {
                key: 'technical',
                title: 'Technical Metadata',
                iconName: 'utility:settings',
                tiles: [
                    this.metricTile(
                        'custom',
                        'Custom Fields',
                        summary.customFields,
                        fields
                    ),
                    this.metricTile(
                        'required',
                        'Required Fields',
                        summary.requiredFields,
                        fields
                    ),
                    this.metricTile(
                        'formula',
                        'Formula Fields',
                        summary.formulaFields,
                        fields
                    ),
                    this.metricTile(
                        'external',
                        'External IDs',
                        summary.externalIdFields,
                        fields
                    ),
                    this.metricTile(
                        'unique',
                        'Unique Fields',
                        summary.uniqueFields,
                        fields
                    ),
                    this.metricTile(
                        'picklist',
                        'Picklist Fields',
                        summary.picklistFields,
                        fields
                    ),
                    this.metricTile(
                        'relationship',
                        'Relationship Fields',
                        summary.relationshipFields,
                        fields
                    )
                ]
            },
            {
                key: 'population',
                title: 'Population Analysis',
                iconName: 'utility:chart',
                tiles: [
                    this.metricTile(
                        'no-data',
                        'No Data',
                        summary.noData,
                        eligible
                    ),
                    this.metricTile(
                        'low-usage',
                        (
                            'Below ' +
                            this.lowUsageThresholdPercent +
                            '% Usage'
                        ),
                        summary.lowUsage,
                        eligible
                    ),
                    this.metricTile(
                        'not-evaluated',
                        'Not Evaluated',
                        summary.notEvaluated,
                        eligible
                    )
                ]
            }
        ];
    }

    /**
     * Creates one consistently formatted rollup tile.
     *
     * The help text is resolved by tile key so all descriptions
     * are maintained in one constant near the top of the file.
     */
    metricTile(
        key,
        label,
        value,
        denominator,
        denominatorLabel,
        emptyText
    ) {
        return {
            key,
            label,
            value,
            detail:
                this.metricDetail(
                    value,
                    denominator,
                    denominatorLabel ||
                        'fields',
                    emptyText ||
                        'No applicable fields'
                ),
            helpText:
                ROLLUP_HELP_TEXT[key] ||
                'Displays the number of audited fields matching this category.'
        };
    }

    /**
     * Formats a metric as a percentage of its relevant denominator.
     */
    metricDetail(
        value,
        denominator,
        denominatorLabel,
        emptyText
    ) {
        if (!denominator) {
            return emptyText;
        }

        const percentage =
            Math.round(
                (
                    value /
                    denominator
                ) *
                1000
            ) /
            10;

        const label =
            denominator === 1
                ? denominatorLabel.replace(
                    /fields$/,
                    'field'
                )
                : denominatorLabel;

        return (
            percentage +
            '% of ' +
            denominator +
            ' ' +
            label
        );
    }

    /* ------------------------------------------------------------------ */
    /* Runtime JSON editor                                                 */
    /* ------------------------------------------------------------------ */

    normalizeConfigurationText(value) {
        const normalized =
            String(
                value === null ||
                value === undefined
                    ? ''
                    : value
            ).trim();

        return normalized || '{}';
    }

    prettyPrintConfigurationText(value) {
        const normalized =
            this.normalizeConfigurationText(
                value
            );

        try {
            return JSON.stringify(
                JSON.parse(
                    normalized
                ),
                null,
                2
            );
        } catch (error) {
            return normalized;
        }
    }

    parseAndValidateConfiguration(value) {
        const normalized =
            this.normalizeConfigurationText(
                value
            );

        if (
            normalized.length >
            MAX_CONFIGURATION_LENGTH
        ) {
            throw new Error(
                'Configuration JSON cannot exceed ' +
                MAX_CONFIGURATION_LENGTH.toLocaleString() +
                ' characters.'
            );
        }

        let parsed;

        try {
            parsed =
                JSON.parse(
                    normalized
                );
        } catch (error) {
            throw new Error(
                'Invalid JSON: ' +
                error.message
            );
        }

        if (
            parsed === null ||
            Array.isArray(parsed) ||
            typeof parsed !==
                'object'
        ) {
            throw new Error(
                'Configuration JSON must be a JSON object.'
            );
        }

        if (
            Object.prototype.hasOwnProperty.call(
                parsed,
                'objectApiNames'
            )
        ) {
            if (
                !Array.isArray(
                    parsed.objectApiNames
                )
            ) {
                throw new Error(
                    'objectApiNames must be an array of object API-name strings.'
                );
            }

            if (
                parsed.objectApiNames.some(
                    (name) =>
                        typeof name !==
                        'string'
                )
            ) {
                throw new Error(
                    'objectApiNames must contain only strings.'
                );
            }
        }

        [
            'includeStandardObjects',
            'includeCustomObjects',
            'includeSystemObjects'
        ].forEach(
            (key) => {
                if (
                    Object.prototype.hasOwnProperty.call(
                        parsed,
                        key
                    ) &&
                    typeof parsed[key] !==
                        'boolean'
                ) {
                    throw new Error(
                        key +
                        ' must be true or false.'
                    );
                }
            }
        );

        if (
            Object.prototype.hasOwnProperty.call(
                parsed,
                'lowUsageThresholdPercent'
            ) &&
            (
                typeof parsed.lowUsageThresholdPercent !==
                    'number' ||
                !Number.isFinite(
                    parsed.lowUsageThresholdPercent
                )
            )
        ) {
            throw new Error(
                'lowUsageThresholdPercent must be a finite number.'
            );
        }

        return parsed;
    }

    handleToggleConfigurationEditor() {
        this.configurationEditorOpen =
            !this.configurationEditorOpen;

        this.configurationError =
            '';
    }

    handleConfigurationDraftChange(event) {
        const detail =
            event.detail ||
            {};

        const value =
            detail.value !==
                undefined
                ? detail.value
                : event.target.value;

        this.configurationDraft =
            value ||
            '';

        this.configurationError =
            '';

        this.configurationNotice =
            '';
    }

    handleConfigurationTemplate(event) {
        const detail =
            event.detail ||
            {};

        const template =
            CONFIGURATION_TEMPLATES[
                detail.value
            ];

        if (!template) {
            return;
        }

        this.configurationDraft =
            JSON.stringify(
                template,
                null,
                2
            );

        this.configurationEditorOpen =
            true;

        this.configurationError =
            '';

        this.configurationNotice =
            'Template loaded. Review the object list, then select Apply Configuration.';
    }

    handleFormatConfiguration() {
        try {
            const parsed =
                this.parseAndValidateConfiguration(
                    this.configurationDraft
                );

            this.configurationDraft =
                JSON.stringify(
                    parsed,
                    null,
                    2
                );

            this.configurationError =
                '';

            this.configurationNotice =
                'JSON is valid and has been formatted.';
        } catch (error) {
            this.configurationError =
                error.message;

            this.configurationNotice =
                '';

            this.configurationEditorOpen =
                true;
        }
    }

    async handleApplyConfiguration() {
        try {
            const parsed =
                this.parseAndValidateConfiguration(
                    this.configurationDraft
                );

            this.configurationDraft =
                JSON.stringify(
                    parsed,
                    null,
                    2
                );

            this.runtimeConfigurationJson =
                JSON.stringify(
                    parsed
                );

            this.configurationError =
                '';

            this.configurationNotice =
                '';

            this.configurationEditorOpen =
                false;

            await this.loadBootstrap({
                resetResults: true,
                configurationAction:
                    'apply'
            });
        } catch (error) {
            this.configurationError =
                error.message;

            this.configurationNotice =
                '';

            this.configurationEditorOpen =
                true;
        }
    }

    async handleResetConfiguration() {
        this.runtimeConfigurationJson =
            null;

        this.configurationDraft =
            this.prettyPrintConfigurationText(
                this._configurationJson
            );

        this.configurationError =
            '';

        this.configurationNotice =
            '';

        this.configurationEditorOpen =
            false;

        await this.loadBootstrap({
            resetResults: true,
            configurationAction:
                'reset'
        });
    }

    /* ------------------------------------------------------------------ */
    /* Bootstrap and object selection                                      */
    /* ------------------------------------------------------------------ */

    async loadBootstrap(options) {
        const settings =
            options ||
            {};

        const resetResults =
            settings.resetResults ===
            true;

        const configurationAction =
            settings.configurationAction ||
            null;

        const requestVersion =
            ++this.bootstrapRequestVersion;

        this.isLoadingObjects =
            true;

        if (
            configurationAction ===
            'apply'
        ) {
            this.initialLoadMessage =
                'Applying the runtime JSON and rebuilding the readable object inventory.';
        } else if (
            configurationAction ===
            'reset'
        ) {
            this.initialLoadMessage =
                'Restoring the component configuration and rebuilding the readable object inventory.';
        } else {
            this.initialLoadMessage =
                'Reading readable Salesforce object metadata and preparing the selector.';
        }

        try {
            const response =
                await getBootstrap({
                    configurationJson:
                        this.effectiveConfigurationJson
                });

            if (
                requestVersion !==
                this.bootstrapRequestVersion
            ) {
                return;
            }

            if (resetResults) {
                this.resetAuditResults();
            }

            this.objectRows =
                (
                    response.objects ||
                    []
                ).map(
                    (option) =>
                        Object.assign(
                            {},
                            option,
                            {
                                objectLabel:
                                    option.objectLabel ||
                                    this.extractObjectLabel(
                                        option
                                    ),
                                objectTypeLabel:
                                    option.objectTypeLabel ||
                                    (
                                        option.customObject
                                            ? 'Custom'
                                            : 'Standard'
                                    )
                            }
                        )
                );

            this.selectedObjectApiNames =
                response.selectedObjectApiNames ||
                [];

            this.lowUsageThresholdPercent =
                response.lowUsageThresholdPercent ===
                    null ||
                response.lowUsageThresholdPercent ===
                    undefined
                    ? 5
                    : response.lowUsageThresholdPercent;

            this.bootstrapWarnings =
                response.warnings ||
                [];

            this.applyObjectFilters();

            if (
                configurationAction ===
                'apply'
            ) {
                this.configurationNotice =
                    'Runtime configuration applied. ' +
                    this.objectRows.length +
                    ' eligible objects are available.';
            } else if (
                configurationAction ===
                'reset'
            ) {
                this.configurationNotice =
                    'Component configuration restored. ' +
                    this.objectRows.length +
                    ' eligible objects are available.';
            }
        } catch (error) {
            if (
                requestVersion !==
                this.bootstrapRequestVersion
            ) {
                return;
            }

            if (configurationAction) {
                this.configurationError =
                    this.reduceError(
                        error
                    );

                this.configurationNotice =
                    '';

                this.configurationEditorOpen =
                    true;
            }

            this.showErrorToast(
                'Unable to load objects',
                error
            );
        } finally {
            if (
                requestVersion ===
                this.bootstrapRequestVersion
            ) {
                this.isLoadingObjects =
                    false;
            }
        }
    }

    extractObjectLabel(option) {
        const label =
            String(
                option.label ||
                option.value ||
                ''
            );

        const suffix =
            ' (' +
            (
                option.value ||
                ''
            ) +
            ')';

        return label.endsWith(
            suffix
        )
            ? label.slice(
                0,
                -suffix.length
            )
            : label;
    }

    handleObjectRowSelection(event) {
        const visibleKeys =
            new Set(
                this.visibleObjectRows.map(
                    (row) =>
                        row.value
                )
            );

        const nextSelection =
            new Set(
                this.selectedObjectApiNames.filter(
                    (apiName) =>
                        !visibleKeys.has(
                            apiName
                        )
                )
            );

        const selectedRows =
            event.detail &&
            event.detail.selectedRows
                ? event.detail.selectedRows
                : [];

        selectedRows.forEach(
            (row) => {
                nextSelection.add(
                    row.value
                );
            }
        );

        this.selectedObjectApiNames =
            this.objectRows
                .filter(
                    (row) =>
                        nextSelection.has(
                            row.value
                        )
                )
                .map(
                    (row) =>
                        row.value
                );

        if (
            this.objectTypeFilter ===
            'selected'
        ) {
            this.applyObjectFilters();
        }
    }

    handleObjectSearch(event) {
        this.objectSearchTerm =
            event.target.value ||
            '';

        this.applyObjectFilters();
    }

    handleObjectTypeFilter(event) {
        this.objectTypeFilter =
            event.detail.value;

        this.applyObjectFilters();
    }

    handleObjectSort(event) {
        const detail =
            event.detail ||
            {};

        const fieldName =
            detail.fieldName;

        const sortDirection =
            detail.sortDirection;

        if (
            !fieldName ||
            [
                'asc',
                'desc'
            ].indexOf(
                sortDirection
            ) ===
                -1
        ) {
            return;
        }

        this.objectSortBy =
            fieldName;

        this.objectSortDirection =
            sortDirection;

        this.applyObjectFilters();
    }

    handleSelectAllMatchingObjects() {
        const selected =
            new Set(
                this.selectedObjectApiNames
            );

        this.visibleObjectRows.forEach(
            (row) => {
                selected.add(
                    row.value
                );
            }
        );

        this.selectedObjectApiNames =
            this.objectRows
                .filter(
                    (row) =>
                        selected.has(
                            row.value
                        )
                )
                .map(
                    (row) =>
                        row.value
                );

        if (
            this.objectTypeFilter ===
            'selected'
        ) {
            this.applyObjectFilters();
        }
    }

    handleClearMatchingObjects() {
        const visible =
            new Set(
                this.visibleObjectRows.map(
                    (row) =>
                        row.value
                )
            );

        this.selectedObjectApiNames =
            this.selectedObjectApiNames.filter(
                (apiName) =>
                    !visible.has(
                        apiName
                    )
            );

        if (
            this.objectTypeFilter ===
            'selected'
        ) {
            this.applyObjectFilters();
        }
    }

    handleClearAllObjectSelection() {
        this.selectedObjectApiNames =
            [];

        if (
            this.objectTypeFilter ===
            'selected'
        ) {
            this.applyObjectFilters();
        }
    }

    applyObjectFilters() {
        const search =
            this.objectSearchTerm
                .trim()
                .toLowerCase();

        const selected =
            new Set(
                this.selectedObjectApiNames
            );

        const rows =
            this.objectRows.filter(
                (row) => {
                    const matchesSearch =
                        !search ||
                        [
                            row.objectLabel,
                            row.value,
                            row.objectTypeLabel
                        ]
                            .join(' ')
                            .toLowerCase()
                            .includes(
                                search
                            );

                    if (!matchesSearch) {
                        return false;
                    }

                    if (
                        this.objectTypeFilter ===
                        'custom'
                    ) {
                        return row.customObject ===
                            true;
                    }

                    if (
                        this.objectTypeFilter ===
                        'standard'
                    ) {
                        return row.customObject !==
                            true;
                    }

                    if (
                        this.objectTypeFilter ===
                        'selected'
                    ) {
                        return selected.has(
                            row.value
                        );
                    }

                    return true;
                }
            );

        this.visibleObjectRows =
            this.sortRowsByField(
                rows,
                this.objectSortBy,
                this.objectSortDirection,
                OBJECT_SORT_TYPES
            );
    }

    /* ------------------------------------------------------------------ */
    /* Result filtering, sorting, and windowing                            */
    /* ------------------------------------------------------------------ */

    handleCancelRun() {
        this.cancelRequested =
            true;
    }

    handleResultObjectFilter(event) {
        const detail =
            event.detail ||
            {};

        const selectedValue =
            detail.value ||
            event.target.value ||
            VIEW_ALL_OBJECTS;

        const valid =
            new Set(
                this.resultObjectFilterOptions.map(
                    (option) =>
                        option.value
                )
            );

        this.selectedResultObjectApiName =
            valid.has(
                selectedValue
            )
                ? selectedValue
                : VIEW_ALL_OBJECTS;

        this.resultObjectFilterManuallyChanged =
            true;

        this.ensureVisibleResultSortField();

        this.applyResultFilters({
            resetWindow: true
        });
    }

    handleFieldSearch(event) {
        this.searchTerm =
            event.target.value ||
            '';

        this.applyResultFilters({
            resetWindow: true
        });
    }

    handleMetadataIssuesToggle(event) {
        this.showMetadataIssuesOnly =
            event.target.checked;

        this.applyResultFilters({
            resetWindow: true
        });
    }

    handleUsageIssuesToggle(event) {
        this.showUsageIssuesOnly =
            event.target.checked;

        this.applyResultFilters({
            resetWindow: true
        });
    }

    handleTrimColumnsToggle(event) {
        this.trimColumns =
            event.target.checked;

        this.ensureVisibleResultSortField();

        this.applyResultFilters({
            resetWindow: true
        });
    }

    handleInfiniteScrollToggle(event) {
        this.useInfiniteScroll =
            event.target.checked;

        this.refreshDisplayedRows({
            resetWindow: true
        });
    }

    handleResultSort(event) {
        const detail =
            event.detail ||
            {};

        const fieldName =
            detail.fieldName;

        const sortDirection =
            detail.sortDirection;

        if (
            !fieldName ||
            [
                'asc',
                'desc'
            ].indexOf(
                sortDirection
            ) ===
                -1
        ) {
            return;
        }

        this.resultSortBy =
            fieldName;

        this.resultSortDirection =
            sortDirection;

        this.applyResultFilters({
            resetWindow: true
        });
    }

    handleRowBatchSizeChange(event) {
        const parsed =
            Number.parseInt(
                event.detail.value,
                10
            );

        this.rowBatchSize =
            Number.isFinite(
                parsed
            ) &&
            parsed >
                0
                ? parsed
                : DEFAULT_ROW_BATCH_SIZE;

        this.refreshDisplayedRows({
            resetWindow: true
        });
    }

    handleFirstPage() {
        if (this.currentPage !== 1) {
            this.currentPage =
                1;

            this.updatePaginatedRows();
        }
    }

    handlePreviousPage() {
        if (this.currentPage > 1) {
            this.currentPage -=
                1;

            this.updatePaginatedRows();
        }
    }

    handleNextPage() {
        if (
            this.currentPage <
            this.totalPages
        ) {
            this.currentPage +=
                1;

            this.updatePaginatedRows();
        }
    }

    handleLastPage() {
        if (
            this.currentPage !==
            this.totalPages
        ) {
            this.currentPage =
                this.totalPages;

            this.updatePaginatedRows();
        }
    }

    handleLoadMore(event) {
        const datatable =
            event.target;

        if (
            !this.infiniteLoadingEnabled ||
            this.isLoadingMoreRows
        ) {
            datatable.isLoading =
                false;

            return;
        }

        this.isLoadingMoreRows =
            true;

        datatable.isLoading =
            true;

        this.infiniteLoadedRowCount =
            Math.min(
                this.infiniteLoadedRowCount +
                    this.rowBatchSize,
                this.filteredRows.length
            );

        this.displayedRows =
            this.filteredRows.slice(
                0,
                this.infiniteLoadedRowCount
            );

        this.isLoadingMoreRows =
            false;

        datatable.isLoading =
            false;
    }

    ensureVisibleResultSortField() {
        const visible =
            new Set(
                this.columns
                    .map(
                        (column) =>
                            column.fieldName
                    )
                    .filter(
                        (fieldName) =>
                            Boolean(
                                fieldName
                            )
                    )
            );

        if (
            !visible.has(
                this.resultSortBy
            )
        ) {
            this.resultSortBy =
                this.showObjectColumn
                    ? (
                        this.trimColumns
                            ? 'objectApiName'
                            : 'objectDisplay'
                    )
                    : 'setupUrl';

            this.resultSortDirection =
                'asc';
        }
    }

    registerAuditedObject(
        result,
        rows
    ) {
        const objectApiName =
            result.objectApiName;

        const objectLabel =
            result.objectLabel ||
            objectApiName;

        const objectResult = {
            objectApiName,
            objectLabel,
            displayLabel:
                objectLabel +
                ' (' +
                objectApiName +
                ')',
            fieldCount:
                rows.length
        };

        const rowsByObject =
            Object.assign(
                {},
                this.rowsByObjectApiName
            );

        rowsByObject[
            objectApiName
        ] = rows;

        this.rowsByObjectApiName =
            rowsByObject;

        this.auditedObjects =
            this.auditedObjects
                .filter(
                    (item) =>
                        item.objectApiName !==
                        objectApiName
                )
                .concat([
                    objectResult
                ])
                .sort(
                    (left, right) =>
                        TEXT_COLLATOR.compare(
                            left.displayLabel,
                            right.displayLabel
                        )
                );

        const summaries =
            Object.assign(
                {},
                this.summaryByObjectApiName
            );

        summaries[
            objectApiName
        ] =
            this.summarizeRows(
                rows
            );

        this.summaryByObjectApiName =
            summaries;

        this.rebuildSummaryMetrics();
        this.refreshResultObjectFilterOptions();

        if (
            this.auditedObjects.length ===
                1 &&
            !this.resultObjectFilterManuallyChanged
        ) {
            this.selectedResultObjectApiName =
                objectApiName;
        }
    }

    refreshResultObjectFilterOptions() {
        const viewAllLabel =
            this.auditedObjects.length
                ? (
                    'View All (' +
                    this.auditedObjects.length +
                    ' objects)'
                )
                : 'View All';

        const objectOptions =
            this.auditedObjects.map(
                (objectResult) => ({
                    label:
                        objectResult.displayLabel +
                        ' - ' +
                        objectResult.fieldCount +
                        ' fields',
                    value:
                        objectResult.objectApiName
                })
            );

        this.resultObjectFilterOptions = [
            {
                label:
                    viewAllLabel,
                value:
                    VIEW_ALL_OBJECTS
            }
        ].concat(
            objectOptions
        );
    }

    summarizeRows(rows) {
        const summary =
            createEmptySummary();

        summary.fieldCount =
            rows.length;

        rows.forEach(
            (row) => {
                const applicable =
                    row.populationAnalysisApplicable ===
                    true;

                const checkbox =
                    row.checkboxField ===
                    true;

                const documentationEvaluated =
                    row.documentationScore !==
                        null &&
                    row.documentationScore !==
                        undefined;

                const descriptionEvaluated =
                    row.descriptionAuditAvailable ===
                    true;

                const historyEvaluated =
                    row.historyTrackingAuditAvailable ===
                        true &&
                    typeof row.fieldHistoryTracked ===
                        'boolean';

                const fieldUsageAvailable =
                    this.isMetadataAvailable(
                        row.fieldUsage
                    );

                const sensitivityAvailable =
                    this.isMetadataAvailable(
                        row.dataSensitivityLevel
                    );

                const complianceAvailable =
                    this.isMetadataAvailable(
                        row.complianceCategorization
                    );

                const fieldUsageSet =
                    this.isMetadataPopulated(
                        row.fieldUsage
                    );

                const sensitivitySet =
                    this.isMetadataPopulated(
                        row.dataSensitivityLevel
                    );

                const complianceSet =
                    this.isMetadataPopulated(
                        row.complianceCategorization
                    );

                if (applicable) {
                    summary.populationEligibleFields +=
                        1;
                } else if (checkbox) {
                    summary.checkboxFields +=
                        1;
                } else {
                    summary.otherNotApplicableFields +=
                        1;
                }

                if (documentationEvaluated) {
                    summary.documentationEvaluated +=
                        1;
                }

                if (
                    row.documentationScore ===
                    100
                ) {
                    summary.documented +=
                        1;
                }

                if (descriptionEvaluated) {
                    summary.descriptionEvaluated +=
                        1;
                }

                if (
                    descriptionEvaluated &&
                    !row.hasDescription
                ) {
                    summary.missingDescription +=
                        1;
                }

                if (!row.hasHelpText) {
                    summary.missingHelpText +=
                        1;
                }

                if (historyEvaluated) {
                    summary.historyEvaluated +=
                        1;
                }

                if (
                    row.fieldHistoryTracked ===
                    true
                ) {
                    summary.historyTracked +=
                        1;
                }

                if (fieldUsageAvailable) {
                    summary.fieldUsageEvaluated +=
                        1;
                }

                if (fieldUsageSet) {
                    summary.fieldUsageSet +=
                        1;
                }

                if (sensitivityAvailable) {
                    summary.sensitivityEvaluated +=
                        1;
                }

                if (sensitivitySet) {
                    summary.sensitivitySet +=
                        1;
                }

                if (complianceAvailable) {
                    summary.complianceEvaluated +=
                        1;
                }

                if (complianceSet) {
                    summary.complianceSet +=
                        1;
                }

                if (
                    fieldUsageAvailable &&
                    sensitivityAvailable &&
                    complianceAvailable
                ) {
                    summary.governanceEvaluated +=
                        1;
                }

                if (
                    fieldUsageSet &&
                    sensitivitySet &&
                    complianceSet
                ) {
                    summary.governanceComplete +=
                        1;
                }

                if (
                    row.customField ===
                    true
                ) {
                    summary.customFields +=
                        1;
                }

                if (
                    row.required ===
                    true
                ) {
                    summary.requiredFields +=
                        1;
                }

                if (
                    row.calculated ===
                    true
                ) {
                    summary.formulaFields +=
                        1;
                }

                if (
                    row.externalId ===
                    true
                ) {
                    summary.externalIdFields +=
                        1;
                }

                if (
                    row.uniqueField ===
                    true
                ) {
                    summary.uniqueFields +=
                        1;
                }

                if (
                    this.isPicklistField(
                        row
                    )
                ) {
                    summary.picklistFields +=
                        1;
                }

                if (
                    String(
                        row.referenceTo ||
                        ''
                    ).trim()
                ) {
                    summary.relationshipFields +=
                        1;
                }

                if (
                    applicable &&
                    row.usageStatus ===
                    'No data'
                ) {
                    summary.noData +=
                        1;
                }

                if (
                    applicable &&
                    row.usageStatus ===
                    'Low usage'
                ) {
                    summary.lowUsage +=
                        1;
                }

                if (
                    applicable &&
                    row.usageStatus ===
                    'Not evaluated'
                ) {
                    summary.notEvaluated +=
                        1;
                }
            }
        );

        return summary;
    }

    rebuildSummaryMetrics() {
        const summary =
            createEmptySummary();

        const objectSummaries =
            Object.values(
                this.summaryByObjectApiName
            );

        summary.objectCount =
            objectSummaries.length;

        objectSummaries.forEach(
            (objectSummary) => {
                Object.keys(
                    summary
                ).forEach(
                    (key) => {
                        if (
                            key !==
                            'objectCount'
                        ) {
                            summary[key] +=
                                Number(
                                    objectSummary[key] ||
                                    0
                                );
                        }
                    }
                );
            }
        );

        this.summaryMetrics =
            summary;
    }

    isMetadataAvailable(value) {
        const normalized =
            String(
                value === null ||
                value === undefined
                    ? ''
                    : value
            )
                .trim()
                .toLowerCase();

        return [
            'unavailable',
            'not available',
            'not reported'
        ].indexOf(
            normalized
        ) ===
            -1;
    }

    isMetadataPopulated(value) {
        if (
            !this.isMetadataAvailable(
                value
            )
        ) {
            return false;
        }

        const normalized =
            String(
                value === null ||
                value === undefined
                    ? ''
                    : value
            )
                .trim()
                .toLowerCase();

        return [
            '',
            'none',
            'not set',
            'not specified',
            'n/a'
        ].indexOf(
            normalized
        ) ===
            -1;
    }

    isPicklistField(row) {
        const fieldType =
            String(
                row.fieldType ||
                ''
            )
                .trim()
                .toLowerCase();

        return (
            fieldType.includes(
                'picklist'
            ) ||
            fieldType ===
                'combobox'
        );
    }

    getScopedRows() {
        if (
            this.selectedResultObjectApiName !==
            VIEW_ALL_OBJECTS
        ) {
            return (
                this.rowsByObjectApiName[
                    this.selectedResultObjectApiName
                ] ||
                []
            );
        }

        let rows = [];

        this.auditedObjects.forEach(
            (objectResult) => {
                rows =
                    rows.concat(
                        this.rowsByObjectApiName[
                            objectResult.objectApiName
                        ] ||
                        []
                    );
            }
        );

        return rows;
    }

    applyResultFilters(options) {
        const settings =
            options ||
            {};

        const resetWindow =
            settings.resetWindow ===
            true;

        const search =
            this.searchTerm
                .trim()
                .toLowerCase();

        let rows =
            this.getScopedRows();

        if (search) {
            rows =
                rows.filter(
                    (row) =>
                        [
                            row.objectLabel,
                            row.objectApiName,
                            row.fieldLabel,
                            row.fieldApiName,
                            row.fieldType,
                            row.fieldHistoryTrackingStatus,
                            row.description,
                            row.helpText,
                            row.fieldUsage,
                            row.dataSensitivityLevel,
                            row.complianceCategorization,
                            row.metadataAuditStatus,
                            row.usageMethod,
                            row.usageStatus,
                            row.note
                        ]
                            .filter(
                                (value) =>
                                    value !==
                                        null &&
                                    value !==
                                        undefined
                            )
                            .join(' ')
                            .toLowerCase()
                            .includes(
                                search
                            )
                );
        }

        if (
            this.showMetadataIssuesOnly
        ) {
            rows =
                rows.filter(
                    (row) =>
                        row.metadataAuditStatus !==
                        'Complete'
                );
        }

        if (
            this.showUsageIssuesOnly
        ) {
            rows =
                rows.filter(
                    (row) =>
                        [
                            'No data',
                            'Low usage',
                            'Not evaluated'
                        ].indexOf(
                            row.usageStatus
                        ) !==
                            -1
                );
        }

        this.ensureVisibleResultSortField();

        const actualSortField =
            RESULT_SORT_FIELD_ALIASES[
                this.resultSortBy
            ] ||
            this.resultSortBy;

        this.filteredRows =
            this.sortRowsByField(
                rows,
                actualSortField,
                this.resultSortDirection,
                RESULT_SORT_TYPES
            );

        this.refreshDisplayedRows({
            resetWindow
        });
    }

    refreshDisplayedRows(options) {
        const settings =
            options ||
            {};

        const resetWindow =
            settings.resetWindow ===
            true;

        if (this.useInfiniteScroll) {
            if (
                resetWindow ||
                !this.infiniteLoadedRowCount
            ) {
                this.infiniteLoadedRowCount =
                    Math.min(
                        this.rowBatchSize,
                        this.filteredRows.length
                    );
            } else {
                this.infiniteLoadedRowCount =
                    Math.min(
                        Math.max(
                            this.infiniteLoadedRowCount,
                            this.rowBatchSize
                        ),
                        this.filteredRows.length
                    );
            }

            this.displayedRows =
                this.filteredRows.slice(
                    0,
                    this.infiniteLoadedRowCount
                );
        } else {
            if (resetWindow) {
                this.currentPage =
                    1;
            }

            this.currentPage =
                Math.min(
                    Math.max(
                        this.currentPage,
                        1
                    ),
                    this.totalPages
                );

            this.updatePaginatedRows();
        }

        this.shouldScrollResultsToTop =
            true;
    }

    updatePaginatedRows() {
        if (!this.filteredRows.length) {
            this.currentPage =
                1;

            this.displayedRows =
                [];

            this.shouldScrollResultsToTop =
                true;

            return;
        }

        this.currentPage =
            Math.min(
                Math.max(
                    this.currentPage,
                    1
                ),
                this.totalPages
            );

        const startIndex =
            (
                this.currentPage -
                1
            ) *
            this.rowBatchSize;

        this.displayedRows =
            this.filteredRows.slice(
                startIndex,
                startIndex +
                this.rowBatchSize
            );

        this.shouldScrollResultsToTop =
            true;
    }

    sortRowsByField(
        rows,
        fieldName,
        sortDirection,
        sortTypes
    ) {
        if (!fieldName) {
            return rows.slice();
        }

        const direction =
            sortDirection ===
            'desc'
                ? -1
                : 1;

        const sortType =
            sortTypes[fieldName] ||
            'text';

        return rows
            .map(
                (
                    row,
                    originalIndex
                ) => ({
                    row,
                    originalIndex
                })
            )
            .sort(
                (left, right) => {
                    const comparison =
                        this.compareSortValues(
                            left.row[
                                fieldName
                            ],
                            right.row[
                                fieldName
                            ],
                            sortType,
                            direction
                        );

                    return comparison ===
                        0
                        ? (
                            left.originalIndex -
                            right.originalIndex
                        )
                        : comparison;
                }
            )
            .map(
                (item) =>
                    item.row
            );
    }

    compareSortValues(
        leftValue,
        rightValue,
        sortType,
        direction
    ) {
        const leftEmpty =
            this.isEmptySortValue(
                leftValue
            );

        const rightEmpty =
            this.isEmptySortValue(
                rightValue
            );

        if (
            leftEmpty &&
            rightEmpty
        ) {
            return 0;
        }

        if (leftEmpty) {
            return 1;
        }

        if (rightEmpty) {
            return -1;
        }

        let comparison;

        if (
            sortType ===
            'number'
        ) {
            comparison =
                this.toSortableNumber(
                    leftValue
                ) -
                this.toSortableNumber(
                    rightValue
                );
        } else if (
            sortType ===
            'boolean'
        ) {
            comparison =
                this.toSortableBoolean(
                    leftValue
                ) -
                this.toSortableBoolean(
                    rightValue
                );
        } else {
            comparison =
                TEXT_COLLATOR.compare(
                    String(
                        leftValue
                    ),
                    String(
                        rightValue
                    )
                );
        }

        return comparison *
            direction;
    }

    isEmptySortValue(value) {
        return (
            value === null ||
            value === undefined ||
            value === ''
        );
    }

    toSortableNumber(value) {
        if (
            typeof value ===
            'number'
        ) {
            return Number.isFinite(
                value
            )
                ? value
                : 0;
        }

        const normalized =
            Number(
                String(
                    value
                ).replace(
                    /[,%$\s]/g,
                    ''
                )
            );

        return Number.isFinite(
            normalized
        )
            ? normalized
            : 0;
    }

    toSortableBoolean(value) {
        if (
            typeof value ===
            'boolean'
        ) {
            return value
                ? 1
                : 0;
        }

        return [
            'true',
            'yes',
            '1'
        ].indexOf(
            String(
                value
            )
                .trim()
                .toLowerCase()
        ) !==
            -1
            ? 1
            : 0;
    }

    resetAuditResults() {
        this.rowsByObjectApiName =
            {};

        this.auditedObjects =
            [];

        this.filteredRows =
            [];

        this.displayedRows =
            [];

        this.summaryByObjectApiName =
            {};

        this.summaryMetrics =
            createEmptySummary();

        this.resultObjectFilterOptions = [
            {
                label: 'View All',
                value: VIEW_ALL_OBJECTS
            }
        ];

        this.selectedResultObjectApiName =
            VIEW_ALL_OBJECTS;

        this.resultObjectFilterManuallyChanged =
            false;

        this.currentPage =
            1;

        this.infiniteLoadedRowCount =
            0;

        this.resultSortBy =
            'setupUrl';

        this.resultSortDirection =
            'asc';
    }

    /* ------------------------------------------------------------------ */
    /* Audit, Setup links, and export                                      */
    /* ------------------------------------------------------------------ */

    buildFieldSetupPath(row) {
        const objectSegment =
            encodeURIComponent(
                row.objectApiName
            );

        const fieldIdentifier =
            row.setupFieldId ||
            row.fieldApiName;

        const fieldsListPath =
            '/lightning/setup/ObjectManager/' +
            objectSegment +
            '/FieldsAndRelationships/view';

        if (!fieldIdentifier) {
            return fieldsListPath;
        }

        const routeBase =
            '/lightning/setup/ObjectManager/' +
            objectSegment +
            '/FieldsAndRelationships/' +
            encodeURIComponent(
                fieldIdentifier
            );

        return this.canOpenDirectMetadataEditor(
            row
        )
            ? (
                routeBase +
                '/edit'
            )
            : (
                routeBase +
                '/view'
            );
    }

    async handleRun() {
        const selectedObjects =
            this.selectedObjectApiNames.slice();

        if (!selectedObjects.length) {
            this.showToast(
                'Select at least one object',
                '',
                'warning'
            );

            return;
        }

        this.isRunning =
            true;

        this.cancelRequested =
            false;

        this.progressCurrent =
            0;

        this.progressTotal =
            selectedObjects.length;

        this.currentObjectLabel =
            '';

        this.auditWarnings =
            [];

        this.auditErrors =
            [];

        this.resetAuditResults();

        await this.runSelectedObject(
            selectedObjects,
            0
        );

        this.finishAuditRun();
    }

    async runSelectedObject(
        selectedObjects,
        index
    ) {
        if (
            this.cancelRequested ||
            index >=
                selectedObjects.length
        ) {
            return;
        }

        const objectApiName =
            selectedObjects[index];

        this.currentObjectLabel =
            this.getObjectLabel(
                objectApiName
            );

        try {
            const result =
                await auditObject({
                    objectApiName,
                    configurationJson:
                        this.effectiveConfigurationJson
                });

            const rows =
                (
                    result.fields ||
                    []
                ).map(
                    (row) =>
                        this.decorateRow(
                            row
                        )
                );

            this.registerAuditedObject(
                result,
                rows
            );

            const warnings =
                (
                    result.warnings ||
                    []
                ).map(
                    (warning) =>
                        result.objectApiName +
                        ': ' +
                        warning
                );

            this.auditWarnings =
                this.auditWarnings.concat(
                    warnings
                );

            if (
                this.selectedResultObjectApiName ===
                    VIEW_ALL_OBJECTS ||
                this.selectedResultObjectApiName ===
                    result.objectApiName
            ) {
                this.applyResultFilters({
                    resetWindow:
                        index ===
                        0
                });
            }
        } catch (error) {
            this.auditErrors =
                this.auditErrors.concat([
                    objectApiName +
                    ': ' +
                    this.reduceError(
                        error
                    )
                ]);
        }

        this.progressCurrent =
            index +
            1;

        await this.runSelectedObject(
            selectedObjects,
            index +
            1
        );
    }

    finishAuditRun() {
        const wasCancelled =
            this.cancelRequested &&
            this.progressCurrent <
                this.progressTotal;

        this.isRunning =
            false;

        this.cancelRequested =
            false;

        this.currentObjectLabel =
            '';

        if (wasCancelled) {
            this.showToast(
                'Audit stopped',
                (
                    this.progressCurrent +
                    ' of ' +
                    this.progressTotal +
                    ' objects completed. Completed results were kept.'
                ),
                'warning'
            );

            return;
        }

        this.showToast(
            this.auditErrors.length
                ? 'Audit completed with errors'
                : 'Audit complete',
            this.auditErrors.length
                ? (
                    this.auditErrors.length +
                    ' object audit(s) failed.'
                )
                : (
                    this.summaryMetrics.objectCount +
                    ' object(s) and ' +
                    this.summaryMetrics.fieldCount +
                    ' field(s) evaluated.'
                ),
            this.auditErrors.length
                ? 'warning'
                : 'success'
        );
    }

    handleClearResults() {
        this.auditWarnings =
            [];

        this.auditErrors =
            [];

        this.searchTerm =
            '';

        this.showMetadataIssuesOnly =
            false;

        this.showUsageIssuesOnly =
            false;

        this.resetAuditResults();
    }

    handleExport() {
        try {
            const exportColumns =
                this.trimColumns
                    ? TRIMMED_EXPORT_COLUMNS
                    : FULL_EXPORT_COLUMNS;

            const headers =
                exportColumns.map(
                    (column) =>
                        this.escapeCsv(
                            column[0]
                        )
                );

            const rows =
                this.filteredRows.map(
                    (row) =>
                        exportColumns
                            .map(
                                (column) =>
                                    this.escapeCsv(
                                        this.exportValue(
                                            row[
                                                column[1]
                                            ]
                                        )
                                    )
                            )
                            .join(',')
                );

            const csvContent =
                '\uFEFF' +
                [
                    headers.join(',')
                ]
                    .concat(
                        rows
                    )
                    .join(
                        '\r\n'
                    );

            const blob =
                new Blob(
                    [
                        csvContent
                    ],
                    {
                        type: 'text/plain'
                    }
                );

            if (this.activeDownloadUrl) {
                URL.revokeObjectURL(
                    this.activeDownloadUrl
                );
            }

            const blobUrl =
                URL.createObjectURL(
                    blob
                );

            this.activeDownloadUrl =
                blobUrl;

            const downloadLink =
                this.template.querySelector(
                    '[data-download-link]'
                );

            if (!downloadLink) {
                URL.revokeObjectURL(
                    blobUrl
                );

                this.activeDownloadUrl =
                    undefined;

                throw new Error(
                    'The export download link was not found.'
                );
            }

            const timestamp =
                new Date()
                    .toISOString()
                    .replace(
                        /[:.]/g,
                        '-'
                    );

            const exportMode =
                this.trimColumns
                    ? 'trimmed'
                    : 'full';

            const objectScope =
                this.selectedResultObjectApiName ===
                VIEW_ALL_OBJECTS
                    ? 'view-all'
                    : this.selectedResultObjectApiName
                        .replace(
                            /[^A-Za-z0-9_-]/g,
                            '_'
                        );

            downloadLink.setAttribute(
                'href',
                blobUrl
            );

            downloadLink.setAttribute(
                'download',
                (
                    'data-dictionary-' +
                    objectScope +
                    '-' +
                    exportMode +
                    '-' +
                    timestamp +
                    '.csv'
                )
            );

            downloadLink.click();

            downloadLink.removeAttribute(
                'href'
            );

            downloadLink.removeAttribute(
                'download'
            );
        } catch (error) {
            this.showToast(
                'Export failed',
                this.reduceError(
                    error
                ),
                'error'
            );
        }
    }

    canOpenDirectMetadataEditor(row) {
        if (
            row.customField !==
                true ||
            typeof row.setupFieldId !==
                'string' ||
            !/^00N/i.test(
                row.setupFieldId
            ) ||
            typeof row.fieldApiName !==
                'string'
        ) {
            return false;
        }

        const lowerFieldApiName =
            row.fieldApiName.toLowerCase();

        if (
            lowerFieldApiName.endsWith(
                '__pc'
            )
        ) {
            return false;
        }

        if (
            lowerFieldApiName.endsWith(
                '__c'
            )
        ) {
            const nameWithoutCustomSuffix =
                lowerFieldApiName.slice(
                    0,
                    -3
                );

            if (
                nameWithoutCustomSuffix.includes(
                    '__'
                )
            ) {
                return false;
            }
        }

        return true;
    }

    decorateRow(row) {
        const directEdit =
            this.canOpenDirectMetadataEditor(
                row
            );

        return Object.assign(
            {},
            row,
            {
                objectDisplay:
                    row.objectLabel +
                    ' (' +
                    row.objectApiName +
                    ')',
                fieldHistoryTrackingStatus:
                    row.fieldHistoryTrackingStatus ||
                    'Unavailable',
                description:
                    row.description ||
                    '',
                helpText:
                    row.helpText ||
                    '',
                fieldUsage:
                    row.fieldUsage ||
                    '',
                dataSensitivityLevel:
                    row.dataSensitivityLevel ||
                    '',
                complianceCategorization:
                    row.complianceCategorization ||
                    '',
                calculatedFormula:
                    row.calculatedFormula ||
                    '',
                referenceTo:
                    row.referenceTo ||
                    '',
                note:
                    row.note ||
                    '',
                setupUrl:
                    this.buildFieldSetupPath(
                        row
                    ),
                setupActionTitle:
                    directEdit
                        ? (
                            'Edit custom field metadata in Lightning Setup'
                        )
                        : (
                            'Open field metadata in Lightning Setup'
                        )
            }
        );
    }

    getObjectLabel(objectApiName) {
        const row =
            this.objectRows.find(
                (item) =>
                    item.value ===
                    objectApiName
            );

        return row
            ? (
                row.objectLabel +
                ' (' +
                row.value +
                ')'
            )
            : objectApiName;
    }

    exportValue(value) {
        if (
            value === null ||
            value === undefined
        ) {
            return '';
        }

        return typeof value ===
            'boolean'
            ? (
                value
                    ? 'TRUE'
                    : 'FALSE'
            )
            : String(
                value
            );
    }

    /**
     * Prevents spreadsheet software from interpreting exported
     * metadata text as a formula.
     */
    escapeCsv(value) {
        const text =
            String(
                value === null ||
                value === undefined
                    ? ''
                    : value
            );

        const safe =
            /^[\s]*[=+\-@]/.test(
                text
            )
                ? (
                    "'" +
                    text
                )
                : text;

        return (
            '"' +
            safe.replace(
                /"/g,
                '""'
            ) +
            '"'
        );
    }

    reduceError(error) {
        if (
            error &&
            Array.isArray(
                error.body
            )
        ) {
            return error.body
                .map(
                    (item) =>
                        item.message
                )
                .join(', ');
        }

        if (
            error &&
            error.body &&
            error.body.message
        ) {
            return error.body.message;
        }

        if (
            error &&
            error.message
        ) {
            return error.message;
        }

        return 'Unknown error';
    }

    showErrorToast(
        title,
        error
    ) {
        this.showToast(
            title,
            this.reduceError(
                error
            ),
            'error'
        );
    }

    showToast(
        title,
        message,
        variant
    ) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}