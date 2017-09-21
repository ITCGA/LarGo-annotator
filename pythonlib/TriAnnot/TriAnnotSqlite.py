#!/usr/bin/env python

import os
import logging
import sqlite3
from collections import Counter, OrderedDict

from TriAnnot.TriAnnotStatus import *
import Utils

class TriAnnotSqlite (object):

    ###################
    ##  Constructor  ##
    ###################
    def __init__(self, databaseFileFullPath):
        # Logger
        self.logger = logging.getLogger("TriAnnot.TriAnnotSqlite")
        self.logger.addHandler(logging.NullHandler())

        self.logger.debug("Creating a new %s object" % (self.__class__.__name__))

        # Atributes
        self.databaseFileFullPath = databaseFileFullPath

        # Names of the tables
        self.globalFilesTableName = "Global_files"
        self.parametersTableName = "Parameters"
        self.sequencesTableName = "Sequences"
        self.instancesTableName = "Instances"
        self.systemStatisticsTableName = "System_Statistics"

        # Create a new database if needed
        if not Utils.isExistingFile(self.databaseFileFullPath):
            self.createDefaultDatabase()
            self.initializeSystemStatisticsTableRow()


    ##################################################
    ##  Table's creation and initialization methods ##
    ##################################################
    def createDefaultDatabase(self):
        try:
            sqlDatabaseConnection = sqlite3.connect(self.databaseFileFullPath)
            dbCursor = sqlDatabaseConnection.cursor()

            # Creation of the table that will store the names and md5 hash of all global files
            dbCursor.execute('''
                CREATE TABLE %s (
                    globalFileFullPath TEXT NOT NULL,
                    globalFileSecureHash TEXT NOT NULL
                )''' % self.globalFilesTableName)

            # Creation of the table that will keep the main parameters safe (ie. parameters required to restart the pipeline execution)
            dbCursor.execute('''
                CREATE TABLE %s (
                    sequenceFileFullPath TEXT NOT NULL,
                    globalConfigurationFileFullPath TEXT NOT NULL,
                    globalTaskFileFullPath TEXT NOT NULL,
                    mainExecDirFullPath TEXT NOT NULL,
                    sequenceType TEXT NOT NULL,
                    debugMode INTEGER NOT NULL,
                    instanceJobRunnerName TEXT NOT NULL,
                    taskJobRunnerName TEXT NOT NULL,
                    maxParallelAnalysis INTEGER NOT NULL,
                    monitoringInterval INTEGER NOT NULL,
                    killOnAbort INTEGER NOT NULL,
                    cleanPattern TEXT NOT NULL,
                    emailTo TEXT,
                    shortIdentifier TEXT NO NULL,
                    chunkOverlappingSize INTEGER NOT NULL
                )''' % self.parametersTableName)

            # Creation of the table that will store the data of each sequence
            dbCursor.execute('''
                CREATE TABLE %s (
                    sequenceName TEXT UNIQUE NOT NULL,
                    numberOfChunk INTEGER NOT NULL,
                    reconstructed INTEGER DEFAULT 0,
                    reconstructionStatus TEXT
                )''' % self.sequencesTableName)

            # Creation of the table that will store the data of each analysis/instance
            dbCursor.execute('''
                CREATE TABLE %s (
                    id INTEGER UNIQUE NOT NULL,
                    sequenceName TEXT NOT NULL,
                    sequenceType TEXT NOT NULL,
                    sequenceStartOffset INTEGER NOT NULL,
                    sequenceEndOffset INTEGER NOT NULL,
                    sequenceSize INTERGER NOT NULL,
                    chunkName TEXT NOT NULL,
                    chunkNumber INTEGER NOT NULL,
                    chunkStartOffset INTEGER NOT NULL,
                    chunkEndOffset INTEGER NOT NULL,
                    chunkSize INTEGER NOT NULL,
                    instanceSubmissionDate DATETIME,
                    instanceStartDate DATETIME,
                    instanceEndDate DATETIME,
                    instanceStatus INTEGER,
                    instanceProgression INTEGER,
                    instanceExecutionTime INTEGER,
                    instanceFastaFileFullPath TEXT,
                    instanceDirectoryFullPath TEXT,
                    instanceDirectorySize INTEGER,
                    instanceJobIdentifier INTEGER,
                    instanceMonitoringCommand TEXT,
                    instanceKillCommand TEXT,
                    instanceBackupArchive TEXT
                )''' % self.instancesTableName)

            # Creation of the table that will store the global statistics
            dbCursor.execute('''
                CREATE TABLE %s (
                    totalCpuTime REAL,
                    totalRealTime REAL,
                    totalDiskUsage INTEGER
                )''' % self.systemStatisticsTableName)

        except Exception as sqlError:
            self.logger.error("An error occured during the creation of the SQLite database !")
            sqlDatabaseConnection.rollback()
            raise sqlError
        finally:
            sqlDatabaseConnection.commit()
            sqlDatabaseConnection.close()


    def initializeSystemStatisticsTableRow(self):
        try:
            sqlDatabaseConnection = sqlite3.connect(self.databaseFileFullPath)
            dbCursor = sqlDatabaseConnection.cursor()

            # Build SQL request (no placholders)
            sqlInsertRequest = 'INSERT INTO %s(totalCpuTime, totalRealTime, totalDiskUsage) VALUES (0.0, 0.0, 0)' % self.systemStatisticsTableName

            self.logger.debug("SQL insert command in the <initializeSystemStatisticsTableRow> method: %s" % sqlInsertRequest)

            # Execute request
            dbCursor.execute(sqlInsertRequest)

        except Exception as sqlError:
            self.logger.error("An error occured during the creation of the unique row in the <%s> table !" % self.systemStatisticsTableName)
            sqlDatabaseConnection.rollback()
            raise sqlError
        finally:
            sqlDatabaseConnection.commit()
            sqlDatabaseConnection.close()


    ###############################
    ##  Table's filling methods  ##
    ###############################
    def genericInsertOrReplaceFromDict(self, tableName, contentDict):
        try:
            sqlDatabaseConnection = sqlite3.connect(self.databaseFileFullPath)
            dbCursor = sqlDatabaseConnection.cursor()

            # Build SQL request (with placholders)
            columns = ', '.join(contentDict.keys())
            placeholders = ':' + ', :'.join(contentDict.keys())

            sqlInsertRequest = 'INSERT OR REPLACE INTO %s(%s) VALUES (%s)' % (tableName, columns, placeholders)

            self.logger.debug("SQL insert command in the <genericInsertOrReplaceFromDict> method: %s" % sqlInsertRequest)

            # Execute request
            dbCursor.execute(sqlInsertRequest, contentDict)

        except Exception as sqlError:
            self.logger.error("An error occured during the filling of table <%s> in the <genericInsertOrReplaceFromDict> method !" % tableName)
            sqlDatabaseConnection.rollback()
            raise sqlError
        finally:
            sqlDatabaseConnection.commit()
            sqlDatabaseConnection.close()


    def registerAllInstances(self, instanceTableEntries):
        try:
            sqlDatabaseConnection = sqlite3.connect(self.databaseFileFullPath)
            dbCursor = sqlDatabaseConnection.cursor()

            analysisNumber = 0
            for instanceTableEntry in instanceTableEntries:
                # Convert the object into a dict and give an id to the analysis
                analysisNumber += 1
                currentAnalysisAsDict = instanceTableEntry.convertToDict()
                currentAnalysisAsDict['id'] = analysisNumber

                # Build SQL request (with placholders)
                columns = ', '.join(currentAnalysisAsDict.keys())
                placeholders = ':' + ', :'.join(currentAnalysisAsDict.keys())

                sqlInsertRequest = 'INSERT INTO %s(%s) VALUES (%s)' % (self.instancesTableName, columns, placeholders)

                self.logger.debug("SQL insert command in the <registerAllInstances> method: %s" % sqlInsertRequest)

                # Execute request
                dbCursor.execute(sqlInsertRequest, currentAnalysisAsDict)

        except Exception as sqlError:
            self.logger.error("An error occured during the registration of the TriAnnot analysis into the <%s> table !" % self.instancesTableName)
            sqlDatabaseConnection.rollback()
            raise sqlError
        finally:
            sqlDatabaseConnection.commit()
            sqlDatabaseConnection.close()


    #####################################################
    ##  Table's consultation methods - Basic requests  ##
    #####################################################
    def _getTableAsListOfDict(self, callingMethod, nbRows= None, columns= None, tableName= None, where= None, orderBy= None, orderWay= 'ASC'):
        # Initializations
        listOfRows = list()
        nbRows = nbRows if nbRows is not None else 'all'
        selectString = '*'
        whereString = ''
        orderByString = ''

        # Prepare request elements
        if columns is not None:
            selectString = ', '.join(columns)
        if where is not None and len(where) > 0:
            whereString = 'WHERE '
            for keyName, keyValue in where.items():
                whereString += '%s = "%s"' % (keyName, keyValue)
        if orderBy is not None:
            orderByString = 'ORDER BY %s %s' % (orderBy, orderWay)

        # Get table content
        try:
            sqlDatabaseConnection = sqlite3.connect(self.databaseFileFullPath)
            sqlDatabaseConnection.row_factory = sqlite3.Row
            sqlDatabaseConnection.text_factory = str

            dbCursor = sqlDatabaseConnection.cursor()

            # Build SQL request (with placholders)
            sqlSelectRequest = 'SELECT %s FROM %s %s %s' % (selectString, tableName, whereString, orderByString)

            self.logger.debug("SQL select command in the <%s> method: %s" % (callingMethod, sqlSelectRequest))

            # Execute request
            dbCursor.execute(sqlSelectRequest)

            if nbRows == 'all':
                collectedRows = dbCursor.fetchall()
            else:
                collectedRows = dbCursor.fetchmany(nbRows)

            # Parse request result
            for collectedRow in collectedRows:
                columnsData = dict()
                for keyName in collectedRow.keys():
                    columnsData[keyName] = collectedRow[keyName]
                listOfRows.append(columnsData)

        except Exception as sqlError:
            self.logger.error("An error occured during the extraction of <%s> rows from table <%s> !" % (nbRows, tableName))
            sqlDatabaseConnection.rollback()
            raise sqlError
        finally:
            sqlDatabaseConnection.commit()
            sqlDatabaseConnection.close()

        # Smart return
        return listOfRows


    def recoverInstancesFromDatabase(self, nbInstances = None, instanceStatus = None):
        if instanceStatus is not None:
            return self._getTableAsListOfDict('recoverInstancesFromDatabase', nbRows= nbInstances, tableName= self.instancesTableName, where= {'instanceStatus': instanceStatus}, orderBy= 'id')
        else:
            return self._getTableAsListOfDict('recoverInstancesFromDatabase', nbRows= nbInstances, tableName= self.instancesTableName, orderBy= 'id')


    def recoverParametersFromDatabase(self):
        return self._getTableAsListOfDict('recoverParametersFromDatabase', tableName= self.parametersTableName)[0]


    def recoverGlobalFileChecksum(self, globalFileFullPath):
        # Execute basic selection request
        requestFirstResult = self._getTableAsListOfDict('recoverGlobalFileChecksum', tableName= self.globalFilesTableName, where= {'globalFileFullPath': globalFileFullPath})[0]

        # Return the useful information
        return requestFirstResult['globalFileSecureHash']


    def getSequencesStatus(self, returnStatusAsString = False):
        # Initializations
        instancesStatus = OrderedDict()

        # Execute basic selection request
        requestRawResults =  self._getTableAsListOfDict('getSequencesStatus', columns = ['sequenceName', 'chunkName', 'instanceStatus', 'instanceProgression'], tableName= self.instancesTableName, orderBy= 'id')

        # Reformat results
        for result in requestRawResults:
            if not instancesStatus.has_key(result['sequenceName']):
                instancesStatus[result['sequenceName']] = OrderedDict()
            if returnStatusAsString:
                adaptedStatus = TriAnnotStatus.getStatusName(result['instanceStatus'])
            else:
                adaptedStatus = result['instanceStatus']
            instancesStatus[result['sequenceName']][result['chunkName']] = {'status': str(adaptedStatus), 'progression': str(result['instanceProgression']) + '%'}

        return instancesStatus


    def getStatusCounters(self, returnStatusAsString = False):
        # Initializations
        allStatus = list()

        # Execute basic selection request
        requestRawResults = self._getTableAsListOfDict('getStatusCounters', columns = ['instanceStatus'], tableName= self.instancesTableName)

        # Counthe number of instance in each status
        for result in requestRawResults:
            if returnStatusAsString:
                allStatus.append(TriAnnotStatus.getStatusName(result['instanceStatus']))
            else:
                allStatus.append(result['instanceStatus'])

        return Counter(allStatus)


    def getSystemStatistics(self):
        return self._getTableAsListOfDict('getSystemStatistics', tableName= self.systemStatisticsTableName)[0]


    def isInstanceMarkedAsSubmitted(self, instanceId):
        # Get the instance submission date (there could be only one result since the where clause is on the primary key)
        requestResult = self._getTableAsListOfDict('isInstanceMarkedAsSubmitted', nbRows= 1, columns= ['instanceSubmissionDate'], tableName= self.instancesTableName, where= {'id': instanceId})[0]

        if requestResult['instanceSubmissionDate'] is not None:
            return True
        else:
            return False


    def getChunkData(self, requiredSequenceName):
        return self._getTableAsListOfDict('getChunkData', columns = ['chunkName', 'chunkNumber', 'chunkSize', 'instanceDirectoryFullPath'], tableName= self.instancesTableName, where= {'sequenceName': requiredSequenceName}, orderBy= 'chunkNumber')



    ##################################################################
    ##  Table's consultation methods  - Complex requests with join  ##
    ##################################################################
    def getSequencesAnalysisStatus(self):
        # Initializations
        sequencesStatus = dict()

        # Get table content
        try:
            sqlDatabaseConnection = sqlite3.connect(self.databaseFileFullPath)
            sqlDatabaseConnection.row_factory = sqlite3.Row
            sqlDatabaseConnection.text_factory = str

            dbCursor = sqlDatabaseConnection.cursor()

            # Build SQL request (with placholders)
            selectString = 'T1.sequenceName, T1.numberOfChunk, count(T2.chunkName) as numberOfFinishedChunk, group_concat(DISTINCT T2.instanceStatus) as distinctInstancesStatus, reconstructed, reconstructionStatus'
            fromJoinString = "%s T1 INNER JOIN %s T2 ON T1.sequenceName = T2.sequenceName" % (self.sequencesTableName, self.instancesTableName)
            whereString = 'T2.instanceStatus between 10 and 12'
            groupByString = 'T1.sequenceName'

            # Build SQL request (with placholders)
            sqlSelectRequest = 'SELECT %s FROM %s WHERE %s GROUP BY %s' % (selectString, fromJoinString, whereString, groupByString)
            self.logger.debug("SQL select command in the <getListOfCompletedSequenceAnalysis> method: %s" % sqlSelectRequest)

            # Execute request
            dbCursor.execute(sqlSelectRequest)

            # Get all results
            collectedRows = dbCursor.fetchall()

            # Parse request result
            for collectedRow in collectedRows:
                columnsData = dict()
                for keyName in collectedRow.keys():
                    if keyName == 'distinctInstancesStatus':
                        distinctStatutes = collectedRow[keyName].split(',')
                        if len(distinctStatutes) > 1:
                            columnsData[keyName] = distinctStatutes
                        else:
                            columnsData[keyName] = int(collectedRow[keyName])
                    else:
                        columnsData[keyName] = collectedRow[keyName]

                sequencesStatus[collectedRow['sequenceName']] = columnsData

            self.logger.debug(sequencesStatus)

        except Exception as sqlError:
            self.logger.error("An error occured during the collect of the status of every sequences in method <getSequencesAnalysisStatus> !")
            sqlDatabaseConnection.rollback()
            raise sqlError
        finally:
            sqlDatabaseConnection.commit()
            sqlDatabaseConnection.close()

        # Smart return
        return sequencesStatus


    ##################################
    ##  Table's row update methods  ##
    ##################################
    def updateSequenceTableDuringReconstruction(self, sequenceName, reconstructionStatus):
        try:
            sqlDatabaseConnection = sqlite3.connect(self.databaseFileFullPath)
            dbCursor = sqlDatabaseConnection.cursor()

            sqlUpdateRequest = 'UPDATE %s set reconstructed= "%d", reconstructionStatus= "%s" WHERE sequenceName= "%s"' % (self.sequencesTableName, 1, reconstructionStatus, sequenceName)

            self.logger.debug("SQL update command (during reconstruction) for table <%s>: %s" % (self.sequencesTableName, sqlUpdateRequest))

            dbCursor.execute(sqlUpdateRequest)

        except Exception as sqlError:
            self.logger.error("An error occured during the update of sequence <%s> in table <%s> (during reconstruction)!" % (sequenceName, self.sequencesTableName))
            sqlDatabaseConnection.rollback()
            raise sqlError
        finally:
            sqlDatabaseConnection.commit()
            sqlDatabaseConnection.close()


    def updateInstanceTableAtSubmission(self, instanceId, instanceStatus, instanceSubmissionDate, instanceFastaFileFullPath, instanceDirectoryFullPath, instanceJobIdentifier, instanceMonitoringCommand, instanceKillCommand):
        try:
            sqlDatabaseConnection = sqlite3.connect(self.databaseFileFullPath)
            dbCursor = sqlDatabaseConnection.cursor()

            sqlUpdateRequest = 'UPDATE %s set instanceStatus= "%d", instanceSubmissionDate= "%s", instanceFastaFileFullPath= "%s", instanceDirectoryFullPath= "%s", instanceJobIdentifier= "%d", instanceMonitoringCommand= "%s", instanceKillCommand= "%s" WHERE id= "%d"' % (self.instancesTableName, instanceStatus, instanceSubmissionDate, instanceFastaFileFullPath, instanceDirectoryFullPath, instanceJobIdentifier, instanceMonitoringCommand, instanceKillCommand, instanceId)

            self.logger.debug("SQL update command (at submission time) for table <%s>: %s" % (self.instancesTableName, sqlUpdateRequest))

            dbCursor.execute(sqlUpdateRequest)

        except Exception as sqlError:
            self.logger.error("An error occured during the update of instance <%d> in table <%s> (at submission)!" % (instanceId, self.instancesTableName))
            sqlDatabaseConnection.rollback()
            raise sqlError
        finally:
            sqlDatabaseConnection.commit()
            sqlDatabaseConnection.close()


    def updateInstanceTableDuringMonitoring(self, instanceId, instanceStatus, instanceProgression):
        try:
            sqlDatabaseConnection = sqlite3.connect(self.databaseFileFullPath)
            dbCursor = sqlDatabaseConnection.cursor()

            sqlUpdateRequest = 'UPDATE %s set instanceStatus= "%d", instanceProgression= "%d" WHERE id= "%d"' % (self.instancesTableName, instanceStatus, instanceProgression, instanceId)

            self.logger.debug("SQL update command (during monitoring) for table <%s>: %s" % (self.instancesTableName, sqlUpdateRequest))

            dbCursor.execute(sqlUpdateRequest)

        except Exception as sqlError:
            self.logger.error("An error occured during the update of instance <%d> in table <%s> (during monitoring) !" % (instanceId, self.instancesTableName))
            sqlDatabaseConnection.rollback()
            raise sqlError
        finally:
            sqlDatabaseConnection.commit()
            sqlDatabaseConnection.close()


    def updateInstanceTableAtCompletion(self, instanceId, instanceStartDate, instanceEndDate, instanceStatus, instanceProgression, instanceExecutionTime, instanceDirectorySize):
        try:
            sqlDatabaseConnection = sqlite3.connect(self.databaseFileFullPath)
            dbCursor = sqlDatabaseConnection.cursor()

            sqlUpdateRequest = 'UPDATE %s set instanceStartDate= "%s", instanceEndDate= "%s", instanceStatus= "%d", instanceProgression= "%d", instanceExecutionTime= "%s", instanceDirectorySize= "%d" WHERE id= "%d"' % (self.instancesTableName, instanceStartDate, instanceEndDate, instanceStatus, instanceProgression, instanceExecutionTime, instanceDirectorySize, instanceId)

            self.logger.debug("SQL update command (at completion) for table <%s>: %s" % (self.instancesTableName, sqlUpdateRequest))

            dbCursor.execute(sqlUpdateRequest)

        except Exception as sqlError:
            self.logger.error("An error occured during the update of instance <%d> in table <%s> (at completion) !" % (instanceId, self.instancesTableName))
            sqlDatabaseConnection.rollback()
            raise sqlError
        finally:
            sqlDatabaseConnection.commit()
            sqlDatabaseConnection.close()


    def updateSystemStatisticsTableAtCompletion(self, totalCpuTime, totalRealTime, totalDiskUsage):
        try:
            sqlDatabaseConnection = sqlite3.connect(self.databaseFileFullPath)
            dbCursor = sqlDatabaseConnection.cursor()

            sqlUpdateRequest = 'UPDATE %s set totalCpuTime= "%.3f", totalRealTime= "%.3f", totalDiskUsage= "%d"' % (self.systemStatisticsTableName, totalCpuTime, totalRealTime, totalDiskUsage)

            self.logger.debug("SQL update command for table <%s>: %s" % (self.systemStatisticsTableName, sqlUpdateRequest))

            dbCursor.execute(sqlUpdateRequest)

        except Exception as sqlError:
            self.logger.error("An error occured during the update of the rows of table <%s> (at instance completion) !" % (self.systemStatisticsTableName))
            sqlDatabaseConnection.rollback()
            raise sqlError
        finally:
            sqlDatabaseConnection.commit()
            sqlDatabaseConnection.close()
