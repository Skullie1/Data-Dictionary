/**
 * Regression tests for DataDictionaryController.
 *
 * Intent:
 * - Validate the LWC-facing Map contract.
 * - Cover configuration, object selection, metadata mapping, population
 *   counting, checkbox exclusion, scoring, and client-safe failures.
 * - Use isolated test data and explicit assertion messages.
 * - Avoid suppression directives and private nested-type references.
 * - Keep every controller method reference on one line so Apex resolves
 *   the class name correctly.
 */
@IsTest
private with sharing class DataDictionaryControllerTest {
    private static final String ORGANIZATION_OBJECT =
        'Organization';

    private static final String CONTACT_OBJECT =
        'Contact';

    /**
     * Verifies object inventory, initial selections, and warnings.
     */
    @IsTest
    static void bootstrapHonorsConfigurationAndWarnings() {
        String configurationJson =
            JSON.serialize(
                new Map<String, Object>{
                    'objectApiNames' =>
                        new List<String>{
                            ORGANIZATION_OBJECT,
                            'organization',
                            CONTACT_OBJECT,
                            'DefinitelyMissing__c'
                        },
                    'includeStandardObjects' =>
                        true,
                    'includeCustomObjects' =>
                        true,
                    'includeSystemObjects' =>
                        false,
                    'lowUsageThresholdPercent' =>
                        17
                }
            );

        Test.startTest();

        Map<String, Object> response =
            DataDictionaryController.getBootstrap(
                configurationJson
            );

        Test.stopTest();

        List<Map<String, Object>> options =
            mapList(
                response,
                'objects'
            );

        List<String> selectedNames =
            stringList(
                response,
                'selectedObjectApiNames'
            );

        List<String> warnings =
            stringList(
                response,
                'warnings'
            );

        Map<String, Object> organizationOption =
            indexMaps(
                options,
                'value'
            ).get(
                ORGANIZATION_OBJECT
            );

        System.Assert.areEqual(
            Decimal.valueOf('17'),
            (Decimal) response.get(
                'lowUsageThresholdPercent'
            ),
            'The configured low-usage threshold should be returned unchanged.'
        );

        System.Assert.areEqual(
            2,
            selectedNames.size(),
            'Configured object names should be de-duplicated case-insensitively.'
        );

        System.Assert.areEqual(
            1,
            warnings.size(),
            'The unknown configured object should produce one warning.'
        );

        System.Assert.isTrue(
            warnings[0].contains(
                'DefinitelyMissing__c'
            ),
            'The warning should identify the unknown object.'
        );

        System.Assert.isNotNull(
            organizationOption,
            'Organization should appear in the readable object inventory.'
        );

        System.Assert.areEqual(
            'Standard',
            (String) organizationOption.get(
                'objectTypeLabel'
            ),
            'Organization should be labeled as a standard object.'
        );

        System.Assert.areEqual(
            false,
            (Boolean) organizationOption.get(
                'customObject'
            ),
            'Organization should not be marked as custom.'
        );
    }

    /**
     * Verifies view-all behavior, object filters, defaults,
     * and invalid JSON.
     */
    @IsTest
    static void bootstrapSupportsViewAllAndValidation() {
        Map<String, Object> viewAll =
            DataDictionaryController.getBootstrap(
                JSON.serialize(
                    new Map<String, Object>{
                        'includeStandardObjects' =>
                            true,
                        'includeCustomObjects' =>
                            false,
                        'includeSystemObjects' =>
                            false
                    }
                )
            );

        List<Map<String, Object>> viewAllOptions =
            mapList(
                viewAll,
                'objects'
            );

        System.Assert.isTrue(
            containsMapValue(
                viewAllOptions,
                'value',
                ORGANIZATION_OBJECT
            ),
            'View-all mode should include readable standard objects.'
        );

        System.Assert.isFalse(
            containsMapValue(
                viewAllOptions,
                'value',
                'FieldDefinition'
            ),
            'System metadata objects should be hidden by default.'
        );

        System.Assert.areEqual(
            0,
            stringList(
                viewAll,
                'selectedObjectApiNames'
            ).size(),
            'View-all mode should not preselect every object.'
        );

        System.Assert.areEqual(
            Decimal.valueOf('5'),
            (Decimal) viewAll.get(
                'lowUsageThresholdPercent'
            ),
            'An omitted threshold should use the stable default.'
        );

        Map<String, Object> excluded =
            DataDictionaryController.getBootstrap(
                JSON.serialize(
                    new Map<String, Object>{
                        'objectApiNames' =>
                            new List<String>{
                                ORGANIZATION_OBJECT
                            },
                        'includeStandardObjects' =>
                            false,
                        'includeCustomObjects' =>
                            true,
                        'includeSystemObjects' =>
                            false
                    }
                )
            );

        System.Assert.isFalse(
            containsMapValue(
                mapList(
                    excluded,
                    'objects'
                ),
                'value',
                ORGANIZATION_OBJECT
            ),
            'Organization should be excluded when standard objects are disabled.'
        );

        System.Assert.areEqual(
            1,
            stringList(
                excluded,
                'warnings'
            ).size(),
            'An explicitly configured but excluded object should produce one warning.'
        );

        try {
            DataDictionaryController.getBootstrap(
                '{invalid-json'
            );

            System.Assert.fail(
                'Invalid JSON should throw AuraHandledException.'
            );
        } catch (AuraHandledException expectedException) {
            System.Assert.isTrue(
                expectedException
                    .getMessage()
                    .contains(
                        'Invalid configuration JSON'
                    ),
                'The exception should explain the configuration JSON problem.'
            );
        }
    }

    /**
     * Verifies a nonempty object audit and summary invariants.
     */
    @IsTest
    static void auditOrganizationReturnsCountsAndMetadata() {
        Test.startTest();

        Map<String, Object> result =
            DataDictionaryController.auditObject(
                ORGANIZATION_OBJECT,
                configurationFor(
                    ORGANIZATION_OBJECT,
                    50
                )
            );

        Test.stopTest();

        Integer totalRecords =
            (Integer) result.get(
                'totalRecords'
            );

        List<Map<String, Object>> fields =
            mapList(
                result,
                'fields'
            );

        Map<String, Object> idRow =
            indexMaps(
                fields,
                'fieldApiName'
            ).get(
                'Id'
            );

        System.Assert.areEqual(
            ORGANIZATION_OBJECT,
            (String) result.get(
                'objectApiName'
            ),
            'The audit should return the canonical object API name.'
        );

        System.Assert.isTrue(
            totalRecords > 0,
            'Organization should expose at least the current organization row.'
        );

        System.Assert.areEqual(
            fields.size(),
            (Integer) result.get(
                'totalFields'
            ),
            'The summary field count should match the returned rows.'
        );

        System.Assert.isNotNull(
            idRow,
            'The Id field should always be present.'
        );

        System.Assert.areEqual(
            true,
            (Boolean) idRow.get(
                'populationAnalysisApplicable'
            ),
            'Id should participate in population analysis.'
        );

        System.Assert.areEqual(
            totalRecords,
            (Integer) idRow.get(
                'populatedRecords'
            ),
            'COUNT(Id) should equal the object record count.'
        );

        System.Assert.areEqual(
            Decimal.valueOf('100.00'),
            (Decimal) idRow.get(
                'populationPercent'
            ),
            'Id should be populated on every record.'
        );

        System.Assert.areEqual(
            'Used',
            (String) idRow.get(
                'usageStatus'
            ),
            'Id should be classified as used.'
        );

        System.Assert.isNotNull(
            idRow.get(
                'fieldUsage'
            ),
            'Field Usage should never be null in the client contract.'
        );

        System.Assert.isNotNull(
            idRow.get(
                'dataSensitivityLevel'
            ),
            'Data Sensitivity Level should never be null in the client contract.'
        );

        System.Assert.isNotNull(
            idRow.get(
                'complianceCategorization'
            ),
            'Compliance Categorization should never be null in the client contract.'
        );

        Integer populationBuckets =
            (Integer) result.get(
                'fieldsWithData'
            ) +
            (Integer) result.get(
                'fieldsWithNoData'
            ) +
            (Integer) result.get(
                'fieldsNotEvaluated'
            );

        System.Assert.areEqual(
            (Integer) result.get(
                'populationEligibleFields'
            ),
            populationBuckets,
            'Every population-eligible field should be in one population bucket.'
        );
    }

    /**
     * Verifies a zero-record object and the empty-object status.
     */
    @IsTest
    static void auditZeroRecordObjectUsesDistinctStatus() {
        Test.startTest();

        Map<String, Object> result =
            DataDictionaryController.auditObject(
                CONTACT_OBJECT,
                configurationFor(
                    CONTACT_OBJECT,
                    5
                )
            );

        Test.stopTest();

        Map<String, Object> lastNameRow =
            indexMaps(
                mapList(
                    result,
                    'fields'
                ),
                'fieldApiName'
            ).get(
                'LastName'
            );

        System.Assert.areEqual(
            0,
            (Integer) result.get(
                'totalRecords'
            ),
            'Contact should have no rows in an isolated test context.'
        );

        System.Assert.isNotNull(
            lastNameRow,
            'Contact.LastName should be present in the audit.'
        );

        System.Assert.areEqual(
            0,
            (Integer) lastNameRow.get(
                'populatedRecords'
            ),
            'A zero-record object should return a zero populated count.'
        );

        System.Assert.areEqual(
            'Object has no records',
            (String) lastNameRow.get(
                'usageStatus'
            ),
            'The status should distinguish an empty object from an unused field.'
        );
    }

    /**
     * Verifies checkbox metadata remains while value analysis
     * is excluded.
     */
    @IsTest
    static void checkboxFieldsAreExcludedFromPopulationAnalysis() {
        Test.startTest();

        Map<String, Object> result =
            DataDictionaryController.auditObject(
                'User',
                configurationFor(
                    'User',
                    5
                )
            );

        Test.stopTest();

        Map<String, Object> checkboxRow =
            indexMaps(
                mapList(
                    result,
                    'fields'
                ),
                'fieldApiName'
            ).get(
                'IsActive'
            );

        System.Assert.isNotNull(
            checkboxRow,
            'User.IsActive should remain in the data dictionary.'
        );

        System.Assert.areEqual(
            true,
            (Boolean) checkboxRow.get(
                'checkboxField'
            ),
            'The row should identify the field as a checkbox.'
        );

        System.Assert.areEqual(
            false,
            (Boolean) checkboxRow.get(
                'populationAnalysisApplicable'
            ),
            'Checkboxes should be excluded from population analysis.'
        );

        System.Assert.areEqual(
            'Excluded by design',
            (String) checkboxRow.get(
                'usageMethod'
            ),
            'The usage method should make the intentional exclusion explicit.'
        );

        System.Assert.areEqual(
            'Not applicable',
            (String) checkboxRow.get(
                'usageStatus'
            ),
            'Checkbox exclusion should not be reported as an audit failure.'
        );

        System.Assert.isNull(
            checkboxRow.get(
                'populatedRecords'
            ),
            'The audit should not execute or return a checkbox TRUE count.'
        );

        System.Assert.isTrue(
            ((String) checkboxRow.get(
                'note'
            )).contains(
                'outside this audit scope'
            ),
            'The row note should explain the checkbox scope decision.'
        );

        System.Assert.isTrue(
            (Integer) result.get(
                'checkboxFieldsExcluded'
            ) > 0,
            'The object summary should count excluded checkbox fields.'
        );
    }

    /**
     * Verifies client-safe validation failures.
     */
    @IsTest
    static void publicMethodsRejectInvalidInputs() {
        assertAuraFailure(
            null,
            '{}',
            'Object API name is required'
        );

        assertAuraFailure(
            'DefinitelyMissing__c',
            '{}',
            'Unknown object'
        );

        assertAuraFailure(
            ORGANIZATION_OBJECT,
            JSON.serialize(
                new Map<String, Object>{
                    'includeStandardObjects' =>
                        false,
                    'includeCustomObjects' =>
                        true,
                    'includeSystemObjects' =>
                        false
                }
            ),
            'not eligible'
        );
    }

    /**
     * Verifies normalization, formatting, and identifier
     * validation seams.
     */
    @IsTest
    static void configurationAndUtilitySeamsCoverBoundaries() {
        Map<String, Object> parsed =
            DataDictionaryController.testParseConfig(
                JSON.serialize(
                    new Map<String, Object>{
                        'objectApiNames' =>
                            new List<String>{
                                ' Account ',
                                'account',
                                null,
                                '',
                                CONTACT_OBJECT
                            },
                        'lowUsageThresholdPercent' =>
                            150
                    }
                )
            );

        System.Assert.areEqual(
            new List<String>{
                'Account',
                CONTACT_OBJECT
            },
            (List<String>) parsed.get(
                'objectApiNames'
            ),
            'Configured names should be trimmed and de-duplicated.'
        );

        System.Assert.areEqual(
            Decimal.valueOf('100'),
            (Decimal) parsed.get(
                'lowUsageThresholdPercent'
            ),
            'Thresholds above 100 should clamp to 100.'
        );

        Map<String, Object> negative =
            DataDictionaryController.testParseConfig(
                '{"lowUsageThresholdPercent":-1}'
            );

        System.Assert.areEqual(
            Decimal.valueOf('0'),
            (Decimal) negative.get(
                'lowUsageThresholdPercent'
            ),
            'Negative thresholds should clamp to zero.'
        );

        Map<String, Object> utilityValues =
            DataDictionaryController.testUtilities(
                new Map<String, Object>{
                    'objectApiName' =>
                        'AccountHistory',
                    'durableId' =>
                        'Account.00NABC',
                    'fieldUsage' =>
                        'DeprecateCandidate',
                    'compliance' =>
                        'GDPR; HIPAA;',
                    'existingNote' =>
                        'First',
                    'newNote' =>
                        'Second',
                    'message' =>
                        repeatCharacter(
                            'x',
                            350
                        ),
                    'queriesNeeded' =>
                        null
                }
            );

        System.Assert.areEqual(
            true,
            (Boolean) utilityValues.get(
                'systemLike'
            ),
            'History objects should be classified as technical.'
        );

        System.Assert.areEqual(
            '00NABC',
            (String) utilityValues.get(
                'setupFieldId'
            ),
            'The final durable-ID segment should be extracted.'
        );

        System.Assert.areEqual(
            'Deprecate Candidate',
            (String) utilityValues.get(
                'fieldUsage'
            ),
            'Internal Field Usage values should be humanized.'
        );

        System.Assert.areEqual(
            'GDPR; HIPAA',
            (String) utilityValues.get(
                'compliance'
            ),
            'Compliance categories should be normalized.'
        );

        System.Assert.areEqual(
            'First | Second',
            (String) utilityValues.get(
                'note'
            ),
            'Notes should use one stable delimiter.'
        );

        System.Assert.areEqual(
            300,
            ((String) utilityValues.get(
                'message'
            )).length(),
            'Client-facing diagnostics should be capped at 300 characters.'
        );

        System.Assert.areEqual(
            false,
            (Boolean) utilityValues.get(
                'queryCapacity'
            ),
            'A null query requirement should never be valid capacity.'
        );

        System.Assert.areEqual(
            'Account__c',
            DataDictionaryController.testValidateApiName(
                'Account__c'
            ),
            'A valid Salesforce API name should pass validation unchanged.'
        );

        try {
            DataDictionaryController.testValidateApiName(
                'Account WHERE Name != null'
            );

            System.Assert.fail(
                'Unsafe dynamic identifiers must be rejected.'
            );
        } catch (IllegalArgumentException expectedException) {
            System.Assert.isTrue(
                expectedException
                    .getMessage()
                    .contains(
                        'Unsafe Salesforce API name'
                    ),
                'The validation message should identify the unsafe input.'
            );
        }

        System.Assert.isTrue(
            !DataDictionaryController.testMetadataWarningsWithEmptySchema(
                ORGANIZATION_OBJECT
            ).isEmpty(),
            'An empty schema context should produce a metadata warning.'
        );

        System.Assert.isFalse(
            DataDictionaryController.testHasReadableMetadataFields(
                Contact.SObjectType
                    .getDescribe()
                    .fields
                    .getMap()
            ),
            'A business object should not satisfy FieldDefinition requirements.'
        );
    }

    /**
     * Verifies field-type mapping and controlled governance metadata.
     */
    @IsTest
    static void fieldRowSeamsCoverMetadataAndTechnicalTypes() {
        Map<String, Object> picklistRow =
            DataDictionaryController.testBuildFieldRow(
                CONTACT_OBJECT,
                'LeadSource'
            );

        Map<String, Object> referenceRow =
            DataDictionaryController.testBuildFieldRow(
                CONTACT_OBJECT,
                'AccountId'
            );

        Map<String, Object> autoNumberRow =
            DataDictionaryController.testBuildFieldRow(
                'Case',
                'CaseNumber'
            );

        Map<String, Object> checkboxRow =
            DataDictionaryController.testBuildFieldRow(
                'User',
                'IsActive'
            );

        Map<String, Object> phoneRow =
            DataDictionaryController.testBuildFieldRowWithMetadata(
                CONTACT_OBJECT,
                'Phone',
                new Map<String, Object>{
                    'setupFieldId' =>
                        '00NABC',
                    'description' =>
                        'Primary business phone.',
                    'historyTracked' =>
                        true,
                    'fieldUsage' =>
                        'Active',
                    'dataSensitivityLevel' =>
                        'Confidential',
                    'complianceCategorization' =>
                        'GDPR'
                }
            );

        System.Assert.isNotNull(
            picklistRow.get(
                'totalPicklistValueCount'
            ),
            'Picklist fields should include value-count metadata.'
        );

        System.Assert.isTrue(
            ((String) referenceRow.get(
                'referenceTo'
            )).contains(
                'Account'
            ),
            'Reference fields should identify their target objects.'
        );

        System.Assert.areEqual(
            true,
            (Boolean) autoNumberRow.get(
                'autoNumber'
            ),
            'CaseNumber should exercise auto-number metadata.'
        );

        System.Assert.isTrue(
            ((String) autoNumberRow.get(
                'note'
            )).contains(
                'Auto-number field'
            ),
            'Auto-number fields should include an explanatory note.'
        );

        System.Assert.areEqual(
            'Excluded by design',
            (String) checkboxRow.get(
                'usageMethod'
            ),
            'Checkbox test rows should use the intentional exclusion status.'
        );

        System.Assert.areEqual(
            'Primary business phone.',
            (String) phoneRow.get(
                'description'
            ),
            'Controlled metadata should populate the field description.'
        );

        System.Assert.areEqual(
            'Yes',
            (String) phoneRow.get(
                'fieldHistoryTrackingStatus'
            ),
            'A true history flag should display as Yes.'
        );

        System.Assert.areEqual(
            'Confidential',
            (String) phoneRow.get(
                'dataSensitivityLevel'
            ),
            'Data Sensitivity Level should remain in the field contract.'
        );

        System.Assert.isNull(
            DataDictionaryController.testBuildFieldRow(
                'MissingObject__c',
                'Name'
            ),
            'Unknown objects should not produce synthetic field rows.'
        );

        System.Assert.isTrue(
            DataDictionaryController.testIsRequired(
                Contact.LastName.getDescribe()
            ),
            'Contact.LastName is a stable required-field example.'
        );

        System.Assert.isFalse(
            DataDictionaryController.testIsRequired(
                Contact.Phone.getDescribe()
            ),
            'Contact.Phone should remain optional.'
        );
    }

    /**
     * Verifies aggregate success, failure isolation,
     * and query-budget fallback.
     */
    @IsTest
    static void aggregateSeamsCoverSuccessFailureAndCapacity() {
        Map<String, Map<String, Object>> aggregateRows =
            DataDictionaryController.testRunAggregate(
                'User',
                new List<String>{
                    'LastName',
                    'DefinitelyMissing__c'
                }
            );

        System.Assert.areEqual(
            'COUNT(field)',
            (String) aggregateRows
                .get(
                    'LastName'
                )
                .get(
                    'usageMethod'
                ),
            'A valid field should succeed after failed-chunk splitting.'
        );

        System.Assert.areEqual(
            'Failed',
            (String) aggregateRows
                .get(
                    'DefinitelyMissing__c'
                )
                .get(
                    'usageMethod'
                ),
            'The invalid field should be isolated and marked failed.'
        );

        try {
            DataDictionaryController.testSetQueryReserve(
                1000
            );

            Map<String, Map<String, Object>> capacityRows =
                DataDictionaryController.testRunAggregate(
                    'User',
                    new List<String>{
                        'LastName'
                    }
                );

            System.Assert.areEqual(
                'Not evaluated',
                (String) capacityRows
                    .get(
                        'LastName'
                    )
                    .get(
                        'usageMethod'
                    ),
                'Fields should be skipped when no query budget remains.'
            );
        } finally {
            DataDictionaryController.testSetQueryReserve(
                null
            );
        }
    }

    /**
     * Verifies population and documentation scoring boundaries.
     */
    @IsTest
    static void scoringSeamsCoverAllStatuses() {
        assertUsageStatus(
            new Map<String, Object>{
                'populationAnalysisApplicable' =>
                    true,
                'populatedRecords' =>
                    null,
                'totalRecords' =>
                    10,
                'threshold' =>
                    Decimal.valueOf('5'),
                'usageStatus' =>
                    null,
                'expectedStatus' =>
                    'Not evaluated'
            }
        );

        assertUsageStatus(
            new Map<String, Object>{
                'populationAnalysisApplicable' =>
                    true,
                'populatedRecords' =>
                    0,
                'totalRecords' =>
                    0,
                'threshold' =>
                    Decimal.valueOf('5'),
                'usageStatus' =>
                    null,
                'expectedStatus' =>
                    'Object has no records'
            }
        );

        assertUsageStatus(
            new Map<String, Object>{
                'populationAnalysisApplicable' =>
                    true,
                'populatedRecords' =>
                    0,
                'totalRecords' =>
                    10,
                'threshold' =>
                    Decimal.valueOf('5'),
                'usageStatus' =>
                    null,
                'expectedStatus' =>
                    'No data'
            }
        );

        assertUsageStatus(
            new Map<String, Object>{
                'populationAnalysisApplicable' =>
                    true,
                'populatedRecords' =>
                    1,
                'totalRecords' =>
                    10,
                'threshold' =>
                    Decimal.valueOf('20'),
                'usageStatus' =>
                    null,
                'expectedStatus' =>
                    'Low usage'
            }
        );

        assertUsageStatus(
            new Map<String, Object>{
                'populationAnalysisApplicable' =>
                    true,
                'populatedRecords' =>
                    5,
                'totalRecords' =>
                    10,
                'threshold' =>
                    Decimal.valueOf('20'),
                'usageStatus' =>
                    null,
                'expectedStatus' =>
                    'Used'
            }
        );

        assertUsageStatus(
            new Map<String, Object>{
                'populationAnalysisApplicable' =>
                    false,
                'populatedRecords' =>
                    null,
                'totalRecords' =>
                    10,
                'threshold' =>
                    Decimal.valueOf('5'),
                'usageStatus' =>
                    'Not applicable',
                'expectedStatus' =>
                    'Not applicable'
            }
        );

        Map<String, Object> complete =
            DataDictionaryController.testDocumentationScenario(
                true,
                true,
                true
            );

        Map<String, Object> missing =
            DataDictionaryController.testDocumentationScenario(
                true,
                false,
                true
            );

        Map<String, Object> unavailable =
            DataDictionaryController.testDocumentationScenario(
                false,
                false,
                false
            );

        System.Assert.areEqual(
            100,
            (Integer) complete.get(
                'documentationScore'
            ),
            'A fully documented field should score 100.'
        );

        System.Assert.areEqual(
            'Complete',
            (String) complete.get(
                'metadataAuditStatus'
            ),
            'A fully documented field should be complete.'
        );

        System.Assert.areEqual(
            50,
            (Integer) missing.get(
                'documentationScore'
            ),
            'One documented attribute should score 50.'
        );

        System.Assert.areEqual(
            'Missing description',
            (String) missing.get(
                'metadataAuditStatus'
            ),
            'The status should identify a missing description.'
        );

        System.Assert.isNull(
            unavailable.get(
                'documentationScore'
            ),
            'Unavailable description metadata should not produce a score.'
        );

        System.Assert.isTrue(
            ((String) unavailable.get(
                'metadataAuditStatus'
            )).contains(
                'Description audit unavailable'
            ),
            'The status should explain why documentation scoring is unavailable.'
        );
    }

    /**
     * Runs one population-scoring boundary assertion.
     */
    private static void assertUsageStatus(
        Map<String, Object> testCase
    ) {
        Map<String, Object> result =
            DataDictionaryController.testScoreUsage(
                testCase
            );

        System.Assert.areEqual(
            (String) testCase.get(
                'expectedStatus'
            ),
            (String) result.get(
                'usageStatus'
            ),
            'The usage scorer should return the expected boundary status.'
        );
    }

    /**
     * Creates the one-object configuration used by audit tests.
     */
    private static String configurationFor(
        String objectApiName,
        Decimal threshold
    ) {
        return JSON.serialize(
            new Map<String, Object>{
                'objectApiNames' =>
                    new List<String>{
                        objectApiName
                    },
                'includeStandardObjects' =>
                    true,
                'includeCustomObjects' =>
                    true,
                'includeSystemObjects' =>
                    false,
                'lowUsageThresholdPercent' =>
                    threshold
            }
        );
    }

    /**
     * Casts a map-list property from the controller response.
     */
    private static List<Map<String, Object>> mapList(
        Map<String, Object> source,
        String key
    ) {
        return (List<Map<String, Object>>)
            source.get(key);
    }

    /**
     * Casts a String-list property from the controller response.
     */
    private static List<String> stringList(
        Map<String, Object> source,
        String key
    ) {
        return (List<String>)
            source.get(key);
    }

    /**
     * Indexes generic map rows by a String property.
     */
    private static Map<String, Map<String, Object>> indexMaps(
        List<Map<String, Object>> rows,
        String keyName
    ) {
        Map<String, Map<String, Object>> result =
            new Map<String, Map<String, Object>>();

        for (Map<String, Object> row : rows) {
            result.put(
                (String) row.get(keyName),
                row
            );
        }

        return result;
    }

    /**
     * Returns whether any row contains the requested String value.
     */
    private static Boolean containsMapValue(
        List<Map<String, Object>> rows,
        String keyName,
        String expectedValue
    ) {
        for (Map<String, Object> row : rows) {
            if (
                (String) row.get(keyName) ==
                expectedValue
            ) {
                return true;
            }
        }

        return false;
    }

    /**
     * Verifies one client-safe validation failure.
     */
    private static void assertAuraFailure(
        String objectApiName,
        String configurationJson,
        String expectedMessageFragment
    ) {
        try {
            DataDictionaryController.auditObject(
                objectApiName,
                configurationJson
            );

            System.Assert.fail(
                'Expected AuraHandledException for object: ' +
                objectApiName
            );
        } catch (AuraHandledException expectedException) {
            System.Assert.isTrue(
                expectedException
                    .getMessage()
                    .contains(
                        expectedMessageFragment
                    ),
                'Expected message fragment "' +
                expectedMessageFragment +
                '" but received "' +
                expectedException.getMessage() +
                '".'
            );
        }
    }

    /**
     * Creates deterministic long text for sanitization tests.
     */
    private static String repeatCharacter(
        String value,
        Integer count
    ) {
        List<String> values =
            new List<String>();

        for (
            Integer index = 0;
            index < count;
            index++
        ) {
            values.add(value);
        }

        return String.join(
            values,
            ''
        );
    }
}