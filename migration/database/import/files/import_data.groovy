import org.apache.tinkerpop.gremlin.structure.Vertex
import org.apache.tinkerpop.gremlin.structure.T
import org.apache.tinkerpop.gremlin.structure.Direction

// Closures stored in `binding` so they are visible inside the per-line
// closures passed to eachLine (groovysh script-scope visibility limitation).

parseValue = { String s ->
    s = s.trim()
    if (s.length() == 0) return null
    if (s == 'null') return null
    if (s == 'true' || s == 'TRUE') return true
    if (s == 'false' || s == 'FALSE') return false

    if (s.length() >= 2 && s.charAt(0) == ('"' as char) && s.charAt(s.length() - 1) == ('"' as char)) {
        return s.substring(1, s.length() - 1)
                .replace('\\"', '"')
                .replace('\\\\', '\\')
                .replace('\\n', '\n')
                .replace('\\t', '\t')
                .replace('\\r', '\r')
    }

    if (s ==~ /-?\d+/) { try { return s.toLong() } catch (e) { return s } }
    if (s ==~ /-?\d+\.\d+([eE][+-]?\d+)?/) { try { return s.toDouble() } catch (e) { return s } }

    if (s.startsWith('[') && s.endsWith(']')) {
        String inner = s.substring(1, s.length() - 1).trim()
        if (inner.length() == 0) return []
        List items = []
        int i = 0, len = inner.length()
        int depth = 0
        boolean inStr = false
        char sc = '"' as char
        int start = 0
        while (i < len) {
            char c = inner.charAt(i)
            if (inStr) {
                if (c == ('\\' as char)) { i += 2; continue }
                if (c == sc) inStr = false
            } else {
                if (c == ('"' as char) || c == ("'" as char)) { inStr = true; sc = c }
                else if (c == ('[' as char) || c == ('{' as char)) depth++
                else if (c == (']' as char) || c == ('}' as char)) depth--
                else if (c == (',' as char) && depth == 0) {
                    items << parseValue(inner.substring(start, i).trim())
                    start = i + 1
                }
            }
            i++
        }
        if (start < len) items << parseValue(inner.substring(start).trim())
        return items
    }

    if (s.startsWith('{') && s.endsWith('}')) {
        return parseProps(s)
    }

    return s
}

parseProps = { String text ->
    text = text.trim()
    if (text.startsWith('{')) text = text.substring(1)
    if (text.endsWith('}')) text = text.substring(0, text.length() - 1)

    Map result = [:]
    int i = 0, len = text.length()
    while (i < len) {
        while (i < len && Character.isWhitespace(text.charAt(i))) i++
        if (i >= len) break

        int keyStart = i
        while (i < len && text.charAt(i) != (':' as char)) i++
        if (i >= len) break
        String key = text.substring(keyStart, i).trim()
        if (key.length() >= 2 && key.charAt(0) == ('"' as char) && key.charAt(key.length() - 1) == ('"' as char)) {
            key = key.substring(1, key.length() - 1)
        }
        i++

        while (i < len && Character.isWhitespace(text.charAt(i))) i++

        int valStart = i
        int depth = 0
        boolean inStr = false
        char strChar = '"' as char
        while (i < len) {
            char c = text.charAt(i)
            if (inStr) {
                if (c == ('\\' as char)) { i += 2; continue }
                if (c == strChar) inStr = false
            } else {
                if (c == ('"' as char) || c == ("'" as char)) { inStr = true; strChar = c }
                else if (c == ('[' as char) || c == ('{' as char)) depth++
                else if (c == (']' as char) || c == ('}' as char)) depth--
                else if (c == (',' as char) && depth == 0) break
            }
            i++
        }
        String rawValue = text.substring(valStart, Math.min(i, len)).trim()
        result[key] = parseValue(rawValue)

        if (i < len && text.charAt(i) == (',' as char)) i++
    }
    return result
}

isLineComplete = { String line ->
    int depth = 0
    boolean inStr = false
    char sc = '"' as char
    int i = 0, len = line.length()
    while (i < len) {
        char c = line.charAt(i)
        if (inStr) {
            if (c == ('\\' as char)) { i += 2; continue }
            if (c == sc) inStr = false
        } else {
            if (c == ('"' as char) || c == ("'" as char)) { inStr = true; sc = c }
            else if (c == ('[' as char) || c == ('{' as char)) depth++
            else if (c == (']' as char) || c == ('}' as char)) depth--
        }
        i++
    }
    return depth <= 0
}

graph = JanusGraphFactory.open('/opt/bitnami/janusgraph/conf/janusgraph-cql.properties')
binding.graph = graph
binding.g = graph.traversal()

// Read schema once; drives per-key type coercion + cardinality-aware writes.
// Source of truth = schema_init.groovy. No hardcoded numericKeys/booleanKeys here.
propTypes = [:]   // keyName → [dataType, cardinality]
schemaMgmt = graph.openManagement()
try {
    schemaMgmt.getRelationTypes(org.janusgraph.core.PropertyKey.class).each { pk ->
        propTypes[pk.name()] = [pk.dataType(), pk.cardinality()]
    }
} finally {
    schemaMgmt.rollback()
}
println "Loaded ${propTypes.size()} property keys from schema."

// Cleanup pass: drop any vertices left over from a previous broken run.
// "Junk" = a vertex that has `node_id` but no `IL_UNIQUE_ID`. These were
// produced by the old regex-based parser when JSON deserialisation failed
// and the fallback regex matched single characters as key/value pairs,
// creating a vertex with garbage props like `o=s, p=k, s=3, i=d, ...`.
// Re-running the importer must remove these so the correct vertices can
// be inserted (the importer skips when node_id already exists in JG).
junkBefore = graph.traversal().V().has('node_id').hasNot('IL_UNIQUE_ID').count().next()
if (junkBefore > 0) {
    println "Cleanup: dropping ${junkBefore} junk vertices left over from a previous run..."
    graph.traversal().V().has('node_id').hasNot('IL_UNIQUE_ID').drop().iterate()
    graph.tx().commit()
    println "Cleanup done. Vertices now: " + graph.traversal().V().count().next()
}

println "--- STARTING DATA MIGRATION (quote-aware parser) ---"

replaceExisting = false
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

println "Importing Nodes..."

binding.tx = graph.buildTransaction().logIdentifier("learning_graph_events").start()
binding.txG = binding.tx.traversal()

if (!binding.hasVariable('state')) {
    binding.state = [accumulating: false, nodeLine: '']
}

stats_imported = 0
stats_skipped = 0
stats_errors = 0

// Coerce raw value → declared schema dataType. Returns null on unrecoverable cast.
coerceToType = { val, dataType ->
    if (val == null) return null
    if (dataType == null) {
        // Undeclared key: fall back to legacy behavior
        if (val instanceof BigDecimal) return val.doubleValue()
        if (val instanceof Map) return val.toString()
        return val
    }
    if (dataType == Long.class) {
        if (val instanceof Number) return ((Number) val).longValue()
        if (val instanceof String) { try { return val.toLong() } catch (e) { return null } }
        return null
    }
    if (dataType == Integer.class) {
        if (val instanceof Number) return ((Number) val).intValue()
        if (val instanceof String) { try { return val.toInteger() } catch (e) { return null } }
        return null
    }
    if (dataType == Double.class) {
        if (val instanceof Number) return ((Number) val).doubleValue()
        if (val instanceof String) { try { return val.toDouble() } catch (e) { return null } }
        return null
    }
    if (dataType == Boolean.class) {
        if (val instanceof Boolean) return val
        if (val instanceof String) {
            String sv = val.trim().toLowerCase()
            if (sv in ['true','yes','1']) return true
            if (sv in ['false','no','0']) return false
            return null
        }
        return null
    }
    if (dataType == String.class) {
        // Sunbird convention: SINGLE-cardinality String prop holds JSON-array/object
        // string when value is collection (e.g. audience=["Student"] → '["Student"]').
        // Knowlg deserializes this back to list at read time.
        if (val instanceof List || val instanceof Map) return groovy.json.JsonOutput.toJson(val)
        return val.toString()
    }
    return val
}

new File('/tmp/nodes.csv').eachLine { line, idx ->
    try {
        if (idx == 1) return

        def state = binding.state
        def g = binding.txG

        if (state.accumulating) {
            state.nodeLine = state.nodeLine + ' ' + line.trim()
            if (isLineComplete(state.nodeLine)) state.accumulating = false
            else return
        } else {
            state.nodeLine = line
            if (!isLineComplete(line)) {
                state.accumulating = true
                return
            }
        }

        String full = state.nodeLine.trim()
        int p1 = full.indexOf(',')
        if (p1 < 0) { stats_skipped++; println "Skipping line $idx: no comma"; return }
        String nodeIdStr = full.substring(0, p1).trim()
        String rest = full.substring(p1 + 1).trim()

        int labStart = rest.indexOf('[')
        int labEnd = rest.indexOf(']')
        if (labStart < 0 || labEnd < 0 || labEnd < labStart) {
            stats_skipped++; println "Skipping line $idx: malformed label"; return
        }
        String labelRaw = rest.substring(labStart + 1, labEnd).replaceAll(/"/, '').trim()
        String afterLabel = rest.substring(labEnd + 1).trim()
        if (afterLabel.startsWith(',')) afterLabel = afterLabel.substring(1).trim()

        if (!afterLabel.startsWith('{')) {
            stats_skipped++; println "Skipping line $idx: no props block"; return
        }

        Long nodeIdVal
        try { nodeIdVal = nodeIdStr.toLong() } catch (e) {
            stats_skipped++; println "Skipping line $idx: bad nodeId '${nodeIdStr}'"; return
        }
        String label = labelRaw

        Map propsMap = parseProps(afterLabel)

        if (!propsMap['IL_UNIQUE_ID']) {
            stats_skipped++
            println "Skipping line $idx: parsed props has no IL_UNIQUE_ID (label=${label}, nodeId=${nodeIdVal})"
            return
        }

        def existing = g.V().has('node_id', nodeIdVal).tryNext().orElse(null)
        if (!existing) {
            def uid = propsMap['IL_UNIQUE_ID']
            if (uid) existing = g.V().has('IL_UNIQUE_ID', uid).tryNext().orElse(null)
        }

        if (existing && replaceExisting) {
            def dropTx = graph.newTransaction()
            dropTx.traversal().V(existing.id()).drop().iterate()
            dropTx.commit()
            existing = null
        }

        if (existing) return

        def v = binding.tx.addVertex(T.label, label, 'node_id', nodeIdVal)
        propsMap.each { k, vprop ->
            if (vprop == null) return
            String keyName = k.toString().trim()
            def schema = propTypes[keyName]
            def dataType = schema ? schema[0] : null
            def cardinality = schema ? schema[1] : null

            if (vprop instanceof List && cardinality == org.janusgraph.core.Cardinality.SET) {
                // Write each element separately so SET / LIST cardinality stores distinct members
                vprop.each { elem ->
                    def coerced = coerceToType(elem, dataType)
                    if (coerced == null) return
                    try { v.property(keyName, coerced) }
                    catch (Exception pe) { println "  skip ${keyName}=${coerced}: ${pe.message}" }
                }
            } else if (vprop instanceof List && cardinality == org.janusgraph.core.Cardinality.LIST) {
                vprop.each { elem ->
                    def coerced = coerceToType(elem, dataType)
                    if (coerced == null) return
                    try { v.property(keyName, coerced) }
                    catch (Exception pe) { println "  skip ${keyName}=${coerced}: ${pe.message}" }
                }
            } else {
                // SINGLE / undeclared: if List, fall back to join
                def raw = vprop instanceof List ? vprop.join(',') : vprop
                def coerced = coerceToType(raw, dataType)
                if (coerced == null) return
                try { v.property(keyName, coerced) }
                catch (Exception pe) { println "  skip ${keyName}=${coerced}: ${pe.message}" }
            }
        }
        stats_imported++
    } catch (Exception e) {
        stats_errors++
        println "Error on line $idx: ${e.message}"
    }
}
binding.tx.commit()
println "Nodes imported=${stats_imported}, skipped=${stats_skipped}, errors=${stats_errors}"

println "Importing Relationships..."

binding.tx2 = graph.buildTransaction().logIdentifier("learning_graph_events").start()
binding.tx2G = binding.tx2.traversal()

edge_imported = 0
edge_skipped = 0

new File('/tmp/relationships.csv').eachLine { line, idx ->
    try {
        if (idx == 1) return

        def g = binding.tx2G

        def matcher = line =~ /^(\d+),\s*"([^"]+)",\s*(\{.*\}|),\s*(\d+)$/
        if (!matcher.matches()) {
            matcher = line =~ /^(\d+),\s*"([^"]+)",\s*,\s*(\d+)$/
        }
        if (!matcher.matches()) {
            edge_skipped++
            println "Skipping edge line $idx: $line"
            return
        }

        Long fromId = matcher[0][1].toLong()
        String relType = matcher[0][2].trim()
        String propsRaw = matcher[0][3].trim()
        Long toId = matcher[0][4].toLong()

        Map propsMap = [:]
        if (propsRaw && propsRaw != '{}') {
            try { propsMap = parseProps(propsRaw) } catch (Exception pe) {
                println "Edge prop parse failed line $idx: ${pe.message}"
            }
        }

        def fromV = g.V().has('node_id', fromId).tryNext().orElse(null)
        def toV = g.V().has('node_id', toId).tryNext().orElse(null)

        if (fromV && toV) {
            def existing = fromV.edges(Direction.OUT, relType).find { it.inVertex().value('node_id') == toId }
            if (!existing) {
                def e = fromV.addEdge(relType, toV)
                propsMap.each { k, vv ->
                    if (vv != null) e.property(k, vv instanceof List ? vv.join(',') : vv)
                }
                edge_imported++
            }
        } else {
            edge_skipped++
        }
    } catch (Exception e) {
        edge_skipped++
        println "Error on edge line $idx: ${e.message}"
    }
}
binding.tx2.commit()
println "Edges imported=${edge_imported}, skipped=${edge_skipped}"

println "Vertices: " + binding.g.V().count().next()
println "Edges: " + binding.g.E().count().next()

println "Closing graph..."
graph.close()
println "Graph closed."

System.exit(0)
