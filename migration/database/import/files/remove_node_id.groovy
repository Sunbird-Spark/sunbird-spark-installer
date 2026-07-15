// Remove the temporary `node_id` property added during Neo4j → JanusGraph import.
// `node_id` is the Neo4j internal integer ID used by import_data.groovy to resolve
// relationship endpoints. It has no meaning in JanusGraph and must be removed after
// import completes.
graph = JanusGraphFactory.open('/opt/bitnami/janusgraph/conf/janusgraph-cql.properties')
g = graph.traversal()

total = g.V().has('node_id').count().next()
println("Vertices with node_id: " + total)

batchSize = 200
processed = 0
g.V().has('node_id').toList().collate(batchSize).each { batch ->
    batch.each { v -> v.property('node_id').remove() }
    graph.tx().commit()
    processed += batch.size()
    println("Removed node_id from " + processed + " / " + total + " vertices")
}

remaining = g.V().has('node_id').count().next()
println("Done. Remaining vertices with node_id: " + remaining)
graph.close()
