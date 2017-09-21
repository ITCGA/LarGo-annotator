#!/usr/bin/env python
# coding: utf-8

###############################
##  External modules import  ##
###############################
import os
import sys
import warnings

import argparse

import time
import datetime
import uuid

import logging
import exceptions
import traceback

import glob
import shutil
import re
import getpass
import fcntl as locker


###############################
##  Internal modules import  ##
###############################
from TriAnnot.TriAnnotVersion import TRIANNOT_VERSION
from TriAnnot.TriAnnotConfig import *
from TriAnnot.TriAnnotConfigurationChecker import *
from TriAnnot.TriAnnotTaskFileChecker import *
from TriAnnot.TriAnnotSqlite import *
from TriAnnot.TriAnnotInstanceTableEntry import *
from TriAnnot.TriAnnotSequenceGoals import *
from TriAnnot.TriAnnotRunner import *
from TriAnnot.TriAnnotInstance import *
from TriAnnot.TriAnnotTask import *
from TriAnnot.ColoredFormatter import *
import TriAnnot.Utils


############################
##  Debug modules import  ##
############################
## Data Dumper equivalent
#import pprint
#import json
#pp = pprint.PrettyPrinter(indent=4)

## Memory usage analysis
#from memory_profiler import profile


###############################
##  TriAnnot Pipeline class  ##
###############################

class TriAnnotPipeline (object):

    ###################
    ##  Constructor  ##
    ###################

    def __init__(self):
        # Get the logger ahd give it a Null Handler
        self.logger = logging.getLogger("TriAnnot")
        self.logger.addHandler(logging.NullHandler())

        # Timers
        self.systemStartTime = None
        self.humanlyReadableStartDate = None
        self.humanlyReadableEndDate = None
        self.humanlyReadableTotalTime = None

        # Identifiers
        self.shortIdentifier = None
        self.uniqueIdentifier = None
        self.programName = os.path.basename(sys.argv[0])
        self.commandLine = ' '.join(sys.argv)

        # Argparse related attributes
        self.mainArgumentParser = None

        self.mainParserBasicOptionGroup = None
        self.mainParserCommonOptionGroup = None

        self.debugMode = None
        self.activateFileLoggers = None
        self.colorizeScreenLogger = False
        self.mainExecDirFullPath = None
        self.helpArgumentIsUsed = None

        self.subparsers = None
        self.databaseArgumentParser = None
        self.runArgumentParser = None
        self.selectedSubCommand = None

        # Run mode specific attributes
        self.runArgumentParser = None

        self.runParserBasicOptionGroup = None
        self.runParserMandatoryOptionGroup = None
        self.runParserConfigOptionGroup = None
        self.runParserRunnerOptionGroup = None
        self.runParserSequenceOptionGroup = None
        self.runParserTriAnnoUnitOptionGroup = None
        self.runParserMiscOptionGroup = None

        self.configFileFullPath = None
        self.cmdLineConfigAlone = None
        self.checkOnly = None

        self.sqliteDatabaseFileName = 'TriAnnotPipeline_database.sqlite3'
        self.sqliteDatabaseFileFullPath = None
        self.sequenceFileFullPath = None
        self.tasksFileFullPath = None
        self.sequenceType = None

        self.instanceJobRunnerName = None
        self.maxParallelAnalysis = None
        self.taskJobRunnerName = None

        self.minimumSequenceLength = None
        self.maximumSequenceLength = None
        self.activateSequenceSplitting = None
        self.chunkOverlappingSize = None

        self.monitoringInterval = None
        self.stillAliveJobMonitoringInterval = None
        self.killOnAbort = None
        self.ignoreOriginalSequenceMasking = None
        self.cleanPattern = None
        self.emailTo = None

        self.availableRunners = None

        # Generated full/global file related attributes
        self.globalConfigurationFileFullPath = None
        self.globalTaskFileFullPath = None

        # List of instances to execute
        self.instances = dict()

        # Lock file management
        self.lockFileFullPath = None
        self.lockFileHandler = None
        self.isAlreadyLocked = False

        # Other attributes
        self.configurationCheckerObject = None
        self.taskFileDescription = ''
        self.pipelineAbortedAfterManagedError = False


    ####################
    ##      Main      ##
    ####################

    def main(self):
        # Store the start time of the anlysis (will be used to compute execution time)
        self.systemStartTime = time.time()
        self.humanlyReadableStartDate = time.strftime("%a %Y-%m-%d at %Hh%Mm%Ss")

        # Assign a UUID to the new TriAnnot analysis
        self._generateTriAnnotUniqueId()

        # Preparation of the analysis
        # This step depends on the sub-command (monitor/resume/retry/run) selected with the command line
        # Please have a look at this method to get more informations
        self.prepareAnalysis()

        # Start Log
        self.displayStartMessage()

        # Main execution loop - Runs and monitor all instances
        try:
            if self.selectedSubCommand == 'monitor':
                self.displayInstancesStatus()
            elif self.selectedSubCommand == 'reconstruct':
                self.performResultFilesReconstruction()
            else:
                self.executeInstances()
                self.cleanMainExecutionFolder()
                self.sendNotificationEmail()
                self.computeTotalElapsedTime()
                self.createTriAnnotFinishedFile()

        except KeyboardInterrupt:
            if self.selectedSubCommand != 'monitor' and self.selectedSubCommand != 'reconstruct':
                self.manageKeyboardInterrupt()

        except Exception as ex:
            # Abort everything in case of unexpected error
            if not self.pipelineAbortedAfterManagedError:
                self.logger.debug("Error traceback message:\n%s" % traceback.format_exc())
                if self.selectedSubCommand != 'monitor' and self.selectedSubCommand != 'reconstruct':
                    self.abortAllInstances("An unexpected error occured ! (Raised error: %s)" % ex.message)
                else:
                    self.logger.error("An unexpected error occured ! (Raised error: %s)" % ex.message)

        finally:
            # Last update of the SQLite database (Mostly used for canceled instances)
            self.treatFinishedOrCanceledInstances()

            # End log
            self.displayEndMessage()

            # Reminder
            self.dislayReminder()

            # Remove lock file
            self.deleteLockFile()


    ###########################
    ##  Main execution loop  ##
    ###########################

    def executeInstances(self):
        # Check if some instances have already been executed (and maybe completed) by a previous TriAnnotPipeline execution
        self.checkForAlreadyCompletedInstances()

        # Display initial status counters
        self.displayStatusCounters()

        while len(self.instances) > 0:
            # Check and update the status of the various instances
            self.checkAndUpdateInstanceStatus()

            # Remove completed/canceled/error instances from the list of instances and update the Instances and System_Statistics tables
            self.treatFinishedOrCanceledInstances()

            # We can continue if there is at least one instance to run or monitor
            if len(self.instances) > 0:
                # Check if the user have created a TriAnnot_abort file in the main execution folder
                self.checkUserAbort()

                # Determine how many instances can be run AND display status counters
                nbInstancesToLaunch = self.getNbInstancesToLaunch()

                # Run new instance(s)
                if nbInstancesToLaunch > 0:
                    self.runInstances(nbInstancesToLaunch)

                # Sleep for a bit before next turn
                time.sleep(float(self.monitoringInterval))


    ###################################################
    ##  Loggers creation and update related methods  ##
    ###################################################

    def updateLoggers(self):
        # Activate the colorization the screen logger if needed
        if self.colorizeScreenLogger:
            self.activateScreenLoggerColorization()

        # Update console handlers level
        if self.helpArgumentIsUsed:
            self.logger.setLevel(logging.WARNING)

        if self.debugMode:
            self.logger.setLevel(logging.DEBUG)

        # Create file handlers if needed
        if self.activateFileLoggers and not self.helpArgumentIsUsed:
            self.createFileHandlers()


    def activateScreenLoggerColorization(self):
        coloredNameLevelMessageformatter = ColoredFormatter("%(name)s - %(levelname)s - %(message)s")
        consoleHandler.setFormatter(coloredNameLevelMessageformatter)


    def createFileHandlers(self):
        # Create additional formatters
        stdOutFormatter = logging.Formatter("(%(levelname)s) %(message)s")
        stdErrorFormatter = logging.Formatter("%(levelname)s - %(module)s (line %(lineno)d) - %(funcName)s - %(asctime)s - Message: %(message)s")

        # Create a file handler for info/debug messages (with a custom formatter)
        stdoutFileHandler = logging.FileHandler(os.path.join(self.mainExecDirFullPath, 'TriAnnotPipeline_' + self.selectedSubCommand + '_' + self.shortIdentifier + '.log'))
        stdoutFileHandler.setFormatter(stdOutFormatter)
        if self.debugMode:
            stdoutFileHandler.setLevel(logging.DEBUG)
        else:
            stdoutFileHandler.setLevel(logging.INFO)
        self.logger.addHandler(stdoutFileHandler)

        # Create a file handler for error messages
        stderrFileHandler = logging.FileHandler(os.path.join(self.mainExecDirFullPath, 'TriAnnotPipeline_' + self.selectedSubCommand + '_' + self.shortIdentifier + '.err'))
        stderrFileHandler.setFormatter(stdErrorFormatter)
        stderrFileHandler.setLevel(logging.ERROR)
        self.logger.addHandler(stderrFileHandler)


    ##########################
    ##  Global log methods  ##
    ##########################

    def displayStartMessage(self):
        self.logger.info('')
        self.logger.info('##############################################################')
        self.logger.info("##       Welcome in %s (Version %s)       ##" % (self.programName, TRIANNOT_VERSION))
        self.logger.info('##############################################################')
        self.logger.info("%s execution (in %s mode) has begun on %s" % (self.programName, self.selectedSubCommand, self.humanlyReadableStartDate))
        self.logger.info('')
        self.logger.info("The unique identifier for this analysis is: %s" % self.uniqueIdentifier)
        self.logger.info('')

        self.logger.info('The command line arguments has been analysed and checked')

        if self.selectedSubCommand == 'run':
            self.displayRunModeStartMessage()
        else:
            self.displayDatabaseBasedModesStartMessage()


    def displayRunModeStartMessage(self):
        if self.configFileFullPath is not None:
            self.logger.info('The selected external configuration file has been loaded and checked')
            self.logger.debug("Configuration file full path is: %s" % self.configFileFullPath)

        if not self.cmdLineConfigAlone:
            self.logger.info('The internal configuration files have been loaded and checked')

        self.logger.info('The selected step/task file has been loaded and checked')
        self.logger.debug("Step/task file full path is: %s" % self.tasksFileFullPath)

        self.logger.info('The selected fasta file has been loaded, splitted and checked')
        self.logger.debug("Sequence file full path is: %s" % self.sequenceFileFullPath)

        self.logger.info('')
        self.logger.info("TriAnnot will now start the analysis of <%d> sequence(s) (with a maximum of <%d> simultaneous analysis)" % (len(self.instances), int(self.maxParallelAnalysis)))
        self.logger.info("The status of the instance(s) will be checked every <%d> second(s)s" % self.monitoringInterval)
        self.logger.info('')


    def displayDatabaseBasedModesStartMessage(self):
        self.logger.info('The selected SQLite database has been used to restore the initial configuration')
        self.logger.debug("SQLite database full path is: %s" % self.sqliteDatabaseFileFullPath)
        self.logger.info('')

        if self.selectedSubCommand == 'resume':
            self.logger.info("TriAnnot will now continue the analysis of the <%d> sequence(s)/chunk(s) (with a maximum of <%d> simultaneous analysis)" % (len(self.instances), int(self.maxParallelAnalysis)))
            self.logger.info("The status of the instance(s) will be checked every <%d> second(s)s" % self.monitoringInterval)
            self.logger.info('')
        elif self.selectedSubCommand == 'retry':
            if len(self.instances) > 0:
                self.logger.info("TriAnnot will now restart the analysis of <%d> failed sequence(s)/chunk(s) analysis (with a maximum of <%d> simultaneous analysis)" % (len(self.instances), int(self.maxParallelAnalysis)))
            else:
                self.logger.info("There is no instances in ERROR state that need to be relaunched !")

            self.logger.info('')


    def displayEndMessage(self):
        # Get data (only in case of exception)
        if self.humanlyReadableEndDate is None or self.humanlyReadableTotalTime is None:
            self.computeTotalElapsedTime()

        # Display end data
        self.logger.info('')
        self.logger.info("%s execution has ended on %s" % (self.programName, self.humanlyReadableEndDate))
        self.logger.info("The current %s execution (in %s mode) has taken approximately: %s" % (self.programName, self.selectedSubCommand, self.humanlyReadableTotalTime))

        self.logger.info('##############################################################')
        self.logger.info('##                     End of execution                     ##')
        self.logger.info('##############################################################')


    def dislayReminder(self):
        self.logger.info('')
        self.logger.info('Final reminder - The command line used for this analysis was:')
        self.logger.info('')
        self.logger.info(' '.join(sys.argv))


    ###############################################
    ##  Pipeline initialization related methods  ##
    ###############################################

    def _generateTriAnnotUniqueId(self):
        now = time.localtime()
        uniqueId = str(uuid.uuid1())
        userName = None

        try:
            userName = '_' + getpass.getuser() + '_'
        except:
            userName = '_'

        self.shortIdentifier = 'TA' + time.strftime("%H%M%S%m%d", now)
        self.uniqueIdentifier = self.shortIdentifier + userName + uniqueId


    def prepareAnalysis(self):
        try:
            # Manage command line arguments parsing and all configuration files (ie. both external and internal) loading and control
            self.manageParametersAndConfiguration()

            # Check if the user is allowed to launch this instance of TriAnnotPipeline.py or not
            if self.selectedSubCommand != 'monitor':
                self.createLockFileHandler()
                self.isAlreadyLocked = not self.addLockOnFileHandler()
                if self.isAlreadyLocked:
                    self.logger.error("Sorry but you can't relaunch %s in run/resume/retry mode when it is already executing in run/resume/retry mode in the selected directory !" % self.programName)
                    self.logger.info("Please properly halt the existing %s execution by using the CTRL+C shortcut before trying to re-execute the same command line" % self.programName)
                    exit(1)

            # At this point the preparation diverged depending on the selected sub command
            if self.selectedSubCommand == 'run':
                # In <run> mode we have to:
                # - Remove redundancy from the configuration (ie. condense the configuration) and perform advanced configuration checks
                # - Load and check the step/task file (we stop here if --check argument/option/parameter/callItAsYouWhich has been used)
                # - Create the global configuration file and the global step/task file
                # - Create the SQLite database
                # - Fill the <Parameters> table of the SQLite database with the main configuration values
                # - Analyse the fasta sequence file
                # - Fill the <Analysis> table of the SQLite database with sequences data
                # - Create mandatory subdirectories
                # - Create basic TriAnnotInstance objects
                self.prepareRunMode()

            else:
                # Any other modes are based on the SQLite database file generated in run mode
                # Therefore, the first thing to do is to check the existence of this file and create a TriAnnotSqlite object
                self.sqliteDatabaseFileFullPath = os.path.join(self.mainExecDirFullPath, self.sqliteDatabaseFileName)
                self.checkSqliteDatabaseFile()
                self.sqliteObject = TriAnnotSqlite(self.sqliteDatabaseFileFullPath)

                if self.selectedSubCommand  == 'resume':
                    # In <resume> mod we have to:
                    # - Read the <Parameters> table to collect the main parameters and define object attributes with them
                    # - Load the global configuration file created in run mode
                    # - Create special TriAnnotInstance objects (with a runner object inside)
                    self.prepareResumeMode()

                elif self.selectedSubCommand  == 'retry':
                    # In <resume> mod we have to:
                    # - Read the <Parameters> table to collect the main parameters and define object attributes with them
                    # - Load the global configuration file created in run mode
                    # - Backup the execution directory of every failed instance
                    # - Reinitialize failed instances in the SQLite database
                    # - Create basic TriAnnotInstance objects
                    self.prepareRetryMode()

                elif self.selectedSubCommand  == 'reconstruct':
                    # In <reconstruct> mod we have to:
                    # - Read the <Parameters> table to collect the main parameters and define object attributes with them
                    # - Load the global step/task file generated in run mode (to determine for which step the reconstruction must occur)
                    self.prepareReconstructMode()

                else:
                    # In <monitor> mode there is no specific task to perform right now
                    self.prepareMonitorMode()

            # Remove old TriAnnot_abort files if needed
            if Utils.isExistingFile(os.path.join(self.mainExecDirFullPath, 'TriAnnot_abort')):
                os.remove(os.path.join(self.mainExecDirFullPath, 'TriAnnot_abort'))

        except Exception, ex:
            if not type(ex) is SystemExit:
                self.logger.debug(traceback.format_exc())
                self.logger.error(ex)
                exit(1)


    def createLockFileHandler(self):
        # Initialization
        self.lockFileFullPath = os.path.join(self.mainExecDirFullPath, 'TriAnnotPipeline.lock')

        # Create a file handler for the lock file
        try:
            self.lockFileHandler = open(self.lockFileFullPath, 'w')
        except IOError:
            self.logger.error("%s could not create the following lock file: %s" % (self.programName, self.lockFileFullPath))
            raise


    def addLockOnFileHandler(self):
        # Try to add a lock on the lock file
        # Return false if the file is already locked
        try:
            locker.lockf(self.lockFileHandler, locker.LOCK_EX | locker.LOCK_NB)
        except IOError:
            self.logger.debug("The following file is already locked: %s" % self.lockFileFullPath)
            return False

        return True


    def getInstanceObjectsFromDatabaseRequest(self, desiredInstanceStatus = list()):
        # Initializations
        errorsList = list()
        dictOfInstances = dict()

        # We always want a list of desired status
        if not isinstance(desiredInstanceStatus, list):
            desiredInstanceStatus = [desiredInstanceStatus]

        # Create a TriAnnotInstance object for each dict returned by the SQLite query
        for instanceDescriptionDict in self.sqliteObject.recoverInstancesFromDatabase():
            if len(desiredInstanceStatus) == 0 or instanceDescriptionDict['instanceStatus'] in desiredInstanceStatus:
                # Try to initialize a TriAnnotInstance object and catch raised errors if needed
                try:
                    instanceObject = TriAnnotInstance(instanceDescriptionDict, self.instanceJobRunnerName)
                except RuntimeError as err:
                    errorsList.append(err.message)
                    continue

                dictOfInstances[instanceObject.id] = instanceObject

        # Display errors if needed
        if len(errorsList) > 0:
            for error in errorsList:
                self.logger.error(error)
            exit(1)

        return dictOfInstances


    ################################################
    ##  Run mode specific initialization methods  ##

    def prepareRunMode(self):
        # Replace configuration wildcard values by their real values and merge some configuration sections
        self.updateAndCondenseConfiguration()

        # Check the validity of the definition of each possible parameters and check all paths defined in configuration files
        self.performAdvancedConfigurationChecks()

        # Load and check the step/task file provided through the -t/--tasks arguments
        self.loadAndCheckTriAnnotTaskFile()

        # If The --check option has been used then the TriAnnotPipeline.py execution will stop here
        if self.checkOnly:
            self.logger.info('Finished checking files. If no error is displayed above, configuration files and tasks file are correct, otherwise, please fix the errors before running the pipeline.')
            exit(0)

        # Define the various monitoring intervals (for standard jobs, long jobs, etc)
        self.setMonitoringIntervals()

        # Create the SQLite database
        self.sqliteDatabaseFileFullPath = os.path.join(self.mainExecDirFullPath, self.sqliteDatabaseFileName)
        self.sqliteObject = TriAnnotSqlite(self.sqliteDatabaseFileFullPath)

        # Write the full configuration for the current analysis in a global XML configuration file
        self.globalConfigurationFileFullPath = TriAnnotConfig.generateGlobalConfigurationFile(self.mainExecDirFullPath, TRIANNOT_VERSION)
        self.prepareAndStoreGlobalFileData(self.globalConfigurationFileFullPath)

        # Write the full step/task file with custom and default parameters for each task
        self.globalTaskFileFullPath = TriAnnotTaskFileChecker.generateFullTaskFile(self.mainExecDirFullPath, TRIANNOT_VERSION, self.taskFileDescription)
        self.prepareAndStoreGlobalFileData(self.globalTaskFileFullPath)

        # Save the main/important parameters in a table of the SQLite database
        self.sqliteObject.genericInsertOrReplaceFromDict(self.sqliteObject.parametersTableName, self.buildMainParametersDict())

        # Analyse sequence file
        self.analyseSequenceFile()

        # Register all instances in a table of the SQLite database
        self.sqliteObject.registerAllInstances(self.InstanceTableEntries)

        # Delete the greedy objects, class variables, etc.
        self.deleteMemoryEaters()

        # Create mandatory subdirectories
        self.createMandatorySubFolders()

        # Generate a list of TriAnnotInstance objects with the data of the Instance table
        self.instances = self.getInstanceObjectsFromDatabaseRequest()


    def setMonitoringIntervals(self):
        self.monitoringInterval = int(TriAnnotConfig.getConfigValue("Runners|%s|monitoringInterval" % self.instanceJobRunnerName))

        if self.monitoringInterval < 60:
            self.stillAliveJobMonitoringInterval = 60
        else:
            self.stillAliveJobMonitoringInterval = 60 + self.monitoringInterval


    def prepareAndStoreGlobalFileData(self, globalFileFullPath):
        # Initializations
        globalFileData = dict()

        # Extract import parameters from the main object
        globalFileData['globalFileFullPath'] = globalFileFullPath
        globalFileData['globalFileSecureHash'] = Utils.getFileChecksum(globalFileFullPath)

        self.sqliteObject.genericInsertOrReplaceFromDict(self.sqliteObject.globalFilesTableName, globalFileData)


    def buildMainParametersDict(self):
        # Initializations
        mainParameters = dict()

        # Extract import parameters from the main object
        mainParameters['sequenceFileFullPath'] = self.sequenceFileFullPath
        mainParameters['globalConfigurationFileFullPath'] = self.globalConfigurationFileFullPath
        mainParameters['globalTaskFileFullPath'] = self.globalTaskFileFullPath
        mainParameters['mainExecDirFullPath'] = self.mainExecDirFullPath
        mainParameters['sequenceType'] = self.sequenceType
        mainParameters['debugMode'] = self.debugMode
        mainParameters['instanceJobRunnerName'] = self.instanceJobRunnerName
        mainParameters['taskJobRunnerName'] = self.taskJobRunnerName
        mainParameters['maxParallelAnalysis'] = self.maxParallelAnalysis
        mainParameters['monitoringInterval'] = self.monitoringInterval
        mainParameters['killOnAbort'] = self.killOnAbort
        mainParameters['cleanPattern'] = self.cleanPattern
        mainParameters['emailTo'] = self.emailTo
        mainParameters['shortIdentifier'] = self.shortIdentifier
        mainParameters['chunkOverlappingSize'] = self.chunkOverlappingSize

        return mainParameters


    def deleteMemoryEaters(self):
        del self.configurationCheckerObject
        del TriAnnotConfigurationChecker.allParametersDefinitions
        del TriAnnotTaskFileChecker.allTaskParametersObjects
        del TriAnnotTaskParameters.generatedSequencesTaskId

        del self.InstanceTableEntries[:]
        self.InstanceTableEntries = None


    def createMandatorySubFolders(self):
        # Generate the list of folders to create
        foldersToCreate = [TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['launcher_files']]

        for folderName in foldersToCreate:
            folderFullPath = os.path.join(self.mainExecDirFullPath, folderName)

            if not Utils.isExistingDirectory(folderFullPath):
                try:
                    os.mkdir(folderFullPath)
                except OSError:
                    self.logger.error("%s can't create the <%s> subdirectory in the main execution directory: %s" % (self.programName, folderName, folderFullPath))
                    exit(1)


    ############################################################
    ##  Common initialization methods for sqlite-based modes  ##

    def checkSqliteDatabaseFile(self):
        # Check SQLite database file existence
        if not Utils.isExistingFile(self.sqliteDatabaseFileFullPath):
            self.logger.error("The following SQLite database file does not exists in the directory specified through the -w/--workdir argument/option or is unreadable: %s" % self.sqliteDatabaseFileFullPath)
            exit(1)

        # Check SQLite database file size
        if Utils.isEmptyFile(self.sqliteDatabaseFileFullPath):
            self.logger.error("The following SQLite database file is empty: %s" % self.sqliteDatabaseFileFullPath)
            exit(1)


    def restoreConfiguration(self):
        # Define the various monitoring intervals (for standard jobs, long jobs, etc)
        self.setSecondaryMonitoringIntervals()

        # Get the parameters stored in the SQLite database during the Run mode
        recoveredParameters = self.sqliteObject.recoverParametersFromDatabase()

        # Upate the main object with recovered parameters
        for parameterName, parameterValue in recoveredParameters.items():
            setattr(self, parameterName, parameterValue)

        # Set Runtime values (for compatibility)
        TriAnnotConfig.TRIANNOT_CONF['Runtime']['instanceJobRunnerName'] = self.instanceJobRunnerName
        TriAnnotConfig.TRIANNOT_CONF['Runtime']['taskJobRunnerName'] = self.taskJobRunnerName

        # Check if the checksum of the global configuration file is still equal to the value stored in the SQLite database
        if Utils.getFileChecksum(self.globalConfigurationFileFullPath) != self.sqliteObject.recoverGlobalFileChecksum(self.globalConfigurationFileFullPath):
            self.logger.error("It seems that the following global configuration file has been manually modified after its automatic creation in run mode: %s" % self.globalConfigurationFileFullPath)
            self.logger.error("To avoid unexpected behavior TriAnnot execution (<%s> mode) will now be aborted !" % self.selectedSubCommand)
            self.logger.error("Please restore the original version of this global configuration file before executing %s again" % self.programName)
            exit(1)

        # Load the global configuration file
        # Create a new TriAnnotConfigurationChecker object
        configurationCheckerObject = TriAnnotConfigurationChecker(self.globalConfigurationFileFullPath, True)

        # Check the existence and access rights of every configuration files
        configurationCheckerObject.checkConfigurationFilesExistence()
        configurationCheckerObject.displayInvalidConfigurationFiles()
        if configurationCheckerObject.nbInvalidConfigurationFiles > 0:
            exit(1)

        self.logger.info('The content of the global XML configuration file will now be loaded into memory')
        for configurationFile in configurationCheckerObject.xmlFilesToCheck:
            # Creation of a TriAnnotConfig object
            configurationLoader = TriAnnotConfig(configurationFile['path'], TRIANNOT_VERSION)
            configurationLoader = TriAnnotConfig(self.globalConfigurationFileFullPath, TRIANNOT_VERSION)

            # Effective loading
            if not configurationLoader.loadConfigurationFile():
                self.abortPipeline('At least one error occured during the loading of the global XML configuration file')
                exit(1)

        # Store clean pattern in memory
        self.convertCleanPatternToDict()


    def setSecondaryMonitoringIntervals(self):
        if self.monitoringInterval < 60:
            self.stillAliveJobMonitoringInterval = 60
        else:
            self.stillAliveJobMonitoringInterval = 60 + self.monitoringInterval


    ####################################################
    ##  Monitor mode specific initialization methods  ##

    def prepareMonitorMode(self):
        pass


    ###################################################
    ##  Resume mode specific initialization methods  ##

    def prepareResumeMode(self):
        # Restore the configuration (from the SQLite database and the global file) and update the attributes of the main object
        self.restoreConfiguration()

        # Generate a list of TriAnnotInstance objects with the data of the Instance table
        self.instances = self.getInstanceObjectsFromDatabaseRequest()

        # Recreate a runner object for already started (but unfinished) instances so that they can be monitored in the main loop
        for instance in self.instances.values():
            if instance.instanceMonitoringCommand is not None and not instance.isExecutionFinishedBasedOnStatus():
                instance.runner = TriAnnotRunner(self.instanceJobRunnerName, 'TriAnnotUnit', instance)
                instance.runner.monitoringCommand = instance.instanceMonitoringCommand
                instance.runner.killCommand = instance.instanceKillCommand


    ##################################################
    ##  Retry mode specific initialization methods  ##

    def prepareRetryMode(self):
        # Restore the configuration (from the SQLite database and the global file) and update the attributes of the main object
        self.restoreConfiguration()

        # Generate a list of TriAnnotInstance objects with the data of the Instance table
        instancesToReinitialize = self.getInstanceObjectsFromDatabaseRequest(desiredInstanceStatus = [TriAnnotStatus.ERROR, TriAnnotStatus.CANCELED])

        # Clean instances in error state
        for instance in instancesToReinitialize.values():
            # Backup the existing instance directory (zip archive) and delete it
            instanceBackupArchive = instance.instanceDirectoryFullPath + '_backup.zip'

            if Utils.isExistingFile(instanceBackupArchive):
                self.logger.warning("The backup archive for %s already exists. Have you investigate enough on the reported errors before relaunching %s ?" % (instance.getDescriptionString(), self.programName))
                os.remove(instanceBackupArchive)

            Utils.createDirectoryBackup(instance.instanceDirectoryFullPath, instanceBackupArchive)
            shutil.rmtree(instance.instanceDirectoryFullPath)

            # Create a temporary TriAnnotInstanceTableEntry object
            tmpInstanceTableEntryObject = TriAnnotInstanceTableEntry()

            # Update a part of its attributes (non instance* attribute) by the value of the current instance
            for attributeName in dir(instance):
                if attributeName.startswith('sequence') or attributeName.startswith('chunk'):
                    setattr(tmpInstanceTableEntryObject, attributeName, getattr(instance, attributeName))

            # Convert the object to dict and update it with the instance id
            modifiedEntry = tmpInstanceTableEntryObject.convertToDict()
            modifiedEntry.update({'id': instance.id, 'instanceBackupArchive': instanceBackupArchive})

            # Make the replacement in the SQLiteDatabase
            self.sqliteObject.genericInsertOrReplaceFromDict(self.sqliteObject.instancesTableName, modifiedEntry)

        # Get the updated list of instance
        self.instances = self.getInstanceObjectsFromDatabaseRequest()


    ########################################################
    ##  Reconstruct mode specific initialization methods  ##

    def prepareReconstructMode(self):
        # Restore the configuration (from the SQLite database and the global file) and update the attributes of the main object
        self.restoreConfiguration()

        # Load the global step/task file (will be used to determine which result files needs to be merged)
        taskFileCheckerObject = TriAnnotTaskFileChecker(self.globalTaskFileFullPath)
        taskFileCheckerObject.loadTaskFile()


    #########################################################
    ##  Command line arguments management related methods  ##
    #########################################################

    def manageParametersAndConfiguration(self):
        # Initialize the command line option parser
        self.mainArgumentParser = argparse.ArgumentParser(
                description = self.generateArgparseDescription('main'),
                formatter_class=argparse.RawTextHelpFormatter,
                add_help = False
        )

        # Create arguments (and argument groups) for the main level parser
        self.addArgumentsToMainParser()

        # Tell the main parser that there will be subparsers
        self.subparsers = self.mainArgumentParser.add_subparsers(
                title='Possible sub-commands (ie. execution modes)',
                description="%s can be executed in five different modes.\nList of existing execution modes:" % self.programName,
                dest = "subparserName"
        )

        # Create sub-parsers
        self.initializeSubParsers()

        # Check if the help argument has been used for the sub-command
        self.helpArgumentIsUsed = self.isHelpArgumentUsed()

        # Get the name of the selected subcommand and common arguments values
        alreadyKnownArguments, otherArguments = self.mainArgumentParser.parse_known_args()

        # Convert already known arguments (+ the sub-command name) into object attributes
        self.checkAndStoreMainParserArguments(alreadyKnownArguments)

        # Update the console handler depending on the --debug argument and create file handlers depending on the --logtofile arguments
        self.updateLoggers()

        # Create arguments (and argument groups) for the selected sub-parser
        self.addArgumentsToSelectedSubParser()

        # Scan the command line for all defined command-line arguments / options
        commandLineArguments = self.mainArgumentParser.parse_args()

        # Execute the default function associated with the selected subparser
        commandLineArguments.func(commandLineArguments)


    def generateArgparseDescription(self, parserName):
        commonWarning = "Warning: arguments shared by every sub-commands (ie. --debug, --logtogile, -w/--workdir, etc.) must be placed BEFORE the sub-command name in your command line !\n         Please, use the following command to display the full list of shared arguments: %s -h\n\n" % self.programName

        if parserName == 'main':
            argparseDescription =  "*******************************************************\n"
            argparseDescription += "*** TriAnnot Pipeline (Version: %s) - Help Section ***\n" % (TRIANNOT_VERSION)
            argparseDescription += "*******************************************************\n\n"

            argparseDescription += commonWarning
            argparseDescription += "Valid command line example: %s --workdir my_directory run|monitor|resume|retry [sub-command options]\n" % self.programName
            argparseDescription += "Invalid command line example: %s run|monitor|resume|retry --workdir my_directory [sub-command options]\n" % self.programName

        else:
            additionalStars = '*' * (len(parserName) + len(TRIANNOT_VERSION))

            argparseDescription =  "%s************************************************************\n" % additionalStars
            argparseDescription += "*** TriAnnot Pipeline - %s mode (Version: %s) - Help Section ***\n" % (parserName, TRIANNOT_VERSION)
            argparseDescription += "%s************************************************************\n\n" % additionalStars

            argparseDescription += commonWarning
            argparseDescription += "Usage example: %s --workdir my_directory %s --%s_mode_option1 ...\n\n" % (self.programName, parserName, parserName)

        return argparseDescription


    def isHelpArgumentUsed(self):
        # Create a mini parser with only one argument
        dummyArgumentParser = argparse.ArgumentParser(add_help = False)
        dummyArgumentParser.add_argument('-h', '--help', action='store_true', help='show this help message and exit')

        alreadyKnownArguments, otherArguments = dummyArgumentParser.parse_known_args()

        # Return True or False depending on the utilization or not of the help option on the command line
        return alreadyKnownArguments.help


    def initializeSubParsers(self):
        # Initializations
        commonMessage = "Please execute the following command to display mode-specific parameters:"
        databaseModeCommonMessage = "Warning: requires an existing SQLite database file (generated in run mode)"

        # Run mode subparser
        self.runArgumentParser = self.subparsers.add_parser(
                'run',
                add_help = False,
                formatter_class=argparse.RawTextHelpFormatter,
                help="Start the analysis of a new sequence file.\n%s\n<%s %s -h>\n\n" % (commonMessage, self.programName, 'run'),
                description = self.generateArgparseDescription('run')
        )

        # Monitor mode subparser
        self.monitorArgumentParser = self.subparsers.add_parser(
                'monitor',
                add_help = False,
                formatter_class=argparse.RawTextHelpFormatter,
                help="Monitor an existing analysis.\n%s\n%s\n<%s %s -h>\n\n" % (databaseModeCommonMessage, commonMessage, self.programName, 'monitor'),
                description = self.generateArgparseDescription('monitor')
        )

        # Resume mode subparser
        self.resumeArgumentParser = self.subparsers.add_parser(
                'resume',
                add_help = False,
                formatter_class=argparse.RawTextHelpFormatter,
                help="Resume/restart an existing halted analysis.\n%s\n%s\n<%s %s -h>\n\n" % (databaseModeCommonMessage, commonMessage, self.programName, 'resume'),
                description = self.generateArgparseDescription('resume')
        )

        # Retry mode subparser
        self.retryArgumentParser = self.subparsers.add_parser(
                'retry',
                add_help = False,
                formatter_class=argparse.RawTextHelpFormatter,
                help="Re-execute all failed instances of an existing analysis.\n%s\nThe old execution directories will be archived/backuped before the new execution attemps.\nThe backups will be automatically deleted after successful re-executions.\n%s\n<%s %s -h>\n\n" % (databaseModeCommonMessage, commonMessage, self.programName, 'retry'),
                description = self.generateArgparseDescription('retry')
        )

        # Reconstruct mode subparser
        self.reconstructArgumentParser = self.subparsers.add_parser(
                'reconstruct',
                add_help = False,
                formatter_class=argparse.RawTextHelpFormatter,
                help="Reconstruct global result files for splitted sequences.\n%s\nWhen a long sequence is splitted into overlapping chunks, the generated chunks are analysed independently.\nThe direct consequence of this procedure is that the sequence annotation is fragmented.\nThis execution mode can be used to sort the annotation results and remap them on the full sequence.\n%s\n<%s %s -h>\n\n" % (databaseModeCommonMessage, commonMessage, self.programName, 'reconstruct'),
                description = self.generateArgparseDescription('retry')
        )


    def addArgumentsToSelectedSubParser(self):
        # Call the appropriate addArguments method depending on the selected sub-command
        {
            'monitor': self.addArgumentsToMonitorSubParser,
            'resume': self.addArgumentsToResumeSubParser,
            'retry': self.addArgumentsToRetrySubParser,
            'reconstruct': self.addArgumentsToReconstructSubParser,
            'run': self.addArgumentsToRunSubParser
        }[self.selectedSubCommand]()


    ###################
    ### Main parser ###

    def addArgumentsToMainParser(self):
        # Argument groups
        self.mainParserBasicOptionGroup = self.mainArgumentParser.add_argument_group('Basic arguments')
        self.mainParserCommonOptionGroup = self.mainArgumentParser.add_argument_group('Common arguments')

        # Basic arguments
        self.mainParserBasicOptionGroup.add_argument('-h', '--help', action='help', help='Show this global help message and exit')
        self.mainParserBasicOptionGroup.add_argument('-v', '--version', action='version', version="TriAnnot version %s" % (TRIANNOT_VERSION))

        # Main arguments
        self.mainParserCommonOptionGroup.add_argument(
                '-w', '--workdir',
                dest = 'execDirPath',
                metavar = 'PATH',
                help = "Name of the main working directory to use/create for this analysis.\nIf not specified, the current directory will be used.\n\n",
                default = os.getcwd()
        )

        self.mainParserCommonOptionGroup.add_argument(
                '--debug',
                dest = 'debugMode',
                action = 'store_true',
                help = "Activate debug mode. In debug mode, %s will be more verbose and some debug specific actions will be executed.\nWarning: this option must be placed BEFORE the sub-command name in the command-line.\n\n" % self.programName,
                default = False
        )

        self.mainParserCommonOptionGroup.add_argument(
                '--logtofile',
                dest = 'activateFileLoggers',
                action = 'store_true',
                help = "When this option is used, all log messages will not only be displayed on screen but also be written in log files.\nWarning: this option must be placed BEFORE the sub-command name in the command-line.\n\n",
                default = False
        )

        self.mainParserCommonOptionGroup.add_argument(
                '--color',
                dest = 'colorizeScreenLogger',
                action = 'store_true',
                help = "Activate the colorization of the screen logger for better visualization.\nWhen this option is used, each log message will be colored depending on its level (ie. DEBUG, INFO, WARNING, ERROR, etc.)\n",
                default = False
        )


    def checkAndStoreMainParserArguments(self, alreadyKnownArguments):
        # Store the name of the selected sub-command
        self.selectedSubCommand = alreadyKnownArguments.subparserName

        # Store logging/debugging arguments
        self.debugMode = alreadyKnownArguments.debugMode
        self.activateFileLoggers = alreadyKnownArguments.activateFileLoggers
        self.colorizeScreenLogger = alreadyKnownArguments.colorizeScreenLogger

        # Check the existence of the working directory and the validity of its name
        if alreadyKnownArguments.execDirPath is not None:
            self.mainExecDirFullPath = os.path.realpath(os.path.expanduser(alreadyKnownArguments.execDirPath))

            if self.mainExecDirFullPath.startswith('-') or re.search(r"[\s\?*]", self.mainExecDirFullPath) is not None:
                self.mainArgumentParser.error("The name of the main working directory (specified through the -d/--workdir argument/option) must not start with '-' and must not contain any whitespace or wildcard characters: %s is not valid" % self.mainExecDirFullPath)

            # We check the existence of the execution directory only if we the -h/--help argument has not been used
            if not self.helpArgumentIsUsed:
                if not Utils.isExistingDirectory(self.mainExecDirFullPath):
                    self.logger.warning("The main working directory (specified through the -d/--workdir argument/option) does not exists and will now be created.")

                    # Working directory creation attempt
                    try:
                        os.mkdir(self.mainExecDirFullPath)
                    except OSError:
                        self.logger.error("The main working directory (specified through the -d/--workdir argument/option) could not be created: %s" % self.mainExecDirFullPath)
                        exit(1)
                else:
                    # When TriAnnotPipeline is executed in Run mode (start of a new analysis) then the main execution directory should not exist or at least be empty
                    # If the directory is not empty then we have to stop the execution and explain the user what he can do
                    if self.selectedSubCommand == 'run' and not Utils.isEmptyDirectory(self.mainExecDirFullPath):
                        self.logger.error("The main working directory (specified through the -d/--workdir argument/option) already exists and is not empty.")
                        self.logger.info("If you want to resume an existing analysis, please use the following command line: %s --workdir %s resume" % (self.programName, self.mainExecDirFullPath))
                        self.logger.info("If you want to re-execute failed instances, please use the following command line: %s --workdir %s retry" % (self.programName, self.mainExecDirFullPath))
                        self.logger.info("If you want to re-use this directory for a new analysis, please manually delete the directory content before re-executing TriAnnot.")
                        exit(1)


    ##########################
    ### Monitor sub-parser ###

    def addArgumentsToMonitorSubParser(self):
        # Argument groups
        monitorParserBasicOptionGroup = self.monitorArgumentParser.add_argument_group('Basic arguments')
        monitorParserOtherOptionGroup = self.monitorArgumentParser.add_argument_group('Other arguments')

        # Basic subparser arguments
        monitorParserBasicOptionGroup.add_argument('-h', '--help', action='help', help='show this specific help message and exit')
        monitorParserBasicOptionGroup.add_argument('-v', '--version', action='version', version="TriAnnot version %s" % (TRIANNOT_VERSION))

        # Other arguments
        monitorParserOtherOptionGroup.add_argument('--progress', dest = 'writeProgressionToFile',
                action = 'store_true',
                help = "Create and fill a <TriAnnot_progress> file (in XML format) in the main execution folder.\nThis file will contain the following informations:\n  - Global repartition of the instance's status\n  - Detailed status for each sequence\n\n",
                default = False)

        # Define auto-executable check method
        self.monitorArgumentParser.set_defaults(func=self.checkAndStoreMonitorModeArguments)


    def checkAndStoreMonitorModeArguments(self, commandLineArguments):
        self.writeProgressionToFile = commandLineArguments.writeProgressionToFile


    #########################
    ### Resume sub-parser ###

    def addArgumentsToResumeSubParser(self):
        # Argument groups
        resumeParserBasicOptionGroup = self.resumeArgumentParser.add_argument_group('Basic arguments')
        resumeParserOtherOptionGroup = self.resumeArgumentParser.add_argument_group('Other arguments')

        # Basic subparser arguments
        resumeParserBasicOptionGroup.add_argument('-h', '--help', action='help', help='show this specific help message and exit')
        resumeParserBasicOptionGroup.add_argument('-v', '--version', action='version', version="TriAnnot version %s" % (TRIANNOT_VERSION), help="show program's version number and exit\n\n")

        # Define auto-executable check method
        self.resumeArgumentParser.set_defaults(func=self.checkAndStoreResumeModeArguments)


    def checkAndStoreResumeModeArguments(self, commandLineArguments):
        pass


    ########################
    ### Retry sub-parser ###

    def addArgumentsToRetrySubParser(self):
        # Argument groups
        retryParserBasicOptionGroup = self.retryArgumentParser.add_argument_group('Basic arguments')
        retryParserOtherOptionGroup = self.retryArgumentParser.add_argument_group('Other arguments')

        # Basic subparser arguments
        retryParserBasicOptionGroup.add_argument('-h', '--help', action='help', help='show this specific help message and exit')
        retryParserBasicOptionGroup.add_argument('-v', '--version', action='version', version="TriAnnot version %s" % (TRIANNOT_VERSION), help="show program's version number and exit\n\n")

        # Define auto-executable check method
        self.retryArgumentParser.set_defaults(func=self.checkAndStoreRetryModeArguments)


    def checkAndStoreRetryModeArguments(self, commandLineArguments):
        pass


    ##############################
    ### Reconstruct sub-parser ###

    def addArgumentsToReconstructSubParser(self):
        # Argument groups
        reconstructParserBasicOptionGroup = self.reconstructArgumentParser.add_argument_group('Basic arguments')
        reconstructParserOtherOptionGroup = self.reconstructArgumentParser.add_argument_group('Other arguments')

        # Basic subparser arguments
        reconstructParserBasicOptionGroup.add_argument('-h', '--help', action='help', help='show this specific help message and exit')
        reconstructParserBasicOptionGroup.add_argument('-v', '--version', action='version', version="TriAnnot version %s" % (TRIANNOT_VERSION))

        # Other arguments
        reconstructParserOtherOptionGroup.add_argument('--force', dest = 'forceReconstruction',
                action = 'store_true',
                help = "When this option is used, the reconstruction procedure will NOT be stopped if the global result files\ncan't be reconstructed for ALL splitted sequences. In this case, TriAnnot will reconstruct the result\nfiles of the sequences for which all chunks have been successfully analysed and ignore all other\nsequences.\n\nWhen this option is NOT used, the reconstruction procedure will be stopped if at least one chunk\nanalysis of at least one sequence is failed or canceled.\n\n",
                default = False)

        # Define auto-executable check method
        self.reconstructArgumentParser.set_defaults(func=self.checkAndStoreReconstructModeArguments)


    def checkAndStoreReconstructModeArguments(self, commandLineArguments):
        self.forceReconstruction = commandLineArguments.forceReconstruction


    ######################
    ### Run sub-parser ###

    def addArgumentsToRunSubParser(self):
        # Argument groups
        self.initializeRunParserGroups()

        # Creation of configuration-like arguments (ie. arguments to define an external configuration file and the way it must be used)
        self.manageConfigLikeRunParserArguments()

        # Configuration loading to allow the display of default and possible values in the Run mode help section
        # Note: the check of the configuration file provided through the command line will be executed at the beginning of this method
        self.loadConfigurationAndExecuteBasicChecks()

        # Creation of all other arguments
        self.manageAllRunParserArguments()

        # Define auto-executable check method
        self.runArgumentParser.set_defaults(func=self.checkAndStoreRunModeArguments)


    def initializeRunParserGroups(self):
        self.runParserBasicOptionGroup = self.runArgumentParser.add_argument_group('Basic arguments')
        self.runParserMandatoryOptionGroup = self.runArgumentParser.add_argument_group('Mandatory arguments')
        self.runParserConfigOptionGroup = self.runArgumentParser.add_argument_group('Configuration loading/control related arguments')
        self.runParserRunnerOptionGroup = self.runArgumentParser.add_argument_group('Job management related arguments')
        self.runParserSequenceOptionGroup = self.runArgumentParser.add_argument_group('Input sequence(s) management related arguments')
        self.runParserTriAnnoUnitOptionGroup = self.runArgumentParser.add_argument_group('Arguments directly transmitted to the TriAnnot Units')
        self.runParserMiscOptionGroup = self.runArgumentParser.add_argument_group('Unclassified arguments')


    def manageConfigLikeRunParserArguments(self):
        # Define configuration-like arguments
        self.fillRunParserConfigOptionGroup()

        # Parse this specific option group
        alreadyKnownArguments, otherArguments = self.runArgumentParser.parse_known_args()

        # Store the value of the arguments into the main object attributes
        if alreadyKnownArguments.configFilePath is not None:
            self.configFileFullPath = os.path.realpath(os.path.expanduser(alreadyKnownArguments.configFilePath))

        self.cmdLineConfigAlone = alreadyKnownArguments.cmdLineConfigAlone
        self.checkOnly = alreadyKnownArguments.checkOnly


    def fillRunParserConfigOptionGroup(self):
        configFileParameterName = '-c/--config'

        self.runParserConfigOptionGroup.add_argument(
                '-c', '--config',
                dest = 'configFilePath',
                metavar = 'XML_CONFIG_FILE',
                help = "Name of an XML configuration file.\nEach parameter defined in this file will supplant its equivalent in any other configuration files.\n\n",
                default = None
        )

        self.runParserConfigOptionGroup.add_argument(
                '--cmdline-config-alone',
                dest = 'cmdLineConfigAlone',
                action = 'store_true',
                help = "Ignore all other configuration files than the one defined through the %s argument.\nWarning: This argument will be ignored if the %s argument is not used.\n\n" % (configFileParameterName, configFileParameterName),
                default = False
        )

        self.runParserConfigOptionGroup.add_argument(
                '--check',
                dest = 'checkOnly',
                action = 'store_true',
                help = "Check the structure and content of the various XML configuration files and step/task files and stop %s execution.\n" % self.programName,
                default = False
        )


    def manageAllRunParserArguments(self):
        # Build help complements and "choices" lists
        helpComplements = self.buildChoicesAndHelpComplements()

        # Basic arguments
        self.runParserBasicOptionGroup.add_argument('-h', '--help', action='help', help='show this <run mode> specific help message and exit')
        self.runParserBasicOptionGroup.add_argument('-v', '--version', action='version', version="TriAnnot version %s" % (TRIANNOT_VERSION))

        # Mandatory arguments
        self.fillRunParserMandatoryOptionGroup()

        # Runners arguments
        self.fillRunParserRunnerOptionGroup(helpComplements)

        # Sequence arguments
        self.fillRunParserSequenceOptionGroup()

        # TriAnnotUnits arguments
        self.fillRunParserTriAnnoUnitOptionGroup()

        # Other arguments
        self.fillRunParserMiscOptionGroup(helpComplements)


    def buildChoicesAndHelpComplements(self):
        # Initializations
        helpComplements = dict.fromkeys(['instanceJobRunnerName', 'taskJobRunnerName', 'multiThreadOverride'], '')
        self.availableRunners = []

        # For the "instanceJobRunnerName" and "taskJobRunnerName" arguments
        for runner in sorted(TriAnnotConfig.TRIANNOT_CONF['Runners']):
            self.availableRunners.append(runner)

        helpComplements['instanceJobRunnerName'] += "Possible values are: %s.\n" % (', '.join(self.availableRunners))
        helpComplements['instanceJobRunnerName'] += "Default runner is: %s.\n" % TriAnnotConfig.TRIANNOT_CONF['Global']['DefaultInstanceJobRunner']

        helpComplements['taskJobRunnerName'] += "Possible values are: %s.\n" % (', '.join(self.availableRunners))
        helpComplements['taskJobRunnerName'] += "Default runner is: %s.\n" % TriAnnotConfig.TRIANNOT_CONF['Global']['DefaultTaskJobRunner']

        # For the "mth-override" arguments
        for runner in self.availableRunners:
            helpComplements['multiThreadOverride'] += "  - Default number of thread by task for runner <%s> is: %s (Maximum: %s).\n" % (runner, TriAnnotConfig.TRIANNOT_CONF['Runners'][runner]['defaultNumberOfThread'], TriAnnotConfig.TRIANNOT_CONF['Runners'][runner]['maximumNumberOfThreadByTool'])

        return helpComplements


    def fillRunParserMandatoryOptionGroup(self):
        # Define argument's choices
        sequenceTypeChoices = ['nucleic', 'proteic']

        # Define arguments
        self.runParserMandatoryOptionGroup.add_argument(
                '-s', '--sequence',
                dest = 'sequenceFilePath',
                metavar = 'FASTA_FILE',
                help = "Sequence file in Fasta format that contains the sequence(s) to annotate.\n\n",
                default = None,
                required = True
        )

        self.runParserMandatoryOptionGroup.add_argument(
                '-t', '--tasks',
                dest = 'tasksFilePath',
                metavar = 'XML_FILE',
                help = "TriAnnot step/task file in XML format that contains the list of tasks to execute.\n\n",
                default = None,
                required = True
        )

        self.runParserMandatoryOptionGroup.add_argument(
                '--type',
                dest = 'sequenceType',
                metavar = 'SEQUENCE_TYPE',
                help = "Type of the sequences to analyze.\nPossible values are: %s.\n" % ', '.join(sequenceTypeChoices),
                default = None,
                choices = sequenceTypeChoices,
                required = True
        )


    def fillRunParserRunnerOptionGroup(self, helpComplements):
        instanceRunnerParameterName = '-ir/--instancerunner'
        taskRunnerParameterName = '-tr/--taskrunner'


        self.runParserRunnerOptionGroup.add_argument(
                '-ir', '--instancerunner',
                dest = 'instanceJobRunnerName',
                help = "Name of the job runner to use to execute an instance of TriAnnotUnit.py for each sequence to analyse.\nRunners configuration can be modified through the following XML configuration file : TriAnnotConfig_Runners.xml.\n%s\n" % helpComplements['instanceJobRunnerName'],
                metavar = 'JOB_RUNNER_NAME',
                choices = self.availableRunners,
                default = TriAnnotConfig.TRIANNOT_CONF['Global']['DefaultInstanceJobRunner']
        )

        self.runParserRunnerOptionGroup.add_argument(
                '-tr', '--taskrunner',
                dest = 'taskJobRunnerName',
                help = "Name of the job runner to use to submit the execution/parsing jobs of each task of a given instance.\nRunners configuration can be modified through the following XML configuration file: TriAnnotConfig_Runners.xml.\n%s\n" % helpComplements['taskJobRunnerName'],
                metavar = 'JOB_RUNNER_NAME',
                choices = self.availableRunners,
                default = TriAnnotConfig.TRIANNOT_CONF['Global']['DefaultTaskJobRunner']
        )

        self.runParserRunnerOptionGroup.add_argument(
                '--maxinstance',
                dest = 'maxParallelAnalysis',
                metavar = 'NUMBER_OF_INSTANCE',
                type = int,
                help = "Maximum number of sequences that will be analysed in parallel (ie. maximum number of TriAnnotUnit.py instance allowed to run at the same time).\nDefault value is: %s.\nWarnings:\n  - When the value of BOTH the %s AND %s arguments is equal to <Local> then NUMBER_OF_INSTANCE\n    can't be greater than <1> !\n  - When the value of the %s argument is set to <Local> then NUMBER_OF_INSTANCE can't be greater than the value\n    of the <totalNumberOfThread> attribute of the <Local> runner !\n" % (TriAnnotConfig.TRIANNOT_CONF['Global']['maxParallelAnalysis'], instanceRunnerParameterName, taskRunnerParameterName, instanceRunnerParameterName),
                default = TriAnnotConfig.TRIANNOT_CONF['Global']['maxParallelAnalysis']
        )

    def fillRunParserSequenceOptionGroup(self):
        maxLengthParameterName = '--maxlength'
        splitSeqParameterName = '--splitseq'

        self.runParserSequenceOptionGroup.add_argument(
                '--minlength',
                dest = 'minimumSequenceLength',
                metavar = 'NB_MIN_CHAR',
                type = int,
                help = "Define the minimum length of an analyzable sequence.\nSequences shorter than NB_MIN_CHAR will NOT be analysed.\nNB_MIN_CHAR could be in amino acids or nucleotides depending of the selected sequence type.\nDefault values for nucleic sequence is: %s nucleotide(s).\nDefault values for proteic sequence: %s amino acid(s).\n\n" % (TriAnnotConfig.TRIANNOT_CONF['Global']['minNucleicSequenceLength'], TriAnnotConfig.TRIANNOT_CONF['Global']['minProteicSequenceLength']),
                default = None
        )

        self.runParserSequenceOptionGroup.add_argument(
                '--maxlength',
                dest = 'maximumSequenceLength',
                metavar = 'NB_MAX_CHAR',
                type = int,
                help = "Define the maximum length of an analyzable sequence.\nSequences longer than NB_MAX_CHAR will NOT be analysed if the %s argument is not used.\nNB_MAX_CHAR could be in amino acids or nucleotides depending of the selected sequence type.\nPlease note that this is never a good idea to allow very long sequence length when your step/task file include blast-like analysis !\nDefault values for nucleic sequence is: %s nucleotide(s).\nDefault values for proteic sequence: %s amino acid(s).\n\n" % (splitSeqParameterName, TriAnnotConfig.TRIANNOT_CONF['Global']['maxNucleicSequenceLength'], TriAnnotConfig.TRIANNOT_CONF['Global']['maxProteicSequenceLength']),
                default = None
        )

        self.runParserSequenceOptionGroup.add_argument(
                '--masked',
                dest = 'ignoreOriginalSequenceMasking',
                action = 'store_false',
                help = "When this option is used, TriAnnot will take into consideration any previous lower-case masking of the initial input sequence during the creation of any sub-sequences.\n\n",
                default = True
        )

        self.runParserSequenceOptionGroup.add_argument(
                '--splitseq',
                dest = 'activateSequenceSplitting',
                action = 'store_true',
                help = "When this option is used, if a sequence of the multi-fasta input file is longer than the maximum authorized sequence size (%s)\nthan TriAnnot will split it into overlapping chunks, analyse each chunk and try to smartly merge the results.\nWarning: This argument will be ignored for proteic sequences.\n\n" % maxLengthParameterName,
                default = False
        )

        self.runParserSequenceOptionGroup.add_argument(
                '--overlap',
                dest = 'chunkOverlappingSize',
                metavar = 'NB_CHAR',
                type = int,
                help = "Define the minimum size of the overlap between two chunks.\nNB_CHAR could be in amino acids or nucleotides depending of the selected sequence type.\nWarning: This argument will be ignored if the %s argument is not used.\nDefault value is: %s nucleotide(s).\n" % (splitSeqParameterName, TriAnnotConfig.TRIANNOT_CONF['Global']['chunkOverlappingSize']),
                default = TriAnnotConfig.TRIANNOT_CONF['Global']['chunkOverlappingSize']
        )

    def fillRunParserTriAnnoUnitOptionGroup(self):
        self.runParserTriAnnoUnitOptionGroup.add_argument(
                '--kill',
                dest = 'killOnAbort',
                action = 'store_true',
                help = "When this option is used, ALL running tasks (whether they are basic subprocesses or jobs of a batch queuing system)\nof each running TriAnnotUnit.py instance (ie. of each sequence analysis) will be killed when a critical error\noccurs in one of the tasks or when a TriAnnot_abort file is detected.\n\nWhen this option is NOT used, ALL running tasks (whether they are basic subprocesses or jobs of a batch queuing system)\nwill be allowed to finish and the TriAnnotUnit.py instance will be properly stopped when a critical error occurs in one\nof the tasks or when a TriAnnot_abort file is detected.\n\n",
                default = False
        )

        self.runParserTriAnnoUnitOptionGroup.add_argument(
                '--clean',
                dest = 'cleanPattern',
                help = "Determine which files and/or directories will be kept/removed at the end of the execution of each sequence analysis.\nEach cleaning type can be activated (using Upper-case letter) or disabled (using Lower-case letter).\nDefault cleaning rules are described in TriAnnot main configuration file: TriAnnotConfig.xml.\nPossible values are:\n  - p/P -> Disable/enable python launchers files cleaning\n  - o/O -> Disable/enable stdout files cleaning\n  - e/E -> Disbale/enable stderr files cleaning\n  - t/T -> Disable/enable temporary folders cleaning\n  - c/C -> Disable/enable common files folder cleaning\n  - s/S -> Disable/enable summary files folder cleaning\n  - l/L -> Disable/enable log files cleaning\n\nExamples:\n  '--clean LOETCSP' to clean everything.\n  '--clean loetcsp' to keep everything.\n",
                metavar = 'CLEAN_PATTERN',
                default = None
        )


    def fillRunParserMiscOptionGroup(self, helpComplements):
        self.runParserMiscOptionGroup.add_argument(
                '--mth-override',
                dest = 'multiThreadOverride',
                metavar = 'NUMBER_OF_THREAD',
                type = int,
                help = "When this option is used, the number of thread to use for EVERY multithread capable tools/tasks launched by\neach TriAnnotUnit.py instance (ie. during each sequence analysis) will be set to the NUMBER_OF_THREAD value.\nIn other words, this option allow you to override the value set in the XML configuration file of each\ncompatible tool or in the step/task file.\nBase on the current content of your TriAnnotConfig_Runners XML configuration file:\n%s\nWarning: use this option wisely to avoid overloading of your computing resources !\n\n" % helpComplements['multiThreadOverride'],
                default = None
        )

        #self.runParserMiscOptionGroup.add_argument(
                #'--email',
                #dest = 'emailTo',
                #help = "Send an email at the end of pipeline execution to given email address. You can set this option more than once to send to multiple recipients",
                #action = 'append',
                #metavar = 'EMAIL_ADDRESS',
                #default = None
        #)


    def checkAndStoreRunModeArguments(self, commandLineArguments):
        # Mandatory arguments (-s/--sequence, -t/--tasks, --type)
        if commandLineArguments.sequenceFilePath is not None:
            self.sequenceFileFullPath = os.path.realpath(os.path.expanduser(commandLineArguments.sequenceFilePath))
            if not Utils.isExistingFile(self.sequenceFileFullPath):
                self.mainArgumentParser.error("The Fasta sequence file specified with the -s/--sequence argument/option does not exists or is unreadable: %s" % self.sequenceFileFullPath)
            if Utils.isEmptyFile(self.sequenceFileFullPath):
                self.mainArgumentParser.error("The Fasta sequence file specified with the -s/--sequence argument/option is empty: %s" % self.sequenceFileFullPath)

        if commandLineArguments.tasksFilePath is not None:
            self.tasksFileFullPath = os.path.realpath(os.path.expanduser(commandLineArguments.tasksFilePath))
            if not Utils.isExistingFile(self.tasksFileFullPath):
                self.mainArgumentParser.error("The full step/task file specified with the -t/--tasks argument/option does not exists or is unreadable: %s" % self.tasksFileFullPath)
            if Utils.isEmptyFile(self.tasksFileFullPath):
                self.mainArgumentParser.error("The full step/task file specified with the -t/--tasks argument/option is empty: %s" % self.tasksFileFullPath)
        self.sequenceType = commandLineArguments.sequenceType

        # Configuration loading/control related arguments
        # Already managed in function manageConfigLikeRunParserArguments (as they are used earlier)

        # Job management related arguments (-ir/--instancerunner, -tr/--taskrunner, --maxinstance)
        self.instanceJobRunnerName = commandLineArguments.instanceJobRunnerName
        self.taskJobRunnerName = commandLineArguments.taskJobRunnerName
        self.checkRunners()

        TriAnnotConfig.TRIANNOT_CONF['Runtime']['instanceJobRunnerName'] = self.instanceJobRunnerName
        TriAnnotConfig.TRIANNOT_CONF['Runtime']['taskJobRunnerName'] = self.taskJobRunnerName

        self.maxParallelAnalysis = commandLineArguments.maxParallelAnalysis
        self.checkMaxParallelAnalysisValue()

        # Input sequence(s) management related arguments (--minlength, --maxlength, --masked, --splitseq, --overlap)
        if commandLineArguments.minimumSequenceLength is not None:
            if type(commandLineArguments.minimumSequenceLength) is not int:
                self.mainArgumentParser.error("The value of the --minlength parameter must be a valid integer ! The following value is not valid: %s" % commandLineArguments.minimumSequenceLength)
            self.minimumSequenceLength = int(commandLineArguments.minimumSequenceLength)
        else:
            if self.sequenceType == 'nucleic':
                self.minimumSequenceLength = int(TriAnnotConfig.TRIANNOT_CONF['Global']['minNucleicSequenceLength'])
            elif self.sequenceType == 'proteic':
                self.minimumSequenceLength = int(TriAnnotConfig.TRIANNOT_CONF['Global']['minProteicSequenceLength'])
            else:
                self.mainArgumentParser.error("Selected sequence type <%s> is not managed at the moment.." % self.sequenceType)

        if commandLineArguments.maximumSequenceLength is not None:
            if type(commandLineArguments.maximumSequenceLength) is not int:
                self.mainArgumentParser.error("The value of the --maxlength parameter must be a valid integer ! The following value is not valid: %s" % maximumSequenceLength)
            self.maximumSequenceLength = int(commandLineArguments.maximumSequenceLength)
        else:
            if self.sequenceType == 'nucleic':
                self.maximumSequenceLength = int(TriAnnotConfig.TRIANNOT_CONF['Global']['maxNucleicSequenceLength'])
            elif self.sequenceType == 'proteic':
                self.maximumSequenceLength = int(TriAnnotConfig.TRIANNOT_CONF['Global']['maxProteicSequenceLength'])
            else:
                self.mainArgumentParser.error("Selected sequence type <%s> is not managed at the moment.." % self.sequenceType)

        if self.minimumSequenceLength > self.maximumSequenceLength:
            self.mainArgumentParser.error("The minimum sequence length can't be greater than the maximum sequence length ! (%s > %s)" % (self.minimumSequenceLength, self.maximumSequenceLength))

        self.ignoreOriginalSequenceMasking = commandLineArguments.ignoreOriginalSequenceMasking

        # Manage sequence splitting
        self.activateSequenceSplitting = commandLineArguments.activateSequenceSplitting
        if self.sequenceType == 'proteic':
            self.activateSequenceSplitting = False

        if self.activateSequenceSplitting:
            if commandLineArguments.chunkOverlappingSize > (self.maximumSequenceLength / 2):
                self.mainArgumentParser.error("The size of the overlap between two chunks can't be greater than half the size of the maximum sequence length ! (%s is greater than %s)" % (commandLineArguments.chunkOverlappingSize, (self.maximumSequenceLength / 2)))
            if commandLineArguments.chunkOverlappingSize < self.minimumSequenceLength:
                self.mainArgumentParser.error("The size of the overlap between two chunks can't be lower than the minimum sequence length ! (%s is lower than %s)" % (commandLineArguments.chunkOverlappingSize, self.minimumSequenceLength))
        self.chunkOverlappingSize = commandLineArguments.chunkOverlappingSize

        # Arguments directly transmitted to TriAnnot Units: --clean, --kill
        if commandLineArguments.cleanPattern is not None:
            # Check clean pattern
            cleanPatternValidationRexex = re.compile(r"^(?!.*?(.).*?\1)[poetcsl]+$", re.IGNORECASE)
            if cleanPatternValidationRexex.match(commandLineArguments.cleanPattern) is None:
                self.mainArgumentParser.error("Cleaning scheme option (-c, --clean) is invalid: %s" % cleanSchemeString)
            else:
                self.cleanPattern = commandLineArguments.cleanPattern
                self.convertCleanPatternToDict()
        else:
            self.convertDictToCleanPattern()

        self.killOnAbort = commandLineArguments.killOnAbort

        # Unclassified arguments (--mth-override, --email)
        # Force each multithread capable tools to use a specific number of thread/slot in every instances
        if commandLineArguments.multiThreadOverride is not None:
            if (int(commandLineArguments.multiThreadOverride) < 1 or int(commandLineArguments.multiThreadOverride) > int(TriAnnotConfig.TRIANNOT_CONF['Runners'][self.taskJobRunnerName]['maximumNumberOfThreadByTool'])):
                self.mainArgumentParser.error("The NUMBER_OF_THREAD value (used for the --mth-override option) can't be lower than <1> or greater than <%s> for the <%s> task job runner: %s is invalid !" % (TriAnnotConfig.TRIANNOT_CONF['Runners'][self.taskJobRunnerName]['maximumNumberOfThreadByTool'], self.taskJobRunnerName, commandLineArguments.multiThreadOverride))
            else:
                TriAnnotConfig.TRIANNOT_CONF['Runtime']['multiThreadOverride'] = str(commandLineArguments.multiThreadOverride)

        #self.emailTo = commandLineArguments.emailTo


    def checkRunners(self):
        # Check if the runner selected as "instance runner" is allowed to run instances
        if TriAnnotConfig.TRIANNOT_CONF['Runners'][self.instanceJobRunnerName]['usageLimitation'] not in ['instance', 'both']:
            self.mainArgumentParser.error("The <%s> job runner selected through the -ir/--instancerunner argument can't be used to run TriAnnotUnit instances !" % self.instanceJobRunnerName)

        # Check if the runner selected as "task runner" is allowed to run tasks
        if TriAnnotConfig.TRIANNOT_CONF['Runners'][self.taskJobRunnerName]['usageLimitation'] not in ['task', 'both']:
            self.mainArgumentParser.error("The <%s> job runner selected through the -tr/--taskrunner argument can't be used to run TriAnnot tasks !" % self.taskJobRunnerName)

        # Check if the combination of runner is valid
        self.checkRunnerCombination()


    def checkRunnerCombination(self):
        if self.instanceJobRunnerName != 'Local':
            if self.taskJobRunnerName != 'Local':
                if TriAnnotConfig.getConfigValue("Runners|%s|allowSubmissionFromComputeNodes" % self.instanceJobRunnerName).lower() == 'no':
                    self.mainArgumentParser.error("The combination of runner you have selected (Instance runner: %s + Task runner: %s) is not valid because the <%s> runner is currently configured to refuse the submission of jobs from the compute nodes (ie.from an already running job).Either change the selected runners or update the runners configuration in the TriAnnotConfig_Runners XML file." % (self.instanceJobRunnerName, self.taskJobRunnerName, self.instanceJobRunnerName))


    def checkMaxParallelAnalysisValue(self):
        if self.maxParallelAnalysis > 1:
            if self.instanceJobRunnerName == 'Local':
                if self.taskJobRunnerName == 'Local':
                    self.mainArgumentParser.error("To avoid overloading, the value of the --maxinstance parameter can't be greater than <1> when the instance runner AND the task runner are both set to <Local> ! The following value is not valid: %s" % self.maxParallelAnalysis)
                elif self.maxParallelAnalysis > int(TriAnnotConfig.TRIANNOT_CONF['Runners']['Local']['totalNumberOfThread']):
                    self.mainArgumentParser.error("\nTo avoid overloading, the value of the --maxinstance parameter can't be greater than the value of the <totalNumberOfThread> attribute of the <Local> runner when the instance runner is set to <Local> ! (%s > %s)\nPlease, either reduce the --maxinstance value or update the configuration of the <Local> runner in the TriAnnotConfig_Runners.xml configuration file." % (self.maxParallelAnalysis, TriAnnotConfig.TRIANNOT_CONF['Runners']['Local']['totalNumberOfThread']))


    def convertCleanPatternToDict(self):
        if not TriAnnotConfig.TRIANNOT_CONF.has_key('Global'):
            TriAnnotConfig.TRIANNOT_CONF['Global'] = dict()
            if not TriAnnotConfig.TRIANNOT_CONF['Global'].has_key('cleanAtTheEnd'):
                TriAnnotConfig.TRIANNOT_CONF['Global']['cleanAtTheEnd'] = dict()

        for letter in self.cleanPattern:
            if letter == 'p':
                TriAnnotConfig.TRIANNOT_CONF['Global']['cleanAtTheEnd']['launcherFiles'] = 'no'
            elif letter == 'P':
                TriAnnotConfig.TRIANNOT_CONF['Global']['cleanAtTheEnd']['launcherFiles'] = 'yes'
            elif letter == 'o':
                TriAnnotConfig.TRIANNOT_CONF['Global']['cleanAtTheEnd']['stdoutFiles'] = 'no'
            elif letter == 'O':
                TriAnnotConfig.TRIANNOT_CONF['Global']['cleanAtTheEnd']['stdoutFiles'] = 'yes'
            elif letter == 'e':
                TriAnnotConfig.TRIANNOT_CONF['Global']['cleanAtTheEnd']['stderrFiles'] = 'no'
            elif letter == 'E':
                TriAnnotConfig.TRIANNOT_CONF['Global']['cleanAtTheEnd']['stderrFiles'] = 'yes'
            elif letter == 't':
                TriAnnotConfig.TRIANNOT_CONF['Global']['cleanAtTheEnd']['tmpFolders'] = 'no'
            elif letter == 'T':
                TriAnnotConfig.TRIANNOT_CONF['Global']['cleanAtTheEnd']['tmpFolders'] = 'yes'
            elif letter == 'c':
                TriAnnotConfig.TRIANNOT_CONF['Global']['cleanAtTheEnd']['commonFilesFolder'] = 'no'
            elif letter == 'C':
                TriAnnotConfig.TRIANNOT_CONF['Global']['cleanAtTheEnd']['commonFilesFolder'] = 'yes'
            elif letter == 's':
                TriAnnotConfig.TRIANNOT_CONF['Global']['cleanAtTheEnd']['summaryFilesFolder'] = 'no'
            elif letter == 'S':
                TriAnnotConfig.TRIANNOT_CONF['Global']['cleanAtTheEnd']['summaryFilesFolder'] = 'yes'
            elif letter == 'l':
                TriAnnotConfig.TRIANNOT_CONF['Global']['cleanAtTheEnd']['logFilesFolder'] = 'no'
            elif letter == 'L':
                TriAnnotConfig.TRIANNOT_CONF['Global']['cleanAtTheEnd']['logFilesFolder'] = 'yes'


    def convertDictToCleanPattern(self):
        # Initializations
        self.cleanPattern = ''

        # Analyse some default configuration variables to build the clean string
        if TriAnnotConfig.TRIANNOT_CONF['Global']['cleanAtTheEnd']['launcherFiles'] == 'no':
            self.cleanPattern += 'p'
        else:
            self.cleanPattern += 'P'

        if TriAnnotConfig.TRIANNOT_CONF['Global']['cleanAtTheEnd']['stdoutFiles'] == 'no':
            self.cleanPattern += 'o'
        else:
            self.cleanPattern += 'O'

        if TriAnnotConfig.TRIANNOT_CONF['Global']['cleanAtTheEnd']['stderrFiles'] == 'no':
            self.cleanPattern += 'e'
        else:
            self.cleanPattern += 'E'

        if TriAnnotConfig.TRIANNOT_CONF['Global']['cleanAtTheEnd']['tmpFolders'] == 'no':
            self.cleanPattern += 't'
        else:
            self.cleanPattern += 'T'

        if TriAnnotConfig.TRIANNOT_CONF['Global']['cleanAtTheEnd']['commonFilesFolder'] == 'no':
            self.cleanPattern += 'c'
        else:
            self.cleanPattern += 'C'

        if TriAnnotConfig.TRIANNOT_CONF['Global']['cleanAtTheEnd']['summaryFilesFolder'] == 'no':
            self.cleanPattern += 's'
        else:
            self.cleanPattern += 'S'

        if TriAnnotConfig.TRIANNOT_CONF['Global']['cleanAtTheEnd']['logFilesFolder'] == 'no':
            self.cleanPattern += 'l'
        else:
            self.cleanPattern += 'L'


    ################################################################
    ##  Configuration files loading and checking related methods  ##
    ################################################################

    def loadConfigurationAndExecuteBasicChecks(self):
       # Create a new TriAnnotConfigurationChecker object
        self.configurationCheckerObject = TriAnnotConfigurationChecker(self.configFileFullPath, self.cmdLineConfigAlone)

        # Check the existence and access rights of every configuration files
        self.configurationCheckerObject.checkConfigurationFilesExistence()
        self.configurationCheckerObject.displayInvalidConfigurationFiles()
        if self.configurationCheckerObject.nbInvalidConfigurationFiles > 0:
            exit(1)

        # Check the syntax of the XML configuration files
        self.configurationCheckerObject.checkXmlSyntaxOfConfigurationFiles()
        self.configurationCheckerObject.displayXmlSyntaxErrors()
        if self.configurationCheckerObject.nbErrorContainingXmlFiles > 0:
            exit(1)

        # Load every XML configuration files into memory
        self.loadAllConfigurationFiles()

        # Check the existence of the mandatory configuration sections
        self.configurationCheckerObject.checkMandatoryConfigurationSections()
        self.configurationCheckerObject.displayMissingMandatoryConfigurationSections()
        if self.configurationCheckerObject.nbMissingMandatoryConfigurationSections > 0:
            exit(1)

        # Check the existence of the mandatory configuration entries
        self.configurationCheckerObject.checkMandatoryConfigurationEntries()
        self.configurationCheckerObject.displayMissingMandatoryConfigurationEntries()
        if self.configurationCheckerObject.nbMissingMandatoryConfigurationEntries > 0:
            exit(1)

        # Check if the dependences between configuration sections are fulfilled
        self.configurationCheckerObject.checkConfigurationDependencies()
        self.configurationCheckerObject.displayBrokenConfigurationDependencies()
        if self.configurationCheckerObject.nbBrokenConfigurationDependencies > 0:
            exit(1)


    def loadAllConfigurationFiles(self):
        self.logger.info('The content of the various XML configuration files will now be loaded into memory')

        for configurationFile in self.configurationCheckerObject.xmlFilesToCheck:
            self.logger.debug("The following configuration file will now be loaded: %s" % configurationFile['name'])
            # Object creation
            if configurationFile['type'] == 'global' or configurationFile['type'] == 'tool':
                configurationLoader = TriAnnotConfig(configurationFile['path'], None)
            else:
                configurationLoader = TriAnnotConfig(configurationFile['path'], TRIANNOT_VERSION)
            # Effective loading
            if not configurationLoader.loadConfigurationFile():
                exit(1)

        self.logger.info('All configuration files have been loaded')


    def updateAndCondenseConfiguration(self):
        # Replace all the special wildcard values (ie. values containing a call to the getValue method) by real values
        self.parseConfigurationFilesSpecialValues()

        # If the configuration section of a tool has an "additionalConfigurationSectionsToInclude" entry
        # then we need to add the contents of these additional configuration sections into the tool's configuration section
        TriAnnotConfig.combineLinkedConfigurationSections()


    def parseConfigurationFilesSpecialValues(self):
        self.logger.debug('Parsing configuration files special values')
        TriAnnotConfig.parseSpecialValues()
        if len(TriAnnotConfig.parsingErrors) > 0:
            for error in TriAnnotConfig.parsingErrors:
                self.logger.error(error)
            exit(1)


    def performAdvancedConfigurationChecks(self):
        # Collect and check parameters definitions for every tools
        self.configurationCheckerObject.checkAllParametersDefinitions()
        self.configurationCheckerObject.displayParametersDefinitionsErrors()
        if self.configurationCheckerObject.nbParametersDefinitionsErrors > 0:
            exit(1)

        # Check the existence and the access rights of every databases, softs, matrices, configuration files/directories and indexes
        self.configurationCheckerObject.checkPathsDefinedInConfigurationFiles()
        self.configurationCheckerObject.displayInvalidPathErrors()
        if self.configurationCheckerObject.nbInvalidPathErrors > 0:
            exit(1)


    ###########################################################
    ##  Step/task file loading and checking related methods  ##
    ###########################################################

    def loadAndCheckTriAnnotTaskFile(self):
        # This method do many things:
        # 1) Load the content of the step/task file into memory (if the XML syntax of the file is valid)
        # 2) Check requested tools availability
        # 3) Check task's sequences
        # 4) Check tash dependencies
        # 5) Check all the parameters of the tasks

        # Create a new TriAnnotTaskFileChecker object
        taskFileCheckerObject = TriAnnotTaskFileChecker(self.tasksFileFullPath)

        # Check the XML syntax of the step/task file
        taskFileCheckerObject.checkTaskFileXmlSyntax()
        taskFileCheckerObject.displayXmlSyntaxErrors()
        if len(taskFileCheckerObject.xmlSyntaxErrors) > 0:
            exit(1)

        # Load and check the version of the step/task file
        taskFileCheckerObject.loadTaskFile()
        self.taskFileDescription = taskFileCheckerObject.taskFileDescription

        if not taskFileCheckerObject.isMadeForCurrentTriAnnotVersion():
            self.logger.error("The selected XML step/task file was written for a different version of TriAnnot (Version <%s> but version <%s> was expected)." % (taskFileCheckerObject.taskFileTriAnnotVersion, TRIANNOT_VERSION))
            self.logger.info("Please, update your step/task file before running TriAnnot again.")
            exit(1)
        taskFileCheckerObject.displayTaskFileLoadingErrors()
        if taskFileCheckerObject.nbTaskFileLoadingErrors > 0:
            exit(1)

        # Check the list of tools referenced in the step/task file
        taskFileCheckerObject.checkToolsAvailability()
        taskFileCheckerObject.displayNotAvailableTools()
        if taskFileCheckerObject.nbNotAvailableTools > 0:
            exit(1)

        # Check the validity of the sequences referenced in the step/task file
        taskFileCheckerObject.checkTasksSequences(self.mainExecDirFullPath)
        taskFileCheckerObject.displayTasksSequenceErrors()
        if taskFileCheckerObject.nbTasksSequenceErrors > 0:
            exit(1)

        # Check dependences
        taskFileCheckerObject.manageSpecialDependencies()
        taskFileCheckerObject.checkAllTasksDependencies()
        taskFileCheckerObject.displayInvalidDependencies()
        if taskFileCheckerObject.nbInvalidDependencies > 0:
            exit(1)

        # Check task parameters
        taskFileCheckerObject.checkAllTasksParameters()
        taskFileCheckerObject.displayInvalidParameters()
        if taskFileCheckerObject.nbInvalidParameters > 0:
            exit(1)


    ###############################################
    ##  Monitor mode specific execution methods  ##
    ###############################################

    def displayInstancesStatus(self):
        # Log
        self.logger.info("The status of the analysis of each sequence will now be displayed")
        self.logger.info('')

        # Get & display status counters
        statusCounters = self.sqliteObject.getStatusCounters()
        self.displayStatusCounters(statusCounters)

        # Get & display sequence's status
        for sequenceName, chunkStatus in self.sqliteObject.getSequencesStatus(returnStatusAsString = True).items():
            self.logger.info('')
            self.logger.info("Status for sequence <%s>:" % sequenceName)
            for chunkName, chunkAttributes in chunkStatus.items():
                self.logger.info("   Chunk %s:" % chunkName)
                for attributeName, attributeValue in chunkAttributes.items():
                    self.logger.info("      %s: %s" % (attributeName.capitalize(), attributeValue))

        # Write the progression in a file if needed
        if self.writeProgressionToFile:
            self.progressFileFullPath = os.path.join(self.mainExecDirFullPath, 'TriAnnot_progress')

            # Removal of the old version
            if Utils.isExistingFile(self.progressFileFullPath):
                os.remove(self.progressFileFullPath)

            # Effective writting
            self.logger.info('')
            self.logger.info("The progression of the analysis will now be written in the the following file: %s" % self.progressFileFullPath)
            self.writeAnalysisProgression(statusCounters)


    def writeAnalysisProgression(self, statusCounters = None):
        # Initializations
        progressFileHandler = None

        # Try to create a file handler for the TriAnnot_progress file
        try:
            progressFileHandler = open(self.progressFileFullPath, 'w')
        except IOError:
            self.logger.error("%s could not create (or update) the following XML progress file: %s" % (self.programName, self.progressFileFullPath))
            raise

        # Add content to the XML file (Note: the with statement allow auto-closing of the file)
        with progressFileHandler:
            #  Build the root of the XML file
            xmlRoot = etree.Element('analysis_progression', {'triannot_version': TRIANNOT_VERSION})

            # Keep track of last report date
            reportDateElement = etree.SubElement(xmlRoot, 'report_date')
            reportDateElement.text = time.strftime("%Y-%m-%d %H:%M:%S")

            # Get status counters if needed
            if statusCounters is None:
                statusCounters = self.sqliteObject.getStatusCounters()

            # Create XML elements for the counters
            statusCountersElement = etree.SubElement(xmlRoot, 'status_repartition')

            for statusCodeOrName, statusCounter in sorted(statusCounters.items()):
                if type(statusCodeOrName) is int:
                    statusCodeOrName = TriAnnotStatus.getStatusName(statusCodeOrName)

                statusNameElement = etree.SubElement(statusCountersElement, statusCodeOrName.lower())
                statusNameElement.text = str(statusCounter)

            # Status and progression percentage of every instances
            statusElement = etree.SubElement(xmlRoot, 'sequences_status')

            for sequenceName, chunkStatus in self.sqliteObject.getSequencesStatus(returnStatusAsString = True).items():
                sequenceElement = etree.SubElement(statusElement, 'sequence', {'name': sequenceName})
                for chunkName, chunkAttributes in chunkStatus.items():
                    chunkElement = etree.SubElement(sequenceElement, 'chunk', {'name': chunkName})
                    for attributeName, attributeValue in chunkAttributes.items():
                        chunkElement.attrib[attributeName] = attributeValue

            # Indent the XML content
            TriAnnotConfig.indent(xmlRoot)

            # Write the generated XML content
            progressFileHandler.write(etree.tostring(xmlRoot, 'ISO-8859-1'))


    ###################################################
    ##  Result files reconstruction related methods  ##
    ###################################################

    def performResultFilesReconstruction(self):
        # Log
        self.logger.info("%s will now try to reconstruct global result files for every splitted sequences" % (self.programName))
        self.logger.info('')

        # Get the status of every sequence analysis
        sequenceStatutes = self.sqliteObject.getSequencesAnalysisStatus()

        # Define which sequences are ready for reconstruction, which are not and which have already been treated
        self.sortSequencesByStatus(sequenceStatutes)

        # If the --force argument has not been used then we need to stop the reconstruction procedure if at least one sequence is not ready for reconstruction
        if not self.forceReconstruction and not self.allSequenceReadyForReconstruction:
            self.logger.warning('TriAnnot is currently configured to cancel the reconstruction procedure if at least one sequence is not ready for reconstruction (default behavior)')
            self.logger.warning("Please use the %s argument of the <%s> sub-command if you want to allow a partial reconstruction." % ('--force', self.selectedSubCommand))
            self.logger.info('')
            self.logger.error("The following sequence(s) is/are not ready for reconstruction: %s" % ', '.join(notReadyForReconstructionSequences))
            self.logger.error('The reconstruction procedure will now be aborted..')
            exit(1)

        # Prepare the directory which will store the reconstructed result files
        self.globalReconstructionFolderFullPath = os.path.join(self.mainExecDirFullPath, 'Reconstructed_result_files')
        if not Utils.isExistingDirectory(self.globalReconstructionFolderFullPath):
            os.mkdir(self.globalReconstructionFolderFullPath)

        # Get the list of step/task identifiers that are concerned by the reconstruction procedure
        self.getTaskIdentifiersForReconstruction()

        # Reconstruct the result files for each sequence that are ready
        for sequenceName in self.sequencesByStatus['ready']:
            self.reconstructCurrentSequenceResultFiles(sequenceName)


    def sortSequencesByStatus(self, sequenceStatutes):
        # Initializations
        self.allSequenceReadyForReconstruction = True
        self.sequencesByStatus = {'ready': list(), 'notReady': list(), 'done': list()}
        readableStatusNames = {'ready': 'Ready for reconstruction', 'notReady': 'Not ready for reconstruction', 'done': 'Already reconstructed'}

        # Sort sequences
        # A sequence is ready for reconstruction if all its chunk have been successfully analysed
        # In other words: if the number of finished chunk is equal to the total number of chunk and if the status of each chunk is COMPLETED
        for sequenceName, sequenceStatus in sequenceStatutes.items():
            if sequenceStatus['reconstructed'] == 1:
                self.logger.debug("Result files for sequence <%s> have already been reconstructed (Status: %s)" % (sequenceName, sequenceStatus['reconstructionStatus']))
                self.sequencesByStatus['done'].append(sequenceName)
            else:
                if sequenceStatus['numberOfChunk'] == sequenceStatus['numberOfFinishedChunk'] and type(sequenceStatus['distinctInstancesStatus']) is int and sequenceStatus['distinctInstancesStatus'] == TriAnnotStatus.COMPLETED:
                    self.logger.debug("Sequence <%s> is ready for reconstruction" % sequenceName)
                    self.sequencesByStatus['ready'].append(sequenceName)
                else:
                    self.logger.debug("Sequence <%s> is NOT ready for reconstruction" % sequenceName)
                    self.sequencesByStatus['notReady'].append(sequenceName)
                    self.allSequenceReadyForReconstruction = False

        # Display sequences status
        self.logger.info('Here is the status of each sequence:')
        for statusName, correspondingSequences in self.sequencesByStatus.items():
            if len(correspondingSequences) > 0:
                reconstructionStatus = ' (Status: %s)' % sequenceStatutes[sequenceName]['reconstructionStatus'] if sequenceStatutes[sequenceName]['reconstructionStatus'] is not None else ''
                for sequenceName in correspondingSequences:
                    self.logger.info('   %s - %s%s' % (sequenceName, readableStatusNames[statusName], reconstructionStatus))
        self.logger.info('')


    def getTaskIdentifiersForReconstruction(self):
        # Initializations
        self.taskIdentifiersForReconstruction = list()

        # Build list
        self.logger.info('The result file reconstruction has been activated for the following tasks:')
        for taskParameterObject in TriAnnotTaskFileChecker.allTaskParametersObjects.values():
            if taskParameterObject.parameters.has_key('activateReconstruction') and taskParameterObject.parameters['activateReconstruction'] == 'yes':
                self.logger.info("   %s" % taskParameterObject.taskDescription)
                self.taskIdentifiersForReconstruction.append(taskParameterObject.taskId)


    def reconstructCurrentSequenceResultFiles(self, sequenceName):
        self.logger.info('')
        self.logger.info("The reconstruction of the result files for sequence <%s> will now start !" % sequenceName)
        self.logger.info('')

        # Initializations
        currentSequenceReconstructionFolderFullPath = os.path.join(self.globalReconstructionFolderFullPath, sequenceName)
        reconstructedGffFolderFullPath = os.path.join(currentSequenceReconstructionFolderFullPath, TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['GFF_files'])
        reconstructedEmblFolderFullPath = os.path.join(currentSequenceReconstructionFolderFullPath, TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['EMBL_files'])

        # Create a subfolder for the current sequence in the global reconstruction folder
        if not Utils.isExistingDirectory(currentSequenceReconstructionFolderFullPath): os.mkdir(currentSequenceReconstructionFolderFullPath)

        # Recovers useful information about the chunks from the database
        self.chunksData = self.sqliteObject.getChunkData(sequenceName)

        # Special case: the sequence has not been splitted and there is no GFF file merging to do
        # We just have to copy the original GFF files in the appropriate subfolder of the Reconstructed_result_files folder
        if (len(self.chunksData) == 1):
            self.logger.info("  => Sequence <%s> has not been splitted during its analysis and its result files will therefore be copied as if into the appropriate reconstruction folder" % sequenceName)
            self.copyEntireResultFolder(self.chunksData[0]['instanceDirectoryFullPath'], currentSequenceReconstructionFolderFullPath, TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['GFF_files'], sequenceName)
            self.copyEntireResultFolder(self.chunksData[0]['instanceDirectoryFullPath'], currentSequenceReconstructionFolderFullPath, TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['EMBL_files'], sequenceName)
            return

        self.logger.info("  => Sequence <%s> has been splitted into <%d> overlapping chunks during its analysis (Overlap size: %s)" % (sequenceName, len(self.chunksData), self.chunkOverlappingSize))

        # Creation of the GFF and EMBL folders in the reconstruction folder of the current sequence
        if not Utils.isExistingDirectory(reconstructedGffFolderFullPath): os.mkdir(reconstructedGffFolderFullPath)
        #if not Utils.isExistingDirectory(reconstructedEmblFolderFullPath): os.mkdir(reconstructedEmblFolderFullPath)

        # Build the list of GFF files that will be merged for each concerned step of the current sequence
        self.getListOfGffFilesToMerge()

        # Determine the start and end position of each chunk on the complete sequence they have been extracted from
        self.determineChunkStartEndPositionOnGlobalSequence()

        # Global result files reconstruction
        for taskId, listOfGffFiles in self.gffFileToMergeByTask.items():
            # Build a unique GFF/EMBL result file for the current task based on all the result files generated for this task during each chunk analysis
            self.buildGlobalResultFileForCurrentTask(taskId, listOfGffFiles, currentSequenceReconstructionFolderFullPath, sequenceName)


    def copyEntireResultFolder(self, instanceDirectoryFullPath, reconstructionFolderFullPath, folderType, sequenceName):
        self.logger.debug("The content of the %s folder for Sequence <%s> will now be copied in the appropriate reconstruction folder" % (folderType, sequenceName))

        try:
            shutil.copytree(os.path.join(instanceDirectoryFullPath, folderType), os.path.join(reconstructionFolderFullPath, folderType), symlinks=True)
        except shutil.Error as shutilError:
            shutilError.message = "The shutil copytree method has returned the following error:" % shutilError
            self.logger.error(shutilError.message)
            raise shutilError
        except OSError as folderCopyError:
            folderCopyError.message= "Cannot copy the content of the following %s folder in the reconstruction folder of the current sequence: %s (%s)" % (folderType, instanceDirectoryFullPath, folderCopyError.strerror)
            self.logger.error(folderCopyError.message)
            raise folderCopyError


    def getListOfGffFilesToMerge(self):
        # Initializations
        self.gffFileToMergeByTask = OrderedDict()

        # Get GFF files fullpaths
        for chunk in self.chunksData:
            for taskId in self.taskIdentifiersForReconstruction:
                if not self.gffFileToMergeByTask.has_key(taskId):
                    self.gffFileToMergeByTask[taskId] = list()

                # Determine if the GFF file for the current task exist in the default GFF folder or has been moved to the Blast result folder
                gffFileFullPath = self.determineAndCheckGffFileFullPath(chunk['instanceDirectoryFullPath'], taskId)

                # Store the path int the list
                self.gffFileToMergeByTask[taskId].append({'chunk': chunk['chunkNumber'], 'path': gffFileFullPath})

        self.logger.debug("gffFileToMergeByTask content: %s" % self.gffFileToMergeByTask)


    def determineAndCheckGffFileFullPath(self, instanceDirectoryFullPath, taskId):
        # Initializations
        defaultGffFileFullPath = os.path.join(instanceDirectoryFullPath, TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['GFF_files'], TriAnnotTaskFileChecker.allTaskParametersObjects[taskId].parameters['gffFile'])
        alternativeGffFileFullPath = os.path.join(instanceDirectoryFullPath, TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['blast_files'], TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['GFF_files'], TriAnnotTaskFileChecker.allTaskParametersObjects[taskId].parameters['gffFile'])

        if Utils.isExistingFile(defaultGffFileFullPath):
            return defaultGffFileFullPath
        elif Utils.isExistingFile(alternativeGffFileFullPath):
            return alternativeGffFileFullPath
        else:
            self.logger.error("The following GFF file does not exists in the default GFF folder or the alternative GFF folder (%s): %s" % (TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['blast_files'], TriAnnotTaskFileChecker.allTaskParametersObjects[taskId].parameters['gffFile']))
            exit(1)


    def determineChunkStartEndPositionOnGlobalSequence(self):
        for chunk in self.chunksData:
            if chunk['chunkNumber'] == 0 or chunk['chunkNumber'] == 1:
                chunk['chunkStartPosition'] = 1
                chunk['chunkEndPosition'] = chunk['chunkSize']
            else:
                chunk['chunkStartPosition'] = (lastChunkEndPosition - self.chunkOverlappingSize) + 1
                chunk['chunkEndPosition'] = chunk['chunkStartPosition'] + chunk['chunkSize'] - 1

            lastChunkEndPosition = chunk['chunkEndPosition']


    def buildGlobalResultFileForCurrentTask(self, taskId, listOfGffFiles, currentSequenceReconstructionFolderFullPath, sequenceName):
        # Initializations
        selectedFeatures = list()

        self.logger.info('')
        self.logger.info("  => Merging GFF result files for task n°%s" % TriAnnotTaskFileChecker.allTaskParametersObjects[taskId].taskDescription)
        self.logger.info('')

        # Extract and group (by kinship) all the features of the selected GFF files +  Update all feature's coordinates on the fly
        # The update consist in a conversation of local coordinates (ie. on the chunk) into global coordinates (ie. on the initial sequence)
        allExtractedFeatureGroups, globalRegionFeatureAttributes, totalNumberOfFeatureGroup = self.extractFeatureGroupsFromAllGffFiles(listOfGffFiles)

        # We continue if at least one feature group has been extracted
        if totalNumberOfFeatureGroup > 0:
            # Build the global region feature and store it
            selectedFeatures.append(self.buildGlobalRegionFeature(globalRegionFeatureAttributes, sequenceName))

            # Filter feature groups (based on the master feature of each group) to kept the best features groups and reject duplicates
            selectedFeatures.extend(self.filterFeatureGroups(allExtractedFeatureGroups, len(listOfGffFiles)))
        else:
            self.logger.info('    -> Skipping the feature selection step (No feature group extracted)')

        # Write the global GFF file for the current step/task
        self.writeGlobalGffFile(selectedFeatures, os.path.join(currentSequenceReconstructionFolderFullPath, TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['GFF_files'], os.path.basename(listOfGffFiles[0]['path'])), taskId)

        # Call a stand alone Perl executable that will write the custom EMBL file by using the EMBL_writer.pm module
        # To Do


    def extractFeatureGroupsFromAllGffFiles(self, listOfGffFiles):
        # Initializations
        featureGroupsOfEachFiles = list()
        totalNumberOfFeatureGroup = 0
        globalRegionFeatureAttributes = ''

        # Group the feature of each GFF file by kinship
        for currentGffFile in listOfGffFiles:
            # Extract the feature group from the GFF file
            self.logger.info("    -> Extracting features from the following GFF file (Chunk n°%d): %s" % (currentGffFile['chunk'], currentGffFile['path']))
            newlyExtractedFeatureGroups, extractedGlobalRegionFeatureAttributes = self.extractFeatureGroups(currentGffFile['path'], self.chunksData[currentGffFile['chunk'] - 1]['chunkStartPosition'])

            # Save the attributes of the global region feature
            if globalRegionFeatureAttributes == '':
                globalRegionFeatureAttributes = extractedGlobalRegionFeatureAttributes

            # Count and display the number of extracted feature groups
            nbExtracteFeatures = len(newlyExtractedFeatureGroups)
            totalNumberOfFeatureGroup += nbExtracteFeatures
            self.logger.info("       -> %d valid group of features has/have been collected" % nbExtracteFeatures)

            # Store extracted groups in the global list
            featureGroupsOfEachFiles.append(newlyExtractedFeatureGroups)

        self.logger.info('')

        return (featureGroupsOfEachFiles, globalRegionFeatureAttributes, totalNumberOfFeatureGroup)


    def extractFeatureGroups(self, gffFileFullPath, chunkStartPosition):
        # Initializations
        featureGroups = OrderedDict()
        globalRegionFeatureAttributes = ''
        currentMainParent = ''

        # File Handler creation
        try:
            gffFileHandler = open(gffFileFullPath, 'rU')
        except IOError:
            self.logger.error("%s could not open/read the following GFF file: %s" % (self.programName, gffFileFullPath))
            raise

        # Browse the file line by line
        with gffFileHandler:
            for rawLine in gffFileHandler:
                cleanLine = rawLine.rstrip()

                # Reject comment lines and empty lines
                if cleanLine.startswith("#") or len(cleanLine.strip()) == 0:
                    continue

                # Create a sort of SeqFeature object
                currentFeature = self.createFeatureWithUpdatedCoordinates(cleanLine, chunkStartPosition)

                # Reject all region/merged features by default (but extract global region feature attributes)
                if currentFeature['featureType'] == 'region':
                    if currentFeature['source'] == 'TriAnnotPipeline':
                        globalRegionFeatureAttributes = currentFeature['attributes']
                    continue

                # Store the current feature in the global hash table
                if currentFeature['attributes'].has_key('Parent') or currentFeature['attributes'].has_key('Derives_from'):
                    # Child feature (or grandchild feature) of the last main feature
                    featureGroups[currentMainParent]['childrens'].append(currentFeature)
                else:
                    # First level feature (ie. feature with no parents)
                    currentMainParent = currentFeature['attributes']['ID']
                    featureGroups[currentFeature['attributes']['ID']] = {'featureObject': currentFeature, 'childrens': list()}

        return (featureGroups, globalRegionFeatureAttributes)


    def createFeatureWithUpdatedCoordinates(self, gffLine, chunkStartPosition):
        # Initializations
        feature = dict()

        # Split the line to separate the GFF columns
        feature['sequenceName'], feature['source'], feature['featureType'], feature['start'], feature['end'], feature['score'], feature['strand'], feature['phase'], attributes = gffLine.split("\t")

        # Extract feature attributes
        feature['attributes'] = self.splitFeatureAttributes(attributes)

        # Update feature coordinates (convert chunk coordinates to sequence coordinates)
        feature['start'] = int(feature['start']) + chunkStartPosition - 1
        feature['end'] = int(feature['end']) + chunkStartPosition - 1

        return feature


    def splitFeatureAttributes(self, attributesString):
        # Initializations
        featureAttributes = OrderedDict()

        # Split the string on ";" to separate the attributes
        attributesList = attributesString.split(';')

        # Store each attribute independently
        for attributeCouple in attributesList:
            # Split the string on "=" to separate the attribute name from its value
            attributeName, attributeValues = attributeCouple.split('=')

            # Split the string on "," to separate the values of the arrtibute and store the attribute in the dict
            listofValues = attributeValues.split(',')

            # Store the value depending on the length of the list generated by the last split
            if len(listofValues) == 1:
                featureAttributes[attributeName] = listofValues[0]
            else:
                featureAttributes[attributeName] = listofValues

        return featureAttributes


    def buildGlobalRegionFeature(self, globalRegionFeatureAttributes, sequenceName):
        # Intializations
        globalRegionFeature = dict()

        # Define each features elements
        globalRegionFeature['sequenceName'] = sequenceName
        globalRegionFeature['source'] = 'TriAnnotPipeline'
        globalRegionFeature['featureType'] = 'region'
        globalRegionFeature['start'] = self.chunksData[0]['chunkStartPosition']
        globalRegionFeature['end'] = self.chunksData[-1]['chunkEndPosition']
        globalRegionFeature['score'] = '.'
        globalRegionFeature['strand'] = '.'
        globalRegionFeature['phase'] = 1

        # Overwrite ID and Name attributes with the sequence name
        globalRegionFeatureAttributes['ID'] = sequenceName
        globalRegionFeatureAttributes['Name'] = sequenceName
        globalRegionFeature['attributes'] = globalRegionFeatureAttributes

        return globalRegionFeature


    def filterFeatureGroups(self, allExtractedFeatureGroups, numberOfGffFile):
        # Initializations
        lastChunk = False
        keptFeaturesList = list()

        for gffFileIndex, gffFileFeatures in enumerate(allExtractedFeatureGroups):
            self.logger.info("    -> Selecting features from file n°%d" % (gffFileIndex + 1))

            # Are we on the last chunk ?
            if (gffFileIndex + 1) == numberOfGffFile:
                lastChunk = True

            for masterFeatureId in gffFileFeatures.keys():
                masterFeatureObject = gffFileFeatures[masterFeatureId]['featureObject']

                # Special case - We are on the last chunk - All features can be kept except the one that start at the first base of the chunk
                if lastChunk:
                    if masterFeatureObject['start'] != self.chunksData[gffFileIndex]['chunkStartPosition']:
                        self.storeFeatureGroup(gffFileFeatures[masterFeatureId], keptFeaturesList)
                        self.deleteTreatedFeatureGroup(gffFileFeatures, masterFeatureId)
                    continue

                # Kept features that start before the start of the next chunk
                if masterFeatureObject['start'] <= self.chunksData[gffFileIndex + 1]['chunkStartPosition']:
                    # Keep features that start before the start of the next chunk
                    if gffFileIndex > 0:
                        # Special case: do not keep features that start exactly at the beginning of a chunk (except for the first chunk)
                        if masterFeatureObject['start'] != self.chunksData[gffFileIndex]['chunkStartPosition']:
                            self.storeFeatureGroup(gffFileFeatures[masterFeatureId], keptFeaturesList)
                    else:
                        self.storeFeatureGroup(gffFileFeatures[masterFeatureId], keptFeaturesList)
                    self.deleteTreatedFeatureGroup(gffFileFeatures, masterFeatureId)
                else:
                    # Keep features that start after the start of the next chunk and end before the end of the current chunk
                    if masterFeatureObject['end'] == self.chunksData[gffFileIndex]['chunkEndPosition']:
                        self.deleteTreatedFeatureGroup(gffFileFeatures, masterFeatureId)
                    else:
                        betterFeatureFound = False
                        # Check if an equivalent or a longer feature exist on the next chunk (Note: the list is already ordered)
                        for nextChunkFeatureId in allExtractedFeatureGroups[gffFileIndex + 1].keys():
                            nextFeatureObject = allExtractedFeatureGroups[gffFileIndex + 1][nextChunkFeatureId]['featureObject']
                            if masterFeatureObject['start'] == nextFeatureObject['start']:
                                if nextFeatureObject['end'] >= masterFeatureObject['end']:
                                    # A better version has been found on the next chunk so we can delete the feature of the current chunk
                                    # Note: the better feature will be automatically kept
                                    betterFeatureFound = True
                                    self.deleteTreatedFeatureGroup(gffFileFeatures, masterFeatureId)
                                    break
                        if not betterFeatureFound:
                            # A better version has NOT been found so we keep the current feature
                            self.storeFeatureGroup(gffFileFeatures[masterFeatureId], keptFeaturesList)
                            self.deleteTreatedFeatureGroup(gffFileFeatures, masterFeatureId)

        return keptFeaturesList


    def storeFeatureGroup(self, featureGroup, keptFeaturesList):
        # Add the master feature to the final tab
        keptFeaturesList.append(featureGroup['featureObject'])

        # Add the childrens features
        keptFeaturesList.extend(featureGroup['childrens'])


    def deleteTreatedFeatureGroup(self, gffFileFeatures, masterFeatureId):
        if masterFeatureId in gffFileFeatures:
            del gffFileFeatures[masterFeatureId]


    def writeGlobalGffFile(self, featuresToWrite, globalGffFileFullPath, taskId):
        self.logger.info('')
        self.logger.info("    -> All conserved features (%d feature(s)) will now be written in the following GFF file: %s" % (len(featuresToWrite), globalGffFileFullPath))

        # Try to create an ouput file handler
        try:
            gffFileHandler = open(globalGffFileFullPath, 'w')
        except IOError:
            self.logger.error("%s can't create the following global GFF file for task %d: %s" % (self.programName, taskId, globalGffFileFullPath))
            raise

        # Write the sequence to the file
        with gffFileHandler:
            for featureToWrite in featuresToWrite:
                gffFileHandler.write(self.convertFeatureToString(featureToWrite) + '\n')


    def convertFeatureToString(self, feature):
        # Initializations
        featureAsString = ''
        columnOrder = ['sequenceName', 'source', 'featureType', 'start', 'end', 'score', 'strand', 'phase', 'attributes']

        # Build the string
        for columnName in columnOrder:
            if columnName == 'attributes':
                for attributeName, attributeValues in feature[columnName].items():
                    if type(attributeValues) == list:
                        featureAsString += attributeName + '=' + ', '.join(attributeValues) + ';'
                    else:
                        featureAsString += attributeName + '=' + str(attributeValues) + ';'
            else:
                featureAsString += str(feature[columnName]) + "\t"

        return featureAsString


    #################################################
    ##  Sequence files management related methods  ##
    #################################################

    def analyseSequenceFile(self):
        # Initializations
        currentOffset = 0
        instanceTableEntryObject = None
        self.InstanceTableEntries = list()
        sequenceNames = list()
        chunkMaxSize = self.maximumSequenceLength
        chunkInterval = chunkMaxSize - self.chunkOverlappingSize

        # Log
        self.logger.info("The fasta input file will now be analyzed")

        # Open the fasta input file
        try:
            sequenceFileHandler = open(self.sequenceFileFullPath, 'rU')
        except IOError:
            self.logger.error("Could not open the following fasta sequence file (specified through the -s/--sequence argument): %s" % self.sequenceFileFullPath)
            exit(1)

        # Read the sequence file line by line and treat each sequence (Note: the with statement allow auto-closing of the file)
        with sequenceFileHandler:
            # Get a line from the file
            currentLine = sequenceFileHandler.readline()

            while currentLine:
                # Treat comment lines
                if currentLine.startswith("#"):
                    currentOffset += len(currentLine)

                # Treat title/description lines
                elif currentLine.startswith(">"):
                    # Treat previous sequence if it exists
                    if instanceTableEntryObject is not None:
                        # Split the sequence into chunks if needed and store either the sequence
                        self.finalizeSequenceTreatment(instanceTableEntryObject, sequenceGoalsObject.chunkStartOffsets, sequenceGoalsObject.chunkEndOffsets)

                    # Increase the offset by the size of the line in bytes
                    currentOffset += len(currentLine)

                    # Manage sequence name
                    cleanSequenceName = self.getCleanSequenceName(currentLine)
                    if cleanSequenceName in sequenceNames:
                        self.logger.error("Each sequence name of the selected (multi-)fasta file must be unique. The following sequence name is used more than once: %s" % cleanSequenceName)
                        exit(1)
                    else:
                        sequenceNames.append(cleanSequenceName)

                    # Create a new TriAnnotInstanceTableEntry object for the new sequence
                    instanceTableEntryObject = TriAnnotInstanceTableEntry(cleanSequenceName, self.sequenceType, currentOffset)

                    # Initialization of a TriAnnotSequenceGoals object
                    sequenceGoalsObject = TriAnnotSequenceGoals(chunkInterval, chunkMaxSize, currentOffset)

                # Treat sequence lines
                else:
                    if instanceTableEntryObject is not None:
                        currentOffset = self.treatSequenceLine(currentLine, currentOffset, instanceTableEntryObject, sequenceGoalsObject)

                # Read a new line
                currentLine = sequenceFileHandler.readline()

            # Treatment of the last sequence of the fasta file
            if len(sequenceNames) >= 1:
                self.finalizeSequenceTreatment(instanceTableEntryObject, sequenceGoalsObject.chunkStartOffsets, sequenceGoalsObject.chunkEndOffsets)

        # Check and display of the number of generated sequences
        if len(sequenceNames) > 0:
            self.logger.info("The offset positions of <%d> sequence(s) has/have been successfully collected in the fasta input file !" % len(sequenceNames))
            self.logger.info("Those sequence(s) has/have been devided into a total of <%d> chunk(s) !" % len(self.InstanceTableEntries))
        else:
            self.logger.error("No sequence has been extracted from the fasta input file! Execution canceled..")
            exit(1)


    def treatSequenceLine(self, currentLine, currentOffset, instanceTableEntryObject, sequenceGoalsObject):
        # Check for non-IUPAC characters on the line
        self.checkSequenceCharacters(currentLine, instanceTableEntryObject.sequenceName)

        # Get line sizes
        nbBytes = len(currentLine)
        nbChar = len(currentLine.strip())

        # Do not leave the current sequence line if all of its bases have not been consumed
        unconsumedBases = nbChar
        while unconsumedBases > 0:
            # Case 0: The sequence is a proteic sequence bigger than maxProteicSequenceLength, we do not split the sequence into chunks but abort the execution
            if self.sequenceType == 'proteic' and (sequenceGoalsObject.alreadyCountedBases + unconsumedBases) > self.maximumSequenceLength:
                self.logger.error("Sequence %s is bigger than the maxProteicSequenceLength (%d)! Execution canceled.." % (instanceTableEntryObject.sequenceName, self.maximumSequenceLength))
                exit(1)

            # Case 1: The goal is on the current line
            if (sequenceGoalsObject.alreadyCountedBases + unconsumedBases) >= sequenceGoalsObject.nextGoal:
                # Determine the number of base to the next goal
                nbCharToGoal = sequenceGoalsObject.nextGoal - sequenceGoalsObject.alreadyCountedBases

                # Update offset
                if unconsumedBases == nbCharToGoal:
                    currentOffset += nbCharToGoal + (nbBytes - nbChar)
                else:
                    currentOffset += nbCharToGoal

                # Store current goal offset and define next goal
                if sequenceGoalsObject.nextGoalIsAStart:
                    sequenceGoalsObject.chunkStartOffsets.append(currentOffset)
                    if sequenceGoalsObject.nextEndGoal == 0:
                        sequenceGoalsObject.nextEndGoal = sequenceGoalsObject.chunkMaxSize
                    else:
                        sequenceGoalsObject.nextEndGoal += sequenceGoalsObject.chunkInterval
                    sequenceGoalsObject.nextGoal = sequenceGoalsObject.nextEndGoal
                    sequenceGoalsObject.nextGoalIsAStart = False
                else:
                    sequenceGoalsObject.chunkEndOffsets.append(currentOffset)
                    sequenceGoalsObject.nextStartGoal += sequenceGoalsObject.chunkInterval
                    sequenceGoalsObject.nextGoal = sequenceGoalsObject.nextStartGoal
                    sequenceGoalsObject.nextGoalIsAStart = True

                # Update "counters"
                sequenceGoalsObject.alreadyCountedBases += nbCharToGoal
                unconsumedBases -= nbCharToGoal

            # Case 2: The goal is NOT on the current line
            else:
                currentOffset += unconsumedBases + (nbBytes - nbChar)
                sequenceGoalsObject.alreadyCountedBases += unconsumedBases
                unconsumedBases = 0

        # Update analysis object
        instanceTableEntryObject.sequenceEndOffset = currentOffset
        instanceTableEntryObject.sequenceSize += nbChar

        return currentOffset


    def getCleanSequenceName(self, descriptionLine):
        # Regex to get the raw sequence name and description
        match = re.match(r"^>(?P<sequenceName>[\S]+)\s*(?P<description>.*)", descriptionLine)
        if not match:
            self.logger.error("The following sequence has an invalid description line: %s" % descriptionLine)
            exit(1)

        sequenceName = match.group('sequenceName')

        # Remove unwanted db prefix
        match = re.match(r"^(gi|lcl|bbs|bbm|gim|gb|emb|pir|sp|ref|dbj|prf|pdb|tp[ged]|tr|gpp|nat|gnl\|[^\|]+)\|(?P<id>[^\|\s]+)", sequenceName)
        if match is not None:
            sequenceName = match.group('id')

        # Remove unauthorized characters
        sequenceName = re.sub(r"[^\w#\.\-,=]", '_', sequenceName)
        sequenceName = re.sub(r"_+$", '', sequenceName)

        if (sequenceName == ''):
            sequenceName = 'unknownId'

        # Cancel TriAnnotPipeline execution if the current sequence name is greater than 50 characters (cause it may cause errors in certain version of RepeatMasker)
        if self.sequenceType == 'nucleic':
            if len(sequenceName) > 50:
                self.logger.error("A sequence identifier longer than 50 characters has been detected: %s" % sequenceName)
                self.logger.debug("Corresponding line is: %s" % descriptionLine)
                self.logger.error("The following fasta input file is not valid: %s" % self.sequenceFileFullPath)
                exit(1)

        return sequenceName


    def checkSequenceCharacters(self, lineToCheck, currentSequenceName):
        # Define the regular expression pattern depending on the sequence type
        if self.sequenceType == 'nucleic':
            validationPattern = re.compile(r"[^ACGTURYSWKMBDHVN]+", re.IGNORECASE)
        else:
            validationPattern = re.compile(r"[^ABCDEFGHIKLMNPQRSTVWXYZ\*]+", re.IGNORECASE)

        # Cancel TriAnnotPipeline execution if a match is found
        if validationPattern.search(lineToCheck.strip()):
            self.logger.error("Sequence <%s> contains unauthorized characters (ie. characters that are not included in the %s IUPAC code) !" % (currentSequenceName, self.sequenceType))
            self.logger.debug("Invalid line: %s" % lineToCheck)
            self.logger.error("The following fasta input file is not valid: %s" % self.sequenceFileFullPath)
            exit(1)


    def finalizeSequenceTreatment(self, instanceTableEntry, chunkStartOffsets, chunkEndOffsets):
        # Store the last end offset
        chunkEndOffsets.append(instanceTableEntry.sequenceEndOffset)

        # Store the builded sequence - OR - split it into chunks and store the chunks
        if self.activateSequenceSplitting == True and instanceTableEntry.sequenceSize > self.maximumSequenceLength:
            # Get the number of chunks to create
            nbChunkToCreate = len(chunkEndOffsets) if (len(chunkEndOffsets) < len(chunkStartOffsets)) else len(chunkStartOffsets)
            self.logger.debug("Number of chunk to create for sequence <%s>: %d" % (instanceTableEntry.sequenceName, nbChunkToCreate))

            # Create and store chunks
            for chunkIndex in range(0, nbChunkToCreate):
                # Generate new basic chunk object (ie which is a copy of the current analysis object)
                chunkObject = TriAnnotInstanceTableEntry(instanceTableEntry.sequenceName, instanceTableEntry.sequenceType, instanceTableEntry.sequenceStartOffset, instanceTableEntry.sequenceEndOffset, instanceTableEntry.sequenceSize)

                # Change attributes of the newly generated chunk
                chunkObject.chunkName = instanceTableEntry.sequenceName + '_chunk_' + str(chunkIndex + 1)
                chunkObject.chunkNumber = chunkIndex + 1
                chunkObject.chunkStartOffset = chunkStartOffsets[chunkIndex]
                chunkObject.chunkEndOffset = chunkEndOffsets[chunkIndex]

                if chunkIndex != nbChunkToCreate - 1:
                    chunkObject.chunkSize = self.maximumSequenceLength
                else:
                    chunkObject.chunkSize = instanceTableEntry.sequenceSize - ((self.maximumSequenceLength - self.chunkOverlappingSize) * (nbChunkToCreate - 1))

                # Store the chunk in the list
                self.InstanceTableEntries.append(chunkObject)
        else:
            # Update chunk related attributes (A non splitted sequence is actually a standalone chunk (chunk 0))
            nbChunkToCreate = 1
            instanceTableEntry.chunkStartOffset = instanceTableEntry.sequenceStartOffset
            instanceTableEntry.chunkEndOffset = instanceTableEntry.sequenceEndOffset
            instanceTableEntry.chunkSize = instanceTableEntry.sequenceSize

            # Store the sequence in the list
            self.InstanceTableEntries.append(instanceTableEntry)

        # Add a new row in the Sequences table
        self.sqliteObject.genericInsertOrReplaceFromDict(self.sqliteObject.sequencesTableName, {'sequenceName': instanceTableEntry.sequenceName, 'numberOfChunk': nbChunkToCreate})


    ############################################
    ##  Instances monitoring related methods  ##
    ############################################

    def checkForAlreadyCompletedInstances(self):
        for instance in self.instances.values():
            # An instance might already be finished if this is not the first time that TriAnnotPipeline.py is executed on the current multi-fasta file
            if instance.isExecutionFinishedBasedOnStatus():
                self.logger.info("The execution of %s was already over during the last execution of %s" % (instance.getDescriptionString(), self.programName))
                self.instances.pop(instance.id)

            # The execution of an instance might have finished between the last and the current TriAnnotPipeline.py execution (with the exact same command line)
            elif instance.isExecutionFinishedBasedOnFiles():
                self.logger.info("The execution of %s has finished since the last execution of %s" % (instance.getDescriptionString(), self.programName))
                instance.postExecutionTreatments()
                self.setInstanceAsFinishedInDatabase(instance)

            # If the previous TriAnnotPipeline.py execution have ended at an inapropriate moment (ie. during the submission process of an instance) then the Instances table might not be up to date
            # So, we have to check the existence of the execution folder and sequence file of each instances registered as PENDING in the SQLite database and display warning when they exists (this special case must be managed manually)
            elif instance.instanceStatus == TriAnnotStatus.PENDING:
                if instance.chunkNumber != 0:
                    probableInstanceDirectoryFullPath = os.path.join(self.mainExecDirFullPath, instance.sequenceName, 'Chunk_' + str(instance.chunkNumber))
                else:
                    probableInstanceDirectoryFullPath = os.path.join(self.mainExecDirFullPath, instance.sequenceName)
                if Utils.isExistingDirectory(probableInstanceDirectoryFullPath) and not Utils.isEmptyDirectory(probableInstanceDirectoryFullPath):
                    self.manageUnmonitorableInstance(instance)


    def checkAndUpdateInstanceStatus(self):
        for instance in self.instances.values():
            self.logger.debug("Status for %s is: %s" % (instance.getDescriptionString(), TriAnnotStatus.getStatusName(instance.instanceStatus)))

            if instance.instanceStatus == TriAnnotStatus.PENDING:
                # Nothing to do for PENDING instances at the moment
                continue

            elif instance.instanceStatus == TriAnnotStatus.SUBMITED and Utils.isExistingDirectory(instance.instanceDirectoryFullPath) and instance.isTriAnnotProgressFileAvailable():
                instance.instanceStatus = TriAnnotStatus.RUNNING
                instance.getInstanceProgression()
                self.sqliteObject.updateInstanceTableDuringMonitoring(instance.id, instance.instanceStatus, 0)

            elif instance.instanceStatus == TriAnnotStatus.RUNNING:
                # Get instance progression from the TriAnnot_progress file if the execution is not already finished
                if not instance.isExecutionFinishedBasedOnFiles():
                    instance.getInstanceProgression()
                    self.sqliteObject.updateInstanceTableDuringMonitoring(instance.id, instance.instanceStatus, instance.instanceProgression)
                else:
                    # The instance status have been updated during the parsing of the TriAnnot_finished file and the post execution treatments..
                    # ..will be done by the "treatFinishedOrCanceledInstances" method so there is nothing more to do here
                    continue

            elif (instance.instanceStatus == TriAnnotStatus.SUBMITED or instance.instanceStatus == TriAnnotStatus.RUNNING) and time.time() - instance.checkedIsAliveTime > int(self.stillAliveJobMonitoringInterval):
                if not instance.isStillAlive():
                    instance.setErrorStatus("%s is not alive anymore" % instance.getDescriptionString().capitalize())
                elif instance._cptFailedCheckStillAlive >= int(instance.runner.maximumFailedMonitoring):
                    instance.setErrorStatus("Failed too many times to check if %s is still alive" % instance.getDescriptionString())
                instance.checkedIsAliveTime = time.time()

            if instance.instanceStatus == TriAnnotStatus.ERROR:
                # Nothing to do for ERROR instances (instances have no dependences contrary to tasks)
                continue


    def displayStatusCounters(self, statusCounters = None):
        # Initializations
        statusStrings = list()

        # Collect status counters in the database if they have not been already passed through parameters
        if statusCounters is None:
            statusCounters = self.sqliteObject.getStatusCounters(returnStatusAsString = True)

        # Prepare the status string to display
        for statusCodeOrName, statusCounter in sorted(statusCounters.items()):
            if type(statusCodeOrName) is int:
                statusCodeOrName = TriAnnotStatus.getStatusName(statusCodeOrName)
            statusStrings.append("%s = %d" % (statusCodeOrName, statusCounter))

        # Display the prepared and formatted string
        self.logger.info("Current repartition of instance status: %s" % ' / '.join(statusStrings))


    #############################################
    ##  Instances preparation related methods  ##
    #############################################

    def createInstanceDirectories(self, instance):
        if instance.instanceDirectoryFullPath is None:
            unitMainExecDirFullPath = os.path.join(self.mainExecDirFullPath, instance.sequenceName)

            # Try to create the main directory of the current TriAnnot unit
            if not Utils.isExistingDirectory(unitMainExecDirFullPath):
                try:
                    os.mkdir(unitMainExecDirFullPath)
                except OSError:
                    self.logger.error("%s can't create the following main instance/unit directory for %s: %s" % (self.programName, instance.getDescriptionString(), unitMainExecDirFullPath))
                    exit(1)

            # When the chunk number is equal to 0 (ie. not splitted sequence) there is no other subdirectories to create
            # We just have to update the instance object in this case
            if instance.chunkNumber == 0:
                instance.instanceDirectoryFullPath = unitMainExecDirFullPath

            # When the chunk number is greater than 0 (ie. splitted sequence) the main instance/unit directory must contains a subdirectory by chunk to analyze
            else:
                chunkDirectoryFullPath = os.path.join(self.mainExecDirFullPath, instance.sequenceName, 'Chunk_' + str(instance.chunkNumber))

                if not Utils.isExistingDirectory(chunkDirectoryFullPath):
                    try:
                        os.mkdir(chunkDirectoryFullPath)
                    except OSError:
                        self.logger.error("%s can't create the following chunk directory for %s: %s" % (self.programName, instance.getDescriptionString(), chunkDirectoryFullPath))
                        exit(1)

                instance.instanceDirectoryFullPath = chunkDirectoryFullPath


    def generateSequenceFileFromOffsets(self, instance):
        # Initializations
        instance.instanceFastaFileFullPath = os.path.join(instance.instanceDirectoryFullPath, instance.chunkName + '.fasta')

        # Try to create an input file handler for the main fasta sequence file
        try:
            mainSequenceFileHandler = open(self.sequenceFileFullPath, 'r')
        except IOError:
            self.logger.error("%s can't open the main fasta sequence file for %s: %s" % (self.programName, instance.getDescriptionString(), self.sequenceFileFullPath))
            raise

        # Get the portion of the file between the start offset and the end offset stored in the instance object
        with mainSequenceFileHandler:
            # Go to the start offset position
            mainSequenceFileHandler.seek(instance.chunkStartOffset)

            # Collect all the characters to the end offset (and removes end of line characters)
            chunkSequenceAsString = "".join(mainSequenceFileHandler.read(instance.chunkEndOffset - instance.chunkStartOffset).splitlines())

        # Try to create an ouput file handler for the chunk fasta sequence file
        try:
            chunkSequenceFileHandler = open(instance.instanceFastaFileFullPath, 'w')
        except IOError:
            self.logger.error("%s can't create the chunk fasta sequence file for %s: %s" % (self.programName, instance.getDescriptionString(), instance.instanceFastaFileFullPath))
            raise

        # Write the sequence to the file
        with chunkSequenceFileHandler:
            chunkSequenceFileHandler.write('>' + instance.chunkName + '\n')

            # Ignore or keep original sequence masking (lower case masking)
            if self.ignoreOriginalSequenceMasking:
                chunkSequenceAsString = chunkSequenceAsString.upper()

            # Split the sequence and print 80 characters par line
            # Note: we can't write the sequence in one line here because it causes crashes with the BioPerl Bio::DB:fasta library (max line length is 65536 char per line and chunks might be longer)
            for substring in Utils.subStringGenerator(chunkSequenceAsString, 80):
                chunkSequenceFileHandler.write(substring + '\n')


    ############################################
    ##  Instances submission related methods  ##
    ############################################

    def getNbInstancesToLaunch(self):
        # Initializations
        nbInstancesToLaunch = 0

        # Get counters from the database
        statusCounters = self.sqliteObject.getStatusCounters()

        # Display resumed status
        self.displayStatusCounters(statusCounters)

        # If there is still one PENDING instance
        if statusCounters[TriAnnotStatus.PENDING] > 0:
            self.logger.debug("There is still <%d> sequence(s) to analyze" % statusCounters[TriAnnotStatus.PENDING])

            # Can we submit new instances ?
            if statusCounters[TriAnnotStatus.RUNNING] < self.maxParallelAnalysis:
                # Determine the number of instance that can be run during this round
                nbInstancesToLaunch = self.maxParallelAnalysis - statusCounters[TriAnnotStatus.RUNNING]
                if statusCounters[TriAnnotStatus.PENDING] < nbInstancesToLaunch:
                    nbInstancesToLaunch = statusCounters[TriAnnotStatus.PENDING]

                self.logger.debug("%s should be able to submit <%d> new instance(s) of TriAnnotUnit.py during this turn if enough computing power is available" % (self.programName, nbInstancesToLaunch))

        return nbInstancesToLaunch


    def runInstances(self, nbInstancesToLaunch):
        # Initializations
        nbSubmittedInstances = 0

        for instance in self.instances.values():
            if nbSubmittedInstances == nbInstancesToLaunch:
                self.logger.debug("<%d> instances have been successfully submitted during this turn" % nbSubmittedInstances)
                break
            else:
                if instance.instanceStatus == TriAnnotStatus.PENDING:
                    # Prepare directories
                    self.createInstanceDirectories(instance)

                    # Generate the fasta sequence file for the chunk (or the full sequence to analyze if there was no split)
                    self.generateSequenceFileFromOffsets(instance)

                    # Can we submit a new instance ? is some computing power available ?
                    if instance.initializeJobRunner('TriAnnotUnit'):
                        # Effective submission of the execution job for the current instance
                        if self.runinstanceJob(instance) == 0:
                            instance.instanceStatus = TriAnnotStatus.SUBMITED
                            instance.instanceJobIdentifier = instance.runner.jobid
                            instance.setStartTime(time.time())

                            # Update of the database at instance submission
                            self.sqliteObject.updateInstanceTableAtSubmission(instance.id, instance.instanceStatus, instance.instanceSubmissionDate, instance.instanceFastaFileFullPath, instance.instanceDirectoryFullPath, instance.instanceJobIdentifier, instance.runner.monitoringCommand, instance.runner.killCommand)

                            # Increase the counter of successfully submitted instances
                            nbSubmittedInstances += 1
                    else:
                        # If a critical problem occurs during the runner initialization we need to cancel the current instance at least or all instances at most
                        if instance.needToAbortPipeline:
                            if not instance.runnerConfigurationIsOk:
                                self.abortAllInstances(instance.abortPipelineReason)
                                break
                            else:
                                self.abortInstance(instance)


    def runinstanceJob(self, instance):
        # Jump in the directory which stores all job files
        os.chdir(os.path.join(self.mainExecDirFullPath, TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['launcher_files']))

        # Define job name and shell launcher full path
        jobName = self.shortIdentifier + "_" + instance.chunkName + "_analysis"
        instance.wrapperFileFullPath = os.path.join(self.mainExecDirFullPath, TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['launcher_files'], "%s.%s.sh" % (jobName, instance.runner.runnerType))

        # Build TAP Program/Parser launcher command line and create shell wrapper
        self.buildTriAnnotUnitCommandLine(instance)
        self.createShellWrapper(instance)

        # Submit job
        instance.instanceSubmissionDate = time.strftime("%Y-%m-%d %H:%M:%S")
        self.logger.info("Submitting a new %s job for %s - Runner: %s {%s}" % (instance.runner.jobType, instance.getDescriptionString(), instance.runner.getRunnerDescription(), instance.instanceSubmissionDate))
        submissionStatus = instance.runner.submitJob(jobName, instance.wrapperFileFullPath)

        # Jump back in the main execution directory
        os.chdir(self.mainExecDirFullPath)

        # Check submission return value
        if submissionStatus != 0:
            instance.failedSubmitCount = instance.failedSubmitCount + 1
            self.logger.debug("Submission failed for %s (%s failure)" % (instance.getDescriptionString(), instance.failedSubmitCount))
            if instance.failedSubmitCount >= int(instance.runner.maximumFailedSubmission):
                instance.setErrorStatus("The maximum number of failed submission has been reached for %s !" % (instance.getDescriptionString()))
            return submissionStatus
        else:
            instance._cptFailedCheckStillAlive = 0
            instance._cptNotAlive = 0
            self.logger.debug("Submission successful for %s (pid/jobid is: %s)" % (instance.getDescriptionString(), instance.runner.jobid))
            return 0


    def buildTriAnnotUnitCommandLine(self, instance):
        # Initializations
        launcherCommand = ''

        # Build TriAnnotUnit command line
        launcherCommand += TriAnnotConfig.TRIANNOT_CONF['PATHS']['soft']['TriAnnotUnit']['bin']

        launcherCommand += " --sequence %s" % instance.instanceFastaFileFullPath
        launcherCommand += " --tasks %s" % self.globalTaskFileFullPath
        launcherCommand += " --config %s" % self.globalConfigurationFileFullPath

        launcherCommand += " --workdir %s" % instance.instanceDirectoryFullPath
        launcherCommand += " --runner %s" % self.taskJobRunnerName
        launcherCommand += " --clean %s" % self.cleanPattern

        launcherCommand += ' --progress --logger file'

        if self.instanceJobRunnerName == 'Local':
            launcherCommand += ' --no-interrupt'

        # Transfer the activation of the debug mode
        if self.debugMode:
            launcherCommand += ' --debug'

        # Does TriAnnotUnit need to kill tasks on abort ?
        if self.killOnAbort:
            launcherCommand += ' --kill'

        # Debug display
        self.logger.debug("Generated TriAnnotUnit command line: %s" % (launcherCommand))

        # Update instance object
        instance.launcherCommandLine = launcherCommand


    def createShellWrapper(self, instance):
        # Create/open file
        try:
            bashFileHandler = open(instance.wrapperFileFullPath, 'w')
        except IOError:
            self.logger.error("%s can't create the Bash launcher file for %s: %s" % (self.programName, instance.getDescriptionString(), instance.wrapperFileFullPath))
            raise

        self.logger.debug("Writing TriAnnotUnit command line in file: %s" % (instance.wrapperFileFullPath))

        # Write content
        bashFileHandler.write("#!/usr/bin/env bash\n\n")
        bashFileHandler.write(instance.launcherCommandLine)

        # Close file handle
        bashFileHandler.close()

        # Update wrapper file rights
        os.system("chmod 750 %s" % instance.wrapperFileFullPath)


    ######################################################
    ##  Completed instances management related methods  ##
    ######################################################

    def treatFinishedOrCanceledInstances(self):
        for instance in self.instances.values():
            if instance.isExecutionFinishedBasedOnStatus():
                self.logger.info("%s is finished - Exit status is: %s" % (instance.getDescriptionString().capitalize(), TriAnnotStatus.getStatusName(instance.instanceStatus)))

                # Post execution treatments
                instance.postExecutionTreatments()

                # Update tables in the SQLite database
                self.setInstanceAsFinishedInDatabase(instance)

                if instance.instanceProgression != 0:
                    self.updateSystemStatistics(instance)

                # Delete the compressed backup archive if the new execution attempt of the instance has been successful
                if Utils.isExistingFile(instance.instanceBackupArchive) and instance.instanceStatus == TriAnnotStatus.COMPLETED:
                    os.remove(instance.instanceBackupArchive)

                # Remove the current instance from the list of instances to submit/monitor
                self.instances.pop(instance.id)


    def setInstanceAsFinishedInDatabase(self, instance):
        # Three possible cases here:
        # Case 1: the instance is finished (either successfully (COMPLETED) or unsuccessfully (ERROR)) and the TriAnnot_finished file is available in both sub cases
        # Case 2: the instance has been canceled (CANCELED status) and the TriAnnot_finished file is available (ie. the abort was fast)
        # Case 3: the instance has been canceled (CANCELED status) and the TriAnnot_finished file is NOT available (ie. the abort take too much time (killOnAbort = False) or the instance has never started (canceled while PENDING))
        # In the same way, the progress file might not be available for unsubmitted instances are instances that have just started

        # Get needed data from the TriAnnot_finished file
        if instance.finishedFileContent is not None:
            instance.instanceStartDate = Utils.findFirstElementOccurence(instance.finishedFileContent, 'start_date', returnTextValue = True)
            instance.instanceEndDate = Utils.findFirstElementOccurence(instance.finishedFileContent, 'end_date', returnTextValue = True)
            instance.instanceExecutionTime = Utils.findFirstElementOccurence(instance.finishedFileContent, 'total_elapsed_time', returnTextValue = True)
        else:
            # The finishedFileContent attribute must not be empty when the status of the instance is not CANCELED
            if instance.instanceStatus != TriAnnotStatus.CANCELED:
                self.logger.error("The finishedFileContent hash table should never be empty when the setInstanceAsFinishedInDatabase method is called for a non canceled instance !")
                exit(1)

        # Get the final percentage of progression (can be different than 100% when status is ERROR or CANCELED)
        if instance.progressFileContent is not None:
            instance.getInstanceProgression()

        # Get the total size of the instance folder (if it exists)
        estimatedDirectorySize = Utils.getDirectoryTreeDiskUsage(instance.instanceDirectoryFullPath)
        if estimatedDirectorySize is not None:
            instance.instanceDirectorySize = estimatedDirectorySize

        # Effective update of the SQLite table
        self.sqliteObject.updateInstanceTableAtCompletion(instance.id, instance.instanceStartDate, instance.instanceEndDate, instance.instanceStatus, instance.instanceProgression, instance.instanceExecutionTime, instance.instanceDirectorySize)


    def updateSystemStatistics(self, instance):
        # Get the current values of the each column of the System_Statistics table
        currentStatistics = self.sqliteObject.getSystemStatistics()

        # If the dictionnary is empty (and if there is no error) then the SystemStatistics table has not been initialized properly and we have to do it
        if len(currentStatistics) == 0:
            self.sqliteObject.initializeSystemStatisticsTableRow()
            currentStatistics['totalCpuTime'] = 0.0
            currentStatistics['totalRealTime'] = 0.0
            currentStatistics['totalDiskUsage'] = 0

        # Get the total real time and the total cpu time from the hash generated from the TriAnnot_finished file of the current instance
        # Note that the TriAnnot_finished file might not exist in some case (see explanation in the setInstanceAsFinishedInDatabase method)
        if instance.finishedFileContent is not None:
            totalCpuTimeCollected = Utils.findFirstElementOccurence(instance.finishedFileContent['unit_result']['total_times']['cpu_time'], 'sum', returnTextValue = True)
            totalRealTimeCollected = Utils.findFirstElementOccurence(instance.finishedFileContent['unit_result']['total_times']['real_time'], 'sum', returnTextValue = True)

            if totalCpuTimeCollected is not None:
                currentStatistics['totalCpuTime'] += float(totalCpuTimeCollected)
            if totalRealTimeCollected is not None:
                currentStatistics['totalRealTime'] += float(totalRealTimeCollected)
            currentStatistics['totalDiskUsage'] += int(instance.instanceDirectorySize)

            # Update the table
            self.sqliteObject.updateSystemStatisticsTableAtCompletion(currentStatistics['totalCpuTime'], currentStatistics['totalRealTime'], currentStatistics['totalDiskUsage'])


    #############################################
    ##  Pipeline cancellation related methods  ##
    #############################################

    #######################
    ## KeyboardInterrupt ##

    def manageKeyboardInterrupt(self):
        self.logger.warning("%s as detected an interruption request (KeyboardInterrupt exception)" % self.programName)

        # Ask the user what he want to do or apply default behavior
        if TriAnnotConfig.getConfigValue('Global|askUserDecisionOnKeyboardInterrupt').lower() == 'yes':
            self.applyUserDecisionOnKeyboardInterrupt()
        else:
            self.applyDefaultBehaviorOnKeyboardInterrupt()


    def applyUserDecisionOnKeyboardInterrupt(self):
        self.logger.info("What do you want to do ?")
        self.logger.info("A) Exit without aborting any instance (execution can be resumed later)")
        self.logger.info("B) Abort all instances softly (ie. running tasks of each running instances are allowed to complete) - Warning: It might take a while -")
        self.logger.info("C) Brutally kill all tasks of all instances")
        userAnswer = self.checked_raw_input("Your decision ? ", inputType = str, inputRange = ('A', 'B', 'C'))

        if userAnswer == 'A':
            self.haltTriAnnotPipelineExecution("You have decided to halt %s execution without aborting the running instances" % self.programName)
        elif userAnswer == 'B':
            self.killOnAbort = False
            self.logger.warning('The abort of the instances might take a while depending on which tasks are currently running !')
            self.abortAllInstances('You have decided to abort all running instances (task killing switch is disabled)')
        else:
            self.killOnAbort = True
            self.abortAllInstances('You have decided to abort all running instances (task killing switch is enabled)')


    def applyDefaultBehaviorOnKeyboardInterrupt(self):
        decision = TriAnnotConfig.getConfigValue('Global|defaultDecisionOnKeyboardInterrupt').lower()

        if defaultDecision == 'exit':
            self.haltTriAnnotPipelineExecution("%s is currently configured to stop itself without aborting the running instances when a KeyboardInterrupt exception is raised" % self.programName)
        elif defaultDecision == 'abort':
            self.abortAllInstances("%s is currently configured to abort all instances without asking for user directives when a KeyboardInterrupt exception is raised" % self.programName)
        else:
            self.logger.warning("The value of your <%s> configuration value is not valid (Possible values are: %s)" % ('defaultDecisionOnKeyboardInterrupt', 'abort, exit'))
            exit(1)


    ############################
    ## Unmonitorable instance ##

    def manageUnmonitorableInstance(self, instance):
        self.logger.error("The execution folder for %s already exists and is not empty while the instance is still marked as PENDING in the SQLite database (The previous %s execution must have been stopped at an ackward moment !)" % (instance.getDescriptionString(), self.programName))
        self.logger.warning("Instance %s can't be monitored by %s anymore.." % (instance.getDescriptionString(), self.programName))

        # Ask the user what he want to do or apply default behavior
        if TriAnnotConfig.getConfigValue('Global|askUserDecisionAboutUnmonitorableInstance').lower() == 'yes':
            self.applyUserDecisionAboutUnmonitorableInstance(instance)
        else:
            self.applyDefaultBehaviorAboutUnmonitorableInstance(instance)


    def applyUserDecisionAboutUnmonitorableInstance(self, instance):
        self.logger.info("What do you want to do about this problem ?" )
        self.logger.info("A) Exit and manage the cancelation of the problematic instance manually")
        self.logger.info("B) Abort the problematic instance softly (ie. currently running tasks will be allowed to complete) - Warning: It might take a while -")
        self.logger.info("C) Brutally kill all tasks of the problematic instance")
        userAnswer = self.checked_raw_input("Your decision ? ", inputType = str, inputRange = ('A', 'B', 'C'))

        if userAnswer == 'A':
            self.logger.info("You have decided to stop the current %s execution and to deal with the un-monitorable instance manually" % self.programName)
            self.logger.info("Please stop %s and delete its execution folder before running %s again." % (instance.getDescriptionString(), self.programName))
            exit(1)
        elif userAnswer == 'B':
            self.killOnAbort = False
            self.logger.warning('The abort of the problematic instance might take a while depending on which tasks are currently running !')
            self.abortInstance(instance, 'You have decided to abort the problematic instance softly (task killing switch is disabled)')
        else:
            self.killOnAbort = True
            self.abortInstance(instance, 'You have decided to abort all running instances (task killing switch is enabled)')


    def applyDefaultBehaviorAboutUnmonitorableInstance(self, instance):
        decision = TriAnnotConfig.getConfigValue('Global|defaultDecisionAboutUnmonitorableInstance').lower()

        if defaultDecision == 'exit':
            self.logger.info("%s is currently configured to stop itself and let the user deal with the un-monitorable instance manually" % self.programName)
            self.logger.info("Please stop %s and delete its execution folder before running %s again." % (instance.getDescriptionString(), self.programName))
            exit(1)
        elif defaultDecision == 'kill':
            self.killOnAbort = True
            self.abortInstance(instance, abortMessage = "%s is currently configured to kill the un-monitorable instance (ie. brutally kill all tasks of the problematic instance)" % self.programName)
        else:
            self.logger.warning("The value of your <%s> configuration value is not valid (Possible values are: %s)" % ('defaultDecisionAboutUnmonitorableInstance', 'exit, kill'))
            exit(1)


    #################################
    ## Other abort related methods ##

    def checked_raw_input(self, question, inputType = None, inputRange = None):
        while True:
            userAnswer = raw_input(question)
            if inputType is not None:
                try:
                    userAnswer = inputType(userAnswer)
                except ValueError:
                    self.logger.info("Input type must be: %s" % inputType.__name__)
                    continue

            if inputRange is not None and userAnswer not in inputRange:
                self.logger.info("Possible values are: %s" % ', '.join(inputRange))
            else:
                return userAnswer


    def checkUserAbort(self):
        if Utils.isExistingFile(os.path.join(self.mainExecDirFullPath, "TriAnnot_abort")):
            self.abortAllInstances("A TriAnnot_abort file has been detected in the main execution folder")


    def abortAllInstances(self, abortMessage):
        # Log
        self.logger.error(abortMessage)
        self.logger.info("All TriAnnotUnit instances will now be aborted/canceled !")

        # Switch the value of the kill switch base on the content of the TriAnnot_abort file if it exist
        self.toggleKillSwitch();

        # Call the abortInstance method for every instance
        for instance in self.instances.values():
            self.abortInstance(instance)

        self.pipelineAbortedAfterManagedError = True


    def toggleKillSwitch(self):
        # Initializations
        abortFileFullPath = os.path.join(self.mainExecDirFullPath, "TriAnnot_abort")

        if Utils.isExistingFile(abortFileFullPath) and os.path.getsize(abortFileFullPath) > 0:
            try:
                abortFileHandler = open(abortFileFullPath, "r")
            except IOError:
                self.logger.error("%s could not open the following abort file: %s" % (self.programName, abortFileFullPath))
                raise

            with abortFileHandler:
                # Change the value of the killOnAbort attribute if the abort file contains the "kill=yes" couple on the first line
                killSwitchLineElements = abortFileHandler.readline().rstrip().split("=")

                if killSwitchLineElements[1].lower() == 'kill' and killSwitchLineElements[1].lower() == 'yes':
                    self.logger.debug('The kill switch has been switched on after parsing of the TriAnnot_abort file')
                    self.killOnAbort = True


    def abortInstance(self, instance, abortMessage = None):
        # Initializations
        killOnAbortAsString = 'on' if self.killOnAbort else 'off'

        # Log
        if abortMessage is not None:
            self.logger.error(abortMessage)

        self.logger.info("Aborting %s (the kill switch is %s)" % (instance.getDescriptionString(), killOnAbortAsString))

        # Effective abort of the instance if it has already start (ie. if the instanceSubmissionDate is set in the database)
        # Warning: instances are always stopped softly (ie. with a TriAnnot_abort file), the killOnAbort value is just transmitted to the instance itself for the abort of its tasks
        instance.abort(self.killOnAbort)

        # Update the status of the instance
        # Note: the finalization steps of this instance (update of the database, etc.) will be executed in the next turn of the main loop
        instance.instanceStatus = TriAnnotStatus.CANCELED


    #############################################################
    ##  Post-pipeline / Analysis finalization related methods  ##
    #############################################################

    def haltTriAnnotPipelineExecution(self, haltMessage):
        # Log
        self.logger.warning(haltMessage)
        self.logger.info('The halted analysis can be resumed with the following command line:')
        self.logger.info('')
        self.logger.info("%s --workdir %s resume" % (self.programName, self.mainExecDirFullPath))


    def cleanMainExecutionFolder(self):
        # Initializations
        filesToDelete = list()
        foldersToDelete = list()

        # Do not clean anything on failure
        if self.pipelineAbortedAfterManagedError and TriAnnotConfig.TRIANNOT_CONF['Global']['cleanAtTheEnd']['doNotCleanFilesOnFailure'].lower() == 'yes':
            return

        # Cleaning of the "Launchers" folder
		### bug fixed June 16th 2016 P. Leroy
        if (TriAnnotConfig.TRIANNOT_CONF['Global']['cleanAtTheEnd']['launcherFiles'].lower() == 'yes' and TriAnnotConfig.TRIANNOT_CONF['Global']['cleanAtTheEnd']['stdoutFiles'].lower() == 'yes' and TriAnnotConfig.TRIANNOT_CONF['Global']['cleanAtTheEnd']['stderrFiles'].lower() == 'yes'):
            if Utils.isExistingDirectory(TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['launcher_files']):
                foldersToDelete.append(os.path.join(self.mainExecDirFullPath, TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['launcher_files']))
        else:
            if TriAnnotConfig.TRIANNOT_CONF['Global']['cleanAtTheEnd']['launcherFiles'].lower() == 'yes':
                pattern = "%s/%s*.py" % ( TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['launcher_files'], self.uniqueIdentifier )
                filesToDelete.extend(glob.glob( pattern ))
            if TriAnnotConfig.TRIANNOT_CONF['Global']['cleanAtTheEnd']['stdoutFiles'].lower() == 'yes':
                pattern = "%s/%s*.o*" % ( TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['launcher_files'], self.uniqueIdentifier )
                filesToDelete.extend(glob.glob( pattern ))
            if TriAnnotConfig.TRIANNOT_CONF['Global']['cleanAtTheEnd']['stderrFiles'].lower() == 'yes':
                pattern = "%s/%s*.e*" % ( TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['launcher_files'], self.uniqueIdentifier )
                filesToDelete.extend(glob.glob( pattern ))

        # Effective cleaning of files
        for fileToDelete in filesToDelete:
            os.remove(fileToDelete)

        for folderToDelete in foldersToDelete:
            shutil.rmtree(folderToDelete)


    def sendNotificationEmail(self):
        #TODO need to implement this method
        if self.emailTo is None:
            return
        try:
            self.logger.warning("Email notification not implemented yet")
            #import smtplib
            #from email.mime.text import MIMEText
            #msg = MIMEText('Your TriAnnot analysis #%s.\n%s' % (analysisId, query))
            #msg['Subject'] = '[TriAnnot] analysis failed/completed'
            #msg['From'] = 'triannot-support@clermont.inra.fr'
            #msg['To'] = self.emailTo.join(',')
            #s = smtplib.SMTP('smtp.clermont.inra.fr')
            #s.sendmail(msg['From'], self.emailTo, msg.as_string())
            #s.quit()

        except:
            self.logger.warning("Failed to send notification email")


    def computeTotalElapsedTime(self):
        self.humanlyReadableEndDate = time.strftime("%a %Y-%m-%d at %Hh%Mm%Ss")

        totalTime = time.time() - self.systemStartTime
        totalHours = int(totalTime / (60.0 * 60.0))
        totalMinutes = int((totalTime - (totalHours * 60.0 * 60.0)) / 60.0)
        totalSeconds = totalTime - (totalHours * 60.0 * 60.0) - (totalMinutes * 60.0)
        self.humanlyReadableTotalTime = "%02iH %02im and %0.2fs" % (totalHours, totalMinutes, totalSeconds)


    def deleteLockFile(self):
        if not self.isAlreadyLocked:
            if Utils.isExistingFile(self.lockFileFullPath):
                locker.lockf(self.lockFileHandler, locker.LOCK_UN)
                self.lockFileHandler.close()
                os.remove(self.lockFileFullPath)


    def createTriAnnotFinishedFile(self):
        # Initializations
        finishedFileHandler = None
        finishedFileFullPath = os.path.join(self.mainExecDirFullPath, 'TriAnnot_finished')

        self.logger.debug("The analysis result will now be written in the following file: %s" % finishedFileFullPath)

        # Try to create a file handler for the TriAnnot_finished file
        try:
            finishedFileHandler = open(finishedFileFullPath, 'w')
        except IOError:
            self.logger.error("%s could not create the following XML file: %s" % (self.programName, finishedFileFullPath))
            raise

        # Get final status counters
        statusCounters = self.sqliteObject.getStatusCounters()

        # Add content to the XML file (Note: the with statement allow auto-closing of the file)
        with finishedFileHandler:
            #  Build the root of the XML file
            xmlRoot = etree.Element('pipeline_result', {'triannot_version': TRIANNOT_VERSION, 'description': self.taskFileDescription})

            # Create standalone sub elements
            startDateElement = etree.SubElement(xmlRoot, 'start_date')
            startDateElement.text = self.humanlyReadableStartDate

            endDateElement = etree.SubElement(xmlRoot, 'end_date')
            endDateElement.text = self.humanlyReadableEndDate

            totalElapsedTimeElement = etree.SubElement(xmlRoot, 'total_elapsed_time')
            totalElapsedTimeElement.text = self.humanlyReadableTotalTime

            commandLineElement = etree.SubElement(xmlRoot, 'command_line')
            commandLineElement.text = self.commandLine

            # System statistics related sub-elements
            finalSystemStatistics = self.sqliteObject.getSystemStatistics()

            if len(finalSystemStatistics) > 0:
                instanceSystemStatisticsElement = etree.SubElement(xmlRoot, 'instances_system_statistics')

                # Add warning comments to the XML file and display them on screen
                if (statusCounters[TriAnnotStatus.CANCELED] > 0 or statusCounters[TriAnnotStatus.ERROR] > 0):
                    self.displayWarningAboutStatisticsImprecision(instanceSystemStatisticsElement, statusCounters[TriAnnotStatus.CANCELED], statusCounters[TriAnnotStatus.ERROR])

                realTimeElement = etree.SubElement(instanceSystemStatisticsElement, 'total_real_time')
                realTimeElement.text = str(finalSystemStatistics['totalRealTime'])

                cpuTimeElement = etree.SubElement(instanceSystemStatisticsElement, 'total_cpu_time')
                cpuTimeElement.text = str(finalSystemStatistics['totalCpuTime'])

                diskUsageElementIec = etree.SubElement(instanceSystemStatisticsElement, 'disk_usage_iec')
                diskUsageElementIec.text = Utils.getHumanlyReadableDiskUsage(finalSystemStatistics['totalDiskUsage'], 'iec')

                diskUsageElementSi = etree.SubElement(instanceSystemStatisticsElement, 'disk_usage_si')
                diskUsageElementSi.text = Utils.getHumanlyReadableDiskUsage(finalSystemStatistics['totalDiskUsage'], 'si')

            # Status and progression percentage of every instances
            statusElement = etree.SubElement(xmlRoot, 'sequences_status')

            for sequenceName, chunkStatus in self.sqliteObject.getSequencesStatus(returnStatusAsString = True).items():
                sequenceElement = etree.SubElement(statusElement, 'sequence', {'name': sequenceName})
                for chunkName, chunkAttributes in chunkStatus.items():
                    chunkElement = etree.SubElement(sequenceElement, 'chunk', {'name': chunkName})
                    for attributeName, attributeValue in chunkAttributes.items():
                        chunkElement.attrib[attributeName] = attributeValue

            # Indent the XML content
            TriAnnotConfig.indent(xmlRoot)

            # Write the generated XML content
            finishedFileHandler.write(etree.tostring(xmlRoot, 'ISO-8859-1'))


    def displayWarningAboutStatisticsImprecision(self, parentElement, nbCanceledInstances, nbInstanceInError):
        # Create the list of warning messages
        warningMessages = list()
        if nbCanceledInstances > 0:
            warningMessages.append("TriAnnotUnit.py instances are softly aborted (ie. we let the currently running tasks of an instance complete before shuting done the instance itself).")
            warningMessages.append("Since this process could be long, %s will not wait for the complete stop of an instance to collect statistics." % self.programName)
            warningMessages.append("As a consequence, the data written below in this XML tag might be underestimated since <%d> instances have been canceled during your analysis." % nbCanceledInstances)
        if nbInstanceInError > 0:
            warningMessages.append("When TriAnnotUnit.py compute the total CPU time and total real time of all the tasks it has executed it does not take into account failed or canceled tasks")
            warningMessages.append("As a consequence, the data written below in this XML tag might be underestimated since <%d> instances were marked as failed during your analysis." % nbInstanceInError)

        # Display + writting
        for warningMessage in warningMessages:
            self.logger.warning(warningMessage)
            parentElement.append(etree.Comment('Warning: ' + warningMessage))


###################
##   Main code   ##
###################

# This code block will only be executed if TriAnnotPipeline.py is called as a script (ie. it will not be executed if the TriAnnotPipeline class is just imported by another module)

if __name__ == "__main__":

    # Initialize default logger
    logger = logging.getLogger("TriAnnot")
    logger.setLevel(logging.INFO)

    # Create a formatter for the console handler
    defaultFormatter = logging.Formatter("%(name)s - %(levelname)s - %(message)s")

    # Create the default console/screen handler
    consoleHandler = logging.StreamHandler(sys.stdout)
    consoleHandler.setFormatter(defaultFormatter)
    logger.addHandler(consoleHandler)

    # Create the main object
    myTriAnnot = TriAnnotPipeline()

    # Execution of the main method
    myTriAnnot.main()

    # Close the logging system
    logging.shutdown()
