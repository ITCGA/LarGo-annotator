#!/usr/bin/env python

# Basic python modules
import os
import time
import logging
import traceback
from time import sleep

# XML parsing module
import xml.etree.cElementTree as etree

# TriAnnot internal modules
from TriAnnot.TriAnnotConfig import *
from TriAnnot.TriAnnotRunner import *
from TriAnnot.TriAnnotStatus import *

class TriAnnotInstance (object):

    ###################
    ##  Constructor  ##
    ###################
    def __init__(self, instanceToLaunchAsDict, requestedJobRunnerName):
        self.logger = logging.getLogger("TriAnnot.TriAnnotInstance")
        self.logger.addHandler(logging.NullHandler())

        # Get attributes from the TriAnnotInstanceTableEntry object
        for attributeName, attributeValue in instanceToLaunchAsDict.iteritems():
            setattr(self, attributeName, attributeValue)

        # Runner related attibutes
        self.runner = None
        self.jobRunnerName = requestedJobRunnerName
        self.runnerConfigurationIsOk = None

        # Instance submission related attributes
        self.launcherCommandLine = None
        self.wrapperFileFullPath = None
        self.failedSubmitCount = 0
        self.startTime = None

        # Monitoring related attributes
        self.checkedIsAliveTime = None
        self._cptFailedCheckStillAlive = 0
        self._cptNotAlive = 0

        # Instance output file parsing related attributes
        self.finishedFileFullPath = None
        self.finishedFileContent = None

        self.progressFileFullPath = None
        self.progressFileContent = None

        # Error related attributes
        self.errorsList = list()
        self.needToAbortPipeline = None
        self.abortPipelineReason = None


    #####################################
    ##  Runner initialization methods  ##
    #####################################
    def initializeJobRunner(self, currentJobType):
        self.logger.debug("%s Job Runner initialization attempt for %s" % (self.jobRunnerName, self.getDescriptionString()))

        # Create a runner object of the appropriate type
        self.runner = TriAnnotRunner(self.jobRunnerName, currentJobType, self)

        # Check if the runner configuration is ok
        if not self.runner.isConfigurationOk():
            self.runnerConfigurationIsOk = False
            return False

        # Check if there is some computing power is available
        if self.runner.isComputingPowerAvailable():
            return True
        else:
            self.runner = None
            return False


    ################################
    ##  Pre execution treatments  ##
    ################################
    def preExecutionTreatments(self):
        pass


    ###########################################
    ##  Instance monitoring related methods  ##
    ###########################################
    def getInstanceProgression(self):
        if self.isTriAnnotProgressFileAvailable():
            if self.parseXmlProgressFile():
                self.instanceProgression = int(Utils.findFirstElementOccurence(self.progressFileContent, 'percentage_of_completion', returnTextValue = True))
        else:
            return 0

    def isStillAlive(self):
        stillAlive = self.runner.isStillAlive()

        if stillAlive:
            self._cptNotAlive = 0
        else:
            self._cptNotAlive += 1
        if self._cptNotAlive >= 2:
            return False
        return True


    def isExecutionFinishedBasedOnStatus(self):
        if self.instanceStatus == TriAnnotStatus.COMPLETED or self.instanceStatus == TriAnnotStatus.ERROR or self.instanceStatus == TriAnnotStatus.CANCELED:
            return True
        else:
            return False


    def isExecutionFinishedBasedOnFiles(self):
        # Check if the TriAnnot_finished file exists, is readable and has been generated more than 10s before the check
        if not self.isTriAnnotFinishedFileAvailable():
            return False

        # Parse the XML TriAnnot_finished file
        if not self.parseXmlFinishedFile():
            return False

        # AT this point we have an existing and valid TriAnnot_finished file
        self.instanceStatus = TriAnnotStatus.getStatusCode(Utils.findFirstElementOccurence(self.finishedFileContent, 'status', returnTextValue = True))

        if self.instanceStatus == TriAnnotStatus.ERROR:
            self.setErrorStatus("Instance/Unit execution has exited with ERROR status")
            return True
        elif self.instanceStatus == TriAnnotStatus.COMPLETED or self.instanceStatus == TriAnnotStatus.CANCELED:
            return True
        else:
            return False


    #################################################
    ##  TriAnnot_finished file management methods  ##
    #################################################
    def isTriAnnotFinishedFileAvailable(self):
        # Set the full path to the TriAnnot_finished file if needed
        if self.finishedFileFullPath is None:
            if self.instanceDirectoryFullPath is not None:
                self.finishedFileFullPath = os.path.join(self.instanceDirectoryFullPath, 'TriAnnot_finished')
            else:
                return False

        if not Utils.isExistingFile(self.finishedFileFullPath, checkOnlyOnce = False):
            return False

        if time.time() - os.path.getmtime(self.finishedFileFullPath) < 10:
            return False

        return True


    def parseXmlFinishedFile(self):
        # Initialization
        rootTag = 'unit_result'
        fileToParseBasename = os.path.basename(self.finishedFileFullPath)
        mandatoryTags = ['status', 'total_elapsed_time', 'start_date', 'end_date']

        # Try to parse the XML file and convert it into a dictionary
        try:
            self.finishedFileContent = Utils.getDictFromXmlFile(self.finishedFileFullPath)

        except Exception as ex:
            self.setErrorStatus("An unexpected error occured during the parsing of the %s XML file (%s): %s" % (fileToParseBasename, self.finishedFileFullPath, ex))
            return False

        # Check for mandatory tags
        if not self.finishedFileContent.has_key(rootTag):
            raise RuntimeError("The %s tag is not the root of the %s XML file and this should never happen !" % (rootTag, fileToParseBasename))

        for mandatoryTag in mandatoryTags:
            if not self.finishedFileContent[rootTag].has_key(mandatoryTag):
                raise RuntimeError("The %s tag does not exist at the first level of the %s XML file and this should never happen !" % (mandatoryTag, fileToParseBasename))

        return True


    #################################################
    ##  TriAnnot_progress file management methods  ##
    #################################################
    def isTriAnnotProgressFileAvailable(self):
        # Set the full path to the TriAnnot_progress file if needed
        if self.progressFileFullPath is None:
            if self.instanceDirectoryFullPath is not None:
                self.progressFileFullPath = os.path.join(self.instanceDirectoryFullPath, 'TriAnnot_progress')
            else:
                return False

        if not Utils.isExistingFile(self.progressFileFullPath, checkOnlyOnce = False):
            return False

        if time.time() - os.path.getmtime(self.progressFileFullPath) < 10:
            return False

        # Try to parse the XML file and convert it into a dictionary
	fileToParseBasename = os.path.basename(self.progressFileFullPath)#shi 20170913
        try:
            self.progressFileContent = Utils.getDictFromXmlFile(self.progressFileFullPath)

        except Exception as ex:
            self.setErrorStatus("An unexpected error occured during the parsing of the %s XML file (%s): %s" % (fileToParseBasename, self.progressFileFullPath, ex))
            #os.remove(self.progressFileFullPath)
            return False

        return True


    def parseXmlProgressFile(self):
        # Initialization
        rootTag = 'unit_progression'
        fileToParseBasename = os.path.basename(self.progressFileFullPath)
        mandatoryTags = ['percentage_of_completion']

        # Try to parse the XML file and convert it into a dictionary
        try:
            self.progressFileContent = Utils.getDictFromXmlFile(self.progressFileFullPath)

        except Exception as ex:
            self.setErrorStatus("An unexpected error occured during the parsing of the %s XML file (%s): %s" % (fileToParseBasename, self.progressFileFullPath, ex))
            return False

        # Check for mandatory tags
        if not self.progressFileContent.has_key(rootTag):
            raise RuntimeError("The %s tag is not the root of the %s XML file and this should never happen !" % (rootTag, fileToParseBasename))

        for mandatoryTag in mandatoryTags:
            if not self.progressFileContent[rootTag].has_key(mandatoryTag):
                raise RuntimeError("The %s tag does not exist at the first level of the %s XML file and this should never happen !" % (mandatoryTag, fileToParseBasename))

        return True


    #################################
    ##  Post execution treatments  ##
    #################################
    def postExecutionTreatments(self):
        # Switch back to the default runner if the execution was made with the fallback runner
        if self.jobRunnerName != TriAnnotConfig.TRIANNOT_CONF['Runtime']['instanceJobRunnerName']:
            self.logger.info("Switching back to the default runner: %s" % (TriAnnotConfig.TRIANNOT_CONF['Runtime']['instanceJobRunnerName']))
            self.jobRunnerName = TriAnnotConfig.TRIANNOT_CONF['Runtime']['instanceJobRunnerName']

        # Execute special actions for specific runner
        if self.runner is not None:
            self.runner.triggerEventsAfterJobCompletion()


    #########################################
    ##  Instance abortion related methods  ##
    #########################################
    def abort(self, killOnAbort = False):
        # To stop a TriAnnotUnit instance we need to create a TriAnnot_abort file in its execution folder
        # Note that the directory might not exists if the current instance has not been submitted yet

        if Utils.isExistingDirectory(self.instanceDirectoryFullPath):
            # Initializations
            abortFileHandler = None
            abortFileFullPath = os.path.join(self.instanceDirectoryFullPath, 'TriAnnot_abort')

            # Abort file creation attempt
            try:
                abortFileHandler = open(abortFileFullPath, 'w')
            except IOError:
                self.logger.error("Cannot create/open the following abort file: %s" % abortFileFullPath)
                raise

            # Add content to the XML file (Note: the with statement allow auto-closing of the file)
            with abortFileHandler:
                if killOnAbort:
                    abortFileHandler.write("kill=yes")


    ##############################
    ##  Unsorted basic methods  ##
    ##############################
    def needToLaunchSubProcesses(self):
        # TriAnnotPipeline.py submit TriAnnotUnit.py instance that execute full workflows so the answer is always yes here
        return True

    def getNumberOfThreadsBasedOnStatus(self):
        return 1


    def setErrorStatus(self, errorMessage):
        self.logger.error("Execution failed for %s - %s" % (self.getDescriptionString(), errorMessage))
        self.instanceStatus = TriAnnotStatus.ERROR
        self.errorsList.append(errorMessage)


    def setStartTime(self, time):
        self.checkedIsAliveTime = time


    def getDescriptionString(self):
        return "instance %s [Chunk name: %s - Chunk size: %s - Sequence type: %s]" % (self.id, self.chunkName, self.chunkSize, self.sequenceType)
