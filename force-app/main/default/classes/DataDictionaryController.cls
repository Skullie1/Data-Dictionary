/**
 * Server-side controller for the Data Dictionary Audit LWC.
 *
 * Intent:
 * - Keep the server footprint to one production Apex class.
 * - Return an object inventory for checkbox-based selection.
 * - Audit one object per Apex transaction.
 * - Enforce sharing, CRUD, FLS, and USER_MODE queries.
 * - Validate every dynamic object and field identifier before SOQL execution.
 * - Return aggregate counts and metadata, never business-record field values.
 * - Include checkbox fields in metadata audits while intentionally excluding
 *   checkbox value distribution from population analysis.
 * - Exclude Data Owner because it can contain personally identifiable information.
 */
public with sharing class DataDictionaryController {
    private static final System.AccessLevel USER_ACCESS =
        System.AccessLevel.USER_MODE;

    private static final Integer AGGREGATE_CHUNK_SIZE = 25;
    private static final Integer QUERY_LIMIT_RESERVE = 3;
    private static final Decimal DEFAULT_LOW_USAGE_THRESHOLD = 5;
    private static final String SAFE_API_NAME_PATTERN =
        '^[A-Za-z][A-Za-z0-9_]*$';

    private static final Set<String> METADATA_OBJECTS = new Set<String>{
        'DataType',
        'EntityDefinition',
        'EntityParticle',
        'FieldDefinition',
        'PicklistValueInfo',
        'Publisher',
        'RelationshipDomain',
        'RelationshipInfo',
        'Service',
        'ServiceDataType',
        'ServiceFieldDataType',
        'UserEntityAccess',
        'UserFieldAccess'
    };

    private static final List<String> SYSTEM_SUFFIXES = new List<String>{
        'history',
        'share',
        'feed',
        'changeevent',
        '__mdt',
        '__e',
        '__b',
        '__x'
    };

    @TestVisible
    private static Integer queryLimitReserveOverride;

    private static final TextUtil TEXT = new TextUtil();
    private static final ResultScorer SCORER = new ResultScorer();

    /**
     * Returns every readable eligible object and the configured initial selection.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getBootstrap(String configurationJson) {
        Config config = new ConfigParser().parse(configurationJson);
        return new SchemaCatalog(
            Schema.getGlobalDescribe(),
            config
        ).buildBootstrap();
    }

    /**
     * Audits one object. The LWC invokes this method once per selected object.
     */
    @AuraEnabled
    public static Map<String, Object> auditObject(
        String objectApiName,
        String configurationJson
    ) {
        Config config = new ConfigParser().parse(configurationJson);

        SchemaCatalog catalog = new SchemaCatalog(
            Schema.getGlobalDescribe(),
            config
        );

        Schema.DescribeSObjectResult objectDescribe =
            catalog.requireAuditableObject(objectApiName);

        return new AuditRunner(
            objectDescribe,
            catalog,
            config
        ).run();
    }

    /**
     * Nullable JSON input applied to stable runtime defaults.
     */
    private class ConfigInput {
        public List<String> objectApiNames;
        public Boolean includeStandardObjects;
        public Boolean includeCustomObjects;
        public Boolean includeSystemObjects;
        public Decimal lowUsageThresholdPercent;
    }

    /**
     * Normalized runtime configuration.
     */
    private class Config {
        public List<String> objectApiNames = new List<String>();
        public Boolean includeStandardObjects = true;
        public Boolean includeCustomObjects = true;
        public Boolean includeSystemObjects = false;
        public Decimal lowUsageThresholdPercent =
            DEFAULT_LOW_USAGE_THRESHOLD;

        /**
         * Converts the normalized configuration into a serializable
         * map for focused tests.
         */
        public Map<String, Object> toMap() {
            return new Map<String, Object>{
                'objectApiNames' => copyNames(),
                'includeStandardObjects' => includeStandardObjects,
                'includeCustomObjects' => includeCustomObjects,
                'includeSystemObjects' => includeSystemObjects,
                'lowUsageThresholdPercent' =>
                    lowUsageThresholdPercent
            };
        }

        /**
         * Returns a defensive copy of the configured object list.
         */
        private List<String> copyNames() {
            List<String> result = new List<String>();
            result.addAll(objectApiNames);
            return result;
        }
    }

    /**
     * Parses, normalizes, and bounds the component JSON configuration.
     */
    private class ConfigParser {
        /**
         * Applies supplied JSON values to stable defaults.
         */
        public Config parse(String configurationJson) {
            Config result = new Config();

            if (String.isBlank(configurationJson)) {
                return result;
            }

            try {
                ConfigInput input = (ConfigInput) JSON.deserialize(
                    configurationJson,
                    ConfigInput.class
                );

                if (input == null) {
                    return result;
                }

                result.objectApiNames =
                    normalizeNames(input.objectApiNames);

                result.includeStandardObjects =
                    input.includeStandardObjects == null
                        ? result.includeStandardObjects
                        : input.includeStandardObjects;

                result.includeCustomObjects =
                    input.includeCustomObjects == null
                        ? result.includeCustomObjects
                        : input.includeCustomObjects;

                result.includeSystemObjects =
                    input.includeSystemObjects == null
                        ? result.includeSystemObjects
                        : input.includeSystemObjects;

                result.lowUsageThresholdPercent =
                    normalizeThreshold(
                        input.lowUsageThresholdPercent
                    );

                return result;
            } catch (System.JSONException jsonException) {
                throw TEXT.handled(
                    'Invalid configuration JSON: ' +
                    TEXT.cleanMessage(
                        jsonException.getMessage()
                    )
                );
            } catch (System.TypeException typeException) {
                throw TEXT.handled(
                    'Invalid configuration JSON: ' +
                    TEXT.cleanMessage(
                        typeException.getMessage()
                    )
                );
            }
        }

        /**
         * Trims and de-duplicates object names while preserving order.
         */
        public List<String> normalizeNames(List<String> names) {
            List<String> result = new List<String>();
            Set<String> seen = new Set<String>();

            if (names == null) {
                return result;
            }

            for (String name : names) {
                if (String.isBlank(name)) {
                    continue;
                }

                String trimmed = name.trim();
                String key = trimmed.toLowerCase();

                if (!seen.contains(key)) {
                    seen.add(key);
                    result.add(trimmed);
                }
            }

            return result;
        }

        /**
         * Restricts the low-usage threshold to zero through one hundred.
         */
        public Decimal normalizeThreshold(Decimal threshold) {
            if (threshold == null) {
                return DEFAULT_LOW_USAGE_THRESHOLD;
            }

            if (threshold < 0) {
                return 0;
            }

            if (threshold > 100) {
                return 100;
            }

            return threshold;
        }
    }

    /**
     * Resolves objects and applies object visibility and configuration filters.
     */
    private class SchemaCatalog {
        private Map<String, Schema.SObjectType> globalMap;
        private Map<String, Schema.SObjectType> lowerCaseMap;
        private Config config;

        /**
         * Builds exact-case and lower-case schema lookups once per request.
         */
        public SchemaCatalog(
            Map<String, Schema.SObjectType> suppliedMap,
            Config suppliedConfig
        ) {
            globalMap =
                suppliedMap == null
                    ? new Map<String, Schema.SObjectType>()
                    : suppliedMap;

            config =
                suppliedConfig == null
                    ? new Config()
                    : suppliedConfig;

            lowerCaseMap =
                new Map<String, Schema.SObjectType>();

            for (String objectName : globalMap.keySet()) {
                Schema.SObjectType objectType =
                    globalMap.get(objectName);

                if (objectType != null) {
                    lowerCaseMap.put(
                        objectName.toLowerCase(),
                        objectType
                    );
                }
            }
        }

        /**
         * Returns all eligible objects. objectApiNames controls initial
         * selection, not an allowlist, so users can add other objects
         * from the table.
         */
        public Map<String, Object> buildBootstrap() {
            List<Map<String, Object>> options =
                new List<Map<String, Object>>();

            List<String> selectedNames =
                new List<String>();

            List<String> warnings =
                new List<String>();

            List<String> allNames =
                new List<String>(globalMap.keySet());

            Set<String> selectedKeys =
                new Set<String>();

            allNames.sort();

            for (String objectName : allNames) {
                Schema.SObjectType objectType =
                    globalMap.get(objectName);

                if (objectType == null) {
                    continue;
                }

                Schema.DescribeSObjectResult describeResult =
                    objectType.getDescribe(
                        SObjectDescribeOptions.DEFERRED
                    );

                if (isEligible(describeResult)) {
                    options.add(
                        toOption(describeResult)
                    );
                }
            }

            for (String configuredName : config.objectApiNames) {
                Schema.SObjectType objectType =
                    resolve(configuredName);

                if (objectType == null) {
                    warnings.add(
                        'Unknown object in configuration: ' +
                        TEXT.cleanMessage(configuredName)
                    );

                    continue;
                }

                Schema.DescribeSObjectResult describeResult =
                    objectType.getDescribe(
                        SObjectDescribeOptions.DEFERRED
                    );

                if (!isEligible(describeResult)) {
                    warnings.add(
                        'Object is not eligible or readable under the ' +
                        'current configuration: ' +
                        describeResult.getName()
                    );

                    continue;
                }

                String canonicalName =
                    describeResult.getName();

                String normalizedName =
                    canonicalName.toLowerCase();

                if (!selectedKeys.contains(normalizedName)) {
                    selectedKeys.add(normalizedName);
                    selectedNames.add(canonicalName);
                }
            }

            return new Map<String, Object>{
                'objects' => options,
                'selectedObjectApiNames' => selectedNames,
                'lowUsageThresholdPercent' =>
                    config.lowUsageThresholdPercent,
                'warnings' => warnings
            };
        }

        /**
         * Resolves and validates the object requested by the LWC.
         */
        public Schema.DescribeSObjectResult requireAuditableObject(
            String requestedName
        ) {
            if (String.isBlank(requestedName)) {
                throw TEXT.handled(
                    'Object API name is required.'
                );
            }

            Schema.SObjectType objectType =
                resolve(requestedName);

            if (objectType == null) {
                throw TEXT.handled(
                    'Unknown object: ' +
                    TEXT.cleanMessage(requestedName)
                );
            }

            Schema.DescribeSObjectResult describeResult =
                objectType.getDescribe(
                    SObjectDescribeOptions.DEFERRED
                );

            if (!isEligible(describeResult)) {
                throw TEXT.handled(
                    'Object is not eligible or readable under the ' +
                    'current configuration: ' +
                    describeResult.getName()
                );
            }

            return describeResult;
        }

        /**
         * Resolves an object API name case-insensitively.
         */
        public Schema.SObjectType resolve(String requestedName) {
            if (String.isBlank(requestedName)) {
                return null;
            }

            String trimmed = requestedName.trim();

            Schema.SObjectType exactMatch =
                globalMap.get(trimmed);

            return exactMatch == null
                ? lowerCaseMap.get(trimmed.toLowerCase())
                : exactMatch;
        }

        /**
         * Applies queryability, access, object-type, and technical-object
         * filters.
         */
        public Boolean isEligible(
            Schema.DescribeSObjectResult describeResult
        ) {
            if (
                describeResult == null ||
                !describeResult.isAccessible() ||
                !describeResult.isQueryable() ||
                !hasAccessibleId(describeResult)
            ) {
                return false;
            }

            Boolean typeAllowed =
                describeResult.isCustom()
                    ? config.includeCustomObjects
                    : config.includeStandardObjects;

            return typeAllowed &&
                (
                    config.includeSystemObjects ||
                    !isSystemLike(
                        describeResult.getName()
                    )
                );
        }

        /**
         * Identifies technical objects normally excluded from a
         * business-focused data dictionary.
         */
        public Boolean isSystemLike(String objectApiName) {
            if (String.isBlank(objectApiName)) {
                return true;
            }

            for (String metadataObject : METADATA_OBJECTS) {
                if (
                    metadataObject.equalsIgnoreCase(
                        objectApiName
                    )
                ) {
                    return true;
                }
            }

            String lowerName =
                objectApiName.toLowerCase();

            for (String suffix : SYSTEM_SUFFIXES) {
                if (lowerName.endsWith(suffix)) {
                    return true;
                }
            }

            return false;
        }

        /**
         * Confirms that the object has an accessible Id field before it
         * is offered for population analysis.
         */
        private Boolean hasAccessibleId(
            Schema.DescribeSObjectResult describeResult
        ) {
            Map<String, Schema.SObjectField> fieldMap =
                describeResult.fields.getMap();

            for (String fieldName : fieldMap.keySet()) {
                if (fieldName.equalsIgnoreCase('Id')) {
                    Schema.SObjectField fieldToken =
                        fieldMap.get(fieldName);

                    return fieldToken != null &&
                        fieldToken
                            .getDescribe()
                            .isAccessible();
                }
            }

            return false;
        }

        /**
         * Converts describe metadata into one object-selector row.
         */
        private Map<String, Object> toOption(
            Schema.DescribeSObjectResult describeResult
        ) {
            String apiName =
                describeResult.getName();

            String label =
                describeResult.getLabel();

            Boolean customObject =
                describeResult.isCustom();

            return new Map<String, Object>{
                'label' =>
                    label +
                    ' (' +
                    apiName +
                    ')',
                'value' => apiName,
                'objectLabel' => label,
                'objectTypeLabel' =>
                    customObject
                        ? 'Custom'
                        : 'Standard',
                'customObject' => customObject
            };
        }
    }

    /**
     * Non-PII FieldDefinition metadata keyed by lower-case field API name.
     */
    private class MetadataBundle {
        public Boolean descriptionAvailable = false;
        public Boolean historyTrackingAvailable = false;
        public Boolean classificationAvailable = false;

        public Map<String, Map<String, Object>> valuesByField =
            new Map<String, Map<String, Object>>();

        public List<String> warnings =
            new List<String>();
    }

    /**
     * Reads governance metadata through a bound USER_MODE query.
     */
    private class MetadataLoader {
        private Set<String> requiredFields = new Set<String>{
            'QualifiedApiName',
            'DurableId',
            'Description',
            'IsFieldHistoryTracked',
            'BusinessStatus',
            'SecurityClassification',
            'ComplianceGroup'
        };

        /**
         * Loads descriptions, history tracking, setup identifiers,
         * Field Usage, sensitivity, and compliance metadata.
         */
        public MetadataBundle load(
            String objectApiName,
            SchemaCatalog catalog
        ) {
            MetadataBundle result =
                new MetadataBundle();

            Schema.SObjectType fieldDefinitionType =
                catalog.resolve('FieldDefinition');

            if (fieldDefinitionType == null) {
                result.warnings.add(
                    'FieldDefinition is unavailable, so governance ' +
                    'metadata could not be audited.'
                );

                return result;
            }

            Schema.DescribeSObjectResult describeResult =
                fieldDefinitionType.getDescribe(
                    SObjectDescribeOptions.DEFERRED
                );

            if (
                !describeResult.isAccessible() ||
                !describeResult.isQueryable() ||
                !hasReadableFields(
                    describeResult.fields.getMap()
                )
            ) {
                result.warnings.add(
                    'The running user cannot read the required ' +
                    'FieldDefinition properties, so governance ' +
                    'metadata is unavailable.'
                );

                return result;
            }

            String queryText =
                'SELECT QualifiedApiName, DurableId, Description, ' +
                'IsFieldHistoryTracked, BusinessStatus, ' +
                'SecurityClassification, ComplianceGroup ' +
                'FROM FieldDefinition ' +
                'WHERE EntityDefinition.QualifiedApiName = :objectName';

            try {
                List<SObject> definitions =
                    Database.queryWithBinds(
                        queryText,
                        new Map<String, Object>{
                            'objectName' => objectApiName
                        },
                        USER_ACCESS
                    );

                for (SObject definition : definitions) {
                    addDefinition(
                        result,
                        definition
                    );
                }

                result.descriptionAvailable = true;
                result.historyTrackingAvailable = true;
                result.classificationAvailable = true;
            } catch (System.QueryException queryException) {
                result.warnings.add(
                    'Field governance metadata could not be queried: ' +
                    TEXT.cleanMessage(
                        queryException.getMessage()
                    )
                );
            }

            return result;
        }

        /**
         * Verifies every selected FieldDefinition property is readable.
         */
        public Boolean hasReadableFields(
            Map<String, Schema.SObjectField> fieldMap
        ) {
            if (fieldMap == null) {
                return false;
            }

            for (String requestedName : requiredFields) {
                Schema.SObjectField fieldToken =
                    findField(
                        fieldMap,
                        requestedName
                    );

                if (
                    fieldToken == null ||
                    !fieldToken
                        .getDescribe()
                        .isAccessible()
                ) {
                    return false;
                }
            }

            return true;
        }

        /**
         * Finds a field token case-insensitively.
         */
        private Schema.SObjectField findField(
            Map<String, Schema.SObjectField> fieldMap,
            String requestedName
        ) {
            for (String fieldName : fieldMap.keySet()) {
                if (
                    fieldName.equalsIgnoreCase(
                        requestedName
                    )
                ) {
                    return fieldMap.get(fieldName);
                }
            }

            return null;
        }

        /**
         * Adds one FieldDefinition result to the normalized field map.
         */
        private void addDefinition(
            MetadataBundle result,
            SObject definition
        ) {
            if (definition == null) {
                return;
            }

            String fieldApiName =
                TEXT.stringValue(
                    definition.get(
                        'QualifiedApiName'
                    )
                );

            if (String.isBlank(fieldApiName)) {
                return;
            }

            result.valuesByField.put(
                fieldApiName.toLowerCase(),
                new Map<String, Object>{
                    'setupFieldId' =>
                        TEXT.extractSetupFieldId(
                            TEXT.stringValue(
                                definition.get(
                                    'DurableId'
                                )
                            )
                        ),
                    'description' =>
                        definition.get(
                            'Description'
                        ),
                    'historyTracked' =>
                        definition.get(
                            'IsFieldHistoryTracked'
                        ),
                    'fieldUsage' =>
                        TEXT.formatFieldUsage(
                            TEXT.stringValue(
                                definition.get(
                                    'BusinessStatus'
                                )
                            )
                        ),
                    'dataSensitivityLevel' =>
                        TEXT.valueOrEmpty(
                            TEXT.stringValue(
                                definition.get(
                                    'SecurityClassification'
                                )
                            )
                        ),
                    'complianceCategorization' =>
                        TEXT.formatCompliance(
                            TEXT.stringValue(
                                definition.get(
                                    'ComplianceGroup'
                                )
                            )
                        )
                }
            );
        }
    }

    /**
     * Field rows plus the describe-derived population-counting plan.
     */
    private class BuildResult {
        public List<Map<String, Object>> rows =
            new List<Map<String, Object>>();

        public CountPlan plan =
            new CountPlan();
    }

    /**
     * Fields eligible for batched COUNT(field) population analysis.
     */
    private class CountPlan {
        public String objectApiName;

        public List<String> aggregateFields =
            new List<String>();

        public Map<String, Map<String, Object>> rowsByFieldName =
            new Map<String, Map<String, Object>>();
    }

    /**
     * Shared field-row inputs that keep method signatures concise.
     */
    private class FieldBuildContext {
        public Schema.DescribeSObjectResult objectDescribe;
        public Integer totalRecords;
        public MetadataBundle metadata;
    }

    /**
     * Converts accessible field describes into the flat LWC row contract.
     */
    private class FieldBuilder {
        /**
         * Builds every accessible field row and its population-count strategy.
         */
        public BuildResult build(
            Schema.DescribeSObjectResult objectDescribe,
            Integer totalRecords,
            MetadataBundle metadata
        ) {
            BuildResult result =
                new BuildResult();

            result.plan.objectApiName =
                objectDescribe.getName();

            FieldBuildContext context =
                new FieldBuildContext();

            context.objectDescribe =
                objectDescribe;

            context.totalRecords =
                totalRecords;

            context.metadata =
                metadata;

            Map<String, Schema.SObjectField> fieldMap =
                objectDescribe.fields.getMap();

            List<String> fieldNames =
                new List<String>(fieldMap.keySet());

            fieldNames.sort();

            for (String fieldName : fieldNames) {
                Schema.SObjectField fieldToken =
                    fieldMap.get(fieldName);

                if (fieldToken == null) {
                    continue;
                }

                Schema.DescribeFieldResult fieldDescribe =
                    fieldToken.getDescribe();

                if (!fieldDescribe.isAccessible()) {
                    continue;
                }

                Map<String, Object> row =
                    buildRow(
                        context,
                        fieldDescribe
                    );

                result.rows.add(row);

                result.plan.rowsByFieldName.put(
                    fieldDescribe.getName(),
                    row
                );

                assignPopulationStrategy(
                    result.plan,
                    fieldDescribe,
                    row
                );
            }

            return result;
        }

        /**
         * Converts one field describe result into the complete field row.
         */
        public Map<String, Object> buildRow(
            FieldBuildContext context,
            Schema.DescribeFieldResult fieldDescribe
        ) {
            String objectApiName =
                context.objectDescribe.getName();

            String fieldApiName =
                fieldDescribe.getName();

            Map<String, Object> fieldMetadata =
                context.metadata.valuesByField.get(
                    fieldApiName.toLowerCase()
                );

            if (fieldMetadata == null) {
                fieldMetadata =
                    new Map<String, Object>();
            }

            String description =
                context.metadata.descriptionAvailable
                    ? (String) fieldMetadata.get(
                        'description'
                    )
                    : null;

            String helpText =
                fieldDescribe.getInlineHelpText();

            Boolean checkboxField =
                fieldDescribe.getType() ==
                Schema.DisplayType.Boolean;

            Map<String, Object> row =
                new Map<String, Object>{
                    'key' =>
                        objectApiName +
                        '.' +
                        fieldApiName,
                    'objectApiName' =>
                        objectApiName,
                    'objectLabel' =>
                        context.objectDescribe.getLabel(),
                    'fieldApiName' =>
                        fieldApiName,
                    'fieldLabel' =>
                        fieldDescribe.getLabel(),
                    'fieldType' =>
                        String.valueOf(
                            fieldDescribe.getType()
                        ),
                    'setupFieldId' =>
                        fieldMetadata.get(
                            'setupFieldId'
                        ),
                    'fieldUsage' =>
                        classification(
                            context.metadata,
                            fieldMetadata,
                            'fieldUsage'
                        ),
                    'dataSensitivityLevel' =>
                        classification(
                            context.metadata,
                            fieldMetadata,
                            'dataSensitivityLevel'
                        ),
                    'complianceCategorization' =>
                        classification(
                            context.metadata,
                            fieldMetadata,
                            'complianceCategorization'
                        ),
                    'totalRecords' =>
                        context.totalRecords,
                    'populatedRecords' =>
                        null,
                    'populationPercent' =>
                        null,
                    'populationAnalysisApplicable' =>
                        false,
                    'checkboxField' =>
                        checkboxField,
                    'usageMethod' =>
                        null,
                    'usageStatus' =>
                        null,
                    'description' =>
                        description,
                    'hasDescription' =>
                        !String.isBlank(description),
                    'descriptionAuditAvailable' =>
                        context.metadata.descriptionAvailable,
                    'helpText' =>
                        helpText,
                    'hasHelpText' =>
                        !String.isBlank(helpText),
                    'documentationScore' =>
                        null,
                    'metadataAuditStatus' =>
                        null,
                    'fieldHistoryTracked' =>
                        null,
                    'fieldHistoryTrackingStatus' =>
                        'Unavailable',
                    'historyTrackingAuditAvailable' =>
                        context.metadata
                            .historyTrackingAvailable,
                    'customField' =>
                        fieldDescribe.isCustom(),
                    'required' =>
                        isRequired(fieldDescribe),
                    'nillable' =>
                        fieldDescribe.isNillable(),
                    'calculated' =>
                        fieldDescribe.isCalculated(),
                    'calculatedFormula' =>
                        fieldDescribe.isCalculated()
                            ? fieldDescribe
                                .getCalculatedFormula()
                            : null,
                    'autoNumber' =>
                        fieldDescribe.isAutoNumber(),
                    'externalId' =>
                        fieldDescribe.isExternalId(),
                    'uniqueField' =>
                        fieldDescribe.isUnique(),
                    'defaultedOnCreate' =>
                        fieldDescribe.isDefaultedOnCreate(),
                    'createable' =>
                        fieldDescribe.isCreateable(),
                    'updateable' =>
                        fieldDescribe.isUpdateable(),
                    'filterable' =>
                        fieldDescribe.isFilterable(),
                    'groupable' =>
                        fieldDescribe.isGroupable(),
                    'sortable' =>
                        fieldDescribe.isSortable(),
                    'aggregatable' =>
                        fieldDescribe.isAggregatable(),
                    'length' =>
                        fieldDescribe.getLength(),
                    'precision' =>
                        fieldDescribe.getPrecision(),
                    'scale' =>
                        fieldDescribe.getScale(),
                    'relationshipName' =>
                        fieldDescribe.getRelationshipName(),
                    'referenceTo' =>
                        referenceTargets(fieldDescribe),
                    'activePicklistValueCount' =>
                        null,
                    'totalPicklistValueCount' =>
                        null,
                    'restrictedPicklist' =>
                        null,
                    'dependentPicklist' =>
                        null,
                    'note' =>
                        informationalNote(fieldDescribe)
                };

            addHistory(
                row,
                context.metadata,
                fieldMetadata
            );

            addPicklist(
                row,
                fieldDescribe
            );

            SCORER.scoreDocumentation(row);

            return row;
        }

        /**
         * Determines whether a caller-supplied value is required on create.
         */
        public Boolean isRequired(
            Schema.DescribeFieldResult fieldDescribe
        ) {
            return fieldDescribe != null &&
                !fieldDescribe.isNillable() &&
                !fieldDescribe.isDefaultedOnCreate() &&
                !fieldDescribe.isCalculated() &&
                !fieldDescribe.isAutoNumber();
        }

        /**
         * Assigns one population-analysis strategy.
         *
         * Checkbox fields remain fully represented in metadata auditing,
         * but no TRUE/FALSE distribution query is executed.
         */
        public void assignPopulationStrategy(
            CountPlan plan,
            Schema.DescribeFieldResult fieldDescribe,
            Map<String, Object> row
        ) {
            if (
                fieldDescribe.getType() ==
                Schema.DisplayType.Boolean
            ) {
                row.put(
                    'populationAnalysisApplicable',
                    false
                );

                row.put(
                    'usageMethod',
                    'Excluded by design'
                );

                row.put(
                    'usageStatus',
                    'Not applicable'
                );

                row.put(
                    'note',
                    TEXT.appendNote(
                        (String) row.get('note'),
                        'Checkbox value distribution is outside ' +
                        'this audit scope'
                    )
                );

                return;
            }

            if (fieldDescribe.isAggregatable()) {
                row.put(
                    'populationAnalysisApplicable',
                    true
                );

                plan.aggregateFields.add(
                    fieldDescribe.getName()
                );

                return;
            }

            row.put(
                'populationAnalysisApplicable',
                false
            );

            row.put(
                'usageMethod',
                'Not supported'
            );

            row.put(
                'usageStatus',
                'Not applicable'
            );

            row.put(
                'note',
                TEXT.appendNote(
                    (String) row.get('note'),
                    'COUNT(field) is not supported for this field type'
                )
            );
        }

        /**
         * Returns a classification value or an explicit unavailable status.
         */
        private String classification(
            MetadataBundle metadata,
            Map<String, Object> values,
            String key
        ) {
            return metadata.classificationAvailable
                ? TEXT.valueOrEmpty(
                    (String) values.get(key)
                )
                : 'Unavailable';
        }

        /**
         * Adds history-tracking status without treating unavailable
         * metadata as false.
         */
        private void addHistory(
            Map<String, Object> row,
            MetadataBundle metadata,
            Map<String, Object> values
        ) {
            if (!metadata.historyTrackingAvailable) {
                return;
            }

            if (!values.containsKey('historyTracked')) {
                row.put(
                    'fieldHistoryTrackingStatus',
                    'Not reported'
                );

                return;
            }

            Boolean tracked =
                (Boolean) values.get(
                    'historyTracked'
                );

            row.put(
                'fieldHistoryTracked',
                tracked
            );

            row.put(
                'fieldHistoryTrackingStatus',
                tracked == true
                    ? 'Yes'
                    : 'No'
            );
        }

        /**
         * Adds picklist counts and flags for picklist-like fields.
         */
        private void addPicklist(
            Map<String, Object> row,
            Schema.DescribeFieldResult fieldDescribe
        ) {
            Schema.DisplayType typeValue =
                fieldDescribe.getType();

            Boolean picklistLike =
                typeValue == Schema.DisplayType.Picklist ||
                typeValue == Schema.DisplayType.MultiPicklist ||
                typeValue == Schema.DisplayType.Combobox;

            if (!picklistLike) {
                return;
            }

            Integer activeCount = 0;

            List<Schema.PicklistEntry> entries =
                fieldDescribe.getPicklistValues();

            for (Schema.PicklistEntry entry : entries) {
                if (entry.isActive()) {
                    activeCount++;
                }
            }

            row.put(
                'activePicklistValueCount',
                activeCount
            );

            row.put(
                'totalPicklistValueCount',
                entries.size()
            );

            row.put(
                'restrictedPicklist',
                fieldDescribe.isRestrictedPicklist()
            );

            row.put(
                'dependentPicklist',
                fieldDescribe.isDependentPicklist()
            );
        }

        /**
         * Returns relationship target API names.
         */
        private String referenceTargets(
            Schema.DescribeFieldResult fieldDescribe
        ) {
            List<String> names =
                new List<String>();

            for (
                Schema.SObjectType target :
                fieldDescribe.getReferenceTo()
            ) {
                if (target != null) {
                    names.add(
                        target.getDescribe(
                            SObjectDescribeOptions.DEFERRED
                        ).getName()
                    );
                }
            }

            names.sort();

            return String.join(
                names,
                '; '
            );
        }

        /**
         * Adds explanatory notes for calculated, auto-number,
         * and deprecated fields.
         */
        private String informationalNote(
            Schema.DescribeFieldResult fieldDescribe
        ) {
            String note;

            if (fieldDescribe.isCalculated()) {
                note =
                    TEXT.appendNote(
                        note,
                        'Formula/calculated field; population does not ' +
                        'represent user-entered data'
                    );
            }

            if (fieldDescribe.isAutoNumber()) {
                note =
                    TEXT.appendNote(
                        note,
                        'Auto-number field'
                    );
            }

            if (fieldDescribe.isDeprecatedAndHidden()) {
                note =
                    TEXT.appendNote(
                        note,
                        'Deprecated and hidden'
                    );
            }

            return note;
        }
    }

    /**
     * Shared result mutations for query failures and skipped fields.
     */
    private class CountResultUtil {
        /**
         * Marks fields that could not be counted before the query reserve.
         */
        public void markNotEvaluated(
            CountPlan plan,
            List<String> fieldNames,
            String reason
        ) {
            if (fieldNames == null) {
                return;
            }

            for (String fieldName : fieldNames) {
                Map<String, Object> row =
                    plan.rowsByFieldName.get(fieldName);

                if (row == null) {
                    continue;
                }

                row.put(
                    'usageMethod',
                    'Not evaluated'
                );

                row.put(
                    'note',
                    TEXT.appendNote(
                        (String) row.get('note'),
                        reason
                    )
                );
            }
        }

        /**
         * Marks one field whose aggregate query failed.
         */
        public void markFailure(
            Map<String, Object> row,
            String reason
        ) {
            if (row == null) {
                return;
            }

            row.put(
                'usageMethod',
                'Failed'
            );

            row.put(
                'note',
                TEXT.appendNote(
                    (String) row.get('note'),
                    reason
                )
            );
        }

        /**
         * Copies a bounded String-list range.
         */
        public List<String> slice(
            List<String> source,
            Integer startIndex,
            Integer endIndex
        ) {
            List<String> result =
                new List<String>();

            if (source == null) {
                return result;
            }

            Integer safeStart =
                Math.max(
                    startIndex == null
                        ? 0
                        : startIndex,
                    0
                );

            Integer safeEnd =
                Math.min(
                    endIndex == null
                        ? source.size()
                        : endIndex,
                    source.size()
                );

            for (
                Integer index = safeStart;
                index < safeEnd;
                index++
            ) {
                result.add(source[index]);
            }

            return result;
        }
    }

    /**
     * Executes bounded COUNT(field) queries and isolates unsupported fields.
     */
    private class AggregateCounter {
        private CountResultUtil resultUtil;

        /**
         * Reuses one result helper across all aggregate chunks.
         */
        public AggregateCounter(
            CountResultUtil suppliedResultUtil
        ) {
            resultUtil = suppliedResultUtil;
        }

        /**
         * Starts aggregate processing at the first field.
         */
        public void populate(CountPlan plan) {
            process(plan, 0);
        }

        /**
         * Processes every aggregate field in bounded chunks.
         */
        public void process(
            CountPlan plan,
            Integer startIndex
        ) {
            if (
                startIndex >=
                plan.aggregateFields.size()
            ) {
                return;
            }

            Integer endIndex =
                Math.min(
                    startIndex +
                    AGGREGATE_CHUNK_SIZE,
                    plan.aggregateFields.size()
                );

            run(
                plan,
                resultUtil.slice(
                    plan.aggregateFields,
                    startIndex,
                    endIndex
                )
            );

            process(
                plan,
                endIndex
            );
        }

        /**
         * Executes one aggregate query and recursively splits it
         * when Salesforce rejects an individual field.
         */
        public void run(
            CountPlan plan,
            List<String> fieldNames
        ) {
            if (
                fieldNames == null ||
                fieldNames.isEmpty()
            ) {
                return;
            }

            if (!hasQueryCapacity(1)) {
                resultUtil.markNotEvaluated(
                    plan,
                    fieldNames,
                    'SOQL query limit reached before counting'
                );

                return;
            }

            TEXT.validateApiName(
                plan.objectApiName
            );

            String safeObjectName =
                String.escapeSingleQuotes(
                    plan.objectApiName
                );

            List<String> selectParts =
                new List<String>();

            Map<String, String> fieldByAlias =
                new Map<String, String>();

            for (
                Integer index = 0;
                index < fieldNames.size();
                index++
            ) {
                String fieldName =
                    fieldNames[index];

                TEXT.validateApiName(fieldName);

                String safeFieldName =
                    String.escapeSingleQuotes(fieldName);

                String aliasName =
                    'f' +
                    String.valueOf(index);

                selectParts.add(
                    'COUNT(' +
                    safeFieldName +
                    ') ' +
                    aliasName
                );

                fieldByAlias.put(
                    aliasName,
                    fieldName
                );
            }

            String queryText =
                'SELECT ' +
                String.join(
                    selectParts,
                    ', '
                ) +
                ' FROM ' +
                safeObjectName +
                ' WHERE Id != null';

            try {
                List<AggregateResult> results =
                    Database.query(
                        queryText,
                        USER_ACCESS
                    );

                applyResult(
                    plan,
                    fieldByAlias,
                    results.isEmpty()
                        ? null
                        : results[0]
                );
            } catch (System.QueryException queryException) {
                splitOrFail(
                    plan,
                    fieldNames,
                    queryException
                );
            }
        }

        /**
         * Copies aggregate aliases into their field rows.
         */
        private void applyResult(
            CountPlan plan,
            Map<String, String> fieldByAlias,
            AggregateResult aggregateRow
        ) {
            for (String aliasName : fieldByAlias.keySet()) {
                Map<String, Object> row =
                    plan.rowsByFieldName.get(
                        fieldByAlias.get(aliasName)
                    );

                if (row == null) {
                    continue;
                }

                row.put(
                    'populatedRecords',
                    aggregateRow == null
                        ? 0
                        : TEXT.toInteger(
                            aggregateRow.get(aliasName)
                        )
                );

                row.put(
                    'usageMethod',
                    'COUNT(field)'
                );
            }
        }

        /**
         * Splits a failed aggregate chunk until the unsupported
         * field is isolated.
         */
        private void splitOrFail(
            CountPlan plan,
            List<String> fieldNames,
            System.QueryException queryException
        ) {
            if (fieldNames.size() == 1) {
                resultUtil.markFailure(
                    plan.rowsByFieldName.get(
                        fieldNames[0]
                    ),
                    'COUNT(field) failed: ' +
                    TEXT.cleanMessage(
                        queryException.getMessage()
                    )
                );

                return;
            }

            Integer splitIndex =
                fieldNames.size() / 2;

            run(
                plan,
                resultUtil.slice(
                    fieldNames,
                    0,
                    splitIndex
                )
            );

            run(
                plan,
                resultUtil.slice(
                    fieldNames,
                    splitIndex,
                    fieldNames.size()
                )
            );
        }
    }

    /**
     * Coordinates total-record and field-population aggregate queries.
     */
    private class UsageCounter {
        private CountResultUtil resultUtil =
            new CountResultUtil();

        private AggregateCounter aggregateCounter =
            new AggregateCounter(resultUtil);

        /**
         * Counts all records readable by the running user.
         */
        public Integer countRecords(String objectApiName) {
            TEXT.validateApiName(objectApiName);

            String safeObjectName =
                String.escapeSingleQuotes(objectApiName);

            String queryText =
                'SELECT COUNT(Id) recordCount FROM ' +
                safeObjectName +
                ' WHERE Id != null';

            List<AggregateResult> results =
                Database.query(
                    queryText,
                    USER_ACCESS
                );

            return results.isEmpty()
                ? 0
                : TEXT.toInteger(
                    results[0].get('recordCount')
                );
        }

        /**
         * Executes the remaining batched population queries.
         */
        public void populate(CountPlan plan) {
            aggregateCounter.populate(plan);
        }

        /**
         * Exposes the aggregate service only to focused controller tests.
         */
        public AggregateCounter aggregate() {
            return aggregateCounter;
        }
    }

    /**
     * Values used while finalizing object-level summary counters.
     */
    private class ScoringContext {
        public Integer totalRecords;
        public Decimal threshold;
        public Boolean descriptionAvailable;
    }

    /**
     * Calculates documentation, usage status, and summary counters.
     */
    private class ResultScorer {
        /**
         * Calculates the two-part description and help-text score.
         */
        public void scoreDocumentation(
            Map<String, Object> row
        ) {
            Boolean descriptionAvailable =
                (Boolean) row.get(
                    'descriptionAuditAvailable'
                );

            Boolean hasDescription =
                (Boolean) row.get(
                    'hasDescription'
                );

            Boolean hasHelpText =
                (Boolean) row.get(
                    'hasHelpText'
                );

            List<String> issues =
                new List<String>();

            if (hasHelpText != true) {
                issues.add(
                    'Missing help text'
                );
            }

            if (descriptionAvailable != true) {
                issues.add(
                    'Description audit unavailable'
                );

                row.put(
                    'documentationScore',
                    null
                );

                row.put(
                    'metadataAuditStatus',
                    String.join(
                        issues,
                        '; '
                    )
                );

                return;
            }

            if (hasDescription != true) {
                issues.add(
                    'Missing description'
                );
            }

            Integer score =
                (
                    hasDescription == true
                        ? 50
                        : 0
                ) +
                (
                    hasHelpText == true
                        ? 50
                        : 0
                );

            row.put(
                'documentationScore',
                score
            );

            row.put(
                'metadataAuditStatus',
                issues.isEmpty()
                    ? 'Complete'
                    : String.join(
                        issues,
                        '; '
                    )
            );
        }

        /**
         * Converts one populated count into its percentage and status.
         */
        public void scoreUsage(
            Map<String, Object> row,
            Integer totalRecords,
            Decimal threshold
        ) {
            if (row == null) {
                return;
            }

            row.put(
                'totalRecords',
                totalRecords
            );

            if (
                (Boolean) row.get(
                    'populationAnalysisApplicable'
                ) != true
            ) {
                row.put(
                    'populationPercent',
                    null
                );

                if (
                    String.isBlank(
                        (String) row.get(
                            'usageStatus'
                        )
                    )
                ) {
                    row.put(
                        'usageStatus',
                        'Not applicable'
                    );
                }

                return;
            }

            Integer populatedRecords =
                (Integer) row.get(
                    'populatedRecords'
                );

            if (
                populatedRecords == null ||
                totalRecords == null
            ) {
                row.put(
                    'populationPercent',
                    null
                );

                row.put(
                    'usageStatus',
                    'Not evaluated'
                );

                return;
            }

            if (totalRecords == 0) {
                row.put(
                    'populationPercent',
                    Decimal.valueOf('0')
                );

                row.put(
                    'usageStatus',
                    'Object has no records'
                );

                return;
            }

            Decimal percentage =
                (
                    Decimal.valueOf(
                        String.valueOf(populatedRecords)
                    ) *
                    100 /
                    Decimal.valueOf(
                        String.valueOf(totalRecords)
                    )
                ).setScale(2);

            Decimal normalizedThreshold =
                threshold == null
                    ? 0
                    : threshold;

            row.put(
                'populationPercent',
                percentage
            );

            if (populatedRecords == 0) {
                row.put(
                    'usageStatus',
                    'No data'
                );
            } else if (
                percentage < normalizedThreshold
            ) {
                row.put(
                    'usageStatus',
                    'Low usage'
                );
            } else {
                row.put(
                    'usageStatus',
                    'Used'
                );
            }
        }

        /**
         * Scores every row and calculates object-level counters.
         */
        public Map<String, Object> finalizeResult(
            List<Map<String, Object>> rows,
            ScoringContext context
        ) {
            Map<String, Integer> counts =
                new Map<String, Integer>{
                    'fieldsWithData' => 0,
                    'fieldsWithNoData' => 0,
                    'lowUsageFields' => 0,
                    'fieldsNotEvaluated' => 0,
                    'populationEligibleFields' => 0,
                    'checkboxFieldsExcluded' => 0,
                    'otherPopulationFieldsNotApplicable' => 0,
                    'fieldsMissingDescription' => 0,
                    'fieldsMissingHelpText' => 0,
                    'fullyDocumentedFields' => 0
                };

            for (Map<String, Object> row : rows) {
                scoreUsage(
                    row,
                    context.totalRecords,
                    context.threshold
                );

                Boolean applicable =
                    (Boolean) row.get(
                        'populationAnalysisApplicable'
                    );

                Boolean checkboxField =
                    (Boolean) row.get(
                        'checkboxField'
                    );

                Integer populatedRecords =
                    (Integer) row.get(
                        'populatedRecords'
                    );

                if (applicable == true) {
                    increment(
                        counts,
                        'populationEligibleFields'
                    );

                    if (populatedRecords == null) {
                        increment(
                            counts,
                            'fieldsNotEvaluated'
                        );
                    } else if (populatedRecords == 0) {
                        increment(
                            counts,
                            'fieldsWithNoData'
                        );
                    } else {
                        increment(
                            counts,
                            'fieldsWithData'
                        );
                    }

                    if (
                        (String) row.get(
                            'usageStatus'
                        ) ==
                        'Low usage'
                    ) {
                        increment(
                            counts,
                            'lowUsageFields'
                        );
                    }
                } else if (checkboxField == true) {
                    increment(
                        counts,
                        'checkboxFieldsExcluded'
                    );
                } else {
                    increment(
                        counts,
                        'otherPopulationFieldsNotApplicable'
                    );
                }

                if (
                    context.descriptionAvailable == true &&
                    (Boolean) row.get(
                        'hasDescription'
                    ) != true
                ) {
                    increment(
                        counts,
                        'fieldsMissingDescription'
                    );
                }

                if (
                    (Boolean) row.get(
                        'hasHelpText'
                    ) != true
                ) {
                    increment(
                        counts,
                        'fieldsMissingHelpText'
                    );
                }

                if (
                    (Integer) row.get(
                        'documentationScore'
                    ) ==
                    100
                ) {
                    increment(
                        counts,
                        'fullyDocumentedFields'
                    );
                }
            }

            Map<String, Object> result =
                new Map<String, Object>();

            for (String key : counts.keySet()) {
                result.put(
                    key,
                    counts.get(key)
                );
            }

            return result;
        }

        /**
         * Increments one initialized summary counter.
         */
        private void increment(
            Map<String, Integer> counts,
            String key
        ) {
            counts.put(
                key,
                counts.get(key) + 1
            );
        }
    }

    /**
     * Coordinates count, metadata, row-building, and scoring services.
     */
    private class AuditRunner {
        private Schema.DescribeSObjectResult objectDescribe;
        private SchemaCatalog catalog;
        private Config config;

        /**
         * Retains the validated object and request-level services.
         */
        public AuditRunner(
            Schema.DescribeSObjectResult suppliedDescribe,
            SchemaCatalog suppliedCatalog,
            Config suppliedConfig
        ) {
            objectDescribe = suppliedDescribe;
            catalog = suppliedCatalog;
            config = suppliedConfig;
        }

        /**
         * Executes the complete audit for one object.
         */
        public Map<String, Object> run() {
            String objectApiName =
                objectDescribe.getName();

            UsageCounter counter =
                new UsageCounter();

            Integer totalRecords;

            try {
                totalRecords =
                    counter.countRecords(
                        objectApiName
                    );
            } catch (System.QueryException queryException) {
                throw TEXT.handled(
                    'Unable to count records for ' +
                    objectApiName +
                    ': ' +
                    TEXT.cleanMessage(
                        queryException.getMessage()
                    )
                );
            }

            MetadataBundle metadata =
                new MetadataLoader().load(
                    objectApiName,
                    catalog
                );

            BuildResult build =
                new FieldBuilder().build(
                    objectDescribe,
                    totalRecords,
                    metadata
                );

            counter.populate(
                build.plan
            );

            ScoringContext scoringContext =
                new ScoringContext();

            scoringContext.totalRecords =
                totalRecords;

            scoringContext.threshold =
                config.lowUsageThresholdPercent;

            scoringContext.descriptionAvailable =
                metadata.descriptionAvailable;

            Map<String, Object> summary =
                SCORER.finalizeResult(
                    build.rows,
                    scoringContext
                );

            return new Map<String, Object>{
                'objectApiName' => objectApiName,
                'objectLabel' =>
                    objectDescribe.getLabel(),
                'totalRecords' => totalRecords,
                'totalFields' =>
                    build.rows.size(),
                'fieldsWithData' =>
                    summary.get(
                        'fieldsWithData'
                    ),
                'fieldsWithNoData' =>
                    summary.get(
                        'fieldsWithNoData'
                    ),
                'lowUsageFields' =>
                    summary.get(
                        'lowUsageFields'
                    ),
                'fieldsNotEvaluated' =>
                    summary.get(
                        'fieldsNotEvaluated'
                    ),
                'populationEligibleFields' =>
                    summary.get(
                        'populationEligibleFields'
                    ),
                'checkboxFieldsExcluded' =>
                    summary.get(
                        'checkboxFieldsExcluded'
                    ),
                'otherPopulationFieldsNotApplicable' =>
                    summary.get(
                        'otherPopulationFieldsNotApplicable'
                    ),
                'fieldsMissingDescription' =>
                    summary.get(
                        'fieldsMissingDescription'
                    ),
                'fieldsMissingHelpText' =>
                    summary.get(
                        'fieldsMissingHelpText'
                    ),
                'fullyDocumentedFields' =>
                    summary.get(
                        'fullyDocumentedFields'
                    ),
                'descriptionAuditAvailable' =>
                    metadata.descriptionAvailable,
                'historyTrackingAuditAvailable' =>
                    metadata.historyTrackingAvailable,
                'warnings' =>
                    metadata.warnings,
                'fields' =>
                    build.rows
            };
        }
    }

    /**
     * Shared validation, formatting, conversion, and client-safe errors.
     */
    private class TextUtil {
        /**
         * Rejects dynamic identifiers that do not match Salesforce
         * object or field API-name syntax.
         */
        public void validateApiName(String apiName) {
            if (
                String.isBlank(apiName) ||
                !Pattern.matches(
                    SAFE_API_NAME_PATTERN,
                    apiName
                )
            ) {
                throw new IllegalArgumentException(
                    'Unsafe Salesforce API name: ' +
                    cleanMessage(apiName)
                );
            }
        }

        /**
         * Returns the final DurableId segment used by field Setup routes.
         */
        public String extractSetupFieldId(String durableId) {
            if (String.isBlank(durableId)) {
                return null;
            }

            List<String> parts =
                durableId.split('\\.');

            return parts.isEmpty()
                ? durableId
                : parts[
                    parts.size() - 1
                ];
        }

        /**
         * Converts internal Field Usage values into display labels.
         */
        public String formatFieldUsage(String value) {
            if (String.isBlank(value)) {
                return '';
            }

            return value.equalsIgnoreCase(
                'DeprecateCandidate'
            )
                ? 'Deprecate Candidate'
                : value;
        }

        /**
         * Normalizes semicolon-delimited compliance categories.
         */
        public String formatCompliance(String value) {
            if (String.isBlank(value)) {
                return '';
            }

            List<String> categories =
                new List<String>();

            for (String category : value.split(';')) {
                if (!String.isBlank(category)) {
                    categories.add(
                        category.trim()
                    );
                }
            }

            return String.join(
                categories,
                '; '
            );
        }

        /**
         * Returns an empty display value for null or blank metadata.
         */
        public String valueOrEmpty(String value) {
            return String.isBlank(value)
                ? ''
                : value;
        }

        /**
         * Converts a dynamic value to String while preserving null.
         */
        public String stringValue(Object value) {
            return value == null
                ? null
                : String.valueOf(value);
        }

        /**
         * Converts an aggregate result into an Integer.
         */
        public Integer toInteger(Object value) {
            return value == null
                ? 0
                : Integer.valueOf(
                    String.valueOf(value)
                );
        }

        /**
         * Adds one note without duplicate separators.
         */
        public String appendNote(
            String existingNote,
            String newNote
        ) {
            if (String.isBlank(newNote)) {
                return existingNote;
            }

            return String.isBlank(existingNote)
                ? newNote
                : existingNote +
                    ' | ' +
                    newNote;
        }

        /**
         * Creates a client-safe exception whose message is testable.
         */
        public AuraHandledException handled(String message) {
            String safeMessage =
                cleanMessage(message);

            AuraHandledException exceptionValue =
                new AuraHandledException(
                    safeMessage
                );

            exceptionValue.setMessage(
                safeMessage
            );

            return exceptionValue;
        }

        /**
         * Removes line breaks and caps client-visible diagnostics.
         */
        public String cleanMessage(String message) {
            if (message == null) {
                return '';
            }

            String cleaned =
                message
                    .replace('\n', ' ')
                    .replace('\r', ' ');

            return cleaned.length() > 300
                ? cleaned.substring(
                    0,
                    300
                )
                : cleaned;
        }
    }

    /**
     * Preserves a small SOQL reserve for framework and error handling.
     */
    private static Boolean hasQueryCapacity(Integer queriesNeeded) {
        if (
            queriesNeeded == null ||
            queriesNeeded < 0
        ) {
            return false;
        }

        Integer reserve =
            queryLimitReserveOverride == null
                ? QUERY_LIMIT_RESERVE
                : queryLimitReserveOverride;

        return (
            Limits.getQueries() +
            queriesNeeded
        ) <= (
            Limits.getLimitQueries() -
            reserve
        );
    }

    // ---------------------------------------------------------------------
    // Focused test seams.
    //
    // These methods expose only primitives, schema tokens, lists, and maps.
    // The test never constructs or references private nested controller types.
    // ---------------------------------------------------------------------

    @TestVisible
    private static Map<String, Object> testParseConfig(
        String jsonValue
    ) {
        return new ConfigParser()
            .parse(jsonValue)
            .toMap();
    }

    @TestVisible
    private static Boolean testIsSystemLikeObject(
        String objectApiName
    ) {
        return new SchemaCatalog(
            new Map<String, Schema.SObjectType>(),
            new Config()
        ).isSystemLike(objectApiName);
    }

    @TestVisible
    private static Map<String, Object> testBuildFieldRow(
        String objectApiName,
        String fieldApiName
    ) {
        return testBuildFieldRowWithMetadata(
            objectApiName,
            fieldApiName,
            null
        );
    }

    @TestVisible
    private static Map<String, Object> testBuildFieldRowWithMetadata(
        String objectApiName,
        String fieldApiName,
        Map<String, Object> suppliedMetadata
    ) {
        Config config =
            new Config();

        config.includeSystemObjects =
            true;

        SchemaCatalog catalog =
            new SchemaCatalog(
                Schema.getGlobalDescribe(),
                config
            );

        Schema.SObjectType objectType =
            catalog.resolve(objectApiName);

        if (
            objectType == null ||
            String.isBlank(fieldApiName)
        ) {
            return null;
        }

        Schema.DescribeSObjectResult objectDescribe =
            objectType.getDescribe(
                SObjectDescribeOptions.DEFERRED
            );

        Schema.SObjectField fieldToken =
            objectDescribe
                .fields
                .getMap()
                .get(fieldApiName);

        if (fieldToken == null) {
            return null;
        }

        MetadataBundle metadata =
            new MetadataBundle();

        if (suppliedMetadata != null) {
            metadata.descriptionAvailable =
                true;

            metadata.historyTrackingAvailable =
                true;

            metadata.classificationAvailable =
                true;

            metadata.valuesByField.put(
                fieldToken
                    .getDescribe()
                    .getName()
                    .toLowerCase(),
                suppliedMetadata
            );
        }

        FieldBuildContext context =
            new FieldBuildContext();

        context.objectDescribe =
            objectDescribe;

        context.totalRecords =
            0;

        context.metadata =
            metadata;

        FieldBuilder builder =
            new FieldBuilder();

        Map<String, Object> row =
            builder.buildRow(
                context,
                fieldToken.getDescribe()
            );

        CountPlan plan =
            new CountPlan();

        plan.objectApiName =
            objectApiName;

        builder.assignPopulationStrategy(
            plan,
            fieldToken.getDescribe(),
            row
        );

        return row;
    }

    @TestVisible
    private static Map<String, Object> testScoreUsage(
        Map<String, Object> inputValues
    ) {
        Map<String, Object> values =
            inputValues == null
                ? new Map<String, Object>()
                : inputValues;

        Map<String, Object> row =
            new Map<String, Object>{
                'populationAnalysisApplicable' =>
                    values.get(
                        'populationAnalysisApplicable'
                    ),
                'populatedRecords' =>
                    values.get(
                        'populatedRecords'
                    ),
                'usageStatus' =>
                    values.get(
                        'usageStatus'
                    )
            };

        SCORER.scoreUsage(
            row,
            (Integer) values.get(
                'totalRecords'
            ),
            (Decimal) values.get(
                'threshold'
            )
        );

        return row;
    }

    @TestVisible
    private static Map<String, Object> testDocumentationScenario(
        Boolean descriptionAvailable,
        Boolean hasDescription,
        Boolean hasHelpText
    ) {
        Map<String, Object> row =
            new Map<String, Object>{
                'descriptionAuditAvailable' =>
                    descriptionAvailable,
                'hasDescription' =>
                    hasDescription,
                'hasHelpText' =>
                    hasHelpText,
                'documentationScore' =>
                    null,
                'metadataAuditStatus' =>
                    null
            };

        SCORER.scoreDocumentation(row);

        return row;
    }

    @TestVisible
    private static Map<String, Map<String, Object>> testRunAggregate(
        String objectApiName,
        List<String> fieldNames
    ) {
        CountPlan plan =
            new CountPlan();

        plan.objectApiName =
            objectApiName;

        List<String> safeFields =
            fieldNames == null
                ? new List<String>()
                : fieldNames;

        for (String fieldName : safeFields) {
            plan.rowsByFieldName.put(
                fieldName,
                new Map<String, Object>{
                    'populationAnalysisApplicable' => true,
                    'populatedRecords' => null,
                    'usageMethod' => null,
                    'usageStatus' => null,
                    'note' => null
                }
            );
        }

        UsageCounter counter =
            new UsageCounter();

        counter.aggregate().run(
            plan,
            safeFields
        );

        return plan.rowsByFieldName;
    }

    @TestVisible
    private static void testSetQueryReserve(
        Integer reserveValue
    ) {
        queryLimitReserveOverride =
            reserveValue;
    }

    @TestVisible
    private static Map<String, Object> testUtilities(
        Map<String, Object> inputValues
    ) {
        Map<String, Object> values =
            inputValues == null
                ? new Map<String, Object>()
                : inputValues;

        return new Map<String, Object>{
            'systemLike' =>
                testIsSystemLikeObject(
                    (String) values.get(
                        'objectApiName'
                    )
                ),
            'setupFieldId' =>
                TEXT.extractSetupFieldId(
                    (String) values.get(
                        'durableId'
                    )
                ),
            'fieldUsage' =>
                TEXT.formatFieldUsage(
                    (String) values.get(
                        'fieldUsage'
                    )
                ),
            'compliance' =>
                TEXT.formatCompliance(
                    (String) values.get(
                        'compliance'
                    )
                ),
            'note' =>
                TEXT.appendNote(
                    (String) values.get(
                        'existingNote'
                    ),
                    (String) values.get(
                        'newNote'
                    )
                ),
            'message' =>
                TEXT.cleanMessage(
                    (String) values.get(
                        'message'
                    )
                ),
            'queryCapacity' =>
                hasQueryCapacity(
                    (Integer) values.get(
                        'queriesNeeded'
                    )
                )
        };
    }

    @TestVisible
    private static String testValidateApiName(String apiName) {
        TEXT.validateApiName(apiName);
        return apiName;
    }

    @TestVisible
    private static Boolean testIsRequired(
        Schema.DescribeFieldResult fieldDescribe
    ) {
        return new FieldBuilder()
            .isRequired(fieldDescribe);
    }

    @TestVisible
    private static List<String> testMetadataWarningsWithEmptySchema(
        String objectApiName
    ) {
        Config config =
            new Config();

        config.includeSystemObjects =
            true;

        MetadataBundle bundle =
            new MetadataLoader().load(
                objectApiName,
                new SchemaCatalog(
                    new Map<String, Schema.SObjectType>(),
                    config
                )
            );

        return bundle.warnings;
    }

    @TestVisible
    private static Boolean testHasReadableMetadataFields(
        Map<String, Schema.SObjectField> fieldMap
    ) {
        return new MetadataLoader()
            .hasReadableFields(fieldMap);
    }
}