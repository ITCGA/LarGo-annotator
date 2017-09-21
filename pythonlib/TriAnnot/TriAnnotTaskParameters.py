#!/usr/bin/env python

import os
import logging

from TriAnnot.TriAnnotConfigurationChecker import *
import Utils

class TriAnnotTaskParameters (object):

    # Class variables
    generatedSequencesTaskId = {}

    #########################
    ###    Constructor    ###
    #########################
    def __init__(self, taskId, taskType):
        # Logger
        self.logger = logging.getLogger("TriAnnot.TriAnnotTaskParameters")
        self.logger.addHandler(logging.NullHandler())

        #self.logger.debug("Creating a new %s object" % (self.__class__.__name__))

        # Attributes
        self.taskId = taskId
        self.taskType = taskType
        self.taskDescription = "%d (%s)" % (taskId, taskType)
        self.taskStep = None
        self.taskSequence = None

        # Get the definitions of all possible parameters for the current type of task
        self.parameters = {}
        self.dependencies = {}
        self.specialDependencies = {}

        # Hardcoded lists of special keywords for needSubstitution parameters
        self.specialKeywords = ['step', 'taskId']

        # Hardcoded list of valid parameter types
        self.validParameterTypes = ['string', 'number', 'boolean', 'configEntry']

        # Errors list
        self.substitutionErrors = None

        # Change class to a specialized subclass if there is one defined for the current task type
        for taskClass in TriAnnotTaskParameters.getAllSubClasses(TriAnnotTaskParameters):
            if taskClass.__name__ == self.taskType:
                self.__class__ = taskClass
                self.logger = logging.getLogger("TriAnnot.TaskParameters.%s" % self.__class__.__name__)
                self.logger.addHandler(logging.NullHandler())
                self.logger.debug("Creating a new %s TaskParameters object" % self.__class__.__name__)
                self.__init__()


    ########################
    ###  Static methods  ###
    ########################
    @staticmethod
    def getAllSubClasses(parentClass):
        classesList = []
        for subClass in parentClass.__subclasses__():
            classesList.append(subClass)
            if subClass.__subclasses__():
                classesList.extend(TriAnnotTaskParameters.getAllSubClasses(subClass))
        return classesList


    ###########################
    ###  Retrieval methods  ###
    ###########################
    def retrieveTaskParameters(self, xmlElt):
        # Initializations
        errorsList = []

        # Collect some basic data about the task
        self.taskStep = int(xmlElt.get('step'))
        self.taskSequence = xmlElt.get('sequence')

        # Collect all parameters
        for parameter in xmlElt.iter('parameter'):
            parameterName = parameter.get('name');

            # is this the first occurence of the current parameter for the current task ?
            if self.parameters.has_key(parameterName):
                if type(self.parameters[parameterName]) is list:
                    self.parameters[parameterName].append(parameter.text)
                else:
                    errorsList.append("Invalid parameter found: <%s> is not an isArray parameter and therefore can't be used more than once in the step/task file" % parameterName)
            else:
                # Two possible cases here:
                # 1) The current parameter is an isArray parameter and we must create and store an array
                #   A) We are in the main TriAnnotPipeline instance so we can check if the current parameter is an isArray parameter from the parameters definitions
                #   B) We are in a child TriAnnotPipeline instance so we can check if the current parameter is an isArray parameter directly from the isArray attribute
                # 2) The current parameter is not an isArray parameter an we only store a string
                if parameter.get('isArray') == 'yes' or Utils.isDefinedAsIsArrayParameterAlt(TriAnnotConfigurationChecker.allParametersDefinitions, self.taskType, parameterName):
                    self.parameters[parameterName] = [parameter.text]
                else:
                    self.parameters[parameterName] = parameter.text

        return errorsList


    def retrieveTaskDependencies(self, xmlElt, authorizedWildcards, actualNumberOfTask):
        # Initializations
        errorsList = []

        # Collect all dependencies
        for dependence in xmlElt.iter('dependence'):
            dependenceId = dependence.get('id', None)

            if dependenceId is None:
                errorsList.append("A dependence without identifier has been detected for task #%s !" % xmlElt.get('id'))
            elif dependenceId in authorizedWildcards:
                if actualNumberOfTask > 0:
                    self.specialDependencies[dependenceId] = dependence.get('type', None)
                else:
                    errorsList.append("A special above-like dependence has been detected for task #%s but there is no task above it !" % xmlElt.get('id'))
            else:
                self.dependencies[int(dependence.get('id'))] = dependence.get('type', None)

        return errorsList


    ##########################
    ###  Checking methods  ###
    ##########################
    def checkTaskParameters(self):
        # Initializations
        errorsList = []

        # Log
        self.logger.debug("Checking parameters for task #%s" % self.taskDescription)

        # Generate an error message for each unauthorized parameters (a parameter is invalid if it does not have a definition)
        for unauthorizedParameter in set(self.parameters.keys()).difference(TriAnnotConfigurationChecker.allParametersDefinitions[self.taskType].keys()):
            errorsList.append("Invalid parameter found: <%s> parameter can't be used for a <%s> task" % (unauthorizedParameter, self.taskType))

        # Loop through the list of possible parameters for the current type of task and check them
        for parameterName in TriAnnotConfigurationChecker.allParametersDefinitions[self.taskType].keys():
            parameterDefinition = TriAnnotConfigurationChecker.allParametersDefinitions[self.taskType][parameterName]

            if self.parameters.has_key(parameterName):
                if parameterDefinition['type'] not in self.validParameterTypes:
                    errorsList.append("Invalid parameter type found: <%s> parameter is defined as a <%s> parameter but this type of parameter is not valid (Possible types are: %s)" % (parameterName, parameterDefinition['type'], ', '.join(self.validParameterTypes)))
                else:
                    # Determine the appropriate check method based on the type of the parameter
                    appropriateCheckMethod = self.determineAppropriateCheckMethod(parameterDefinition['type'])

                    # Effective check for both mono-value and multi-value parameters
                    if type(self.parameters[parameterName]) is list:
                        for parameterValue in self.parameters[parameterName]:
                            if Utils.isEmptyValue(parameterValue):
                                errorsList.append("Empty parameter found: one of the occurence of the <%s> parameter has no value and parameters without value are not allowed" % parameterName)
                            else:
                                errorsList.extend(appropriateCheckMethod(parameterValue, parameterName, parameterDefinition))
                    else:
                        if Utils.isEmptyValue(self.parameters[parameterName]):
                            errorsList.append("Empty parameter found: <%s> parameter has no value and parameters without value are not allowed" % parameterName)
                        else:
                            errorsList.extend(appropriateCheckMethod(self.parameters[parameterName], parameterName, parameterDefinition))
            else:
                # The current parameter has not been used in the step/task file
                # We therefore need to check if it was an optional or a mandatory parameter
                if Utils.isDefinedAsMandatoryParameter(parameterDefinition):
                    possibleValuesMessage = ''
                    if parameterDefinition.has_key('possibleValues'):
                        possibleValuesMessage = "(Possible values are: %s)" % ', '.join(parameterDefinition['possibleValues'].values())
                    errorsList.append("Missing mandatory parameter found: <%s> parameter is defined as mandatory for each <%s> task but has not been used in the input step/task file %s" % (parameterName, self.taskType, possibleValuesMessage))

        return errorsList


    def determineAppropriateCheckMethod(self, parameterType):
        if parameterType == "string":
            return self.checkStringParameter
        elif parameterType == "number":
            return self.checkNumberParameter
        elif parameterType == "boolean":
            return self.checkBooleanParameter
        elif parameterType == "configEntry":
            return self.checkConfigEntryParameter


    def checkStringParameter(self, value, parameterName, parameterDefinition):
        errorsList = []
        if parameterDefinition.has_key('maxLength') and len(value) > int(parameterDefinition['maxLength']):
            errorsList.append("Invalid parameter found: <%s> must not exceed <%s> characters." % (parameterName, parameterDefinition['maxLength']))
        if parameterDefinition.has_key('minLength') and len(value) < int(parameterDefinition['minLength']):
            errorsList.append("Invalid parameter found: <%s> must contain at least <%s> characters." % (parameterName, parameterDefinition['minLength']))
        if parameterDefinition.has_key('validationRegex'):
            pattern = re.compile(parameterDefinition['validationRegex'])
            if not pattern.search(value):
                if parameterDefinition.has_key('invalidRegexMessage'):
                    errorsList.append("Invalid parameter found: %s" % (parameterDefinition['invalidRegexMessage']))
                else:
                    errorsList.append("Invalid parameter found: <%s> must match the following regex: %s" % (parameterName, parameterDefinition['validationRegex']))
        if parameterDefinition.has_key('possibleValues') and value not in parameterDefinition['possibleValues'].values():
            errorsList.append("Invalid parameter found: <%s> must be set to one of the following values: %s" % (parameterName, ', '.join(parameterDefinition['possibleValues'].values())))
        return errorsList


    def checkNumberParameter(self, value, parameterName, parameterDefinition):
        errorsList = []
        try:
            float(value)
        except ValueError, TypeError:
            errorsList.append("Invalid parameter found: <%s> must be set to a numeric value" % parameterName)
            return errorsList
        if parameterDefinition.has_key('maxValue') and float(value) > float(parameterDefinition['maxValue']):
            errorsList.append("Invalid parameter found: <%s> must be lower than <%s>" % (parameterName, parameterDefinition['maxValue']))
        if parameterDefinition.has_key('minValue') and float(value) < float(parameterDefinition['minValue']):
            errorsList.append("Invalid parameter found: <%s> must be greater than <%s>" % (parameterName, parameterDefinition['minValue']))
        if parameterDefinition.has_key('possibleValues'):
            isValueOk = False
            for possibleValue in parameterDefinition['possibleValues'].values():
                if float(value) == float(possibleValue):
                    isValueOk = True
                    break
            if not isValueOk:
                errorsList.append("Invalid parameter found: <%s> must be set to one of the following values: %s" % (parameterName, ', '.join(parameterDefinition['possibleValues'].values())))
        return errorsList


    def checkBooleanParameter(self, value, parameterName, parameterDefinition):
        errorsList = []
        if value != parameterDefinition['trueValue'] and value != parameterDefinition['falseValue'] :
            errorsList.append("Invalid parameter found: <%s> is a boolean value and must be set to <%s> or <%s>" % (parameterName, parameterDefinition['trueValue'], parameterDefinition['falseValue']))
        return errorsList


    def checkConfigEntryParameter(self, value, parameterName, parameterDefinition):
        # Initializations
        errorsList = []

        # Generate an error message if the value used in the step/task file does not belong to the list of
        if not value in parameterDefinition['possibleValues'].values():
            errorsList.append("Invalid parameter found: <%s> must be set to one of the following values: %s" % (parameterName, ', '.join(parameterDefinition['possibleValues'].values())))

        return errorsList


    # Abstract method
    def deeperDatabaseCompatibilityCheck(self):
        self.logger.debug("Abstract deeperDatabaseCompatibilityCheck method is called for task #%s" % self.taskDescription)

        # This is an abstract method that will just return an empty list of errors for all the tasks that don't require a deeper check of the database compatibility
        return []


    def updateListOfParameters(self):
        # Initializations
        self.substitutionErrors = []
        self.nbSubstitutionErrors = 0

        # Log
        self.logger.debug("The list of parameters for the current task will now be extended with the default parameters")
        self.logger.debug("Encapsulated keywords (like {step} for example) will now be replaced by real values")

        # Get the definitions of the parameters of the current type of task
        taskParametersDefinitions = TriAnnotConfigurationChecker.allParametersDefinitions[self.taskType]

        # Update the list of parameters for the current task - Several possible cases
        # 1) The parameter exists in the original step/task file and IS an isArray parameter according to the configuration --> Update - Replacement of special keywords (Ex: {step}) in each value
        # 2) The parameter exists in the original step/task file and IS NOT an isArray parameter according to the configuration --> Update - Replacement of special keywords (Ex: {step}) in the value)
        # 3) The parameter does not exists in the original step/task file but have SEVERAL default values in the corresponding tool's configuration file --> New parameter with multiple values (and keywords replaced)
        # 4) The parameter does not exists in the original step/task file but have one default value in the corresponding tool's configuration file --> New parameter with a single value (and keywords replaced)
        for parameterName in taskParametersDefinitions.keys():
            if self.parameters.has_key(parameterName):
                if type(self.parameters[parameterName]) == list:
                    for index, parameterValue in enumerate(self.parameters[parameterName]):
                        self.parameters[parameterName][index] = self.specialKeywordReplacement(parameterName, parameterValue, taskParametersDefinitions)
                else:
                    self.parameters[parameterName] = self.specialKeywordReplacement(parameterName, self.parameters[parameterName], taskParametersDefinitions)
            else:
                if taskParametersDefinitions[parameterName].has_key('defaultValue'):
                    if type(taskParametersDefinitions[parameterName]['defaultValue']) == dict:
                        self.parameters[parameterName] = []
                        for elementValue in taskParametersDefinitions[parameterName]['defaultValue'].values():
                            self.parameters[parameterName].append(self.specialKeywordReplacement(parameterName, elementValue, taskParametersDefinitions))
                    else:
                        self.parameters[parameterName] = self.specialKeywordReplacement(parameterName, taskParametersDefinitions[parameterName]['defaultValue'], taskParametersDefinitions)

        self.nbSubstitutionErrors = len(self.substitutionErrors)


    def specialKeywordReplacement(self, parameterName, initialParameterValue, taskParametersDefinitions):
        # Initializations
        updatedValue = initialParameterValue

        # Special case - Override of the number of thread to use for EVERY multithread capable tools/tasks if needed
        if parameterName == 'nbCore' and TriAnnotConfig.TRIANNOT_CONF['Runtime'].has_key('multiThreadOverride'):
            updatedValue = TriAnnotConfig.TRIANNOT_CONF['Runtime']['multiThreadOverride']

        # Determine if the parameter's value need a sting substitution (ie. a replacement of {element} substrings)
        needSubstitution = Utils.doesParameterNeedSubstitution(taskParametersDefinitions[parameterName])

        # If the parameter can contain a {keyword} to replace we have to check its validity
        if needSubstitution:
            # Build regexp pattern
            regexpPattern = re.compile(r'{([\w\.]+)}', re.IGNORECASE)

            # Search every occurence of the built pattern in the input chain and make the required substitution
            for match in regexpPattern.findall(initialParameterValue):
                # Circular substitution
                if match == parameterName:
                    self.substitutionErrors.append("Parameter <%s> - A circular substitution chain have been detected. Substitution is impossible !" % (parameterName))
                # Special keyword "step"
                elif match == 'step':
                    updatedValue = re.sub("{%s}" % match, str(self.taskStep), updatedValue)
                # Special keyword taskID
                elif match == 'taskId':
                    updatedValue = re.sub("{%s}" % match, str(self.taskId), updatedValue)
                # Other possible keywords for the current type of task
                elif match in taskParametersDefinitions.keys():
                    if Utils.isDefinedAsIsArrayParameter(taskParametersDefinitions[match]):
                        self.substitutionErrors.append("Parameter <%s> - The {%s} substring can't be replaced because it corresponds to the name of a parameter that can have multiple values (isArray attribute set to yes)" % (parameterName, match))
                    else:
                        if self.parameters.has_key(match):
                            replacementValue = self.specialKeywordReplacement(match, self.parameters[match], taskParametersDefinitions)
                            updatedValue = re.sub("{%s}" % match, str(replacementValue), updatedValue)
                        else:
                            if taskParametersDefinitions[match].has_key('defaultValue'):
                                replacementValue = self.specialKeywordReplacement(match, taskParametersDefinitions[match]['defaultValue'], taskParametersDefinitions)
                                updatedValue = re.sub("{%s}" % match, str(replacementValue), updatedValue)
                            else:
                                self.substitutionErrors.append("Parameter <%s> - The {%s} substring correspond to a parameter which is not defined in the input step/task file and have no default value in the configuration file" % (parameterName, match))

                else:
                    self.substitutionErrors.append("Parameter <%s> - The {%s} substring can't be replaced because it does not match the name of another possible parameter of the current task (or one of the following special keyword: %s)" % (parameterName, match, ', '.join(self.specialKeywords)))

        return updatedValue


    @staticmethod
    def getListOfDatabaseParameters(taskType, fullListOfParameters):
        # Initializations
        listOfDatabaseParameters = []

        # Extract the names of the database-like parameters from the full list of parameters for a task
        for parameterName in fullListOfParameters:
            # Get the parameters definitions for the requested type
            currentParametersDefinitions = TriAnnotConfigurationChecker.allParametersDefinitions[taskType]

            # Discard non ConfigEntry parameters
            if not currentParametersDefinitions[parameterName]['type'] == "configEntry":
                continue

            # Discard parameters that does not correspond to a database
            if not currentParametersDefinitions[parameterName]['listOfValuesPath'] == 'PATHS|db':
                continue

            listOfDatabaseParameters.append(parameterName)

        return listOfDatabaseParameters


# Import all subclasses from TaskParameters folder
for f in glob.glob(os.path.dirname(__file__)+"/TaskParameters/*.py"):
    name = os.path.basename(f)[:-3]
    if name != "__init__":
        __import__("TaskParameters." + name, locals(), globals())
