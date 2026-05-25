// Set graphId = 'domain' for all vertices that have IL_UNIQUE_ID but no graphId
graph = JanusGraphFactory.open('/opt/bitnami/janusgraph/conf/janusgraph-cql.properties')
g = graph.traversal()

println("Setting graphId for vertices without graphId...")
count = g.V().has('IL_UNIQUE_ID').hasNot('graphId').count().next()
println("Vertices needing graphId: " + count)

g.V().has('IL_UNIQUE_ID').hasNot('graphId').property('graphId', 'domain').iterate()
graph.tx().commit()

updated = g.V().has('graphId', 'domain').count().next()
println("Vertices with graphId=domain: " + updated)
println("Done.")
graph.close()
