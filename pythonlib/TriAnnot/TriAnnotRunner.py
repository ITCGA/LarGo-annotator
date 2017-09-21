#!/usr/bin/env python

import os
import logging
import subprocess, shlex

from TriAnnot.TriAnnotConfig import *

class TriAnnotRunner (object):

    # Constructor
    def __init__(self, runnertype, jobType, instanceOrTaskObject):
        # Logger
        self.logger = logging.getLogger("TriAnnot.TriAnnotRunner")
        self.logger.addHandler(logging.NullHandler())

        #self.logger.debug("Creating a new %s object (Basic Runner)" % (self.__class__.__name__))

        # Attributes
        self.runnerType = runnertype
        self.jobObject = instanceOrTaskObject
        self.jobid = None
        self.jobType = jobType

        self.submitCommand = None
        self.monitoringCommand = None
        self.killCommand = None

        self.submitCommandPattern = None
        self.monitoringCommandPattern = None;
        self.killCommandPattern = None;

        self.defaultNumberOfThread = TriAnnotConfig.TRIANNOT_CONF['Runners'][self.runnerType]['defaultNumberOfThread'];
        self.maximumNumberOfThreadByTool = TriAnnotConfig.TRIANNOT_CONF['Runners'][self.runnerType]['maximumNumberOfThreadByTool'];

        self.monitoringInterval = TriAnnotConfig.TRIANNOT_CONF['Runners'][self.runnerType]['monitoringInterval'];

        self.maximumFailedSubmission = TriAnnotConfig.TRIANNOT_CONF['Runners'][self.runnerType]['maximumFailedSubmission'];
        self.maximumFailedMonitoring = TriAnnotConfig.TRIANNOT_CONF['Runners'][self.runnerType]['maximumFailedMonitoring'];


        # Change class to a specialized subclass if there is one defined for self.runnerType
        for runnerClass in TriAnnotRunner.__subclasses__():
            if runnerClass.__name__ == self.runnerType:
                self.__class__ = runnerClass
                self.logger = logging.getLogger("TriAnnot.Runner.%s" % self.__class__.__name__)
                self.logger.addHandler(logging.NullHandler())
                self.__init__()


    # Semi-Virtual methods
    def getRunnerDescription(self):
        raise NotImplementedError('No getRunnerDescription method implemented for runner %s' % (self.runnerType))


    def isConfigurationOk(self):
        raise NotImplementedError('No isConfigurationOk method implemented for runner %s' % (self.runnerType))


    def isComputingPowerAvailable(self):
        raise NotImplementedError('No isComputingPowerAvailable method implemented for runner %s' % (self.runnerType))


    def isCompatibleWithCurrentTool(self):
        raise NotImplementedError('No isCompatibleWithCurrentTool method implemented for runner %s' % (self.runnerType))


    def submitJob(self, job):
        raise NotImplementedError('No submitJob method implemented for runner %s' % (self.runnerType))


    def isStillAlive(self):
        raise NotImplementedError('No isStillAlive method implemented for runner %s' % (self.runnerType))


    def triggerEventsAfterJobSubmission(self):
        raise NotImplementedError('No triggerEventsAfterJobSubmission method implemented for runner %s' % (self.runnerType))


    def triggerEventsAfterJobCompletion(self):
        raise NotImplementedError('No triggerEventsAfterJobCompletion method implemented for runner %s' % (self.runnerType))


    # Common methods
    def getRunnerName(self):
        return self.runnerType


    def setMonitoringInterval(self, newInterval):
        self.monitoringInterval = newInterval


    def checkCommandPatternForUnsupportedKeywords(self, commandPattern, patternType):
        # Build regexp pattern
        regexpPattern = re.compile(r'{(\w+)}', re.IGNORECASE)

        # Search every occurence of the built pattern in the input chain
        for match in regexpPattern.findall(commandPattern):
            # Check if an object attribute correspond to the word found by the regexp
            if not hasattr(self, match):
                self.configurationErrors.append("Keyword <%s> is not supported in the %s command pattern for runner %s !" % (match, patternType, self.runnerType))


    def replaceKeywordsInCommandPattern(self, command, patternType):
        # Initializations
        modifiedCommand = command

        # Build regexp pattern
        regexpPattern = re.compile(r'{(\w+)}', re.IGNORECASE)

        # Search every occurence of the built pattern in the input chain
        for match in regexpPattern.findall(command):
            # Check if an object attribute correspond to the word found by the regexp
            if hasattr(self, match):
                if getattr(self, match) is not None and getattr(self, match) != "":
                    # Replace the match word by the attribute value in the patternType command
                    modifiedCommand = re.sub("{%s}" % match, str(getattr(self, match)), modifiedCommand)
                else:
                    self.jobObject.needToAbortPipeline = True
                    self.jobObject.abortPipelineReason = "Keyword <%s> is supported in the %s command pattern for runner %s but the corresponding object attribute has no value.. (Did you use an empty value in your TriAnnotConfig_Runners.xml file ?)" % (match, patternType, self.runnerType)
            else:
                self.jobObject.needToAbortPipeline = True
                self.jobObject.abortPipelineReason = "Keyword <%s> is not supported in the %s command pattern for runner %s ! Please update your TriAnnotConfig_Runners.xml file and retry.." % (match, patternType, self.runnerType)

        return modifiedCommand


# Import all subclasses from Runners folder
for f in glob.glob(os.path.dirname(__file__)+"/Runners/*.py"):
    name = os.path.basename(f)[:-3]
    if name != "__init__":
        __import__("Runners." + name, locals(), globals())
