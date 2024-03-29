
# imports
source("./R/impl/configuration/ConfigurationFactory.R")
source("./_StartHere/ConnectionDetails/Results/ConnectionDetailsForResults.R")

# libraries
library(R6)

CreateStrategusResultsTablesUtil = R6Class (
  classname = "CreateStrategusResultsTablesUtil",
  public = list (
    
    # -------------------------------------------------------------------------
    # Implementation details
    # -------------------------------------------------------------------------
    
    # ---
    #
    # constructor
    #
    # ---
    
    initialize = function() {
      self$config <- ConfigurationFactory$getConfiguration()
      self$resultsDatabaseSchemaCreationLogFolder <- self$config$logDir
      self$resultsDatabaseSchemaPrefix <- self$config$resultsSchemaPrefix
      self$resultsDatabaseSchemaSuffixList <- ConfigurationFactory$getSuffixList()
    },
    
    # ---
    #
    # configuration
    #
    # ---
    
    config = NULL,
    
    resultsDatabaseSchemaCreationLogFolder = NULL,
    resultsDatabaseSchemaPrefix = NULL,
    resultsDatabaseSchemaSuffixList = NULL,
    
    # ---
    #
    # logging
    # 
    # ---
    
    initLogging = function(resultsDatabaseSchemaCreationLogFolder) {
      # stdout logging
      ParallelLogger::clearLoggers()
      ParallelLogger::addDefaultFileLogger(
        fileName = file.path(resultsDatabaseSchemaCreationLogFolder, "results-schema-setup-log.txt"),
        name = "RESULTS_SCHEMA_SETUP_FILE_LOGGER"
      )
      # stderr logging
      ParallelLogger::addDefaultErrorReportLogger(
        fileName = file.path(resultsDatabaseSchemaCreationLogFolder, 'results-schema-setup-errorReport.txt'),
        name = "RESULTS_SCHEMA_SETUP_ERROR_LOGGER"
      )
    },
    
    # ---
    #
    # did the module complete
    #
    # ---
    
    isModuleComplete = function(moduleFolder) {
      doneFileFound = (length(list.files(path = moduleFolder, pattern = "done")) > 0)
      isDatabaseMetaDataFolder = basename(moduleFolder) == "DatabaseMetaData"
      return(doneFileFound || isDatabaseMetaDataFolder)
    },
    
    # ---
    #
    # database connection
    # 
    # --
    
    getConnection = function() {
      resultsDatabaseConnectionDetails = ConnectionDetailsForResults$createConnectionDetails()
      connection = DatabaseConnector::connect(connectionDetails = resultsDatabaseConnectionDetails)
      return(connection)
    },
    
    # ---
    #
    # drop and create schema functions
    #
    # ---
    
    dropSchema = function(schemaName, connection) {
      writeLines(paste("Droping schema if exists: ", schemaName))
      sqlString = paste("drop schema if exists ", schemaName, " cascade")
      DatabaseConnector::executeSql(connection, sqlString)
    },
    
    createSchema = function(schemaName, connection) {
      writeLines(paste("Creating schema: ", schemaName))
      sqlString = paste("create schema ", schemaName)
      DatabaseConnector::executeSql(connection, sqlString)
    },
    
    dropAndRecreateSchema = function(schemaName, connection) {
      self$dropSchema(schemaName, connection)
      self$createSchema(schemaName, connection)
    },
    
    # ---
    #
    # create a table for each module
    #
    # ---
    
    createModuleTables = function(moduleFolders, resultsDatabaseSchema, connection) {
      message("Creating results tables in schema: ", resultsDatabaseSchema)
      for (moduleFolder in moduleFolders) {
        moduleName = basename(moduleFolder)
        if (self$isModuleComplete(moduleFolder) == FALSE) {
          warning("Module ", moduleName, " did not complete. Skipping table creation")
        } else {
          self$createModuleTable(moduleName, moduleFolder, resultsDatabaseSchema, connection)
        }
      }
    },
    
    # ---
    #
    # create a table for a single module
    #
    # ---
    
    createModuleTable = function(moduleName, moduleFolder, resultsDatabaseSchema, connection) {
      message("- Creating results for module ", moduleName)
      rdmsFile = file.path(moduleFolder, "resultsDataModelSpecification.csv")
      message(rdmsFile)
      if (file.exists(rdmsFile) == FALSE) {
        stop("resultsDataModelSpecification.csv not found in ", moduleFolder)
      } else {
        specification = CohortGenerator::readCsv(file = rdmsFile)
        sql = ResultModelManager::generateSqlSchema(csvFilepath = rdmsFile)
        sql = SqlRender::render(
          sql = sql,
          database_schema = resultsDatabaseSchema
        )
        DatabaseConnector::executeSql(connection = connection, sql = sql)
      }
    },
    
    # ---
    #
    # create a characterization table
    # (not sure why this is a one-off)
    #
    # ---
    
    createCharacterizationTable = function(resultsDatabaseSchema, connection) {
      message("Creating empty characterization tables in schema: ", resultsDatabaseSchema)
      rdmsFile = "./etc/results/cc_resultsDataModelSpecification.csv"
      specification = CohortGenerator::readCsv(file = rdmsFile)
      sql = ResultModelManager::generateSqlSchema(csvFilepath = rdmsFile)
      sql = SqlRender::render(
        sql = sql,
        database_schema = resultsDatabaseSchema
      )
      DatabaseConnector::executeSql(connection = connection, sql = sql)
    },
    
    # ---
    #
    # is the schema empty
    #
    # ---
    
    schemaIsEmpty = function(resultsDatabaseSchema, connection) {
      tables = DatabaseConnector::getTableNames(
        connection = connection,
        databaseSchema = resultsDatabaseSchema
      )
      if(length(tables) == 0) {
        return(TRUE)
      } else {
        return(FALSE)
      }
    },
    
    # -------------------------------------------------------------------------
    # Public interface: This is the core functionality of this class.  
    # -------------------------------------------------------------------------
    
    # ---
    #
    # create results tables
    #
    # ---
    
    createResultsTables = function(dropExisting = FALSE) {
      # init 
      self$initLogging(self$resultsDatabaseSchemaCreationLogFolder)
      # get a database connection
      connection = self$getConnection()
      # get the modules
      moduleFolders = ConfigurationFactory$getModuleList()
      tryCatch({
        # echo status
        message("Creating result tables based on definitions found in ", ConfigurationFactory$getResultsDir())
        # create a separate schema for each data partner
        for (schemaSuffix in self$resultsDatabaseSchemaSuffixList) {
          resultsDatabaseSchema = paste(self$resultsDatabaseSchemaPrefix, schemaSuffix, sep = "")
          # drop and recreate the schema
          if(dropExisting == TRUE) {
            writeLines(paste("DROPPING DATABASE SCHEMA: ", resultsDatabaseSchema))
            self$dropAndRecreateSchema(resultsDatabaseSchema, connection)
            writeLines(paste("DROPPED DATABASE SCHEMA:  ", resultsDatabaseSchema))
          }
          # create the data tables if the schema is empty
          if (self$schemaIsEmpty(resultsDatabaseSchema, connection)) {
            # create the module tables
            self$createModuleTables(moduleFolders, resultsDatabaseSchema, connection)
            # create the characterization table
            self$createCharacterizationTable(resultsDatabaseSchema, connection)
          } else {
            message("SKIPPING - Results tables already exist")
          }
        }
      },
      finally = {
        # Disconnect from the database -------------------------------------------------
        DatabaseConnector::disconnect(connection)
        # Unregister loggers -----------------------------------------------------------
        ParallelLogger::unregisterLogger("RESULTS_SCHEMA_SETUP_FILE_LOGGER")
        ParallelLogger::unregisterLogger("RESULTS_SCHEMA_SETUP_ERROR_LOGGER")
      })
      
    }
  )
)

CreateStrategusResultsTablesUtil$exec <- function(dropExisting = FALSE) {
  util <- CreateStrategusResultsTablesUtil$new()  
  util$createResultsTables(dropExisting)
}



