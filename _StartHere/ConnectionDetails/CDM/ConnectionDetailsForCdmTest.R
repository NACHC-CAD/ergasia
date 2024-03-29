# ---
#
# Run this script to test the connection details for the cdm connection.  
#
# ---

source("./R/impl/configuration/ConfigurationFactory.R")
source("./R/impl/connection/ConnectionDetailsFactory.R")
source("./R/impl/connection/ConnectionDetailsTester.R")

config <- ConfigurationFactory$getConfiguration()
dbms <- config$dbms

connectionDetails <- ConnectionDetailsFactory$getCdmConnectionDetails()
ConnectionDetailsTester$testConnection(connectionDetails, dbms)

