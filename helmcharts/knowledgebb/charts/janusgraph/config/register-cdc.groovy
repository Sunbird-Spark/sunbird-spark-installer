// register-cdc.groovy
// This script is intended to be run by JanusGraph Server on startup or via gremlin-console

import org.slf4j.Logger
import org.slf4j.LoggerFactory
import org.janusgraph.core.JanusGraphFactory

// Use Binding variable for logger to ensure scope availability in Gremlin shell
logger = LoggerFactory.getLogger("register-cdc-script");

try {
    println "Attempting to load GraphLogProcessor..."
    logger.info("Attempting to load GraphLogProcessor...");
    
    // Dynamically load the class to ensure it's on classpath
    Class<?> processorClass = Class.forName("org.sunbird.janusgraph.cdc.GraphLogProcessor");
    println "Class org.sunbird.janusgraph.cdc.GraphLogProcessor loaded successfully."
    
    // Debug bindings
    try {
        logger.info("Available bindings: " + binding.getVariables().keySet());
    } catch (Exception e) {}

    graphInstance = null;
    try {
        graphInstance = graph;
        println "Found graph instance in binding: " + graphInstance
    } catch (MissingPropertyException e) {
        println "Variable 'graph' not found in binding. Attempting to open graph manually..."
        try {
            def configPath = "/opt/bitnami/janusgraph/conf/janusgraph.properties"
            if (new File(configPath).exists()) {
                graph = JanusGraphFactory.open(configPath)
                graphInstance = graph
                println "Graph opened successfully from " + configPath
            } else {
                println "ERROR: Configuration file not found at " + configPath
                return;
            }
        } catch (Exception ex) {
            println "ERROR opening graph manually: " + ex.getMessage()
            return;
        }
    }

    if (graphInstance != null) {
        println "Using graph instance for CDC registration..."
        
        // Prepare Configuration
        Map<String, Object> config = new HashMap<>();
        
        // Configuration for the CDC processor
        config.put("graph.txn.log_processor.enable", "true");
        config.put("graph.txn.log_processor.sinks", "LOG"); // Set to "KAFKA,LOG" to enable both
        config.put("graph.txn.log_processor.converter", "SUNBIRD_LEGACY");
        
        // Kafka Configs (Optional - enable if using KAFKA sink)
        // config.put("kafka.bootstrap.servers", "kafka:29092");
        // config.put("kafka.topics.graph.event", "sunbirddev.learning.graph.events");

        println "CDC Config: " + config
        logger.info("CDC Config: " + config);
        
        // Call start method: start(JanusGraph graph, Map<String, Object> config)
        java.lang.reflect.Method startMethod = processorClass.getMethod("start", org.janusgraph.core.JanusGraph.class, Map.class);
        startMethod.invoke(null, graphInstance, config);
        
        println "GraphLogProcessor invoked successfully."
        logger.info("GraphLogProcessor invoked successfully.");
    } else {
        println "ERROR: Graph instance 'graph' not found. CDC Processor NOT started."
        logger.error("Graph instance 'graph' not found. CDC Processor NOT started.");
    }
} catch (ClassNotFoundException e) {
    println "ERROR: GraphLogProcessor class not found. Ensure jar is in /lib."
    logger.error("GraphLogProcessor class not found. Ensure janusgraph-cdc-extension jar is in /lib.", e);
} catch (NoSuchMethodException e) {
    println "ERROR: Start method not found in processor class."
    logger.error("Start method not found. Check method signature.", e);
} catch (Exception e) {
    println "ERROR starting GraphLogProcessor: " + e.getMessage()
    logger.error("Error starting GraphLogProcessor", e);
}
