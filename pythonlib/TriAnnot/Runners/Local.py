#!/usr/bin/env python

import os
import logging
from TriAnnot.TriAnnotRunner import *

class Local (TriAnnotRunner):

    # Static class variables
    numberOfActiveThreads = 0;
    configurationChecked = False

    def __init__(self):
        # Log
        self.logger.debug("Creating a new %s object (Specialized runner)" % (self.__class__.__name__))

        # Attributes
        self.className = self.__class__.__name__

        self.totalNumberOfThread = TriAnnotConfig.TRIANNOT_CONF['Runners'][self.runnerType]['totalNumberOfThread'];

        self.monitoringCommandPattern = TriAnnotConfig.TRIANNOT_CONF['Runners'][self.runnerType]['monitoringCommandPattern'];
        self.killCommandPattern = TriAnnotConfig.TRIANNOT_CONF['Runners'][self.runnerType]['killCommandPattern'];


    def getRunnerDescription(self):
        runnerDescription = self.runnerType

        if self.jobObject.getNumberOfThreadsBasedOnStatus() > 1:
            runnerDescription += " (MultiThread: %s)" % (self.jobObject.getNumberOfThreadsBasedOnStatus())

        return runnerDescription


    def isConfigurationOk(self):
        if Local.configurationChecked:
            return True

        # Initializations
        self.configurationErrors = []

        # Check all keywords in command patterns
        self.checkCommandPatternForUnsupportedKeywords(self.monitoringCommandPattern, "monitoring")
        self.checkCommandPatternForUnsupportedKeywords(self.killCommandPattern, "kill")

        if len(self.configurationErrors) > 0:
            for error in self.configurationErrors:
                self.logger.error(error)
            self.jobObject.needToAbortPipeline = True
            self.jobObject.abortPipelineReason = "There is at least one configuration error for runner %s. Please update your TriAnnotConfig_Runners.xml file." % self.runnerType
            return False
        else:
            Local.configurationChecked = True
            return True


    def isComputingPowerAvailable(self):
        if int(self.numberOfActiveThreads) < int(self.totalNumberOfThread):
            return True
        else:
            self.logger.debug("Maximum number of thread already reached. New job submission will be postponed !")
            return False


    def isCompatibleWithCurrentTool(self):
        return True


    def submitJob(self, jobName, wrapperFileFullPath):
        jobstdout = open(jobName + '.o0', "w")
        jobstderr = open(jobName + '.e0', "w")

        try:
            process = subprocess.Popen([wrapperFileFullPath], stdout=jobstdout, stderr=jobstderr, close_fds=True)
        except Exception, ex:
            self.logger.debug(traceback.format_exc())
            raise(ex)
            return 1

        self.jobid = process.pid

        # Replace keywords by values in the monitoring and kill commands
        self.monitoringCommand = self.replaceKeywordsInCommandPattern(self.monitoringCommandPattern, "monitoring")
        self.killCommand = self.replaceKeywordsInCommandPattern(self.killCommandPattern, "kill")

        self.logger.debug("Monitoring command after keyword replacement: %s" % self.monitoringCommand)
        self.logger.debug("Kill command after keyword replacement: %s" % self.killCommand)

        self.triggerEventsAfterJobSubmission()

        return 0


    def isStillAlive(self):
        monitoringResult = []

        try:
            monitoringResult = subprocess.Popen(shlex.split(self.monitoringCommand),  stdout=subprocess.PIPE, stderr=subprocess.STDOUT).communicate()[0].split("\n")
        except:
            self.logger.debug(traceback.format_exc())
            self.logger.warning("Failed to check if %s job for %s (pid: %s) is still alive" % (self.className, self.jobObject.getDescriptionString(), self.jobid))
            self.jobObject._cptFailedCheckStillAlive = self.jobObject.task_cptFailedCheckStillAlive + 1
            return True

        if len(monitoringResult) == 0 or str(self.jobid) not in monitoringResult[1]:
            self.logger.warning("%s job for %s (pid: %s) does not exist anymore" % (self.className, self.jobObject.getDescriptionString(), self.jobid))
            return False
        else:
            self.jobObject._cptFailedCheckStillAlive = 0
            self.logger.debug("%s job for %s (pid: %s) is still alive" % (self.className, self.jobObject.getDescriptionString(), self.jobid))
            return True


    def triggerEventsAfterJobSubmission(self):
        # Increment the number of active thread
        Local.numberOfActiveThreads += self.jobObject.getNumberOfThreadsBasedOnStatus()


    def triggerEventsAfterJobCompletion(self):
        Local.decrementActiveThreadCounter(self.jobObject.getNumberOfThreadsBasedOnStatus())
        self.jobid = None


    @staticmethod
    def decrementActiveThreadCounter(decValue):
        if Local.numberOfActiveThreads > 0:
            Local.numberOfActiveThreads -= decValue
