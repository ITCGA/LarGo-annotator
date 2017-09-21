#!/usr/bin/env python

import os
import time
import logging
import uuid
import re
from TriAnnot.TriAnnotRunner import *


class SunGridEngine (TriAnnotRunner):

    # Static class variables
    configurationChecked = False

    def __init__(self):
        # Log
        self.logger.debug("Creating a new %s object" % (self.__class__.__name__))

        # Attributes
        self.className = self.__class__.__name__

        self.submitCommandPattern = TriAnnotConfig.TRIANNOT_CONF['Runners'][self.runnerType]['submitCommandPattern'];
        self.monitoringCommandPattern = TriAnnotConfig.TRIANNOT_CONF['Runners'][self.runnerType]['monitoringCommandPattern'];
        self.killCommandPattern = TriAnnotConfig.TRIANNOT_CONF['Runners'][self.runnerType]['killCommandPattern'];

        self.defaultQueueName = TriAnnotConfig.TRIANNOT_CONF['Runners'][self.runnerType]['defaultQueueName'];
        self.parallelEnvironmentName = TriAnnotConfig.TRIANNOT_CONF['Runners'][self.runnerType]['parallelEnvironmentName'];
        self.requestedRessources = TriAnnotConfig.TRIANNOT_CONF['Runners'][self.runnerType]['requestedRessources'];

        self.allowSubmissionFromComputeNodes = TriAnnotConfig.TRIANNOT_CONF['Runners'][self.runnerType]['allowSubmissionFromComputeNodes'];


    def getRunnerDescription(self):
        runnerDescription = self.runnerType

        if self.parallelEnvironmentName != "" and self.jobObject.getNumberOfThreadsBasedOnStatus() > 1:
            runnerDescription += " (Parallel Environment: %s - %d slots)" % (self.parallelEnvironmentName, self.jobObject.getNumberOfThreadsBasedOnStatus())

        return runnerDescription


    def isConfigurationOk(self):
        # When the checks have been done with the first job, there is nothing to do here
        if SunGridEngine.configurationChecked:
            return True

        # Initializations
        self.configurationErrors = []

        # Check if the default queue defined the configuration file is valid
        listOfValidQueues = self.getAvailableQueues()
        if self.defaultQueueName in listOfValidQueues:
            self.logger.debug("Queue <%s> for runner %s is authorized on the current cluster" % (self.defaultQueueName, self.runnerType))
        else:
            self.configurationErrors.append("Queue <%s> for runner %s is not available on the current cluster" % (self.defaultQueueName, self.runnerType))

        # Check all keywords in command patterns
        self.checkCommandPatternForUnsupportedKeywords(self.submitCommandPattern, "submission")
        self.checkCommandPatternForUnsupportedKeywords(self.monitoringCommandPattern, "monitoring")
        self.checkCommandPatternForUnsupportedKeywords(self.killCommandPattern, "kill")

        if len(self.configurationErrors) > 0:
            for error in self.configurationErrors:
                self.logger.error(error)
            self.jobObject.needToAbortPipeline = True
            self.jobObject.abortPipelineReason = "There is at least one configuration error for runner %s. Please update your TriAnnotConfig_Runners.xml file." % self.runnerType
            return False
        else:
            SunGridEngine.configurationChecked = True
            return True


    def isComputingPowerAvailable(self):
        return True


    def isCompatibleWithCurrentTool(self):
        if self.allowSubmissionFromComputeNodes == 'no' and self.jobObject.needToLaunchSubProcesses():
            return False
        else:
            return True


    def submitJob(self, jobName, wrapperFileFullPath):
        # Command line building
        # Replace keywords by values in the basic submit commands
        self.submitCommand = self.replaceKeywordsInCommandPattern(self.submitCommandPattern, "submission")

        # Basic parameters
        self.submitCommand += " -N %s" % (jobName)

        # Queue - Uncomment the following lines if your command pattern does not include the -q option
        #if self.defaultQueueName != "":
            #self.submitCommand += " -q %s" % (self.defaultQueueName)

        # Parallel Environment
        if self.parallelEnvironmentName != "" and self.jobObject.getNumberOfThreadsBasedOnStatus() > 1:
            self.submitCommand += " -pe %s %d" % (self.parallelEnvironmentName, self.jobObject.getNumberOfThreadsBasedOnStatus())

        # Ressources
        if type(self.requestedRessources) is dict:
            self.submitCommand += " -l %s" % (",".join(self.requestedRessources.values()))
        elif self.requestedRessources != "":
            self.submitCommand += " -l %s" % (self.requestedRessources)

        # Script to run
        self.submitCommand += " " + wrapperFileFullPath

        # Output file
        outputFile = "qsub_%s.result" % (str(uuid.uuid4()))
        self.submitCommand += " > " + outputFile

        self.logger.debug("Full submission command: " + self.submitCommand)

        # Effective submission
        returnStatus = os.system(self.submitCommand)

        if returnStatus == 0:
            jobidFileHandler = open(outputFile, "r")
            self.jobid = int(jobidFileHandler.readline().split(" ")[2])
            jobidFileHandler.close()
            os.remove(outputFile)

            # Replace keywords by values in the monitoring and kill commands
            self.monitoringCommand = self.replaceKeywordsInCommandPattern(self.monitoringCommandPattern, "monitoring")
            self.killCommand = self.replaceKeywordsInCommandPattern(self.killCommandPattern, "kill")

            self.logger.debug("Monitoring command after keyword replacement: %s" % self.monitoringCommand)
            self.logger.debug("Kill command after keyword replacement: %s" % self.killCommand)

        return returnStatus


    def isStillAlive(self):
        monitoringResult = []

        try:
            monitoringResult = subprocess.Popen(shlex.split(self.monitoringCommand),  stdout=subprocess.PIPE, stderr=subprocess.STDOUT).communicate()[0].split("\n")
            if len(monitoringResult) >= 2 and str(self.jobid) not in monitoringResult[1]:
                raise Warning("Could not check if job number %d for %s is still alive with the following monitoring command: %s" % (self.jobid, self.jobObject.getDescriptionString(), self.monitoringCommand))
        except:
            self.logger.debug(traceback.format_exc())
            self.logger.warning("Failed to check if %s job for %s (jobid %s) is still alive" % (self.className, self.jobObject.getDescriptionString(), self.jobid))
            self.jobObject._cptFailedCheckStillAlive = self.jobObject._cptFailedCheckStillAlive + 1
            return True

        if len(monitoringResult) <= 0 or "do not exist" in monitoringResult[0]:
            self.logger.warning("%s job for %s (jobid: %s) does not exist anymore" % (self.className, self.jobObject.getDescriptionString(), self.jobid))
            return False
        else:
            self.jobObject._cptFailedCheckStillAlive = 0
            self.logger.debug("%s job for %s (jobid: %s) is still alive" % (self.className, self.jobObject.getDescriptionString(), self.jobid))
            return True


    def triggerEventsAfterJobSubmission(self):
        pass


    def triggerEventsAfterJobCompletion(self):
        self.jobid = None


    def getAvailableQueues(self):
        availableQueues = []

        try:
            availableQueues = subprocess.Popen(['qconf', '-sql'],  stdout=subprocess.PIPE).communicate()[0].split("\n")
        except:
            self.logger.warning("The list of available queues could not be retrieved with qconf command..")

        return availableQueues
