#!/usr/bin/env python

import os
import logging
from collections import OrderedDict
import xml.etree.cElementTree as etree

from TriAnnot.TriAnnotConfig import *
from TriAnnot.TriAnnotVersion import TRIANNOT_VERSION
from TriAnnot.TriAnnotTaskParameters import *
from TriAnnot.TriAnnotConfigurationChecker import *
import Utils

# Debug
#import pprint
#pp = pprint.PrettyPrinter(indent=4)


class TriAnnotTaskFileChecker (object):
    # Class variables initializations
    allTaskParametersObjects = OrderedDict()

    #####################
    ###  Constructor  ###
    #####################
    def __init__(self, taskFileFullPath):
        # Logger
        self.logger = logging.getLogger("TriAnnot.TriAnnotTaskFileChecker")
        self.logger.addHandler(logging.NullHandler())

        self.logger.debug("Creating a new %s object" % (self.__class__.__name__))

        # Attributes
        self.bypassSyntaxValidation = False
        self.taskFileFullPath = taskFileFullPath
        self.taskFileName = None
        self.numberOfTasks = 0
        self.allTasksSequences = {}
        self.allTasksTypes = {}

        # Initial checks
        self.checkTaskFileExistence()
        self.checkIfXmlSyntaxCanBeControled()

        # Errors list
        self.xmlSyntaxErrors = None
        self.taskFileLoadingErrors = None
        self.notAvailableTools = None
        self.tasksSequenceErrors = None
        self.invalidDependencies = None
        self.invalidParameters = None

        # Hardcoded list of valid wildcard dependence:
        self.validWildcards = ['above', 'idem_above', 'all_above']


    ###################################
    ###  Task file existence check  ###
    ###################################
    def checkTaskFileExistence(self):
        if not Utils.isExistingFile(self.taskFileFullPath):
            raise RuntimeError("The following step/task file does not exist or is not readable: %s" % self.taskFileFullPath)
        else:
            self.taskFileName = os.path.basename(self.taskFileFullPath)


    ############################
    ###  Tools availability  ###
    ############################
    def checkIfXmlSyntaxCanBeControled(self):
        # Activate the bypass if XMLlint is not available
        if not Utils.isXmllintAvailable():
            self.bypassSyntaxValidation = True
            self.logger.warning("XMLlint is not available on your system ! TriAnnot will not be able to validate the syntax of the XML configuration files from their XML schemas !")


    ###############################
    ###  XML syntax validation  ###
    ###############################
    def checkTaskFileXmlSyntax(self):
        # Initializations
        self.xmlSyntaxErrors = []

        self.logger.info('The XML syntax of the step/task file will now be checked')

        if self.bypassSyntaxValidation:
            self.logger.warning('Bypassing XML syntax validation (XMLlint is not installed)')
        else:
            # Get the XML schema file
            xmlSchemaFullPath = Utils.determineXMLSchemaPath('TriAnnotTasks.xsd')

            if xmlSchemaFullPath is not None:
                # Run xmllint to check the syntax of the step/task file
                self.logger.debug("Checking file <%s>" % self.taskFileName)

                try:
                    cmd = ['xmllint', '--noout', '--schema', xmlSchemaFullPath, self.taskFileFullPath]
                    validationResult = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT).communicate()[0]
                    pattern = re.compile(self.taskFileName + ' validates')
                    if not pattern.search(validationResult):
                        self.xmlSyntaxErrors.append(validationResult)
                except:
                    self.logger.debug(traceback.format_exc())
                    raise RuntimeError("An unexpected error occured during the syntax validation procedure of the following step/task file: %s" % self.taskFileFullPath)
            else:
                self.logger.warning('Bypassing XML syntax validation (XML schema is missing)')


    def displayXmlSyntaxErrors(self):
        # Errors can be displayed if they haven't been collected
        if self.xmlSyntaxErrors is None:
            self.logger.warning("XML syntax errors can't be listed if they haven't been collected")
            return 1

        # Display XML syntax errors for each tool
        if len(self.xmlSyntaxErrors) > 0:
            self.logger.info("There is at least one syntax error in your step/task file")
            self.logger.info('Please fix every error described below before executing TriAnnot again !')
            for error in self.xmlSyntaxErrors:
                self.logger.error("Error(s) reported by XMLlint:")
                self.logger.error("\n****************************************\n%s****************************************" % error)
        else:
            self.logger.info('No syntax error has been detected')

        return 0


    ################################
    ###  Step/Task file loading  ###
    ################################
    def loadTaskFile(self):
        # Initialization & Log
        self.taskFileLoadingErrors = dict()
        self.nbTaskFileLoadingErrors = 0

        self.logger.info('The step/task file will now be loaded')

        # Create a new xml.etree.ElementTree object
        self.xmlTree = etree.parse(self.taskFileFullPath)

        # Get the description and version of the step/task file
        xmlRoot = self.xmlTree.getroot()

        self.taskFileTriAnnotVersion = xmlRoot.get('triannot_version', None)
        if self.taskFileTriAnnotVersion is None:
            raise AssertionError("The <triannot_version> attribute is missing in the <analysis> tag of your step/task file")

        self.taskFileDescription = xmlRoot.get('description', None)

        # Analyse each program block/tag to collect the parameters and dependencies of each task
        self.analyzeProgramBlocks()

        if self.numberOfTasks == 0:
            raise AssertionError("There is no <program> tag in your step/task file")

        self.displayStepFileDescription()


    def analyzeProgramBlocks(self):
        # Initializations
        previousTaskId = None

        # Load the content of each program tag (1 tag described a task to run)
        for programBlock in self.xmlTree.iter(tag='program'):
            # Get basic information on the current task
            taskType = programBlock.get('type', None)
            taskId = int(programBlock.get('id'))

            if previousTaskId is not None and previousTaskId > taskId:
                raise AssertionError("The numeric identifiers of the tasks/programs must be used in ascending order ! Task #%s can't follow task #%s.." % (taskId, previousTaskId))

            # Creation of a TriAnnoTaskParameters object
            newTaskParametersObject = TriAnnotTaskParameters(taskId, taskType)

            # Collect parameters and dependencies
            self.taskFileLoadingErrors[taskId] = newTaskParametersObject.retrieveTaskParameters(programBlock)
            self.taskFileLoadingErrors[taskId].extend(newTaskParametersObject.retrieveTaskDependencies(programBlock, self.validWildcards, self.numberOfTasks))

            # Add the current task sequence to the list of input sequences
            if newTaskParametersObject.taskSequence not in self.allTasksSequences.keys():
                self.allTasksSequences[newTaskParametersObject.taskSequence] = {'nbOccurence': 0, 'Occurences': []}
            self.allTasksSequences[newTaskParametersObject.taskSequence]['nbOccurence'] += 1
            self.allTasksSequences[newTaskParametersObject.taskSequence]['Occurences'].append(taskId)

            # Store some data about the tasks
            if taskType not in self.allTasksTypes.keys():
                self.allTasksTypes[taskType] = {'nbOccurence': 0, 'Occurences': []}
            self.allTasksTypes[taskType]['nbOccurence'] += 1
            self.allTasksTypes[taskType]['Occurences'].append(taskId)

            # Store the current TaskParameters object in a class variable
            TriAnnotTaskFileChecker.allTaskParametersObjects[taskId] = newTaskParametersObject

            # Update counters
            self.numberOfTasks += 1
            previousTaskId = taskId
            self.nbTaskFileLoadingErrors += len(self.taskFileLoadingErrors[taskId])


    def displayStepFileDescription(self):
        if self.taskFileDescription is not None:
            self.logger.info("Step/Task file description: <%s>" % self.taskFileDescription)
        self.logger.info("Step/Task file has been created for TriAnnot version <%s>" % self.taskFileTriAnnotVersion)
        self.logger.info("Number of task described in the step/task file: %s" % self.numberOfTasks)


    def displayTaskFileLoadingErrors(self):
        # Errors can be displayed if they haven't been collected
        if self.taskFileLoadingErrors is None:
            self.logger.warning("Task file loading errors can't be displayed until it has been collected")
            return 1

        # Display the list of loading errors
        if self.nbTaskFileLoadingErrors > 0:
            self.logger.info("Total number of errors detected during the initial loading of the step/task file: %d !" % self.nbTaskFileLoadingErrors)
            self.logger.info('Please fix all the errors described below before running TriAnnot again !')
            for taskId, listOfLoadingErrors in self.taskFileLoadingErrors.items():
                if len(listOfLoadingErrors) > 0:
                    self.logger.error("Loading errors for task %s:" % TriAnnotTaskFileChecker.allTaskParametersObjects[taskId].taskDescription)
                    for loadingError in listOfLoadingErrors:
                        self.logger.error(loadingError)
        else:
            self.logger.info('The step/task file has been loaded successfully')

        return 0


    #############################
    ###  Attributes checking  ###
    #############################
    def isMadeForCurrentTriAnnotVersion(self, expectedVersion = TRIANNOT_VERSION):
        if self.taskFileTriAnnotVersion != expectedVersion:
            return False
        else:
            return True


    ############################
    ###  Check program list  ###
    ############################
    def checkToolsAvailability(self):
        # Initializations
        self.notAvailableTools = dict()
        self.nbNotAvailableTools = 0

        self.logger.info('The availability of the tools referenced in the step/task file will now be checked')

        # Check if the type of each program correspond to the name of an available tool
        for taskType in self.allTasksTypes.keys():
            # A tool is available if it possess a valid and activated configuration file
            if not TriAnnotConfig.TRIANNOT_CONF.has_key(taskType):
                if self.notAvailableTools.has_key(taskType):
                    self.notAvailableTools[taskType] += 1
                else:
                    self.notAvailableTools[taskType] = 1
                    self.nbNotAvailableTools += 1


    def displayNotAvailableTools(self):
        # Errors can be displayed if they haven't been collected
        if self.notAvailableTools is None:
            self.logger.warning("The list of unavailable tools can't be displayed until it has been collected")
            return 1

        # Display the list of unavailable tools
        if self.nbNotAvailableTools > 0:
            self.logger.info("Total number of unavailable tools referenced in the step/task file: %d !" % self.nbNotAvailableTools)
            self.logger.info('Please remove the following tools from your step/task file or update your configuration before running TriAnnot again !')
            for programName, numberOfOccurence in self.notAvailableTools.items():
                self.logger.error("Program <%s> is not available (Number of occurence: %d)" % (programName, numberOfOccurence))
        else:
            self.logger.info('All the tools referenced in the step/task file are available')

        return 0


    ###############################################
    ###  Check the input sequences of the tasks ###
    ###############################################
    def checkTasksSequences(self, executionDirectory):
        # Initializations & Log
        self.tasksSequenceErrors = []
        self.nbTasksSequenceErrors = 0

        self.logger.info('The validity of the sequences used along the step/task file will now be checked')

        for sequence in self.allTasksSequences:
            if sequence == 'initial':
                # Nothing to do here, the -s/--sequence option is mandatory
                continue
            elif TriAnnotTaskParameters.generatedSequencesTaskId.has_key(sequence):
                # Check if a task don't try to use a sequence before its creation by another task
                for occurence in self.allTasksSequences[sequence]['Occurences']:
                    if occurence < TriAnnotTaskParameters.generatedSequencesTaskId[sequence]['taskIdentifier']:
                        self.tasksSequenceErrors.append("Task #%s wants to use the <%s> sequence that will not be available at this time of the analysis pipeline (It will be generated later on by task #%s)" % (occurence, sequence, TriAnnotTaskParameters.generatedSequencesTaskId[sequence]['taskIdentifier']))
                    else:
                        continue
            else:
                # If the sequence is not the initial sequence file or a sequence file generated by another step..
                # ..then we check if it already exist in the "Sequences" directory
                if not Utils.isExistingFile(os.path.join(executionDirectory, TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['sequence_files'], sequence)):
                    self.tasksSequenceErrors.append("The following tasks wants to use the <%s> sequence that is not generated by another step or already presents in the <%s> directory: %s" % (sequence, TriAnnotConfig.TRIANNOT_CONF['DIRNAME']['sequence_files'], ', '.join(str(taskId) for taskId in self.allTasksSequences[sequence]['Occurences'])))

        self.nbTasksSequenceErrors = len(self.tasksSequenceErrors)


    def displayTasksSequenceErrors(self):
        # Errors can be displayed if they haven't been collected
        if self.tasksSequenceErrors is None:
            self.logger.warning("Sequence errors can't be listed if they haven't been collected")
            return 1

        # Display the list of sequence errors
        if self.nbTasksSequenceErrors > 0:
            self.logger.info("Total number of missing or invalid input sequences: %d !" % self.nbTasksSequenceErrors)
            self.logger.info('Please check and update your step/task file before executing TriAnnot again !')
            for sequenceError in self.tasksSequenceErrors:
                self.logger.error(sequenceError)
        else:
            self.logger.info('All the sequences referenced in the step/task file already exists or will be generated on time')

        return 0


    #########################################
    ###  Special dependencies management  ###
    #########################################
    def manageSpecialDependencies(self):
        # Initializations
        alreadyUpdatedTasks = []
        nbOfSpecialDependencies = 0

        self.logger.info('Special non numeric dependencies will now be replaced')

        # Loop through the list of task
        for taskId, taskObject in TriAnnotTaskFileChecker.allTaskParametersObjects.items():

            # Loop through the list of special dependencies ('above', 'idem_above', etc.) and replace them by numeric dependencies
            for dependenceId, dependenceType in taskObject.specialDependencies.items():
                nbOfSpecialDependencies += 1

                if len(alreadyUpdatedTasks) == 0:
                    raise AssertionError("A wildcard dependence <%s> has been found for task #%s but there is no task above this one in step/task file" % (dependenceId, taskId))
                else:
                    self.logger.debug("Replacing the <%s> wildcard dependence for task %s" % (dependenceId, taskObject.taskDescription))
                    if dependenceId == 'above':
                        TriAnnotTaskFileChecker.addDependenceToExistingTask(taskId, alreadyUpdatedTasks[-1], TriAnnotTaskFileChecker.allTaskParametersObjects[alreadyUpdatedTasks[-1]].taskType)
                    elif dependenceId == 'all_above':
                        for previousTaskId in alreadyUpdatedTasks:
                            TriAnnotTaskFileChecker.addDependenceToExistingTask(taskId, previousTaskId, TriAnnotTaskFileChecker.allTaskParametersObjects[previousTaskId].taskType)
                    elif dependenceId == 'idem_above':
                        for previousTaskDepId, previousTaskDepType in TriAnnotTaskFileChecker.allTaskParametersObjects[alreadyUpdatedTasks[-1]].dependencies.items():
                            TriAnnotTaskFileChecker.addDependenceToExistingTask(taskId, previousTaskDepId, previousTaskDepType)

            # If the sequence file of the current task is generated during the pipeline execution (Example: SequenceMasker)..
            # ..then we need to update the list of dependencies for the current task
            if TriAnnotTaskParameters.generatedSequencesTaskId.has_key(taskObject.taskSequence):
                TriAnnotTaskFileChecker.addDependenceToExistingTask(taskId, TriAnnotTaskParameters.generatedSequencesTaskId[taskObject.taskSequence]['taskIdentifier'], TriAnnotTaskParameters.generatedSequencesTaskId[taskObject.taskSequence]['generatedBy'])

            alreadyUpdatedTasks.append(taskId)

        self.logger.info("All special non numeric dependencies have been replaced (%d replacement)" % nbOfSpecialDependencies)


    @staticmethod
    def addDependenceToExistingTask(taskId, dependenceId, dependenceType = None):
        TriAnnotTaskFileChecker.allTaskParametersObjects[taskId].dependencies[int(dependenceId)] = dependenceType


    #########################################
    ###  Check the full dependence lists  ###
    #########################################
    def checkAllTasksDependencies(self):
        # Initializations
        self.invalidDependencies = dict()
        self.nbInvalidDependencies = 0

        self.logger.info('The validity of each task\'s dependencies will now be checked')

        # Loop through the list of task
        for taskId, taskObject in TriAnnotTaskFileChecker.allTaskParametersObjects.items():

            if not self.invalidDependencies.has_key(taskObject.taskDescription):
                self.invalidDependencies[taskObject.taskDescription] = []

            # Loop through the list of dependencies of each task
            for dependenceId, dependenceType in taskObject.dependencies.items():
                # Dependence to a task that does not exist in the step/task file
                if not dependenceId in TriAnnotTaskFileChecker.allTaskParametersObjects.keys():
                    self.invalidDependencies[taskObject.taskDescription].append("Task #%s depends on task #%s which is not defined in the step/task file" % (taskId, dependenceId))
                    self.nbInvalidDependencies += 1
                else:
                    # Wrong type of dependence
                    if dependenceType is not None and dependenceType != TriAnnotTaskFileChecker.allTaskParametersObjects[dependenceId].taskType:
                        self.invalidDependencies[taskObject.taskDescription].append("Task #%s depends on task #%s but the types does not match. The type of the dependence is set to <%s> but the type of task #%s is <%s>" % (taskId, dependenceId, dependenceType, dependenceId, TriAnnotTaskFileChecker.allTaskParametersObjects[dependenceId].taskType))
                        self.nbInvalidDependencies += 1

                    # Circular dependences
                    if taskId in TriAnnotTaskFileChecker.allTaskParametersObjects[dependenceId].dependencies:
                        self.invalidDependencies[taskObject.taskDescription].append("A circular dependency has been detected between task #%s and task #%s" % (taskId, dependenceId))
                        self.nbInvalidDependencies += 1


    def displayInvalidDependencies(self):
        # Errors can be displayed if they haven't been collected
        if self.invalidDependencies is None:
            self.logger.warning("Invalid dependencies can't be listed if they haven't been collected")
            return 1

        # Display the list of badly defined parameters
        if self.nbInvalidDependencies > 0:
            self.logger.info("Total number of invalid dependencies in your step/task file: %d !" % self.nbInvalidDependencies)
            self.logger.info('Please double check the dependencies of all your tasks before running TriAnnot again !')
            for taskIdentifier, invalidDependencies in self.invalidDependencies.items():
                if len(invalidDependencies) > 0:
                    self.logger.error("Invalid dependencies for task %s:" % taskIdentifier)
                    for invalidDependence in invalidDependencies:
                        self.logger.error(invalidDependence)
        else:
            self.logger.info("All task\'s dependencies seems to be valid")

        return 0


    ###########################################
    ###  Check the parameters of the tasks  ###
    ###########################################
    def checkAllTasksParameters(self):
        # Initializations
        self.invalidParameters = dict()
        self.nbInvalidParameters = 0

        self.logger.info('The validity of each task\'s parameters will now be checked')

        # Loop through the list of task
        for taskId, taskObject in TriAnnotTaskFileChecker.allTaskParametersObjects.items():
            # Check all the parameters of the current task one by one
            self.invalidParameters[taskObject.taskDescription] = taskObject.checkTaskParameters()

            # Some ultimate checks must be made if no error have been detected so far
            if len(self.invalidParameters[taskObject.taskDescription]) == 0:
                # The basic tests of the database-like parameters (ConfigEntry) made in the checkTaskParameters() method lacks of accuracy in some specific case (because parameters are treated independently)
                # For example, if an Exonerate task require the TAEugs database and if this database exists in either NucleicBlast OR ProteicBlast format then checkTaskParameters() does not return any error
                # However, the Exonerate task possess a "queryType" parameter that defines if the database must be nucleic or proteic
                # So, by using this information, we can return an error if the TAEugs is only in nucleic format when the "queryType" parameter is set to "protein"
                self.invalidParameters[taskObject.taskDescription].extend(taskObject.deeperDatabaseCompatibilityCheck())

                # Now that we know that the existing parameters (used in the step/task file) are Ok and that the configuration is Ok
                # We can add the default parameters to the list of parameters of the current task
                # In the process, special keywords (Ex: {step}) that are present in all parameters that have a needSubstitution attribute can be replaced by their real value
                taskObject.updateListOfParameters()
                if taskObject.nbSubstitutionErrors > 0:
                    self.invalidParameters[taskObject.taskDescription].extend(taskObject.substitutionErrors)

            self.nbInvalidParameters += len(self.invalidParameters[taskObject.taskDescription])


    def displayInvalidParameters(self):
        # Errors can be displayed if they haven't been collected
        if self.invalidParameters is None:
            self.logger.warning("Errors of parameterization can't be listed if they haven't been collected")
            return 1

        # Display the list of badly defined parameters
        if self.nbInvalidParameters > 0:
            self.logger.info("Total number of detected errors in your tasks parameters: %d !" % self.nbInvalidParameters)
            self.logger.info('Please double check the values of your tasks parameters before running TriAnnot again !')
            for taskIdentifier, invalidParameters in self.invalidParameters.items():
                if len(invalidParameters) > 0:
                    self.logger.error("Invalid parameters for task %s:" % taskIdentifier)
                    for invalidParameter in invalidParameters:
                        self.logger.error(invalidParameter)
        else:
            self.logger.info("All task\'s parameters seems to be valid")

        return 0


    ###################################################
    ###  Global/Merged configuration file creation  ###
    ###################################################
    @staticmethod
    def generateFullTaskFile(destinationDirectory, triAnnotVersion, originalDescription, overwriteExistingFile = False):
        # Initializations
        filePrefix = 'TriAnnot_full_taskfile'
        fileSuffix = ''
        configurationFile = None
        cpt = 1
        if originalDescription is None:
            originalDescription = ''

        # Do not overwrite the existing global file if requested
        if not overwriteExistingFile:
            while os.path.exists(os.path.join(destinationDirectory, filePrefix + fileSuffix + '.xml')):
                fileSuffix = '_%s' % cpt
                cpt += 1

        # Creation of the merged file
        fullTaskFileFullPath = os.path.join(destinationDirectory, filePrefix + fileSuffix + '.xml')
        TriAnnotConfig.logger.info("Creation of a full XML step/task file containg both custom and default parameters for each task: %s" % (fullTaskFileFullPath))

        try:
            # Create handler
            taskFileHandler = open(fullTaskFileFullPath, 'w')

            #  Build the root of the XML file
            analysisRoot = etree.Element('analysis', {'triannot_version': triAnnotVersion, 'description': originalDescription + ' (full)'})

            # Loop through the task list to build the <program> blocks/elements
            for taskId, taskObject in TriAnnotTaskFileChecker.allTaskParametersObjects.items():
                # Create the program element
                programElement = etree.Element('program', {'id': str(taskObject.taskId), 'step': str(taskObject.taskStep), 'type': taskObject.taskType, 'sequence': taskObject.taskSequence})

                # Add dependencies
                TriAnnotTaskFileChecker.createDependenciesTags(programElement, taskObject.dependencies)

                # Create and add to the program tag/block all the parameter tags
                TriAnnotTaskFileChecker.createParameterTags(programElement, taskObject)

                # Add the full parent tag/block to the xml root
                analysisRoot.append(programElement)

            # Indent the XML content
            TriAnnotConfig.indent(analysisRoot)

            # Write the generated XML content
            taskFileHandler.write(etree.tostring(analysisRoot, 'ISO-8859-1'))
        except IOError:
            TriAnnotConfig.logger.error("Could not create the following global XML configuration file: %s" % (fullTaskFileFullPath))
            raise
        finally:
            if taskFileHandler is not None:
                taskFileHandler.close()
            else:
                fullTaskFileFullPath = None

        return fullTaskFileFullPath


    @staticmethod
    def createDependenciesTags(programTag, taskDependencies):
        # Create main tag
        if len(taskDependencies) > 0:
            dependenciesElement = etree.SubElement(programTag, 'dependences')

        # Create sub tags
        for dependenceId, dependenceType in taskDependencies.items():
            depenenceElement = etree.SubElement(dependenciesElement, 'dependence', {'id': str(dependenceId), 'type': dependenceType})


    @staticmethod
    def createParameterTags(programTag, taskObject):
        # Get the list of parameters definitions for the current type of task
        taskParametersDefinitions = TriAnnotConfigurationChecker.allParametersDefinitions[taskObject.taskType]

        # Create all "parameter" tag/block
        for parameterName in taskParametersDefinitions.keys():
            # Determine if the parameter can have multiple values
            isArrayBoolean = Utils.isDefinedAsIsArrayParameter(taskParametersDefinitions[parameterName])

            if taskObject.parameters.has_key(parameterName):
                # If the parameter have several values then we create a parameter tag/block for each of tem
                if type(taskObject.parameters[parameterName]) == list:
                    for value in taskObject.parameters[parameterName]:
                        parameterElement = etree.SubElement(programTag, 'parameter', {'name': parameterName})
                        parameterElement.text = value
                        if isArrayBoolean:
                            parameterElement.set('isArray', 'yes')
                else:
                    parameterElement = etree.SubElement(programTag, 'parameter', {'name': parameterName})
                    parameterElement.text = taskObject.parameters[parameterName]
                    if isArrayBoolean:
                        parameterElement.set('isArray', 'yes')
