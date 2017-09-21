#!/usr/bin/env python

###############################
##  External modules import  ##
###############################
import os
import sys
import warnings

import argparse
import time
import uuid

import logging
import exceptions
import traceback

import glob
import shutil
import re
import getpass
import signal


###############################
##  Internal modules import  ##
###############################
from TriAnnot.TriAnnotVersion import TRIANNOT_VERSION
from TriAnnot.TriAnnotConfig import *
from TriAnnot.TriAnnotConfigurationChecker import *
from TriAnnot.TriAnnotTaskFileChecker import *
from TriAnnot.TriAnnotTask import *
from TriAnnot.TriAnnotStatus import *
from TriAnnot.ColoredFormatter import *
import TriAnnot.Utils

from TriAnnot.TriAnnotSqlite import *

############################
##  Debug modules import  ##
############################
# Data Dumper equivalent
#import pprint
#pp = pprint.PrettyPrinter(indent=4)

## Memory usage analysis
#from memory_profiler import profile


###############################
##  TriAnnot Pipeline class  ##
###############################

class TriAnnotUnit (object):

    ###################
    ##  Constructor  ##
    ###################

    def __init__(self):
        # Get the logger and give it a Null Handler
        self.logger = logging.getLogger("TriAnnot")
        self.logger.addHandler(logging.NullHandler())

        # Program and command line
        self.programName = os.path.basename(sys.argv[0])
        self.commandLine = ' '.join(sys.argv)

        # Identifiers
        self.shortIdentifier = None
        self.uniqueIdentifier = None

        # Dates and timers
        self.humanlyReadableStartDate = None
        self.humanlyReadableEndDate = None

        # Argparse related attributes
        self.argumentParser = None
        self.helpArgumentIsUsed = None
        self.basicOptionGroup = None
        self.mandatoryOptionGroup = None
        self.recommendedOptionGroup = None
        self.loggingAndDebuggingOptionGroup = None
        self.hiddenOptionGroup = None
        self.miscOptionGroup = None

        # Command line arguments related attributes
        self.sequenceFileFullPath = None
        self.globalTaskFileFullPath = None
        self.globalConfigurationFileFullPath = None

        self.mainExecDirFullPath = os.getcwd()
        self.availableRunners = []
        self.defaultJobRunnerName = None
        self.jobRunnerName = None
        self.debugMode = False
        self.colorizeScreenLogger = False
        self.loggerType = None
        self.reportProgress = False

        self.killOnAbort = False
        #self.emailTo = None

        # Job monitoring related attributes
        self.monitoringInterval = None
        self.stillAliveJobMonitoringInterval = None
        self._previousProgress = ''

        # Task related attributes
        self.tasks = {}
        self.completedTasks = {}
        self.totalTasksCount = 0

        # Other TriAnnot objects related attributes
        self.taskFileDescription = ''

        # Other attributes
        self.pipelineAborted = False
        self.progressFileFullPath = None
        self.analysisStatus = None
        self.totalElapsedTime = None
        self.analysisTimes = None


    ###################
    ##  Main Method  ##
    ###################

    def main(self):
        # Store the start time of the analysis (will be used to compute execution time)
        startTimeStamp = time.time()

        # The initialize method is in charge of all the preparation of the analysis.
        # Here is a non exhaustive list of what this method (or rather the sub methods it calls) do:
        # - Command line arguments management
        # - Configuration files loading
        # - Check sequence file existence in the appropriate folder
        # - Step/task file loading
        # - Creation of the list of tasks to execute (ie. list of TriAnnotTask objects)
        # - Subdirectories creation
        self.initialize()

        # Start Log
        self.humanlyReadableStartDate = time.strftime("%Y-%m-%d %H:%M:%S")
        self.displayStartLogMessages()

        # Main execution loop - Runs and monitor all tasks of the list of tasks
        try:
            self.executeTasks()
        except Exception as ex:
            if not self.pipelineAborted:
                self.logger.debug("Error traceback message:\n%s" % traceback.format_exc())
                self.abortPipeline("An unexpected error occured ! (Raised error: %s)" % ex.message)
        finally:
            # The finalize method is in charge of all the post-pipeline execution tasks.
            # Here is a non exhaustive list of what this method (or rather the sub methods it calls) do:
            # Collect statistics about the execution of the various tasks
            # Display those statistics
            # Move some blast results to a specific folder (ie Blast that are followed by Exonerate)
            # Clean folders
            self.finalize()

            # End log (execution time)
            self.humanlyReadableEndDate = time.strftime("%Y-%m-%d %H:%M:%S")
            self.displayEndLogMessages(startTimeStamp)

            # Create the TriAnnot_finished file that can be used as an indicator of the end of the execution
            # This XML file will contain analysis statistics, analysis final status
            self.createTriAnnotFinishedFile()


    def displayStartLogMessages(self):
        self.logger.info("Starting TriAnnot Unit (Start time: %s)" % self.humanlyReadableStartDate)
        self.logger.info("Unique identifier for this analysis is: %s" % self.uniqueIdentifier)
        self.logger.info("Analysis launched with the following tasks XML file: %s" % self.globalTaskFileFullPath)


    def displayEndLogMessages(self, startTimeStamp):
        # Total time elapsed
        self.logger.info("Finished TriAnnot Unit (End time: %s)" % self.humanlyReadableEndDate)

        totalTime = time.time() - startTimeStamp
        totalHours = int(totalTime / (60.0 * 60.0))
        totalMinutes = int((totalTime - (totalHours * 60.0 * 60.0)) / 60.0)
        totalSeconds = totalTime - (totalHours * 60.0 * 60.0) - (totalMinutes * 60.0)
        self.totalElapsedTime = "%02iH %02im %0.2fs" % (totalHours, totalMinutes, totalSeconds)
        self.logger.info("TriAnnot analysis total time elapsed: %s" % self.totalElapsedTime)

        # Reminder
        self.logger.info('')
        self.logger.info('Reminder - The command line used for this analysis was:')
        self.logger.info(self.commandLine)


    ###############################################
    ##  Pipeline initialization related methods  ##
    ###############################################

    def initialize(self):
        try:
            # Assign a UUID to the new TriAnnot analysis
            self._generateTriAnnotUniqueId()

            # Manage command line arguments, check and load the configuration files and the step/task file
            self.loadAndCheckEverything()

            # Catch the SIGINT signal if needed
            self.manageSigintSignal()

            # Prepare the list of tasks to execute (TriAnnotTask objects)
            self.generateAllTriAnnotTaskObjects()

            # Create standard sub-directories into the main execution directory
            self.createCommonFolders()

            # Create a symlink pointing to the main Fasta sequence file in the default "Sequences" folder
            self.createSequenceSymlink()

            # Remove old TriAnnot_* files (where * is failed, abort and finished)
            self.cleanUpBeforeStart()

            # Delete the greedy objects, class variables, etc.
            self.deleteMemoryEaters()

        except Exception, ex:
            if not type(ex) is SystemExit:
                self.logger.debug(traceback.format_exc())
                self.logger.error(ex)
                exit(1)


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


    def loadAndCheckEverything(self):
        # Parse command line arguments before configuration file loading
        # Note: The execution will be stopped if any of the mandatory arguments is not defined and a full Usage will be displayed
        self.getCommandLineArguments(isCalledAfterConfigurationLoading = False)

        # Load the content of the global configuration file if needed
        if self.globalConfigurationFileFullPath is not None:
            self.loadGlobalConfigurationFile()

        # Parse command line arguments after configuration file loading
        # A full help message with default and possible values will be displayed if a valid global/full configuration file has been provided
        # If the -c/--config argument has not been used an incomplete help message without default and possible values will be displayed
        self.getCommandLineArguments(isCalledAfterConfigurationLoading = True)

        # Load the content of the global step/task file into memory
        self.loadGlobalTaskFile()


    def createCommonFolders(self):
        foldersToCreate = TriAnnotConfig.getConfigValue('DIRNAME').values();
        if not Utils.isExistingDirectory(self.mainExecDirFullPath):
            try:
                os.mkdir(self.mainExecDirFullPath)
            except OSError:
                self.logger.error("Main working directory (-d, --workdir) for this analysis does not exists and could not be created: %s" % self.mainExecDirFullPath)
                exit(1)

        try:
            os.chdir(self.mainExecDirFullPath)
        except OSError:
            self.logger.error("Could not access main working directory (-d, --workdir) for this analysis: %s" % self.mainExecDirFullPath)
            exit(1)

        for folder in foldersToCreate:
            if not Utils.isExistingDirectory( os.path.join(self.mainExecDirFullPath, folder) ):
                os.mkdir( os.path.join(self.mainExecDirFullPath, folder) )


    def createSequenceSymlink(self):
        # Initializations
        symlinkDestination = os.path.join(self.mainExecDirFullPath, TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['sequence_files'], 'initial')

        # Symlink creation
        os.symlink(self.sequenceFileFullPath, symlinkDestination)


    def cleanUpBeforeStart(self):
        try:
            if Utils.isExistingFile(os.path.join(self.mainExecDirFullPath, 'TriAnnot_finished')):
                os.remove(os.path.join(self.mainExecDirFullPath, 'TriAnnot_finished'))
        except:
            pass


    def deleteMemoryEaters(self):
        del TriAnnotTaskFileChecker.allTaskParametersObjects


    #########################################################
    ##  Command line arguments management related methods  ##
    #########################################################

    def getCommandLineArguments(self, isCalledAfterConfigurationLoading = False):
        # Initialize the command line option parser
        self.argumentParser = argparse.ArgumentParser(description = self.generateArgparseDescription(), formatter_class=argparse.RawTextHelpFormatter, add_help = False)

        # Create option groups
        self.initializeArgparseGroupsNew()

        # Deal with the help option
        if self.helpArgumentIsUsed is None:
            self.helpArgumentIsUsed = self.isHelpArgumentUsed()

        # Initialize options
        self.initializeAllArgparseArguments(isCalledAfterConfigurationLoading)

        # Scan the command line for all defined command-line arguments / options
        commandLineArguments = self.argumentParser.parse_args()

        # Use command line arguments to update the main object attributes
        self.updateMainObjectWithArguments(commandLineArguments, isCalledAfterConfigurationLoading)

        # Adapt the loggers to the presence/absence of the --debug, --nologfile and --help arguments (We do it only ont time (ie. bebore configuration file(s) loading))
        if not isCalledAfterConfigurationLoading:
            self.updateLoggers()


    def generateArgparseDescription(self):
        argparseDescription = "*****************************************************\n"
        argparseDescription += "*** TriAnnotUnit.py (Version: %s) - Help Section ***\n" % (TRIANNOT_VERSION)
        argparseDescription += "*****************************************************\n"

        if self.globalConfigurationFileFullPath is None:
            argparseDescription += "\nWarning: Default and possible values can't be displayed if a global/full configuration file is not provided through the -c/--config option !"

        return argparseDescription


    def isHelpArgumentUsed(self):
        # Create a mini parser with only one argument
        helpOnlyArgumentParser = argparse.ArgumentParser(add_help = False)
        helpOnlyArgumentParser.add_argument('-h', '--help', action='store_true', help='show this help message and exit')

        alreadyKnownArguments, otherArguments = helpOnlyArgumentParser.parse_known_args()

        # Return True or False depending on the utilization or not of the help option on the command line
        return alreadyKnownArguments.help


    def initializeArgparseGroupsNew(self):
        self.basicOptionGroup = self.argumentParser.add_argument_group('Basic arguments')
        self.mandatoryOptionGroup = self.argumentParser.add_argument_group('Mandatory arguments')
        self.recommendedOptionGroup = self.argumentParser.add_argument_group('Recommended arguments')
        self.loggingAndDebuggingOptionGroup = self.argumentParser.add_argument_group('Logging & Debugging arguments')
        self.hiddenOptionGroup = self.argumentParser.add_argument_group('Hidden arguments')
        self.miscOptionGroup = self.argumentParser.add_argument_group('Unclassified arguments')


    def initializeAllArgparseArguments(self, setDefaultAndPossibleValues = False):
        # Initializations
        helpComplements = dict.fromkeys(['jobRunnerName', 'monitoringInterval', 'numberOfThread'], '')
        activateRequirement = False if self.helpArgumentIsUsed else True

        # Build help complement and "choices" list + manage help option
        # Warning: Default and possible values can't be collected if the -c/--config command line argument has not been used
        if setDefaultAndPossibleValues:
            if self.globalConfigurationFileFullPath is not None:
                # jobRunnerName argument
                for runner in TriAnnotConfig.TRIANNOT_CONF['Runners']:
                    self.availableRunners.append(runner)
                helpComplements['jobRunnerName'] += "Possible values are: %s.\n" % (', '.join(self.availableRunners))
                self.defaultJobRunnerName = TriAnnotConfig.TRIANNOT_CONF['Global']['DefaultTaskJobRunner']
                helpComplements['jobRunnerName'] += "Default runner is: %s.\n" % self.defaultJobRunnerName

                # "monitoringInterval" and "numberOfThread" arguments
                for runner in self.availableRunners:
                    helpComplements['numberOfThread'] += "Default value for runner <%s> is: %s (Maximum: %s).\n" % (runner, TriAnnotConfig.TRIANNOT_CONF['Runners'][runner]['defaultNumberOfThread'], TriAnnotConfig.TRIANNOT_CONF['Runners'][runner]['maximumNumberOfThreadByTool'])
                    helpComplements['monitoringInterval'] += "Default value for runner <%s> is: %s.\n" % (runner, TriAnnotConfig.TRIANNOT_CONF['Runners'][runner]['monitoringInterval'])

            # Create an active help option
            self.basicOptionGroup.add_argument('-h', '--help', action='help', help='show this help message and exit')
        else:
            # Create a dummy help option so that it appears in the Usage if needed
            self.basicOptionGroup.add_argument('-h', '--help', action='store_true', help='Dummy help option that do nothing')

        # Basic arguments
        self.basicOptionGroup.add_argument('-v', '--version', action='version', version="TriAnnot version %s" % (TRIANNOT_VERSION))

        # Mandatory arguments
        self.fillMandatoryOptionGroup(activateRequirement)

        # Recommended arguments
        self.fillRecommendedOptionGroup(helpComplements, setDefaultAndPossibleValues)

        # Debug and Logging arguments
        self.fillLoggingAndDebuggingOptionGroup()

        # Hidden arguments
        self.fillHiddenOptionGroup()

        # Other arguments
        self.fillMiscOptionGroup(helpComplements)


    def fillMandatoryOptionGroup(self, activateRequirement):
        self.mandatoryOptionGroup.add_argument('-s', '--sequence', dest = 'sequenceFilePath',
                metavar = 'FASTA_FILE',
                help = "Sequence file in Fasta format that contains the sequence(s) to annotate.\n\n",
                default = None,
                required = activateRequirement)

        self.mandatoryOptionGroup.add_argument('-t', '--tasks', dest = 'tasksFilePath',
                metavar = 'XML_FILE',
                help = "TriAnnot step/task file in XML format that contains the list of tasks to execute.\n\n",
                default = None,
                required = activateRequirement)

        self.mandatoryOptionGroup.add_argument('-c', '--config', dest = 'configFilePath',
                metavar = 'XML_CONFIG_FILE',
                help = "Name of an XML configuration file.\n",
                default = None,
                required = activateRequirement)


    def fillRecommendedOptionGroup(self, helpComplements, activateChoices):
        self.recommendedOptionGroup.add_argument('-d', '--workdir', dest = 'execDirPath',
                metavar = 'PATH',
                help = "Name of the main working directory to use/create for this analysis.\nIf not specified, the current directory will be used.\n\n",
                default = self.mainExecDirFullPath)

        if activateChoices:
            self.recommendedOptionGroup.add_argument('-r', '--runner', dest = 'jobRunnerName',
                    help = "Name of the job runner to use to submit the execution/parsing jobs of each task.\nLook at the following XML configuration file for more information: TriAnnotConfig_Runners.xml.\n%s\n" % helpComplements['jobRunnerName'],
                    metavar = 'JOB_RUNNER_NAME',
                    choices = self.availableRunners,
                    default = self.defaultJobRunnerName)
        else:
            self.recommendedOptionGroup.add_argument('-r', '--runner', dest = 'jobRunnerName',
                    help = "Name of the job runner to use to submit the execution/parsing jobs of each task.\nLook at the following XML configuration file for more information: TriAnnotConfig_Runners.xml.\n%s\n" % helpComplements['jobRunnerName'],
                    metavar = 'JOB_RUNNER_NAME',
                    default = self.defaultJobRunnerName)


        self.recommendedOptionGroup.add_argument('--clean', dest = 'cleanAtTheEnd',
                help = "Determine which files and/or directories will be kept/removed at the end of the analysis.\nEach cleaning type can be activated (using Upper-case letter) or disabled (using Lower-case letter).\nDefault cleaning rules are described in TriAnnot main configuration file: TriAnnotConfig.xml.\nPossible values are:\n  - p/P -> Disable/enable python launchers files cleaning\n  - o/O -> Disable/enable stdout files cleaning\n  - e/E -> Disbale/enable stderr files cleaning\n  - t/T -> Disable/enable temporary folders cleaning\n  - c/C -> Disable/enable common files folder cleaning\n  - s/S -> Disable/enable summary files folder cleaning\n  - l/L -> Disable/enable log files cleaning\n\nExamples:\n  '--clean LOETCSP' to clean everything.\n  '--clean loetcsp' to keep everything.\n",
                metavar = 'CLEAN_PATTERN',
                default = None)


    def fillLoggingAndDebuggingOptionGroup(self):
        # Define argument's choices
        loggerTypeChoices = ['screen', 'file', 'both']

        # Define arguments
        self.loggingAndDebuggingOptionGroup.add_argument('--debug', dest = 'debugMode',
                action = 'store_true',
                help = "Activate debug mode. In debug mode, %s will be more verbose and some debug specific action will be executed.\n\n" % self.programName,
                default = False)

        self.loggingAndDebuggingOptionGroup.add_argument('--logger', dest = 'loggerType',
                metavar = 'LOGGER_TYPE',
                choices = loggerTypeChoices,
                help = "Determine how %s will manage log messages. Log messages can be displayed on screen, written in files or both.\nPossible values are: %s.\n\n" % (self.programName, ', '.join(loggerTypeChoices)),
                default = 'both')

        self.loggingAndDebuggingOptionGroup.add_argument('--color', dest = 'colorizeScreenLogger', action = 'store_true', help = "Activate the colorization of the screen logger for better visualization.\nWhen this option is used, each log message will be colored depending on its level (ie. DEBUG, INFO, WARNING, ERROR, etc.)\n\n", default = False)

        self.loggingAndDebuggingOptionGroup.add_argument('--progress', dest = 'progress',
                action = 'store_true',
                help = "Create and fill a <TriAnnot_progress> file (in XML format) in the execution folder.\nThis file will contain the following informations:\n  - Number of finished tasks\n  - Total number of tasks\n  - Percentage of completed task\n  - Date of the last update of the progression\n",
                default = False)


    def fillHiddenOptionGroup(self):
        # The '--no-interrupt' argument could be used to tell a TriAnnotUnit.py instance to ignore any keyboard interruption (ie. use of ctrl+c)
        # This argument is meant to be used when TriAnnotUnit.py is launched by TriAnnotPipeline.py with the "Local" runner
        # The objective is to be able to use ctrl+c on TriAnnotPipeline.py without passing the ctrl+c to every child process (ie. TriAnnotUnit instance)
        self.hiddenOptionGroup.add_argument('--no-interrupt', dest = 'ignoreKeyboardInterrupt',
                action = 'store_true',
                help = argparse.SUPPRESS,
                default = False)


    def fillMiscOptionGroup(self, helpComplements):
        self.miscOptionGroup.add_argument('--kill', dest = 'killOnAbort',
                action = 'store_true',
                help = "When this option is used, ALL currently running tasks (whether they are basic subprocesses or jobs of a batch\nqueuing system) will be killed when a critical error occurs in one of the tasks or when a TriAnnot_abort file\nis detected.\n\nWhen this option is NOT used, ALL currently running tasks (whether they are basic subprocesses or jobs of a batch\nqueuing system) will be allowed to finish and the analysis pipeline will be properly stopped when a critical error\noccurs in one of the tasks or when a TriAnnot_abort file is detected.\n\n",
                default = False)

        #self.miscOptionGroup.add_argument('--email', dest = 'emailTo',
                #help = "Send an email at the end of pipeline execution to given email address. You can set this option more than once to send to multiple recipients",
                #action = 'append',
                #metavar = 'EMAIL_ADDRESS',
                #default = None)


    def updateMainObjectWithArguments(self, commandLineArguments, isCalledAfterConfigurationLoading):
        # Explanation: Some attributes can be defined on the first call, some others can only be defined after the loading of the configuration files
        # Case 1: Convert simple command line arguments (ie. arguments that can be treated before configuration file(s) loading) into object attributes
        if not isCalledAfterConfigurationLoading:
            # Basic arguments
            self.debugMode = commandLineArguments.debugMode
            self.loggerType = commandLineArguments.loggerType
            self.colorizeScreenLogger = commandLineArguments.colorizeScreenLogger
            self.reportProgress = commandLineArguments.progress
            self.ignoreKeyboardInterrupt = commandLineArguments.ignoreKeyboardInterrupt
            self.killOnAbort = commandLineArguments.killOnAbort
            #self.emailTo = commandLineArguments.emailTo

            # Check the existence of the files and directories specified through command line arguments
            self.checkAndStorePathLikeArguments(commandLineArguments)

        # Case 2: Convert complex command line arguments (ie. arguments that can't be treated before configuration file(s) loading) into object attributes
        else:
            # Deal with the job runner
            # We have to store the runner name in the Runtime section of TRIANNOT_CONF to be able to use the getRunnerName method during XML special values replacements
            # For example, if the runner name is SunGridEngine, then the call "getValue(Runners|getRunnerName()|defaultNumberOfThread)" will become "getValue(Runners|SunGridEngine|defaultNumberOfThread)"
            self.jobRunnerName = commandLineArguments.jobRunnerName
            TriAnnotConfig.TRIANNOT_CONF['Runtime']['jobRunnerName'] = self.jobRunnerName

            # Check if the selected runner is allowed to run TriAnnot tasks
            if TriAnnotConfig.TRIANNOT_CONF['Runners'][self.jobRunnerName]['usageLimitation'] not in ['task', 'both']:
                self.argumentParser.error("The <%s> job runner selected through the -r/--runner argument can't be used to run TriAnnot tasks !" % self.jobRunnerName)

            # Determine and store all kinds of monitoring interval in the main object
            self.monitoringInterval = int(TriAnnotConfig.getConfigValue("Runners|%s|monitoringInterval" % self.jobRunnerName))

            if self.monitoringInterval < 60:
                self.stillAliveJobMonitoringInterval = 60
            else:
                self.stillAliveJobMonitoringInterval = 60 + self.monitoringInterval

            # Deal with the special --clean argument
            if commandLineArguments.cleanAtTheEnd is not None:
                self.treatCleanAtTheEndParameter(commandLineArguments.cleanAtTheEnd)


    def checkAndStorePathLikeArguments(self, commandLineArguments):
        # Check sequence file
        if commandLineArguments.sequenceFilePath is not None:
            self.sequenceFileFullPath = os.path.realpath(os.path.expanduser(commandLineArguments.sequenceFilePath))
            if not Utils.isExistingFile(self.sequenceFileFullPath):
                self.argumentParser.error("The Fasta sequence file specified with the -s/--sequence argument/option does not exists or is unreadable: %s" % self.sequenceFileFullPath)
            if Utils.isEmptyFile(self.sequenceFileFullPath):
                self.argumentParser.error("The Fasta sequence file specified with the -s/--sequence argument/option is empty: %s" % self.sequenceFileFullPath)

        # Check full task file
        if commandLineArguments.tasksFilePath is not None:
            self.globalTaskFileFullPath = os.path.realpath(os.path.expanduser(commandLineArguments.tasksFilePath))
            if not Utils.isExistingFile(self.globalTaskFileFullPath):
                self.argumentParser.error("The full step/task file specified with the -t/--tasks argument/option does not exists or is unreadable: %s" % self.globalTaskFileFullPath)
            if Utils.isEmptyFile(self.globalTaskFileFullPath):
                self.argumentParser.error("The full step/task file specified with the -t/--tasks argument/option is empty: %s" % self.globalTaskFileFullPath)

        # Check full configuration file
        if commandLineArguments.configFilePath is not None:
            self.globalConfigurationFileFullPath = os.path.realpath(os.path.expanduser(commandLineArguments.configFilePath))
            if not Utils.isExistingFile(self.globalConfigurationFileFullPath):
                self.argumentParser.error("The full XML configuration file specified with the -c/--config argument/option does not exists or is unreadable: %s" % self.globalConfigurationFileFullPath)
            if Utils.isEmptyFile(self.globalConfigurationFileFullPath):
                self.argumentParser.error("The full XML configuration file specified with the -c/--config argument/option is empty: %s" % self.globalConfigurationFileFullPath)

        # Check main execution directory full path
        if commandLineArguments.execDirPath is not None:
            self.mainExecDirFullPath = os.path.realpath(os.path.expanduser(commandLineArguments.execDirPath))
            if not Utils.isExistingDirectory(self.mainExecDirFullPath):
                self.argumentParser.error("The main execution directory specified with the -d/--workdir argument/option does not exists or is not accessible: %s" % self.mainExecDirFullPath)


    def treatCleanAtTheEndParameter(self, cleanSchemeString):
        # clean validation pattern checks that each letter appear only once in cleanSchemeString
        cleanValidationPattern = re.compile(r"^(?!.*?(.).*?\1)[poetcsl]+$", re.IGNORECASE)
        if cleanValidationPattern.match(cleanSchemeString) is None:
            self.argumentParser.error("Cleaning scheme option (-c, --clean) is invalid: %s" % cleanSchemeString)
        for letter in cleanSchemeString:
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


    ###############################
    ##  Logging related methods  ##
    ###############################

    def updateLoggers(self):
        # Generate formaters
        self.createFormaters()

        # Adapt the logger level based on the situation (Must be set even if there is no console handler)
        if self.debugMode:
            self.logger.setLevel(logging.DEBUG)
        elif self.helpArgumentIsUsed:
            # We don't want to display non error related log messages when the -h/--help comand line argument is used
            self.logger.setLevel(logging.WARNING)
        else:
            self.logger.setLevel(logging.INFO)

        # Create handlers
        if self.helpArgumentIsUsed:
            # The logging mode is forced to screen when we just want to display the help section
            self.createConsoleHandler()
        else:
            # Create appropriate handlers based on the selected logger type
            if self.loggerType == 'screen':
                self.createConsoleHandler()
            elif self.loggerType == 'file':
                self.createFileHandlers()
            else:
                self.createConsoleHandler()
                self.createFileHandlers()


    def createFormaters(self):
        self.screenFormatter = logging.Formatter("%(name)s - %(levelname)s - %(message)s")
        self.screenColoredFormatter = ColoredFormatter("%(name)s - %(levelname)s - %(message)s")
        self.stdOutFormatter = logging.Formatter("(%(levelname)s) %(message)s")
        self.stdErrorFormatter = logging.Formatter("%(levelname)s - %(module)s (line %(lineno)d) - %(funcName)s - %(asctime)s - Message: %(message)s")


    def createConsoleHandler(self):
        # Create the default console/screen handler
        stdoutConsoleHandler = logging.StreamHandler(sys.stdout)
        if self.colorizeScreenLogger:
            stdoutConsoleHandler.setFormatter(self.screenColoredFormatter)
        else:
            stdoutConsoleHandler.setFormatter(self.screenFormatter)
        self.logger.addHandler(stdoutConsoleHandler)


    def createFileHandlers(self):
        # Create a file handler for info/debug messages
        stdoutFileHandler = logging.FileHandler(os.path.join(self.mainExecDirFullPath, 'TriAnnotUnit_' + self.shortIdentifier + '.log'))
        stdoutFileHandler.setFormatter(self.stdOutFormatter)
        if self.debugMode:
            stdoutFileHandler.setLevel(logging.DEBUG)
        else:
            stdoutFileHandler.setLevel(logging.INFO)
        self.logger.addHandler(stdoutFileHandler)

        # Create a file handler for error messages
        stderrFileHandler = logging.FileHandler(os.path.join(self.mainExecDirFullPath, 'TriAnnotUnit_' + self.shortIdentifier + '.err'))
        stderrFileHandler.setFormatter(self.stdErrorFormatter)
        stderrFileHandler.setLevel(logging.ERROR)
        self.logger.addHandler(stderrFileHandler)


    def createFileHandlers_back(self):
        # Create a file handler for info/debug messages (with a custom formatter)
        stdoutFileHandler = logging.FileHandler(os.path.join(self.mainExecDirFullPath, 'TriAnnotUnit_' + self.shortIdentifier + '.log'))
        if self.debugMode:
            stdoutFileHandler.setFormatter(self.levelMessageFormatter)
            stdoutFileHandler.setLevel(logging.DEBUG)
        else:
            stdoutFileHandler.setLevel(logging.INFO)

        self.logger.addHandler(stdoutFileHandler)

        # Create a file handler for error messages
        stderrFileHandler = logging.FileHandler(os.path.join(self.mainExecDirFullPath, 'TriAnnotUnit_' + self.shortIdentifier + '.err'))
        stderrFileHandler.setLevel(logging.ERROR)
        self.logger.addHandler(stderrFileHandler)


    #########################################
    ##  Signal management related methods  ##
    #########################################

    def manageSigintSignal(self):
        if self.ignoreKeyboardInterrupt:
            signal.signal(signal.SIGINT, self.keyboardInterruptHandler)


    def keyboardInterruptHandler(self, signum, frame):
        self.logger.warning('A keyboard interruption (probably sent by the parent process) has been detected and ignored because the --no-interrupt argument has been used')


    ##################################################
    ##  Configuration file loading related methods  ##
    ##################################################

    def loadGlobalConfigurationFile(self):
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


    ##############################################
    ##  Step/task file loading related methods  ##
    ##############################################

    def loadGlobalTaskFile(self):
        # Create a new TriAnnotTaskFileChecker object
        taskFileCheckerObject = TriAnnotTaskFileChecker(self.globalTaskFileFullPath)

        # Load and check the version of the step/task file
        taskFileCheckerObject.loadTaskFile()
        self.taskFileDescription = taskFileCheckerObject.taskFileDescription

        if not taskFileCheckerObject.isMadeForCurrentTriAnnotVersion():
            self.abortPipeline("The selected XML step/task file was written for a different version of TriAnnot (Written for version <%s> but version <%s> was expected)." % (taskFileCheckerObject.taskFileTriAnnotVersion, TRIANNOT_VERSION))

        taskFileCheckerObject.displayTaskFileLoadingErrors()

        if taskFileCheckerObject.nbTaskFileLoadingErrors > 0:
           self.abortPipeline('At least one error occured during the loading of the global step/task file')


    #####################################
    ##  Creation of the list of tasks  ##
    #####################################

    def generateAllTriAnnotTaskObjects(self):
        # Initializations
        errorsList = []

        # Create a TriAnnotTask object for each program block
        for taskParameterObjectId in TriAnnotTaskFileChecker.allTaskParametersObjects:
            # Try to initialize a TriAnnotTask object and catch raised errors if needed
            # A possible error is, for example, an attempt to create an object for an abstract class like FuncAnnot
            try:
                currentTask = TriAnnotTask(taskParameterObjectId)
            except RuntimeError as err:
                errorsList.append(err.message)
                continue

            # Add parameters and other informations to the Task object
            currentTask.mainExecDir = self.mainExecDirFullPath
            currentTask.jobRunnerName = self.jobRunnerName

            # Store the current task object in the global list of tasks
            self.tasks[currentTask.id] = currentTask

        # Display errors if needed
        if len(errorsList) > 0:
            for error in errorsList:
                self.logger.error(error)
            exit(1)

        # Display the list and the number of tasks to execute
        if self.logger.isEnabledFor(logging.DEBUG):
            self.logger.debug('Detailed list of tasks to execute:')
            for taskId in sorted(self.tasks.keys()):
                self.logger.debug(self.tasks[taskId].toString())
        self.logger.info("Total number of tasks to execute: %s" % len(self.tasks))


    ##############################################
    ##  Pre-pipeline execution related methods  ##
    ##############################################

    def checkAlreadyCompletedTasks(self):
        for task in self.tasks.values():
            if task.isExecSuccessfullFromAbstractFile(False):
                self.logger.info("Execution step for %s has already been done" % (task.getDescriptionString()))
                self._postExecutionTreatments(task)
                #if task.isSkipped:
                #    self.cancelTasksDependingOn(task,  "Task %s [%s] return skipped status" % (task.id, task.type))
                if task.needParsing:
                    task.status = TriAnnotStatus.FINISHED_EXEC
                    if task.isParsingSuccessfullFromAbstractFile(False):
                        self.logger.info("Parsing step for %s has already been done" % (task.getDescriptionString()))
                        self._postParsingTreatments(task)
                        task.status = TriAnnotStatus.COMPLETED
                else:
                    task.status = TriAnnotStatus.COMPLETED


    ###########################################
    ##  Tasks pre-execution related methods  ##
    ###########################################

    def _preExecutionTreatments(self, task):
        # Execution task specific pre-treatment
        task.preExecutionTreatments()

        # Abort pipeline or cancel depending tasks if needed
        if task.needToAbortPipeline:
            self.abortPipeline(task.abortPipelineReason)
        elif task.needToCancelDependingTasks:
            self.cancelTasksDependingOn(task, task.cancelDependingTasksReason)


    def _preParsingTreatments(self, task):
        # Parsing task specific pre-treatment
        task.preParsingTreatments()

        # Abort pipeline or cancel depending tasks if needed
        if task.needToAbortPipeline:
            self.abortPipeline(task.abortPipelineReason)
        elif task.needToCancelDependingTasks:
            self.cancelTasksDependingOn(task, task.cancelDependingTasksReason)


    #######################################
    ##  Tasks execution related methods  ##
    #######################################

    def executeTasks(self):
        self.totalTasksCount = len(self.tasks)
        self.checkAlreadyCompletedTasks()

        while len(self.tasks) > 0:
            self.checkAndUpdateTasksStatus()
            self._execParsingOnExecFinishedTasks()
            self._treatCompletedAndCanceledTasks()
            self._execPendingTasksWithoutUnsatisfiedDependence()
            if self.reportProgress:
                self.generateOrUpdateProgressFile()
            if len(self.tasks) > 0:
                self.checkUserAbort()
                time.sleep(float(self.monitoringInterval))


    def _execPendingTasksWithoutUnsatisfiedDependence(self):

        for task in self.tasks.values():
            if task.status == TriAnnotStatus.PENDING and not task.hasUnsatifiedDependences():
                # Prepare the execution job for the current task
                self._preExecutionTreatments(task)

                # Can we submit a new task ? is some computing power available ?
                if task.initializeJobRunner('execution'):
                    # Effective submission of the execution job for the current task
                    if self._runTaskJob(task) == 0:
                        task.status = TriAnnotStatus.SUBMITED_EXEC
                        task.setStartTime(time.time())

                # Do we need to abort the pipeline because of an error ?
                if task.needToAbortPipeline:
                    task.status = TriAnnotStatus.ERROR
                    self.abortPipeline(task.abortPipelineReason)


    def _treatCompletedAndCanceledTasks(self):
        for task in self.tasks.values():
            if task.status == TriAnnotStatus.COMPLETED:
                self.logger.info("%s is completed" % (task.getDescriptionString().capitalize()))
                self.setTasksCompletedDependence(task.id)
                self.completedTasks[task.id] = task
                self.tasks.pop(task.id)
            elif task.status == TriAnnotStatus.CANCELED:
                self.logger.info("%s is canceled" % (task.getDescriptionString()))
                self.completedTasks[task.id] = task
                self.tasks.pop(task.id)


    def _execParsingOnExecFinishedTasks(self):
        for task in self.tasks.values():
            if task.status == TriAnnotStatus.FINISHED_EXEC and task.needParsing:
                # Prepare the parsing job for the current task
                self._preParsingTreatments(task)

                # Can we submit a new task ? is some computing power available ?
                if task.initializeJobRunner('parsing'):
                    # Effective submission of the parsing job for the current task
                    if self._runTaskJob(task) == 0:
                        task.setStartTime(time.time())
                        task.status = TriAnnotStatus.SUBMITED_PARSING

                # Do we need to abort the pipeline because of an error ?
                if task.needToAbortPipeline:
                    task.status = TriAnnotStatus.ERROR
                    self.abortPipeline(task.abortPipelineReason)

            elif task.status == TriAnnotStatus.FINISHED_EXEC and not task.needParsing:
                self.logger.debug("The output of %s does not need to be parsed. Setting status to COMPLETED" % (task.getDescriptionString()))
                task.status = TriAnnotStatus.COMPLETED


    def _runTaskJob(self, task):
        # Jump in the directory which stores all job files
        os.chdir(os.path.join(self.mainExecDirFullPath, TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['launcher_files']))

        # Define job name and shell launcher full path
        jobName = self.uniqueIdentifier + "_" + str(task.id).zfill(3) + "_" + task.runner.jobType + "_" + task.type
        task.wrapperFileFullPath = os.path.join(self.mainExecDirFullPath, TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['launcher_files'], "%s.%s.sh" % (jobName, task.runner.runnerType))

        # Build TAP Program/Parser launcher command line and create shell wrapper
        self._buildLauncherCommandLine(task)
        self._createShellWrapper(task)

        # Submit job
        self.logger.info("Submitting %s job for %s - Runner: %s {%s}" % (task.runner.jobType, task.getDescriptionString(), task.runner.getRunnerDescription(), time.strftime("%Y-%m-%d %H:%M:%S")))
        submissionStatus = task.runner.submitJob(jobName, task.wrapperFileFullPath)

        # Jump back in the main execution directory
        os.chdir(self.mainExecDirFullPath)

        # Check submission return value
        if submissionStatus != 0:
            task.failedSubmitCount = task.failedSubmitCount + 1
            self.logger.debug("Submission failed for %s (%s failure)" % (task.getDescriptionString(), task.failedSubmitCount))
            if task.failedSubmitCount >= int(task.runner.maximumFailedSubmission):
                task.needToAbortPipeline = True
                task.abortPipelineReason = "Maximum number of failed submission has been reached for %s !" % (task.getDescriptionString())
            return submissionStatus
        else:
            task._cptFailedCheckStillAlive = 0
            task._cptNotAlive = 0
            self.logger.debug("%s pid/jobid is: %s" % (task.getDescriptionString().capitalize(), task.runner.jobid))
            return 0


    def _buildLauncherCommandLine(self, task):
        # Initializations
        launcherCommand = ''
        sequenceFileFullPath = ''

        # Build Program/Parser launcher command
        if task.runner.jobType == 'execution' and task.sequence != 'initial':
            sequenceFileFullPath = os.path.join(self.mainExecDirFullPath, TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['sequence_files'], task.sequence)
        else:
            sequenceFileFullPath = self.sequenceFileFullPath

        if task.runner.jobType == 'execution':
            launcherCommand += TriAnnotConfig.TRIANNOT_CONF['PATHS']['soft']['Program_Launcher']['bin']
        elif task.runner.jobType == 'parsing':
            launcherCommand += "%s -filetoparse %s " % (TriAnnotConfig.TRIANNOT_CONF['PATHS']['soft']['Parser_Launcher']['bin'], task.fileToParse)
        else:
            self.abortPipeline("Unsupported job type: %s" % task.runner.jobType)

        launcherCommand += " -stagelist %s" % self.globalTaskFileFullPath
        launcherCommand += " -sequence %s" % sequenceFileFullPath
        launcherCommand += " -configfile %s" % self.globalConfigurationFileFullPath
        launcherCommand += " -workdir %s" % self.mainExecDirFullPath
        launcherCommand += " -progid %s" % task.id

        # In debug mode, a part of the configuration will be rechecked just before the execution of a tool on a compute node
        if self.debugMode:
            launcherCommand += " -verbose 3"
            launcherCommand += " -check path"
        else:
            launcherCommand += " -verbose 1"

        # Debug display
        self.logger.debug("Generated Perl launcher command line: %s" % (launcherCommand))

        # Update task object
        task.launcherCommand = launcherCommand


    def _createShellWrapper(self, task):
        # Create/open file
        bashFileHandle = open(task.wrapperFileFullPath, "w")

        self.logger.debug("Writing launcher command line in file: %s" % (task.wrapperFileFullPath))

        # Write content
        bashFileHandle.write("#!/usr/bin/env bash\n\n")
        bashFileHandle.write(task.launcherCommand)

        # Close file handle
        bashFileHandle.close()

        # Update wrapper file rights
        os.system("chmod 750 %s" % task.wrapperFileFullPath)


    #####################################################################
    ##  Tasks monitoring & Tasks status modifications related methods  ##
    #####################################################################

    def checkAndUpdateTasksStatus(self):
        self.logger.debug("Current status of uncompleted tasks:")

        for task in self.tasks.values():
            self.logger.debug("Status for %s is: %s" % (task.getDescriptionString(), TriAnnotStatus.getStatusName(task.status)))

            if task.status == TriAnnotStatus.PENDING:
                continue

            elif task.status == TriAnnotStatus.SUBMITED_EXEC and os.path.isdir(task.getTaskExecDirName()):
                task.status = TriAnnotStatus.RUNNING_EXEC
            elif task.status == TriAnnotStatus.SUBMITED_PARSING  and os.path.isdir(task.getParsingDir()):
                task.status = TriAnnotStatus.RUNNING_PARSING
            elif task.status == TriAnnotStatus.RUNNING_EXEC and task.isExecAbstractFileAvalaible() and task.isExecSuccessfullFromAbstractFile():
                self._postExecutionTreatments(task)
                task.status = TriAnnotStatus.FINISHED_EXEC
            elif task.status == TriAnnotStatus.RUNNING_PARSING and task.isParsingAbstractFileAvalaible() and task.isParsingSuccessfullFromAbstractFile():
                self._postParsingTreatments(task)
                task.status = TriAnnotStatus.COMPLETED
            elif (task.status == TriAnnotStatus.SUBMITED_EXEC or task.status == TriAnnotStatus.RUNNING_EXEC or  task.status == TriAnnotStatus.SUBMITED_PARSING or task.status == TriAnnotStatus.RUNNING_PARSING) and time.time() - task.checkedIsAliveTime > int(self.stillAliveJobMonitoringInterval):
                if not task.isStillAlive():
                    task.setErrorStatus("Task is not alive anymore")
                elif task._cptFailedCheckStillAlive >= int(task.runner.maximumFailedMonitoring):
                    task.setErrorStatus("Failed too many times to check if task is still alive")
                task.checkedIsAliveTime = time.time()

            if task.status == TriAnnotStatus.ERROR:
                self.abortPipeline("%s failed." % (task.getDescriptionString().capitalize()))


    def setTasksCompletedDependence(self, completedTaskId):
        for task in self.tasks.values():
            task.setCompletedDependence(completedTaskId)


    def checkUserAbort(self):
        if Utils.isExistingFile(os.path.join(self.mainExecDirFullPath, "TriAnnot_abort")):
            # Make a last update of the progress file and abort
            self.generateOrUpdateProgressFile()
            self.abortPipeline("A TriAnnot_abort file has been detected in the main execution folder")


    def generateOrUpdateProgressFile(self):
        # Initializations
        progressFileHandler = None
        if self.progressFileFullPath is None:
            self.progressFileFullPath = os.path.join(self.mainExecDirFullPath, 'TriAnnot_progress')

        # Get the number of completed tasks
        completedTasksCount = len(self.completedTasks)
        currentProgress = "%s/%s" % (completedTasksCount, self.totalTasksCount)

        # Create or update the progress file if the analysis have move forward
        if currentProgress != self._previousProgress:
            # Store current progression in an object attribute
            self._previousProgress = currentProgress

            # Get formatted timestamp
            now =  time.strftime("%Y-%m-%d %H:%M:%S")
            self.logger.debug("%s/%s tasks completed - %s" % (completedTasksCount, self.totalTasksCount, now))

            # Try to create a file handler for the TriAnnot_progress file
            try:
                progressFileHandler = open(self.progressFileFullPath, 'w')
            except IOError:
                self.logger.error("%s could not create (or update) the following XML progress file: %s" % (self.programName, self.progressFileFullPath))
                raise

            # Add content to the XML file (Note: the with statement allow auto-closing of the file)
            with progressFileHandler:
                #  Build the root of the XML file
                xmlRoot = etree.Element('unit_progression', {'triannot_version': TRIANNOT_VERSION, 'description': self.taskFileDescription})

                # Save progression data as sub element of the xml root element
                alreadyCompletedTasksElement = etree.SubElement(xmlRoot, 'already_completed_tasks')
                alreadyCompletedTasksElement.text = str(completedTasksCount)

                totalNumberOfTasksElement = etree.SubElement(xmlRoot, 'total_number_of_tasks')
                totalNumberOfTasksElement.text = str(self.totalTasksCount)

                percentageOfCompletionElement = etree.SubElement(xmlRoot, 'percentage_of_completion')
                if completedTasksCount > 0:
                    percentageOfCompletionElement.text = str(int((1.0*completedTasksCount/self.totalTasksCount)*100))
                else:
                    percentageOfCompletionElement.text = '0'

                reportDateElement = etree.SubElement(xmlRoot, 'report_date')
                reportDateElement.text = now

                # Indent the XML content
                TriAnnotConfig.indent(xmlRoot)

                # Write the generated XML content
                progressFileHandler.write(etree.tostring(xmlRoot, 'ISO-8859-1'))


    ############################################
    ##  Tasks post-execution related methods  ##
    ############################################

    def _postExecutionTreatments(self, task):
        # Execution task specific post treatment
        task.postExecutionTreatments()

        # Abort pipeline or cancel depending tasks if needed
        if task.needToAbortPipeline:
            self.abortPipeline(task.abortPipelineReason)
        elif task.needToCancelDependingTasks:
            self.cancelTasksDependingOn(task, task.cancelDependingTasksReason)


    def _postParsingTreatments(self, task):
        # Parsing task specific post treatment
        task.postParsingTreatments()

        # Abort pipeline or cancel depending tasks if needed
        if task.needToAbortPipeline:
            self.abortPipeline(task.abortPipelineReason)
        elif task.needToCancelDependingTasks:
            self.cancelTasksDependingOn(task, task.cancelDependingTasksReason)


    def cancelTasksDependingOn(self, task, cancelReason):
        for taskToCheck in self.tasks.values():
            if taskToCheck.status == TriAnnotStatus.PENDING and task.id in taskToCheck.dependences:
                self.logger.info("Canceling %s - Reason: %s" % (taskToCheck.getDescriptionString(), cancelReason))
                taskToCheck.status = TriAnnotStatus.CANCELED
                self.cancelTasksDependingOn(taskToCheck, "%s was canceled" % (taskToCheck.getDescriptionString().capitalize()))


    #########################################
    ##  Pipeline aborting related methods  ##
    #########################################

    def abortPipeline(self, message):
        # Setting analysis status to error
        self.analysisStatus = TriAnnotStatus.ERROR

        # Log
        self.logger.error(message)
        self.logger.info("%s execution will now be aborted.." % self.programName)

        # Check if we need to turn the task kill switch on (by reading the TriAnnot_abort file)
        self.toggleKillSwitch();

        # Abort all running tasks (kill them directly or display kill commands  depending of the kill switch)
        self.abortRunningTasks()

        # Tell the rest of the pipeline that this is not an unexpected error case
        self.pipelineAborted = True

        exit(1)


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


    def abortRunningTasks(self):
        for task in self.tasks.values():
            if task.runner is not None:
                if task.runner.jobid is not None:
                    task.abort(self.killOnAbort)


    #############################################################
    ##  Post-pipeline / Analysis finalization related methods  ##
    #############################################################

    def finalize(self):
        try:
            self.getAnalysisTimes()
            self.displayAnalysisTimes()
            self.moveBlastResultsForWhichExonerateExists()
            self.clean()
            sys.stdout.flush()
        except Exception as ex:
            self.logger.debug("Traceback message:\n%s" % traceback.format_exc())
            self.logger.error(ex.message)

        if self.analysisStatus != TriAnnotStatus.ERROR:
            self.analysisStatus = TriAnnotStatus.COMPLETED


    def getAnalysisTimes(self):
        # Initializations
        execTimes = {}
        parsingTimes = {}

        self.analysisTimes = OrderedDict()
        self.analysisTimes['execution_tasks_times'] = {'real_time' : OrderedDict([('minimum', 0.0), ('maximum', 0.0), ('mean', 0.0), ('sum', 0.0)]), 'cpu_time' : OrderedDict([('minimum', 0.0), ('maximum', 0.0), ('mean', 0.0), ('sum', 0.0)]) }
        self.analysisTimes['parsing_tasks_times'] = { 'real_time' : OrderedDict([('minimum', 0.0), ('maximum', 0.0), ('mean', 0.0), ('sum', 0.0)]), 'cpu_time' : OrderedDict([('minimum', 0.0), ('maximum', 0.0), ('mean', 0.0), ('sum', 0.0)]) }
        self.analysisTimes['total_times'] = { 'real_time' : OrderedDict([('mean', 0.0), ('sum', 0.0)]), 'cpu_time' : OrderedDict([('mean', 0.0), ('sum', 0.0)]) }

        # Compute the various execution times
        for task in self.completedTasks.values():
            # Execution tasks
            if task.benchmark.has_key('exec') and task.benchmark['exec'].has_key('times') and task.benchmark['exec']['times'].has_key('real') and task.benchmark['exec']['times'].has_key('cpu'):
                execTimes[task.id] = {}
                execTimes[task.id]['real'] = float(task.benchmark['exec']['times']['real'])
                self.analysisTimes['execution_tasks_times']['real_time']['sum'] += execTimes[task.id]['real']
                execTimes[task.id]['cpu'] = float(task.benchmark['exec']['times']['cpu'])
                self.analysisTimes['execution_tasks_times']['cpu_time']['sum'] += execTimes[task.id]['cpu']
                if self.analysisTimes['execution_tasks_times']['real_time']['maximum'] < execTimes[task.id]['real']:
                    self.analysisTimes['execution_tasks_times']['real_time']['maximum'] = execTimes[task.id]['real']
                if self.analysisTimes['execution_tasks_times']['cpu_time']['maximum'] < execTimes[task.id]['cpu']:
                    self.analysisTimes['execution_tasks_times']['cpu_time']['maximum'] = execTimes[task.id]['cpu']
                if self.analysisTimes['execution_tasks_times']['real_time']['minimum'] == 0.0 or self.analysisTimes['execution_tasks_times']['real_time']['minimum'] > execTimes[task.id]['real']:
                    self.analysisTimes['execution_tasks_times']['real_time']['minimum'] = execTimes[task.id]['real']
                if self.analysisTimes['execution_tasks_times']['cpu_time']['minimum'] == 0.0 or self.analysisTimes['execution_tasks_times']['cpu_time']['minimum'] > execTimes[task.id]['cpu']:
                    self.analysisTimes['execution_tasks_times']['cpu_time']['minimum'] = execTimes[task.id]['cpu']

            # Parsing Tasks
            if task.benchmark.has_key('parsing') and task.benchmark['parsing'].has_key('times') and task.benchmark['parsing']['times'].has_key('real') and task.benchmark['parsing']['times'].has_key('cpu'):
                parsingTimes[task.id] = {}
                parsingTimes[task.id]['real'] = float(task.benchmark['parsing']['times']['real'])
                self.analysisTimes['parsing_tasks_times']['real_time']['sum'] += parsingTimes[task.id]['real']
                parsingTimes[task.id]['cpu'] = float(task.benchmark['parsing']['times']['cpu'])
                self.analysisTimes['parsing_tasks_times']['cpu_time']['sum'] += parsingTimes[task.id]['cpu']
                if self.analysisTimes['parsing_tasks_times']['real_time']['maximum'] < parsingTimes[task.id]['real']:
                    self.analysisTimes['parsing_tasks_times']['real_time']['maximum'] = parsingTimes[task.id]['real']
                if self.analysisTimes['parsing_tasks_times']['cpu_time']['maximum'] < parsingTimes[task.id]['cpu']:
                    self.analysisTimes['parsing_tasks_times']['cpu_time']['maximum'] = parsingTimes[task.id]['cpu']
                if self.analysisTimes['parsing_tasks_times']['real_time']['minimum'] == 0.0 or self.analysisTimes['parsing_tasks_times']['real_time']['minimum'] > parsingTimes[task.id]['real']:
                    self.analysisTimes['parsing_tasks_times']['real_time']['minimum'] = parsingTimes[task.id]['real']
                if self.analysisTimes['parsing_tasks_times']['cpu_time']['minimum'] == 0.0 or self.analysisTimes['parsing_tasks_times']['cpu_time']['minimum'] > parsingTimes[task.id]['cpu']:
                    self.analysisTimes['parsing_tasks_times']['cpu_time']['minimum'] = parsingTimes[task.id]['cpu']

        self.analysisTimes['execution_tasks_times']['cpu_time']['mean'] = self.analysisTimes['execution_tasks_times']['cpu_time']['sum'] / max(len(execTimes.keys()), 1)
        self.analysisTimes['execution_tasks_times']['real_time']['mean'] = self.analysisTimes['execution_tasks_times']['real_time']['sum'] / max(len(execTimes.keys()), 1)
        self.analysisTimes['parsing_tasks_times']['cpu_time']['mean'] = self.analysisTimes['parsing_tasks_times']['cpu_time']['sum'] / max(len(parsingTimes.keys()), 1)
        self.analysisTimes['parsing_tasks_times']['real_time']['mean'] = self.analysisTimes['parsing_tasks_times']['real_time']['sum'] / max(len(parsingTimes.keys()), 1)

        self.analysisTimes['total_times']['cpu_time']['sum'] = self.analysisTimes['execution_tasks_times']['cpu_time']['sum'] + self.analysisTimes['parsing_tasks_times']['cpu_time']['sum']
        self.analysisTimes['total_times']['real_time']['sum'] = self.analysisTimes['execution_tasks_times']['real_time']['sum'] + self.analysisTimes['parsing_tasks_times']['real_time']['sum']
        self.analysisTimes['total_times']['cpu_time']['mean'] = self.analysisTimes['total_times']['cpu_time']['sum'] / max(len(self.completedTasks.keys()), 1)
        self.analysisTimes['total_times']['real_time']['mean'] = self.analysisTimes['total_times']['real_time']['sum'] / max(len(self.completedTasks.keys()), 1)


    def displayAnalysisTimes(self):
        self.logger.info("Analysis timings report (seconds):  minimum    maximum       mean        sum")
        self.logger.info("Execution (real time taken):       %s" % '   '.join("%8d" % value for value in self.analysisTimes['execution_tasks_times']['real_time'].values()))
        self.logger.info("Execution (CPU time used):         %s" % '   '.join("%8d" % value for value in self.analysisTimes['execution_tasks_times']['cpu_time'].values()))
        self.logger.info("Parsing (real time taken):         %s" % '   '.join("%8d" % value for value in self.analysisTimes['parsing_tasks_times']['real_time'].values()))
        self.logger.info("Parsing (CPU time used):           %s" % '   '.join("%8d" % value for value in self.analysisTimes['parsing_tasks_times']['cpu_time'].values()))
        self.logger.info("Total (real time taken):                                 %s" % '   '.join("%8d" % value for value in self.analysisTimes['total_times']['real_time'].values()))
        self.logger.info("Total (CPU time used):                                   %s" % '   '.join("%8d" % value for value in self.analysisTimes['total_times']['cpu_time'].values()))


    def moveBlastResultsForWhichExonerateExists(self):
        if not Utils.isExistingDirectory(os.path.join(self.mainExecDirFullPath, TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['blast_files'])):
            os.mkdir(os.path.join(self.mainExecDirFullPath, TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['blast_files']))
        blastGffFolder = os.path.join(self.mainExecDirFullPath, TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['blast_files'], TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['GFF_files'])
        blastEmblFolder = os.path.join(self.mainExecDirFullPath, TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['blast_files'], TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['EMBL_files'])
        if not Utils.isExistingDirectory(blastGffFolder):
            os.mkdir(blastGffFolder)
        if not Utils.isExistingDirectory(blastEmblFolder):
            os.mkdir(blastEmblFolder)

        if Utils.isExistingDirectory(os.path.join(self.mainExecDirFullPath, TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['GFF_files'])):
            pattern = "%s/*BLAST*.gff" % ( os.path.join(self.mainExecDirFullPath, TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['GFF_files']) )
            fileNamePattern = re.compile("(?P<id>\d+)(_BESTHIT)?_BLAST[XPN]_(?P<db>.+)\.gff")
            for file in glob.glob( pattern ):
                fileName = os.path.basename(file)
                match = fileNamePattern.match(fileName)
                if match is not None:
                    exonerateFileName = "%s_EXONERATE_%s.gff" % ( match.group('id'), match.group('db') )
                    if os.path.isfile(os.path.join(self.mainExecDirFullPath, TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['GFF_files'], exonerateFileName)):
                        shutil.move(file, os.path.join(blastGffFolder, fileName))

        if Utils.isExistingDirectory(os.path.join(self.mainExecDirFullPath, TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['EMBL_files'])):
            pattern = "%s/*BLAST*.embl" % ( os.path.join(self.mainExecDirFullPath, TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['EMBL_files']) )
            fileNamePattern = re.compile("(?P<id>\d+)(_BESTHIT)?_BLAST[XPN]_(?P<db>.+)\.embl")
            for file in glob.glob( pattern ):
                fileName = os.path.basename(file)
                match = fileNamePattern.match(fileName)
                if match is not None:
                    exonerateFileName = "%s_EXONERATE_%s.embl" % ( match.group('id'), match.group('db') )
                    if os.path.isfile(os.path.join(self.mainExecDirFullPath, TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['EMBL_files'], exonerateFileName)):
                        shutil.move(file, os.path.join(blastEmblFolder, fileName))


    def clean( self ):
        if self.pipelineAborted and TriAnnotConfig.TRIANNOT_CONF['Global']['cleanAtTheEnd']['doNotCleanFilesOnFailure'].lower() == 'yes':
            return

        lFileToRemove = []
        lFolderToRemove = []

        if (TriAnnotConfig.TRIANNOT_CONF['Global']['cleanAtTheEnd']['launcherFiles'].lower() == 'yes' and TriAnnotConfig.TRIANNOT_CONF['Global']['cleanAtTheEnd']['stdoutFiles'].lower() == 'yes' and TriAnnotConfig.TRIANNOT_CONF['Global']['cleanAtTheEnd']['stderrFiles'].lower() == 'yes'):
            if Utils.isExistingDirectory(TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['launcher_files']):
                lFolderToRemove.append(TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['launcher_files'])
        else:
            if TriAnnotConfig.TRIANNOT_CONF['Global']['cleanAtTheEnd']['launcherFiles'].lower() == 'yes':
                pattern = "%s/%s*.py" % ( TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['launcher_files'], self.uniqueIdentifier )
                lFileToRemove.extend(glob.glob( pattern ))
            if TriAnnotConfig.TRIANNOT_CONF['Global']['cleanAtTheEnd']['stdoutFiles'].lower() == 'yes':
                pattern = "%s/%s*.o*" % ( TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['launcher_files'], self.uniqueIdentifier )
                lFileToRemove.extend(glob.glob( pattern ))
            if TriAnnotConfig.TRIANNOT_CONF['Global']['cleanAtTheEnd']['stderrFiles'].lower() == 'yes':
                pattern = "%s/%s*.e*" % ( TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['launcher_files'], self.uniqueIdentifier )
                lFileToRemove.extend(glob.glob( pattern ))

        if TriAnnotConfig.TRIANNOT_CONF['Global']['cleanAtTheEnd']['tmpFolders'].lower() == 'yes' and not TriAnnotConfig.TRIANNOT_CONF['Global']['cleanAtTheEnd']['commonFilesFolder'].lower() == 'yes':
            if Utils.isExistingDirectory(TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['tmp_files']):
                pattern = "%s/*" % ( TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['tmp_files'])
                for file in glob.glob( pattern ):
                    if os.path.islink(file):
                        path = os.readlink(file)
                        os.unlink(file)
                        shutil.move(path, file)

        if TriAnnotConfig.TRIANNOT_CONF['Global']['cleanAtTheEnd']['tmpFolders'].lower() == 'yes':
            pattern = "???_*_execution"
            lFolderToRemove.extend(glob.glob( pattern ))
            pattern = "???_*_parsing"
            lFolderToRemove.extend(glob.glob( pattern ))
        if TriAnnotConfig.TRIANNOT_CONF['Global']['cleanAtTheEnd']['commonFilesFolder'].lower() == 'yes':
            if Utils.isExistingDirectory(TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['tmp_files']):
                lFolderToRemove.append(TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['tmp_files'])

        if TriAnnotConfig.TRIANNOT_CONF['Global']['cleanAtTheEnd']['summaryFilesFolder'].lower() == 'yes':
            if Utils.isExistingDirectory(TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['summary_files']):
                lFolderToRemove.append(TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['summary_files'])

        if TriAnnotConfig.TRIANNOT_CONF['Global']['cleanAtTheEnd']['logFilesFolder'].lower() == 'yes':
            if Utils.isExistingDirectory(TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['log_files']):
                lFolderToRemove.append(TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['log_files'])

        for file in lFileToRemove:
            os.remove(file)
        for folder in lFolderToRemove:
            shutil.rmtree(folder)


    def createTriAnnotFinishedFile(self):
        # Initializations
        finishedFileHandler = None
        finishedFileFullPath = os.path.join(self.mainExecDirFullPath, 'TriAnnot_finished')

        # Try to create a file handler for the TriAnnot_finished file
        try:
            finishedFileHandler = open(finishedFileFullPath, 'w')
        except IOError:
            self.logger.error("%s could not create the following XML file: %s" % (self.programName, finishedFileFullPath))
            raise

        # Add content to the XML file (Note: the with statement allow auto-closing of the file)
        with finishedFileHandler:

            #  Build the root of the XML file
            xmlRoot = etree.Element('unit_result', {'triannot_version': TRIANNOT_VERSION, 'description': self.taskFileDescription})

            # Create standalone sub elements
            startDateElement = etree.SubElement(xmlRoot, 'start_date')
            startDateElement.text = self.humanlyReadableStartDate

            analysisStatusElement = etree.SubElement(xmlRoot, 'status')
            analysisStatusElement.text = TriAnnotStatus.getStatusName(self.analysisStatus)

            endDateElement = etree.SubElement(xmlRoot, 'end_date')
            endDateElement.text = self.humanlyReadableEndDate

            totalElapsedTimeElement = etree.SubElement(xmlRoot, 'total_elapsed_time')
            totalElapsedTimeElement.text = self.totalElapsedTime

            commandLineElement = etree.SubElement(xmlRoot, 'command_line')
            commandLineElement.text = self.commandLine

            # Automatic creation of sub elements to write all the analysis times (Real/CPU time for Execution/Parsing/all tasks)
            if self.analysisTimes is not None:
                if self.analysisStatus == TriAnnotStatus.ERROR:
                    xmlRoot.append(etree.Comment('Warning: The statistics recovery procedure does not take into consideration the data of the failed and canceled tasks'))
                    xmlRoot.append(etree.Comment("Since the current analysis status is <%s> then the following data are underestimated" % TriAnnotStatus.getStatusName(self.analysisStatus)))
                for timeCategory in self.analysisTimes.keys():
                    timeCategoryElement = etree.SubElement(xmlRoot, timeCategory)
                    for timeType in self.analysisTimes[timeCategory].keys():
                        timeTypeElement = etree.SubElement(timeCategoryElement, timeType)
                        for timeSubType in self.analysisTimes[timeCategory][timeType].keys():
                            timeSubTypeElement = etree.SubElement(timeTypeElement, timeSubType)
                            timeSubTypeElement.text = str(self.analysisTimes[timeCategory][timeType][timeSubType])

            # Indent the XML content
            TriAnnotConfig.indent(xmlRoot)

            # Write the generated XML content
            finishedFileHandler.write(etree.tostring(xmlRoot, 'ISO-8859-1'))


###################
##   Main code   ##
###################

# This code block will only be executed if TriAnnotUnit.py is called as a script (ie. it will not be executed if the TriAnnotUnit class is just imported by another module)

if __name__ == "__main__":

    # Creation of the main object
    myTriAnnotUnit = TriAnnotUnit()

    # Execution of the main method
    myTriAnnotUnit.main()

    # Closing the logging system
    logging.shutdown()
