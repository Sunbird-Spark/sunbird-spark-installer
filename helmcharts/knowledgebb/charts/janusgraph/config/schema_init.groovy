// schema_init.groovy
// Purpose: Initialize JanusGraph Schema & Indexes on server startup.
// Loaded via ScriptFileGremlinPlugin in gremlin-server.yaml — runs inside the
// gremlin server's own JanusGraph instance, avoiding the two-instance coordination
// delay that causes INSTALLED→REGISTERED to stall.
import org.janusgraph.core.schema.SchemaAction
import org.janusgraph.core.schema.SchemaStatus
import org.janusgraph.core.Cardinality
import org.janusgraph.core.Multiplicity
import org.apache.tinkerpop.gremlin.structure.Vertex
import java.time.temporal.ChronoUnit

// 1. Connect to graph.
// When loaded via ScriptFileGremlinPlugin at server startup, 'graph' is already
// bound by the gremlin server — use it directly (single instance, no coordination delay).
// When run via gremlin.sh -e in the schema-init Job, 'graph' is not bound —
// fall back to a direct connection for post-deploy verification.
isServerContext = false
try {
    jg = graph
    isServerContext = true
    println "Running in gremlin server context (ScriptFileGremlinPlugin)."
} catch (MissingPropertyException e) {
    jg = org.janusgraph.core.JanusGraphFactory.open('/opt/bitnami/janusgraph/conf/janusgraph.properties')
    println "Running in schema-init Job context (verification only)."
}

// 2. Force-close stale JanusGraph instances left by previous failed runs.
// ONLY safe to run from server context — in Job context the live gremlin server
// instance would appear as "non-current" and get incorrectly force-closed.
if (isServerContext) {
    println "Checking for stale JanusGraph instances..."
    mgmtClean = jg.openManagement()
    try {
        def openInstances = mgmtClean.getOpenInstances()
        println "Registered instances: ${openInstances}"
        openInstances.each { instance ->
            if (!instance.endsWith("(current)")) {
                println "Force-closing stale instance: $instance"
                mgmtClean.forceCloseInstance(instance)
            }
        }
        mgmtClean.commit()
        println "Stale instance cleanup complete."
    } catch (Exception e) {
        mgmtClean.rollback()
        println "Warning: stale instance cleanup failed (non-fatal): ${e.message}"
    }
} else {
    println "Skipping stale instance cleanup (Job context — server instance must not be disturbed)."
}

mgmt = jg.openManagement()

println "--- STARTING SCHEMA INITIALIZATION ---"

// 3. Define Property Keys
// Helper closure to create property if missing
makeProperty = { key, dataType, cardinality ->
    if (!mgmt.containsPropertyKey(key)) {
        println "Creating Property: $key"
        mgmt.makePropertyKey(key).dataType(dataType).cardinality(cardinality).make()
    }
}

// === Property keys — derived from working production cluster (ed-testing) ===
// Source: live janusgraph schema export. dataType + cardinality must match prod
// because knowlg-service validates against these.
makeProperty('IL_FUNC_OBJECT_TYPE', String.class, Cardinality.SINGLE)
makeProperty('IL_SEQUENCE_INDEX', Long.class, Cardinality.SINGLE)
makeProperty('IL_SYS_NODE_TYPE', String.class, Cardinality.SINGLE)
makeProperty('IL_TAG_NAME', String.class, Cardinality.SINGLE)
makeProperty('IL_UNIQUE_ID', String.class, Cardinality.SINGLE)
makeProperty('additionalCategories', String.class, Cardinality.SINGLE)
makeProperty('allowAnonymousAccess', String.class, Cardinality.SINGLE)
makeProperty('allowBranching', String.class, Cardinality.SINGLE)
makeProperty('allowSkip', String.class, Cardinality.SINGLE)
makeProperty('answer', String.class, Cardinality.SINGLE)
makeProperty('appIcon', String.class, Cardinality.SINGLE)
makeProperty('appId', String.class, Cardinality.SINGLE)
makeProperty('artifactUrl', String.class, Cardinality.SINGLE)
makeProperty('assets', String.class, Cardinality.SINGLE)
makeProperty('attributions', String.class, Cardinality.SINGLE)
makeProperty('audience', String.class, Cardinality.SINGLE)
makeProperty('author', String.class, Cardinality.SINGLE)
makeProperty('autoCreateBatch', String.class, Cardinality.SINGLE)
makeProperty('batches', String.class, Cardinality.SINGLE)
makeProperty('board', String.class, Cardinality.SINGLE)
makeProperty('boardIds', String.class, Cardinality.SINGLE)
makeProperty('category', String.class, Cardinality.SINGLE)
makeProperty('categoryId', String.class, Cardinality.SINGLE)
makeProperty('certType', String.class, Cardinality.SINGLE)
makeProperty('channel', String.class, Cardinality.SINGLE)
makeProperty('childNodes', String.class, Cardinality.LIST)
makeProperty('cloudStorageKey', String.class, Cardinality.SINGLE)
makeProperty('code', String.class, Cardinality.SINGLE)
makeProperty('collaborators', String.class, Cardinality.SINGLE)
makeProperty('compatibilityLevel', Integer.class, Cardinality.SINGLE)
makeProperty('consumerId', String.class, Cardinality.SINGLE)
makeProperty('containsUserData', String.class, Cardinality.SINGLE)
makeProperty('contentDisposition', String.class, Cardinality.SINGLE)
makeProperty('contentEncoding', String.class, Cardinality.SINGLE)
makeProperty('contentType', String.class, Cardinality.SINGLE)
makeProperty('contentTypesCount', String.class, Cardinality.SINGLE)
makeProperty('copyright', String.class, Cardinality.SINGLE)
makeProperty('copyrightYear', Integer.class, Cardinality.SINGLE)
makeProperty('createdBy', String.class, Cardinality.SINGLE)
makeProperty('createdFor', String.class, Cardinality.SINGLE)
makeProperty('createdOn', String.class, Cardinality.SINGLE)
makeProperty('creator', String.class, Cardinality.SINGLE)
makeProperty('credentials', String.class, Cardinality.SINGLE)
makeProperty('data', String.class, Cardinality.SINGLE)
makeProperty('defaultCourseFramework', String.class, Cardinality.SINGLE)
makeProperty('defaultFramework', String.class, Cardinality.SINGLE)
makeProperty('defaultLicense', String.class, Cardinality.SINGLE)
makeProperty('depth', Integer.class, Cardinality.SINGLE)
makeProperty('depth_of_knowledge', String.class, Cardinality.SINGLE)
makeProperty('description', String.class, Cardinality.SINGLE)
makeProperty('dialcodeRequired', String.class, Cardinality.SINGLE)
makeProperty('dialcodes', String.class, Cardinality.SINGLE)
makeProperty('discussionForum', String.class, Cardinality.SINGLE)
makeProperty('domain', String.class, Cardinality.SINGLE)
makeProperty('downloadUrl', String.class, Cardinality.SINGLE)
makeProperty('editorState', String.class, Cardinality.SINGLE)
makeProperty('evalUnordered', Boolean.class, Cardinality.SINGLE)
makeProperty('framework', String.class, Cardinality.SINGLE)
makeProperty('generateDIALCodes', String.class, Cardinality.SINGLE)
makeProperty('gradeLevel', String.class, Cardinality.SINGLE)
makeProperty('gradeLevelIds', String.class, Cardinality.SINGLE)
makeProperty('graphId', String.class, Cardinality.SINGLE)
makeProperty('hierarchy', String.class, Cardinality.SINGLE)
makeProperty('idealScreenDensity', String.class, Cardinality.SINGLE)
makeProperty('idealScreenSize', String.class, Cardinality.SINGLE)
makeProperty('identifier', String.class, Cardinality.SINGLE)
makeProperty('index', Integer.class, Cardinality.SINGLE)
makeProperty('industry', String.class, Cardinality.SINGLE)
makeProperty('interactionTypes', String.class, Cardinality.SINGLE)
makeProperty('interceptionPoints', String.class, Cardinality.SINGLE)
makeProperty('isPartialScore', Boolean.class, Cardinality.SINGLE)
makeProperty('isShuffleOption', Boolean.class, Cardinality.SINGLE)
makeProperty('issuer', String.class, Cardinality.SINGLE)
makeProperty('itemType', String.class, Cardinality.SINGLE)
makeProperty('keywords', String.class, Cardinality.SINGLE)
makeProperty('language', String.class, Cardinality.LIST)
makeProperty('languageCode', String.class, Cardinality.SINGLE)
makeProperty('lastPublishedBy', String.class, Cardinality.SINGLE)
makeProperty('lastPublishedOn', String.class, Cardinality.SINGLE)
makeProperty('lastStatusChangedOn', String.class, Cardinality.SINGLE)
makeProperty('lastSubmittedOn', String.class, Cardinality.SINGLE)
makeProperty('lastUpdatedBy', String.class, Cardinality.SINGLE)
makeProperty('lastUpdatedOn', String.class, Cardinality.SINGLE)
makeProperty('leafNodes', String.class, Cardinality.SINGLE)
makeProperty('leafNodesCount', Integer.class, Cardinality.SINGLE)
makeProperty('lhs_options', String.class, Cardinality.SINGLE)
makeProperty('license', String.class, Cardinality.SINGLE)
makeProperty('lockKey', String.class, Cardinality.SINGLE)
makeProperty('maxAttempts', Integer.class, Cardinality.SINGLE)
makeProperty('maxScore', Integer.class, Cardinality.SINGLE)
makeProperty('max_score', Integer.class, Cardinality.SINGLE)
makeProperty('mediaType', String.class, Cardinality.SINGLE)
makeProperty('medium', String.class, Cardinality.SINGLE)
makeProperty('mediumIds', String.class, Cardinality.SINGLE)
makeProperty('metadata', String.class, Cardinality.SINGLE)
makeProperty('mimeType', String.class, Cardinality.SINGLE)
makeProperty('mimeTypesCount', String.class, Cardinality.SINGLE)
makeProperty('mode', String.class, Cardinality.SINGLE)
makeProperty('name', String.class, Cardinality.SINGLE)
makeProperty('navigationMode', String.class, Cardinality.SINGLE)
makeProperty('node_id', Long.class, Cardinality.SINGLE)
makeProperty('objectType', String.class, Cardinality.SINGLE)
makeProperty('options', String.class, Cardinality.SINGLE)
makeProperty('orgIdFieldName', String.class, Cardinality.SINGLE)
makeProperty('organisation', String.class, Cardinality.SINGLE)
makeProperty('os', String.class, Cardinality.SINGLE)
makeProperty('osId', String.class, Cardinality.SINGLE)
makeProperty('outRelations', String.class, Cardinality.SINGLE)
makeProperty('ownershipType', String.class, Cardinality.SINGLE)
makeProperty('pdfUrl', String.class, Cardinality.SINGLE)
makeProperty('pkgVersion', Double.class, Cardinality.SINGLE)
makeProperty('plugins', String.class, Cardinality.SINGLE)
makeProperty('portalOwner', String.class, Cardinality.SINGLE)
makeProperty('posterImage', String.class, Cardinality.SINGLE)
makeProperty('pragma', String.class, Cardinality.SINGLE)
makeProperty('prevState', String.class, Cardinality.SINGLE)
makeProperty('prevStatus', String.class, Cardinality.SINGLE)
makeProperty('previewUrl', String.class, Cardinality.SINGLE)
makeProperty('primaryCategory', String.class, Cardinality.SINGLE)
makeProperty('publishChecklist', String.class, Cardinality.SINGLE)
makeProperty('publishComment', String.class, Cardinality.SINGLE)
makeProperty('publishError', String.class, Cardinality.SINGLE)
makeProperty('publisher', String.class, Cardinality.SINGLE)
makeProperty('purpose', String.class, Cardinality.SINGLE)
makeProperty('qType', String.class, Cardinality.SINGLE)
makeProperty('qlevel', String.class, Cardinality.SINGLE)
makeProperty('qrCodeProcessId', String.class, Cardinality.SINGLE)
makeProperty('questionTitle', String.class, Cardinality.SINGLE)
makeProperty('questionType', String.class, Cardinality.SINGLE)
makeProperty('qumlVersion', Double.class, Cardinality.SINGLE)
makeProperty('rejectComment', String.class, Cardinality.SINGLE)
makeProperty('rejectReasons', String.class, Cardinality.SINGLE)
makeProperty('relational_metadata', String.class, Cardinality.SINGLE)
makeProperty('requiresSubmit', String.class, Cardinality.SINGLE)
makeProperty('reservedDialcodes', String.class, Cardinality.SINGLE)
makeProperty('resourceType', String.class, Cardinality.SINGLE)
makeProperty('reviewError', String.class, Cardinality.SINGLE)
makeProperty('rhs_options', String.class, Cardinality.SINGLE)
makeProperty('s3Key', String.class, Cardinality.SINGLE)
makeProperty('sYS_INTERNAL_LAST_UPDATED_ON', String.class, Cardinality.SINGLE)
makeProperty('schemaVersion', String.class, Cardinality.SINGLE)
makeProperty('scoreCutoffType', String.class, Cardinality.SINGLE)
makeProperty('se_FWIds', String.class, Cardinality.SINGLE)
makeProperty('se_boardIds', String.class, Cardinality.SINGLE)
makeProperty('se_boards', String.class, Cardinality.SINGLE)
makeProperty('se_domainIds', String.class, Cardinality.SINGLE)
makeProperty('se_domains', String.class, Cardinality.SINGLE)
makeProperty('se_gradeLevelIds', String.class, Cardinality.SINGLE)
makeProperty('se_gradeLevels', String.class, Cardinality.SINGLE)
makeProperty('se_industryIds', String.class, Cardinality.SINGLE)
makeProperty('se_industrys', String.class, Cardinality.SINGLE)
makeProperty('se_mediumIds', String.class, Cardinality.SINGLE)
makeProperty('se_mediums', String.class, Cardinality.SINGLE)
makeProperty('se_skillIds', String.class, Cardinality.SINGLE)
makeProperty('se_skills', String.class, Cardinality.SINGLE)
makeProperty('se_subjectIds', String.class, Cardinality.SINGLE)
makeProperty('se_subjects', String.class, Cardinality.SINGLE)
makeProperty('searchIdFieldName', String.class, Cardinality.SINGLE)
makeProperty('searchLabelFieldName', String.class, Cardinality.SINGLE)
makeProperty('setType', String.class, Cardinality.SINGLE)
makeProperty('showFeedback', Boolean.class, Cardinality.SINGLE)
makeProperty('showHints', Boolean.class, Cardinality.SINGLE)
makeProperty('showNotification', Boolean.class, Cardinality.SINGLE)
makeProperty('showSolutions', Boolean.class, Cardinality.SINGLE)
makeProperty('showTimer', Boolean.class, Cardinality.SINGLE)
makeProperty('shuffle', Boolean.class, Cardinality.SINGLE)
makeProperty('signatoryList', String.class, Cardinality.SINGLE)
makeProperty('size', Integer.class, Cardinality.SINGLE)
makeProperty('skill', String.class, Cardinality.SINGLE)
makeProperty('status', String.class, Cardinality.SINGLE)
makeProperty('streamingUrl', String.class, Cardinality.SINGLE)
makeProperty('subject', String.class, Cardinality.SINGLE)
makeProperty('subjectIds', String.class, Cardinality.SINGLE)
makeProperty('summaryType', String.class, Cardinality.SINGLE)
makeProperty('systemDefault', String.class, Cardinality.SINGLE)
makeProperty('targetBoardIds', String.class, Cardinality.SINGLE)
makeProperty('targetDomainIds', String.class, Cardinality.SINGLE)
makeProperty('targetFWIds', String.class, Cardinality.SINGLE)
makeProperty('targetGradeLevelIds', String.class, Cardinality.SINGLE)
makeProperty('targetIdFieldName', String.class, Cardinality.SINGLE)
makeProperty('targetIndustryIds', String.class, Cardinality.SINGLE)
makeProperty('targetMediumIds', String.class, Cardinality.SINGLE)
makeProperty('targetObjectType', String.class, Cardinality.SINGLE)
makeProperty('targetSkillIds', String.class, Cardinality.SINGLE)
makeProperty('targetSubjectIds', String.class, Cardinality.SINGLE)
makeProperty('template', String.class, Cardinality.SINGLE)
makeProperty('templateId', String.class, Cardinality.SINGLE)
makeProperty('templateType', String.class, Cardinality.SINGLE)
makeProperty('template_id', String.class, Cardinality.SINGLE)
makeProperty('term', String.class, Cardinality.SINGLE)
makeProperty('timeLimits', String.class, Cardinality.SINGLE)
makeProperty('title', String.class, Cardinality.SINGLE)
makeProperty('toc_url', String.class, Cardinality.SINGLE)
makeProperty('totalCompressedSize', Integer.class, Cardinality.SINGLE)
makeProperty('totalQuestions', Integer.class, Cardinality.SINGLE)
makeProperty('totalScore', Integer.class, Cardinality.SINGLE)
makeProperty('trackable', String.class, Cardinality.SINGLE)
makeProperty('type', String.class, Cardinality.SINGLE)
makeProperty('url', String.class, Cardinality.SINGLE)
makeProperty('used_for', String.class, Cardinality.SINGLE)
makeProperty('userConsent', String.class, Cardinality.SINGLE)
makeProperty('variants', String.class, Cardinality.SINGLE)
makeProperty('version', Integer.class, Cardinality.SINGLE)
makeProperty('versionKey', String.class, Cardinality.SINGLE)
makeProperty('visibility', String.class, Cardinality.SINGLE)
makeProperty('year', String.class, Cardinality.SINGLE)


// 4. Define Vertex Labels
makeVLabel = { name ->
    if (!mgmt.containsVertexLabel(name)) {
        println "Creating VertexLabel: $name"
        mgmt.makeVertexLabel(name).make()
    }
}

// Vertex labels — derived from working production cluster (ed-testing)
makeVLabel('AssessmentItem')
makeVLabel('AssessmentItemImage')
makeVLabel('Asset')
makeVLabel('Category')
makeVLabel('CategoryInstance')
makeVLabel('Channel')
makeVLabel('Collection')
makeVLabel('CollectionImage')
makeVLabel('Concept')
makeVLabel('Content')
makeVLabel('ContentImage')
makeVLabel('Dimension')
makeVLabel('Domain')
makeVLabel('Framework')
makeVLabel('License')
makeVLabel('ObjectCategory')
makeVLabel('ObjectCategoryDefinition')
makeVLabel('Question')
makeVLabel('QuestionSet')
makeVLabel('QuestionSetImage')
makeVLabel('ROOT')
makeVLabel('Term')

// 5. Define Edge Labels
makeELabel = { name, multiplicity ->
    if (!mgmt.containsEdgeLabel(name)) {
        println "Creating EdgeLabel: $name"
        mgmt.makeEdgeLabel(name).multiplicity(multiplicity).make()
    }
}

makeELabel('hasSequenceMember', Multiplicity.MULTI)
makeELabel('associatedTo', Multiplicity.MULTI)

// 6. Define Indexes (CRITICAL: Index-First Strategy)
// allIndexNames is the single source of truth — used both for creation and for
// the enable/await phases below. Add new indexes here and nowhere else.
allIndexNames = []

makeCompositeIndex = { name, keyName, unique ->
    allIndexNames << name
    if (!mgmt.containsGraphIndex(name)) {
        println "Creating Composite Index: $name (Unique: $unique)"
        def builder = mgmt.buildIndex(name, Vertex.class)
        def key = mgmt.getPropertyKey(keyName)
        if (key) {
           builder.addKey(key)
           if (unique) builder.unique()
           builder.buildCompositeIndex()
           println "Index $name CREATED."
        } else {
            println "ERROR: Property key $keyName missing for index $name"
        }
    } else {
        println "Index $name already exists."
    }
}

// 6a. Unique Indexes
makeCompositeIndex('byUniqueId', 'IL_UNIQUE_ID', true)

// 6b. Non-Unique Indexes
makeCompositeIndex('byCode', 'code', false)
makeCompositeIndex('byIdentifier', 'identifier', false)
makeCompositeIndex('byChannel', 'channel', false)
makeCompositeIndex('byFramework', 'framework', false)
makeCompositeIndex('byMimeType', 'mimeType', false)
makeCompositeIndex('byContentType', 'contentType', false)
makeCompositeIndex('byVisibility', 'visibility', false)
makeCompositeIndex('byObjectTypeAndStatus', 'IL_FUNC_OBJECT_TYPE', false)
makeCompositeIndex('byNodeType', 'IL_SYS_NODE_TYPE', false)

// Workspace + portal hot-path queries — index frequently-filtered fields
makeCompositeIndex('byStatus', 'status', false)
makeCompositeIndex('byCreatedBy', 'createdBy', false)
makeCompositeIndex('byObjectType', 'objectType', false)
makeCompositeIndex('byPrimaryCategory', 'primaryCategory', false)
makeCompositeIndex('byResourceType', 'resourceType', false)
makeCompositeIndex('byMediaType', 'mediaType', false)
makeCompositeIndex('byName', 'name', false)
makeCompositeIndex('byVersionKey', 'versionKey', false)
makeCompositeIndex('byGraphId', 'graphId', false)
makeCompositeIndex('byNodeIdNum', 'node_id', false)

// 7. Commit Changes
println "Committing Transaction..."
mgmt.commit()

// 8. Explicitly register any indexes still at INSTALLED
println "Registering INSTALLED indexes..."
mgmtR = jg.openManagement()
registerFailed = false
allIndexNames.each { indexName ->
    try {
        def idx = mgmtR.getGraphIndex(indexName)
        if (idx) {
            def status = idx.getIndexStatus(idx.getFieldKeys()[0])
            if (status == SchemaStatus.INSTALLED) {
                println "Registering index: $indexName (currently INSTALLED)"
                mgmtR.updateIndex(idx, SchemaAction.REGISTER_INDEX).get()
            } else {
                println "Index $indexName is already $status — skipping register."
            }
        } else {
            println "ERROR: Index $indexName not found during registration."
            registerFailed = true
        }
    } catch (Exception e) {
        println "ERROR: Could not register index $indexName: ${e.message}"
        registerFailed = true
    }
}
if (registerFailed) {
    mgmtR.rollback()
    throw new RuntimeException("One or more indexes failed to register — rolled back. Check errors above.")
}
mgmtR.commit()
println "Registration committed."

// 9. Wait for all indexes to reach REGISTERED (or ENABLED if already there)
println "Waiting for all indexes to reach REGISTERED status..."
allIndexNames.each { indexName ->
    try {
        println "Awaiting REGISTERED for index: $indexName ..."
        def report = org.janusgraph.graphdb.database.management.ManagementSystem
            .awaitGraphIndexStatus(jg, indexName)
            .status(SchemaStatus.REGISTERED, SchemaStatus.ENABLED)
            .timeout(5L, ChronoUnit.MINUTES)
            .call()
        if (report.getSucceeded()) {
            println "Index $indexName reached REGISTERED or ENABLED."
        } else {
            throw new RuntimeException("Index $indexName did not reach REGISTERED within timeout: ${report}")
        }
    } catch (RuntimeException e) {
        throw e
    } catch (Exception e) {
        throw new RuntimeException("Index $indexName failed to reach REGISTERED: ${e.message}", e)
    }
}

// 10. Enable all indexes that are still in REGISTERED state
println "Enabling all REGISTERED indexes..."
mgmt2 = jg.openManagement()
enableFailed = false
allIndexNames.each { indexName ->
    try {
        def idx = mgmt2.getGraphIndex(indexName)
        if (idx) {
            def status = idx.getIndexStatus(idx.getFieldKeys()[0])
            if (status == SchemaStatus.REGISTERED) {
                println "Enabling index: $indexName (currently REGISTERED)"
                mgmt2.updateIndex(idx, SchemaAction.ENABLE_INDEX).get()
            } else {
                println "Index $indexName is already $status — skipping enable."
            }
        } else {
            println "ERROR: Index $indexName not found."
            enableFailed = true
        }
    } catch (Exception e) {
        println "ERROR: Could not enable index $indexName: ${e.message}"
        enableFailed = true
    }
}
if (enableFailed) {
    mgmt2.rollback()
    throw new RuntimeException("One or more indexes failed to enable — rolled back. Check errors above.")
}
mgmt2.commit()
println "Enable actions committed."

// 11. Wait for all indexes to reach ENABLED
println "Waiting for all indexes to reach ENABLED status..."
enabledFailed = false
allIndexNames.each { indexName ->
    try {
        println "Awaiting ENABLED for index: $indexName ..."
        def report = org.janusgraph.graphdb.database.management.ManagementSystem
            .awaitGraphIndexStatus(jg, indexName)
            .status(SchemaStatus.ENABLED)
            .timeout(5L, ChronoUnit.MINUTES)
            .call()
        if (report.getSucceeded()) {
            println "Index $indexName is ENABLED."
        } else {
            println "ERROR: Index $indexName did not reach ENABLED within timeout: ${report}"
            enabledFailed = true
        }
    } catch (Exception e) {
        println "ERROR: awaitGraphIndexStatus ENABLED for $indexName: ${e.message}"
        enabledFailed = true
    }
}

// 12. Final status report
println "--- FINAL INDEX STATUS REPORT ---"
mgmt3 = jg.openManagement()
try {
    allIndexNames.each { indexName ->
        try {
            def idx = mgmt3.getGraphIndex(indexName)
            if (idx) {
                def status = idx.getIndexStatus(idx.getFieldKeys()[0])
                println "Index $indexName: $status"
            } else {
                println "Index $indexName: NOT FOUND"
            }
        } catch (Exception e) {
            println "Index $indexName: ERROR - ${e.message}"
        }
    }
} finally {
    mgmt3.rollback()
}

if (enabledFailed) {
    throw new RuntimeException("One or more indexes did not reach ENABLED status. Check errors above.")
}

println "--- SCHEMA INITIALIZATION COMPLETE ---"
