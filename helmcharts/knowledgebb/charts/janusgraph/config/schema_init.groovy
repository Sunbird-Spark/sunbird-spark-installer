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

makeProperty('IL_UNIQUE_ID', String.class, Cardinality.SINGLE)
makeProperty('IL_FUNC_OBJECT_TYPE', String.class, Cardinality.SINGLE) // ObjectType
makeProperty('IL_SYS_NODE_TYPE', String.class, Cardinality.SINGLE)    // NodeType
makeProperty('IL_TAG_NAME', String.class, Cardinality.SINGLE) 

makeProperty('identifier', String.class, Cardinality.SINGLE)
makeProperty('code', String.class, Cardinality.SINGLE)
makeProperty('name', String.class, Cardinality.SINGLE)
makeProperty('status', String.class, Cardinality.SINGLE)
makeProperty('channel', String.class, Cardinality.SINGLE)
makeProperty('framework', String.class, Cardinality.SINGLE)
makeProperty('mimeType', String.class, Cardinality.SINGLE)
makeProperty('contentType', String.class, Cardinality.SINGLE)
makeProperty('pkgVersion', Double.class, Cardinality.SINGLE)
makeProperty('versionKey', String.class, Cardinality.SINGLE)
makeProperty('visibility', String.class, Cardinality.SINGLE)
makeProperty('childNodes', String.class, Cardinality.LIST) // Array/List in data
makeProperty('depth', Integer.class, Cardinality.SINGLE)
makeProperty('index', Integer.class, Cardinality.SINGLE)
makeProperty('description', String.class, Cardinality.SINGLE)
makeProperty('createdBy', String.class, Cardinality.SINGLE)
makeProperty('createdOn', String.class, Cardinality.SINGLE)
makeProperty('lastUpdatedOn', String.class, Cardinality.SINGLE)
makeProperty('lastStatusChangedOn', String.class, Cardinality.SINGLE)
makeProperty('portalOwner', String.class, Cardinality.SINGLE)
makeProperty('downloadUrl', String.class, Cardinality.SINGLE)
makeProperty('artifactUrl', String.class, Cardinality.SINGLE)
makeProperty('appId', String.class, Cardinality.SINGLE)
makeProperty('consumerId', String.class, Cardinality.SINGLE)
makeProperty('mediaType', String.class, Cardinality.SINGLE)
makeProperty('compatibilityLevel', Integer.class, Cardinality.SINGLE)
makeProperty('osId', String.class, Cardinality.SINGLE)
makeProperty('language', String.class, Cardinality.LIST)


// 4. Define Vertex Labels
makeVLabel = { name ->
    if (!mgmt.containsVertexLabel(name)) {
        println "Creating VertexLabel: $name"
        mgmt.makeVertexLabel(name).make()
    }
}

makeVLabel('Content')
makeVLabel('Framework')
makeVLabel('Category')
makeVLabel('CategoryInstance')
makeVLabel('Term')
makeVLabel('ObjectCategory')
makeVLabel('ObjectCategoryDefinition')
makeVLabel('Channel')
makeVLabel('License')
makeVLabel('Concept')
makeVLabel('Asset')
makeVLabel('Domain')
makeVLabel('Dimension')

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