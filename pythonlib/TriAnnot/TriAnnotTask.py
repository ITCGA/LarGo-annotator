#!/usr/bin/env python

import os
import logging
import time
import subprocess, shlex
import traceback
import glob
import re

import xml.etree.cElementTree as etree

from TriAnnot.TriAnnotConfig import *
from TriAnnot.TriAnnotRunner import *
from TriAnnot.TriAnnotTaskFileChecker import *
from TriAnnot.TriAnnotStatus import *


class Dependence (object):
    def __init__(self):
        self.id = None
        self.type = None

    def __init__(self, taskId):
        self.id = taskId
        self.type = None

    def __init__(self, taskId, type):
        self.id = taskId
        self.type = type


class TriAnnotTask (object):

    def __init__(self, taskId):
        self.logger = logging.getLogger("TriAnnot.TriAnnotTask")
        self.logger.addHandler(logging.NullHandler())

        # Initialize some attributes from the corresponding TaskParameters object
        self.id = taskId
        self.step = TriAnnotTaskFileChecker.allTaskParametersObjects[taskId].taskStep
        self.sequence = TriAnnotTaskFileChecker.allTaskParametersObjects[taskId].taskSequence
        self.type = TriAnnotTaskFileChecker.allTaskParametersObjects[taskId].taskType
        self.parameters = TriAnnotTaskFileChecker.allTaskParametersObjects[taskId].parameters
        self.dependences = TriAnnotTaskFileChecker.allTaskParametersObjects[taskId].dependencies

        # Other attibutes
        self.completedDependences = {}
        self.status = TriAnnotStatus.PENDING
        self.needParsing = False
        self.fileToParse = None
        self.mainExecDir = None
        self.execAbstract = {}
        self.parsingAbstract = {}
        self.benchmark = {}
        self.maskingStatistics = None
        self.errorInfo = None

        self.needToAbortPipeline = False
        self.abortPipelineReason = None
        self.needToCancelDependingTasks = False
        self.cancelDependingTasksReason = None

        self.runner = None
        self.jobRunnerName = None
        self.launcherCommand = None
        self.wrapperFileFullPath = None

        self.failedSubmitCount = 0
        self.isSkipped = False
        self.startTime = None
        self.checkedIsAliveTime = None

        self._parsingAbstractFilePath = None
        self._execAbstractFilePath = None
        self._cptFailedCheckStillAlive = 0
        self._cptNotAlive = 0

        # Change class to a specialized subclass if there is one defined for self.type
        for taskClass in TriAnnotTask.getAllSubClasses(TriAnnotTask):
            if taskClass.__name__ == self.type:
                self.__class__ = taskClass
                self.logger = logging.getLogger("TriAnnot.Task.%s" % self.__class__.__name__)
                self.logger.addHandler(logging.NullHandler())
                self.logger.debug("Creating a new %s task object" % self.__class__.__name__)
                self.__init__()


    @staticmethod
    def getAllSubClasses(parentClass):
        classesList = []
        for subClass in parentClass.__subclasses__():
            classesList.append(subClass)
            if subClass.__subclasses__():
                classesList.extend(TriAnnotTask.getAllSubClasses(subClass))
        return classesList


    def needToLaunchSubProcesses(self):
        return False


    def initializeJobRunner(self, currentJobType):
        self.logger.debug("%s Job Runner initialization attempt for %s" % (self.jobRunnerName, self.getDescriptionString()))

        # Create a runner object of the appropriate type
        self.runner = TriAnnotRunner(self.jobRunnerName, currentJobType, self)

        # Determine if the created runner is compatible with the tool to execute
        if self.runner.isCompatibleWithCurrentTool():
            # Check if the runner configuration is ok
            if not self.runner.isConfigurationOk():
                return False

            # Check if there is some computing power is available
            if self.runner.isComputingPowerAvailable():
                return True
            else:
                self.runner = None
                return False
        else:
            # Avoid an infinite loop if the runner is already the fallback runner
            if self.jobRunnerName == TriAnnotConfig.getConfigValue('Global|FallbackJobRunner'):
                self.needToAbortPipeline = True
                self.abortPipelineReason = "Unsupported case: The fallback runner (%s) is not compatible with %s" % (self.jobRunnerName, self.getDescriptionString())
                return False

            # Switch from the Default/Selected runner to the Fallback runner
            self.runner = None
            self.logger.warning("Selected runner (%s) is not compatible with %s with its current configuration" % (self.jobRunnerName, self.getDescriptionString()))
            self.jobRunnerName = TriAnnotConfig.getConfigValue('Global|FallbackJobRunner')
            self.logger.info("Switching to the fallback runner <%s> for %s" % (self.jobRunnerName, self.getDescriptionString()))

            # Recursive call (with the fallback runner)
            if self.initializeJobRunner(currentJobType):
                return True
            else:
                return False


    def preExecutionTreatments(self):
        pass


    def postExecutionTreatments(self):
        # Switch back to the default runner if the execution was made with the fallback runner
        if self.jobRunnerName != TriAnnotConfig.TRIANNOT_CONF['Runtime']['jobRunnerName']:
            self.logger.info("Switching back to the default runner: %s" % (TriAnnotConfig.TRIANNOT_CONF['Runtime']['jobRunnerName']))
            self.jobRunnerName = TriAnnotConfig.TRIANNOT_CONF['Runtime']['jobRunnerName']


    def preParsingTreatments(self):
        # By default, parsers don't need multiple threads
        # Please override this method in subclasses if needed
        if self.parameters.has_key('nbCore') and self.parameters['nbCore'] > 1:
            self.parameters['nbCore'] = 1


    def postParsingTreatments(self):
        pass


    def toString(self):
        result =  "%s %s: step: %s | sequence: %s" % (self.id, self.type, self.step, self.sequence)
        if len(self.dependences) > 0:
            result += " | Dependences (" + ', '.join(map(str, self.dependences)) + ")"
        else:
            result += " | No dependence"
        return result


    def setCompletedDependence(self, completedTaskId):
        completedTaskId = int(completedTaskId)
        if completedTaskId in self.dependences and completedTaskId not in self.completedDependences:
            self.completedDependences[completedTaskId] = self.dependences[completedTaskId]


    def hasUnsatifiedDependences(self):
        return len(self.dependences) > len(self.completedDependences)


    def abort(self, killOnAbort = False):
        # Kill the job or display instructions to do it
        if killOnAbort:
            killOutputMessage = None
            self.logger.info("Task number %s (%s) will now be killed" % (self.id, self.type))
            self.logger.debug("Kill command is: %s" % self.runner.killCommand)
            try:
                killOutputMessage = subprocess.Popen(shlex.split(self.runner.killCommand), stdout=subprocess.PIPE, stderr=subprocess.STDOUT).communicate()[0].rstrip()
            except:
                self.logger.error('Failed to kill task number %s' % (self.id))
                self.logger.debug(traceback.format_exc())

            if (killOutputMessage):
                self.logger.info(killOutputMessage)
        else:
            self.logger.info("To abort task number %s (%s), please run command: %s" % (self.id, self.type, self.runner.killCommand))


    # Return True if Abstract file contains information about successfull exec completion, False otherwise
    def isExecSuccessfullFromAbstractFile(self, onErrorSetErrorStatus = True):
        if self.runner is not None:
            self.runner.triggerEventsAfterJobCompletion()

        if not self.readExecAbstractFile(onErrorSetErrorStatus):
            return False

        if not self.execAbstract.has_key('exit_status'):
            if onErrorSetErrorStatus:
                self.setErrorStatus("Could not retrieve exit_status value from exec abstract file")
            return False
        elif self.execAbstract['exit_status'] == 'ERROR':
            if onErrorSetErrorStatus:
                self.setErrorStatus("Execution exited with ERROR status")
            return False

        if self.execAbstract['exit_status'] == 'SKIP':
            self.isSkipped = True

        if self.execAbstract.has_key('need_parsing') and self.execAbstract['need_parsing'] == 'yes':
            self.needParsing = True
            if not self.execAbstract.has_key('output_file'):
                if onErrorSetErrorStatus:
                    self.setErrorStatus("Could not retrieve output_file value from exec abstract file")
                return False
            self.fileToParse = self.execAbstract['output_file']

        return True


    # Return True if file exists and has been parsed successfully, False otherwise
    def readExecAbstractFile(self, onErrorSetErrorStatus = True):
        self.execAbstract = {}
        xmlFilePath = self.getExecAbstractFilePath()
        if not Utils.isExistingFile(xmlFilePath, checkOnlyOnce = not onErrorSetErrorStatus):
            if onErrorSetErrorStatus:
                self.setErrorStatus("Exec abstract file does not exists: %s" % xmlFilePath)
            return False

        try:
            xmlTree = etree.parse(xmlFilePath)
            for xmlElem in xmlTree.getroot().getchildren():
                if xmlElem.tag == 'benchmark':
                    self.readBenchmarkInfo(xmlElem, 'exec')
                elif xmlElem.text is not None and xmlElem.text.strip() != '':
                    self.execAbstract[xmlElem.tag] = xmlElem.text
            if xmlTree.find('masking_statistics') is not None:
                self.maskingStatistics = {}
                for xmlElem in xmlTree.find('masking_statistics').getchildren():
                    if xmlElem.text is not None and xmlElem.text.strip() != '':
                        self.maskingStatistics[xmlElem.tag] = xmlElem.text
            if xmlTree.find('protein_creation_statistics') is not None:
                self.proteinCreationStatistics = {}
                for xmlElem in xmlTree.find('protein_creation_statistics').getchildren():
                    if xmlElem.text is not None and xmlElem.text.strip() != '':
                        self.proteinCreationStatistics[xmlElem.tag] = xmlElem.text
        except SyntaxError:
            if onErrorSetErrorStatus:
                self.setErrorStatus("Exec abstract file is not a valid XML file")
            return False

        return True


    def readBenchmarkInfo(self, benchmarkXmlElem, benchType):
        if not self.benchmark.has_key(benchType):
            self.benchmark[benchType] = {}
        for xmlElem in benchmarkXmlElem.getchildren():
            self.benchmark[benchType][xmlElem.tag] = {}
            for subXmlElem in xmlElem.getchildren():
                if subXmlElem.text is not None and subXmlElem.text.strip() != '':
                    self.benchmark[benchType][xmlElem.tag][subXmlElem.tag] = subXmlElem.text


    def isParsingSuccessfullFromAbstractFile(self, onErrorSetErrorStatus = True):
        if self.runner is not None:
            self.runner.triggerEventsAfterJobCompletion()

        if not self.readParsingAbstractFile(onErrorSetErrorStatus):
            return False

        if not self.parsingAbstract.has_key('exit_status'):
            if onErrorSetErrorStatus:
                self.setErrorStatus("Could not retrieve exit_status value from parsing abstract file")
            return False
        elif self.parsingAbstract['exit_status'] == 'ERROR':
            if onErrorSetErrorStatus:
                self.setErrorStatus("Parsing exited with ERROR status")
            return False

        if self.parsingAbstract.has_key('GFF_creation') and self.parsingAbstract['GFF_creation'] != 'OK':
            if onErrorSetErrorStatus:
                self.setErrorStatus("Parsing GFF file creation failed")
            return False

        if self.parsingAbstract.has_key('EMBL_creation') and self.parsingAbstract['EMBL_creation'] != 'OK':
            if onErrorSetErrorStatus:
                self.setErrorStatus("Parsing EMBL file creation failed")
            return False

        return True


    def readParsingAbstractFile(self, onErrorSetErrorStatus = True):
        self.parsingAbstract = {}
        xmlFilePath = self.getParsingAbstractFilePath()
        if not Utils.isExistingFile(xmlFilePath, checkOnlyOnce = not onErrorSetErrorStatus):
            if onErrorSetErrorStatus:
                self.setErrorStatus("Parsing abstract file does not exists: %s" % xmlFilePath)
            return False

        try:
            xmlTree = etree.parse(xmlFilePath)
            for xmlElem in xmlTree.find('parsing').getchildren():
                if xmlElem.tag == 'benchmark':
                    self.readBenchmarkInfo(xmlElem, 'parsing')
                elif xmlElem.text is not None and xmlElem.text.strip() != '':
                    self.parsingAbstract[xmlElem.tag] = xmlElem.text
            for xmlElem in xmlTree.find('conversion').getchildren():
                if xmlElem.text is not None and xmlElem.text.strip() != '':
                    self.parsingAbstract[xmlElem.tag] = xmlElem.text
            if xmlTree.find('orf_discovery_statistics') is not None:
                self.orfDiscoveryStatistics = {}
                for xmlElem in xmlTree.find('orf_discovery_statistics').getchildren():
                    if xmlElem.text is not None and xmlElem.text.strip() != '':
                        self.orfDiscoveryStatistics[xmlElem.tag] = xmlElem.text
        except SyntaxError:
            if onErrorSetErrorStatus:
                self.setErrorStatus("Parsing abstract file is not a valid XML file")
            return False

        return True


    def getNumberOfThreadsBasedOnStatus(self):
        # Deal with nbCore parameter
        nbCoreParameter = 0

        if self.parameters.has_key('nbCore'):
            if TriAnnotConfig.TRIANNOT_CONF['Runtime'].has_key('numberOfThread') and TriAnnotConfig.TRIANNOT_CONF['Runtime']['numberOfThread'] is not None:
                nbCoreParameter = int(TriAnnotConfig.TRIANNOT_CONF['Runtime']['numberOfThread'])
            else:
                nbCoreParameter = int(self.parameters['nbCore'])

        # Deal with status
        if self.status == TriAnnotStatus.PENDING or self.status == TriAnnotStatus.SUBMITED_EXEC or self.status == TriAnnotStatus.RUNNING_EXEC:
            return nbCoreParameter

        elif self.status == TriAnnotStatus.FINISHED_EXEC or self.status == TriAnnotStatus.SUBMITED_PARSING or self.status == TriAnnotStatus.RUNNING_PARSING or self.status == TriAnnotStatus.FINISHED_PARSING:
            return 1

        elif self.status == TriAnnotStatus.COMPLETED:
            if self.needParsing:
                return 1
            else:
                return nbCoreParameter
        else:
            return 0


    def setErrorStatus(self, info):
        self.logger.error("%s failed - %s" % (self.getDescriptionString().capitalize(), info))
        self.status = TriAnnotStatus.ERROR
        self.errorInfo = info


    def setStartTime(self, time):
        self.startTime = time
        self.checkedIsAliveTime = time


    def getTaskExecDirName(self):
        return str(self.id).zfill(3) + "_" + self.type + '_execution'


    def getParsingDir(self):
        return str(self.id).zfill(3) + "_" + self.type + '_parsing'


    def getParsingAbstractFilePath(self):
        if self._parsingAbstractFilePath is None:
            self._parsingAbstractFilePath = os.path.join(self.mainExecDir, TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['summary_files'], str(self.id).zfill(3) + "_" + self.type + "_parsing_result.xml")
        return self._parsingAbstractFilePath


    def getExecAbstractFilePath(self):
        if self._execAbstractFilePath is None:
            self._execAbstractFilePath = os.path.join(self.mainExecDir, TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['summary_files'], str(self.id).zfill(3) + "_" + self.type + "_execution_result.xml")
        return self._execAbstractFilePath


    def isParsingAbstractFileAvalaible(self):
        return os.path.isfile(self.getParsingAbstractFilePath()) and (time.time() - os.path.getmtime(self.getParsingAbstractFilePath()) > 10)


    def isExecAbstractFileAvalaible(self):
        return os.path.isfile(self.getExecAbstractFilePath()) and (time.time() - os.path.getmtime(self.getExecAbstractFilePath()) > 10)


    def getDescriptionString(self):
        description = "task %s " % (self.id)
        if self.status in [TriAnnotStatus.SUBMITED_EXEC, TriAnnotStatus.RUNNING_EXEC]:
            description += "exec "
        elif self.status in [TriAnnotStatus.SUBMITED_PARSING, TriAnnotStatus.RUNNING_PARSING]:
            description += "parsing "
        description += "[%s" % (self.type)
        if self.parameters.has_key('database'):
            description += " %s" % (self.parameters['database'])
        description += ' - step %s]' % (self.step)
        return description


    def isStillAlive(self):
        stillAlive = self.runner.isStillAlive()

        if stillAlive:
            self._cptNotAlive = 0
        else:
            self._cptNotAlive += 1
        if self._cptNotAlive >= 2:
            return False
        return True


# Import all subclasses from Task folder
for f in glob.glob(os.path.dirname(__file__)+"/Task/*.py"):
    name = os.path.basename(f)[:-3]
    if name != "__init__":
        __import__("Task." + name, locals(), globals())
