import org.apache.tinkerpop.gremlin.structure.Vertex
import org.apache.tinkerpop.gremlin.structure.T
import org.apache.tinkerpop.gremlin.structure.Direction
import groovy.json.JsonSlurper

// Open Graph
graph = JanusGraphFactory.open('/opt/bitnami/janusgraph/conf/janusgraph-cql.properties')
// Bind graph and traversal to global binding for access in closures
binding.graph = graph
binding.g = graph.traversal()

println "--- STARTING DATA MIGRATION (User Script Fixed) ---"

def replaceExisting = false
if (binding.hasVariable('args')) {
    replaceExisting = args.any { it == 'replace=true' }
}
if (binding.hasVariable('replace') && (binding.replace == 'true' || binding.replace == true)) {
    replaceExisting = true
}
if (System.getProperty('replace') == 'true') {
    replaceExisting = true
}
println "replace parameter is set to: ${replaceExisting}"

// --- 1. NODES ---
println "Importing Nodes..."

binding.tx = graph.buildTransaction().logIdentifier("learning_graph_events").start()
binding.txG = binding.tx.traversal()

if (!binding.hasVariable('state')) {
    binding.state = [accumulating: false, jsonBuffer: '', nodeLine: '']
}

new File('/tmp/nodes.csv').eachLine { line, idx ->
    try {
        if (idx == 1) return // skip header

        def state = binding.state
        // Use transaction traversal for CDC log identifier
        def g = binding.txG

        if (state.accumulating) {
            state.nodeLine += ' ' + line.trim()
            if (line.trim().endsWith('}')) state.accumulating = false
            else return
        } else {
            state.nodeLine = line
            if (!line.trim().endsWith('}')) {
                state.accumulating = true
                return
            }
        }

        def parts = state.nodeLine.split(/,(?=\s*\[?["{])/)
        
        if (parts.size() < 3) {
             println "Skipping malformed line $idx: ${state.nodeLine}"
             return
        }

        def nodeIdVal = parts[0].toLong()
        def labelRaw = parts[1].replaceAll(/\[|\]|"/, '')
        def label = labelRaw.trim()
        def propsRaw = parts[2..-1].join(',')

        // Quote unquoted keys + normalize Neo4j booleans (matches db-migration logic)
        def propsFixed = propsRaw
            .replaceAll(/([{,]\s*)(\w+):/, '$1"$2":')
            .replaceAll(/\bTRUE\b/, 'true')
            .replaceAll(/\bFALSE\b/, 'false')

        def rawMap = [:]
        try {
            rawMap = new JsonSlurper().parseText(propsFixed)
        } catch (Exception e) {
            // Fallback for very messy lines
            println "  JSON Parse failed on line $idx, attempting manual extraction..."
            propsFixed.findAll(/"([^"]+)":\s*("[^"]*"|[^,}]+)/).each { m ->
                def k = m[1]
                def v = m[2].replaceAll(/^"|"$/, '')
                rawMap[k] = v
            }
        }
        
        def propsMap = rawMap.collectEntries { k, v ->
            def cleanVal = v
            if (v instanceof String) {
                cleanVal = v.trim()
            } else if (v instanceof List) {
                cleanVal = v.collect { it instanceof String ? it.trim() : it }
            }
            return [(k.toString().trim()): cleanVal]
        }

        def existing = g.V().has('node_id', nodeIdVal).tryNext().orElse(null)
        
        if (!existing) {
            def uniqueId = propsMap['IL_UNIQUE_ID']
            if (uniqueId) {
                existing = g.V().has('IL_UNIQUE_ID', uniqueId).tryNext().orElse(null)
            }
        }

        if (existing && replaceExisting) {
            def dropTx = graph.newTransaction()
            dropTx.traversal().V(existing.id()).drop().iterate()
            dropTx.commit()
            existing = null
        }

        if (!existing) {
            def v = binding.tx.addVertex(T.label, label, 'node_id', nodeIdVal)
            propsMap.each { k, vprop ->
                if (vprop != null) {
                    if (vprop instanceof List) vprop = vprop.join(',')
                    else if (vprop instanceof BigDecimal) vprop = vprop.doubleValue()
                    v.property(k, vprop)
                }
            }
        }
    } catch (Exception e) {
        println "Error on line $idx: ${e.message}"
    }
}
binding.tx.commit()
println "\nNodes Imported."


// --- 2. RELATIONSHIPS ---
println "Importing Relationships..."

binding.tx2 = graph.buildTransaction().logIdentifier("learning_graph_events").start()
binding.tx2G = binding.tx2.traversal()

new File('/tmp/relationships.csv').eachLine { line, idx ->
    try {
        if (idx == 1) return

        def g = binding.tx2G 

        // Adjusted regex for: from, "label", {props}, to
        def matcher = line =~ /^(\d+),\s*"([^"]+)",\s*(\{.*\}|),\s*(\d+)$/
        if (!matcher.matches()) {
            // Fallback for simple relations without properties
            matcher = line =~ /^(\d+),\s*"([^"]+)",\s*,\s*(\d+)$/
        }

        if (!matcher.matches()) {
            println "Skipping malformed edge line $idx: $line"
            return
        }

        def fromId = matcher[0][1].toLong()
        def relType = matcher[0][2].trim()
        def propsRaw = matcher[0][3].trim()
        def toId = matcher[0][4].toLong()

        def propsMap = [:]
        if (propsRaw && propsRaw != "{}") {
             // Simple prop parsing for Neo4j edge props like {IL_SEQUENCE_INDEX: 1}
             propsRaw.replaceAll(/^\{|\}$/, '').split(',').each { kv ->
                def kvParts = kv.split(':')
                if (kvParts.size() == 2) {
                    def k = kvParts[0].trim().replaceAll(/^"|"$/, '')
                    def v = kvParts[1].trim().replaceAll(/^"|"$/, '')
                    if (v ==~ /^\d+$/) v = v.toLong()
                    else if (v ==~ /^\d+\.\d+$/) v = v.toDouble()
                    propsMap[k] = v
                }
             }
        }

        def fromV = g.V().has('node_id', fromId).tryNext().orElse(null)
        def toV = g.V().has('node_id', toId).tryNext().orElse(null)

        if (fromV && toV) {
            def existing = fromV.edges(Direction.OUT, relType).find { it.inVertex().value('node_id') == toId }
            if (!existing) {
                def e = fromV.addEdge(relType, toV)
                propsMap.each { k, v -> e.property(k, v) }
            }
        } else {
            // Silently skip if nodes don't exist, matching common bulk load patterns
        }
    } catch (Exception e) {
        println "Error on edge line $idx: ${e.message}"
    }
}
binding.tx2.commit()
println "Relationships Imported."

// Verify
println "Vertices: " + binding.g.V().count().next()
println "Edges: " + binding.g.E().count().next()

// Close the graph gracefully to ensure CDC transaction logs are flushed
println "Closing graph to flush CDC logs..."
graph.close()
println "Graph closed successfully."

System.exit(0)