#!/usr/bin/env python

import os
import logging

from TriAnnot.TriAnnotConfig import *
import Utils

class TriAnnotTool (object):

    # Constructor
    def __init__(self, toolType):
        # Logger
        self.logger = logging.getLogger("TriAnnot.TriAnnotTool")
        self.logger.addHandler(logging.NullHandler())

        #self.logger.debug("Creating a new %s object" % (self.__class__.__name__))

        # Attributes
        self.toolType = toolType
        self.mainConfigurationCategories = ['commonParameters', 'execParameters', 'parserParameters', 'reconstructionParameters']
        self.configurationErrors = []
        self.parametersDefinitions = dict()

        # Change class to a specialized subclass if there is one defined for self.toolType
        for toolType in TriAnnotTool.__subclasses__():
            if toolType.__name__ == self.toolType:
                self.__class__ = toolType
                self.logger = logging.getLogger("TriAnnot.Tools.%s" % self.__class__.__name__)
                self.logger.addHandler(logging.NullHandler())
                self.__init__()


    ##########################################
    ###  Parameters definitions retrieval  ###
    ##########################################
    def retrieveParametersDefinitions(self):
        # Log
        self.logger.debug('Retrieving the definitions of <%s> parameters' % self.toolType)

        # Collect all parameters defintions for the current tool
        for parameterCategory in self.mainConfigurationCategories:
            if TriAnnotConfig.isConfigValueDefined('%s|%s' % (self.toolType, parameterCategory)):
                parametersInCurrentCategory = TriAnnotConfig.getConfigValue('%s|%s' % (self.toolType, parameterCategory))
                # Browse the parameters by category
                for parameterName in parametersInCurrentCategory.keys():
                    if not self.parametersDefinitions.has_key(parameterName):
                        self.parametersDefinitions[parameterName] = {'parameterCategory': parameterCategory}
                    elif self.parametersDefinitions[parameterName]['parameterCategory'] != parameterCategory:
                        self.configurationErrors.append("Parameter <%> is duplicated in two different categories: %s and %s" % (parameterName, self.parametersDefinitions[parameterName]['parameterCategory'], parameterCategory))
                        next
                    # Store each attribute (type, defaultValue, possibleValues, etc.) of the current parameter
                    for key in parametersInCurrentCategory[parameterName].keys():
                        self.parametersDefinitions[parameterName][key] = parametersInCurrentCategory[parameterName][key]


    ######################################
    ###  Parameters definitions check  ###
    ######################################
    def checkParametersDefinitions(self):
        # Log
        self.logger.debug('Checking the definitions of <%s> parameters' % self.toolType)

        # Check if the current section possess all the mandatory parameters in its parserParameters category
        if TriAnnotConfig.isConfigValueDefined('%s|%s' % (self.toolType, 'parserParameters')):
            self.checkMandatoryParametersDefinitionsExistence()

        # Check the validity of parameters defintions
        self.validateParametersDefinitions()


    def checkMandatoryParametersDefinitionsExistence(self):
        # Initializations
        mandatoryDefinitions = self.getMandatoryDefinitionsList()

        # Check if all the element from the above list exists in the list of parameter for the current tool
        missingDefinitions = set(mandatoryDefinitions).difference(self.parametersDefinitions.keys())

        for missingDefinition in missingDefinitions:
            self.configurationErrors.append('The mandatory entry <%s> is missing in the <parserParameters> entry of the <%s> XML configuration file.' % (missingDefinition, self.toolType))


    def getMandatoryDefinitionsList(self):
        return ['sourceTag', 'gffFile', 'emblFile', 'EMBLFormat']


    def validateParametersDefinitions(self):
        for parameterName in self.parametersDefinitions.keys():
            # Log and initialization
            self.logger.debug("Validation of the <%s> parameter (Type: %s)" % (parameterName, self.parametersDefinitions[parameterName]['type']))

            validateFunction = None
            validSubEntries = ['mandatory', 'needSubstitution', 'defaultValue', 'type', 'parameterCategory']
            parameterType = self.parametersDefinitions[parameterName]['type']

            # Select the method that will be used to check the current parameter depending on its type
            if parameterType == "string":
                validateFunction = self.validateStringParameterDefinition
                validSubEntries.extend(['minLength', 'maxLength', 'validationRegex', 'invalidRegexMessage', 'possibleValues', 'isArray'])
            elif parameterType == "number":
                validateFunction = self.validateNumberParameterDefinition
                validSubEntries.extend(['minValue', 'maxValue', 'possibleValues', 'isArray'])
            elif parameterType == "boolean":
                validateFunction = self.validateBooleanParameterDefinition
                validSubEntries.extend(['trueValue', 'falseValue'])
            elif parameterType == "configEntry":
                validateFunction = self.validateConfigEntryParameterDefinition
                validSubEntries.extend(['listOfValuesPath', 'listOfValuesMode', 'listOfValuesFilter', 'additionalValues', 'isArray'])
            else:
                self.configurationErrors.append("Parameter <%s> - Type <%s> is not a valid parameter type" % (parameterName, parameterType))
                continue

            # Check for unauthorized sub-entries
            invalidSubEntries = set(self.parametersDefinitions[parameterName].keys()) - set(validSubEntries)
            if invalidSubEntries:
                self.configurationErrors.append("Parameter <%s> - The following sub-entries are not allowed for a <%s> parameter: %s" % (parameterName, parameterType, ', '.join(invalidSubEntries)))
            if self.parametersDefinitions[parameterName].has_key('isArray') and self.parametersDefinitions[parameterName]['isArray'] not in ('yes', 'no'):
                self.configurationErrors.append("Parameter <%s> - The <isArray> sub-entry can only be set to 'yes' or 'no'" % parameterName)
            if (not self.parametersDefinitions[parameterName].has_key('isArray') or self.parametersDefinitions[parameterName]['isArray'] != 'yes') \
              and self.parametersDefinitions[parameterName].has_key('defaultValue') and type(self.parametersDefinitions[parameterName]['defaultValue']) == dict:
                self.configurationErrors.append("Parameter <%s> - This parameter must have an <isArray> sub-entry set to 'yes' to be allowed to have multiple default values " % parameterName)

            # Call the validation method selected above
            validateFunction(parameterName)


    def validateStringParameterDefinition(self, parameterName):
        # Initializations
        validationRegex = None
        minLength = None
        maxLength = None
        nbErrorBeforeCheck = len(self.configurationErrors)

        # Basic checks and preparation for advanced checks
        if self.parametersDefinitions[parameterName].has_key('minLength'):
            if self.parametersDefinitions[parameterName]['minLength'].isdigit():
                minLength = int(self.parametersDefinitions[parameterName]['minLength'])
            else:
                self.configurationErrors.append("Parameter <%s> - The value of the <minLength> sub-entry must be a numeric value (<%s> is not valid)" % (parameterName, self.parametersDefinitions[parameterName]['minLength']))

        if self.parametersDefinitions[parameterName].has_key('maxLength'):
            if self.parametersDefinitions[parameterName]['maxLength'].isdigit():
                maxLength = int(self.parametersDefinitions[parameterName]['maxLength'])
            else:
                self.configurationErrors.append("Parameter <%s> - The value of the <maxLength> sub-entry must be a numeric value (<%s> is not valid)" % (parameterName, self.parametersDefinitions[parameterName]['maxLength']))

        if minLength is not None and maxLength is not None and minLength > maxLength:
            self.configurationErrors.append("Parameter <%s> - The <minLength> value can't be greater than the <maxLength> value (%s <=> %s)" % (parameterName, minLength, maxLength))

        if self.parametersDefinitions[parameterName].has_key('validationRegex'):
            try:
                validationRegex = re.compile(self.parametersDefinitions[parameterName]['validationRegex'])
            except re.error:
                self.configurationErrors.append("Parameter <%s> - The following <validationRegex> is not a valid regular expression: %s" % (parameterName, self.parametersDefinitions[parameterName]['validationRegex']))

        # If there was no error at this point we can make more advanced checks
        if len(self.configurationErrors) == nbErrorBeforeCheck:
            self.checkStringPossibleValues(parameterName, minLength, maxLength, validationRegex)
            self.checkStringDefaultValues(parameterName, minLength, maxLength, validationRegex)


    def checkStringPossibleValues(self, parameterName, minLength, maxLength, validationRegex):
        if self.parametersDefinitions[parameterName].has_key('possibleValues'):
            # Get the list of possible values
            self.transformPossibleValuesAttInDict(parameterName, 'string')
            possibleValuesList = self.parametersDefinitions[parameterName]['possibleValues'].values()

            # Generate an error message if the list of possible value is empty
            if len(possibleValuesList) == 0:
                self.configurationErrors.append("Parameter <%s> - The list of possible values for this string parameter is empty and this should never be the case - Please either add at least one possible value in the possibleValues attribute or remove this possibleValues attribute" % parameterName)
            else:
                # Check every possible values
                for value in possibleValuesList:
                    if Utils.isEmptyValue(value):
                        self.configurationErrors.append("Parameter <%s> - Empty value/sub-entry detected for the possibleValues attribute - Please check that each defined value/sub-entry have a non null value" % parameterName)
                    else:
                        # Check the length of the current possible value
                        if ( minLength is not None and len(value) < minLength ) or ( maxLength is not None and len(value) > maxLength ):
                            self.configurationErrors.append("Parameter <%s> - The following possible value have an invalid number of characters: %s (Valid size is %d-%d characters)" % (parameterName, value, minLength, maxLength))
                        # Check if the current possible value can pass the validation regular expression
                        if validationRegex is not None and not validationRegex.search(value):
                            self.configurationErrors.append("Parameter <%s> - The following possible value does not match the selected regular expression (%s): %s" % (parameterName, self.parametersDefinitions[parameterName]['validationRegex'], value))



    def checkStringDefaultValues(self, parameterName, minLength, maxLength, validationRegex):
        if self.parametersDefinitions[parameterName].has_key('defaultValue'):
            # Get the list of default values
            defaultValuesList = self.getCleanListOfDefaultValues(parameterName)

            # Generate an error message if the list of default value is empty
            if len(defaultValuesList) == 0:
                self.configurationErrors.append("Parameter <%s> - The list of default values for this string parameter is empty and this should never be the case - Please either add at least one default value in the defaultValue attribute or remove this defaultValue attribute" % parameterName)
            else:
                # Check every default values
                for value in defaultValuesList:
                    if Utils.isEmptyValue(value):
                        self.configurationErrors.append("Parameter <%s> - Empty value/sub-entry detected for the defaultValue attribute - Please check that each defined value/sub-entry have a non null value" % parameterName)
                    else:
                        # Check the length of the current default value
                        if ( minLength is not None and len(value) < minLength ) or ( maxLength is not None and len(value) > maxLength ):
                            self.configurationErrors.append("Parameter <%s> - The following default value have an invalid number of characters (Valid size is %d-%d characters): %s" % (parameterName, minLength, maxLength, value))
                        # Check if the current default value can pass the validation regular expression
                        if validationRegex is not None and not validationRegex.search(value):
                            self.configurationErrors.append("Parameter <%s> - The following default value does not match the selected regular expression: %s" % (parameterName, value))
                        # Check if the current default value is equal to one of the possible values
                        if self.parametersDefinitions[parameterName].has_key('possibleValues') and value not in self.parametersDefinitions[parameterName]['possibleValues'].values():
                            self.configurationErrors.append("Parameter <%s> - The following default value is not in the list of possible values: %s (Possible values are: %s)" % (parameterName, value, ', '.join(self.parametersDefinitions[parameterName]['possibleValues'].values())))


    def validateNumberParameterDefinition(self, parameterName):
        # Initializations
        minValue = None
        maxValue = None
        nbErrorBeforeCheck = len(self.configurationErrors)

        # Basic checks and preparation for advanced checks
        if self.parametersDefinitions[parameterName].has_key('minValue'):
            try:
                minValue = float(self.parametersDefinitions[parameterName]['minValue'])
            except ValueError, TypeError:
                self.configurationErrors.append("Parameter <%s> - The value of the <minValue> sub-entry must be a numeric value (<%s> is not valid)" % (parameterName, self.parametersDefinitions[parameterName]['minValue']))

        if self.parametersDefinitions[parameterName].has_key('maxValue'):
            try:
                maxValue = float(self.parametersDefinitions[parameterName]['maxValue'])
            except ValueError, TypeError:
                self.configurationErrors.append("Parameter <%s> - The value of the <maxValue> sub-entry must be a numeric value (<%s> is not valid)" % (parameterName, self.parametersDefinitions[parameterName]['maxValue']))

        if minValue is not None and maxValue is not None and minValue > maxValue:
            self.configurationErrors.append("Parameter <%s> - The <minValue> value can't be greater than the <maxValue> value (%s <=> %s)" % (parameterName, minValue, maxValue))

        # If there was no error at this point we can make more advanced checks
        if len(self.configurationErrors) == nbErrorBeforeCheck:
            self.checkNumericPossibleValues(parameterName, minValue, maxValue)
            self.checkNumericDefaultValues(parameterName, minValue, maxValue)


    def checkNumericPossibleValues(self, parameterName, minValue, maxValue):
        if self.parametersDefinitions[parameterName].has_key('possibleValues'):
            # Get the list of possible values
            self.transformPossibleValuesAttInDict(parameterName, 'number')
            possibleValuesList = self.parametersDefinitions[parameterName]['possibleValues'].values()

            # Generate an error message if the list of possible value is empty
            if len(possibleValuesList) == 0:
                self.configurationErrors.append("Parameter <%s> - The list of possible values for this numeric parameter is empty and this should never be the case - Please either add at least one possible value in the possibleValues attribute or remove this possibleValues attribute" % parameterName)
            else:
                # Check every possible values
                for value in possibleValuesList:
                    if Utils.isEmptyValue(value):
                        self.configurationErrors.append("Parameter <%s> - Empty sub-entry detected for the possibleValues attribute - Please check that each defined sub-entry have a non null/empty value" % parameterName)
                    else:
                        try:
                            value = float(value)
                            # Check if the current default value is between the minimum and maximum value
                            if ( minValue is not None and value < minValue ) or ( maxValue is not None and value > maxValue ):
                               self.configurationErrors.append("Parameter <%s> - The following possible value is lower than the minimum value (%g) or greater than the maximum value (%g): %g" % (parameterName, minValue, maxValue, value))
                        except ValueError, TypeError:
                            self.configurationErrors.append("Parameter <%s> - The following possible value is not a valid numeric value: %s" % (parameterName, value))


    def checkNumericDefaultValues(self, parameterName, minValue, maxValue):
        if self.parametersDefinitions[parameterName].has_key('defaultValue'):
            # Get the list of default values
            defaultValuesList = self.getCleanListOfDefaultValues(parameterName)

            # Generate an error message if the list of default value is empty
            if len(defaultValuesList) == 0:
                self.configurationErrors.append("Parameter <%s> - The list of default values for this numeric parameter is empty and this should never be the case - Please either add at least one default value in the defaultValue attribute or remove this defaultValue attribute" % parameterName)
            else:
                # Check every default values
                for value in defaultValuesList:
                    if Utils.isEmptyValue(value):
                        self.configurationErrors.append("Parameter <%s> - Empty value/sub-entry detected for the defaultValue attribute - Please check that each defined value/sub-entry have a non null value" % parameterName)
                    else:
                        # Check if the current default value is equal to one of the possible values
                        if self.parametersDefinitions[parameterName].has_key('possibleValues') and value not in self.parametersDefinitions[parameterName]['possibleValues'].values():
                            self.configurationErrors.append("Parameter <%s> - The following default value is not in the list of possible values: %s (Possible values are: %s)" % (parameterName, value, ', '.join(self.parametersDefinitions[parameterName]['possibleValues'].values())))
                        # Check if the current default value is between the minimum and maximum value
                        try:
                            value = float(value)
                            if ( minValue is not None and value < minValue) or ( maxValue is not None and value > maxValue):
                                self.configurationErrors.append("Parameter <%s> - The following default value is lower than the minimum value (%g) or greater than the maximum value (%g): %g" % (parameterName, minValue, maxValue, value))
                        except ValueError, TypeError:
                            self.configurationErrors.append("Parameter <%s> - The following default value is not a valid numeric value: %s" % (parameterName, value))


    def validateBooleanParameterDefinition(self, parameterName):
        trueValue = None
        falseValue = None

        if not self.parametersDefinitions[parameterName].has_key('trueValue'):
            self.configurationErrors.append("Parameter <%s> - A <trueValue> sub-entry is mandatory for a <boolean> parameter" % (parameterName))
        else:
            trueValue = self.parametersDefinitions[parameterName]['trueValue']

        if not self.parametersDefinitions[parameterName].has_key('falseValue'):
            self.configurationErrors.append("Parameter <%s> - A <falseValue> sub-entry is mandatory for a <boolean> parameter" % (parameterName))
        else:
            falseValue = self.parametersDefinitions[parameterName]['falseValue']

        if self.parametersDefinitions[parameterName].has_key('defaultValue') and trueValue is not None and falseValue is not None \
          and self.parametersDefinitions[parameterName]['defaultValue'] not in [trueValue, falseValue]:
            self.configurationErrors.append("Parameter <%s> - The following default value is not in the list of possible values: %s (Possible values are: %s, %s)" % (parameterName, self.parametersDefinitions[parameterName]['defaultValue'], trueValue, falseValue))


    def validateConfigEntryParameterDefinition(self, parameterName):
        nbErrorBeforeCheck = len(self.configurationErrors)

        if not self.parametersDefinitions[parameterName].has_key('listOfValuesMode'):
            self.configurationErrors.append("Parameter <%s> - A <listOfValuesMode> sub-entry is mandatory for a <configEntry> parameter (Possible values are 'keys' or 'values')" % (parameterName))
        else:
            if self.parametersDefinitions[parameterName]['listOfValuesMode'] not in ['keys', 'values']:
                self.configurationErrors.append("Parameter <%s> - The <listOfValuesMode> sub-entry can only be set to 'keys' or 'values'" % (parameterName))

        if not self.parametersDefinitions[parameterName].has_key('listOfValuesPath') or self.parametersDefinitions[parameterName]['listOfValuesPath'] == '':
            self.configurationErrors.append("Parameter <%s> - A <listOfValuesPath> sub-entry is mandatory for a <configEntry> parameter" % (parameterName))
        elif not TriAnnotConfig.isConfigValueDefined(self.parametersDefinitions[parameterName]['listOfValuesPath']):
            self.configurationErrors.append("Parameter <%s> - The <listOfValuesPath> sub-entry references an undefined configuration entry: %s." % (parameterName, self.parametersDefinitions[parameterName]['listOfValuesPath']))
        elif type(TriAnnotConfig.getConfigValue(self.parametersDefinitions[parameterName]['listOfValuesPath'])) != dict :
            self.configurationErrors.append("Parameter <%s> - The <listOfValuesPath> sub-entry references a configuration entry that does not have any sub-entry: %s." % (parameterName, self.parametersDefinitions[parameterName]['listOfValuesPath']))
        else:
            # validating filter definition is only possible when listOfValuesPath is valid
            self.validateListOfValuesFilterDefinition(parameterName)

        # Check default values if there was no error with the rest of the definition
        if len(self.configurationErrors) == nbErrorBeforeCheck:
            self.getAndCheckConfigEntryPossibleValues(parameterName)
            self.checkConfigEntryDefaultValues(parameterName)


    def validateListOfValuesFilterDefinition(self, parameterName):
        if self.parametersDefinitions[parameterName].has_key('listOfValuesFilter'):
            filterDefinition = self.parametersDefinitions[parameterName]['listOfValuesFilter']
            invalidSubEntries = set(filterDefinition.keys()) - set(['filterPath', 'filterMode', 'filterLogicalOperator', 'filterAllowedValues', 'filterRejectedValues'])
            if invalidSubEntries:
                self.configurationErrors.append("Parameter <%s> - The following sub-entries are not allowed in the filter definition: %s" % (parameterName, ', '.join(invalidSubEntries)))
            if not filterDefinition.has_key('filterMode'):
                self.configurationErrors.append("Parameter <%s> - A <filterMode> sub-entry is mandatory in the definition of a filter (Possible values are 'keys' or 'values')" % (parameterName))
            elif filterDefinition['filterMode'] not in ['keys', 'values']:
                self.configurationErrors.append("Parameter <%s> - The following filter mode is not valid: %s (Possible values are 'keys' or 'values')" % (parameterName, filterDefinition['filterMode']))
            if not filterDefinition.has_key('filterPath'):
                self.configurationErrors.append("Parameter <%s> - A <filterPath> sub-entry is mandatory in the definition of a filter" % (parameterName))
            else:
                listOfValuesEntry = TriAnnotConfig.getConfigValue(self.parametersDefinitions[parameterName]['listOfValuesPath'])
                for listOfValuesEntrySubKey in listOfValuesEntry.keys():
                    pathToTest = "%s|%s|%s" % (self.parametersDefinitions[parameterName]['listOfValuesPath'], listOfValuesEntrySubKey, filterDefinition['filterPath'])
                    if not TriAnnotConfig.isConfigValueDefined(pathToTest):
                        self.configurationErrors.append("Parameter <%s> - The configuration entry pointed by the following path does not exists: %s" % (parameterName, pathToTest))
            if not filterDefinition.has_key('filterAllowedValues') and not filterDefinition.has_key('filterRejectedValues'):
                self.configurationErrors.append("Parameter <%s> - A filter definition must contain either a <filterAllowedValues> sub-entry OR a <filterRejectedValues> sub-entry" % (parameterName))
            if filterDefinition.has_key('filterAllowedValues') and filterDefinition.has_key('filterRejectedValues'):
                self.configurationErrors.append("Parameter <%s> - A filter definition can't contain both a <filterAllowedValues> sub-entry AND a <filterRejectedValues> sub-entry" % (parameterName))
            if filterDefinition.has_key('filterLogicalOperator') and filterDefinition['filterLogicalOperator'] != 'or' and filterDefinition['filterLogicalOperator'] != 'and':
                self.configurationErrors.append("Parameter <%s> - The following <filterLogicalOperator> is not valid: %s (Possible values ar 'or' or 'and')" % (parameterName, filterDefinition['filterLogicalOperator']))


    def getAndCheckConfigEntryPossibleValues(self, parameterName):
        # The list of possible values is auto-generated for configEntry parameters (based on listOfValuesPath and listOfValuesFilter)
        self.transformPossibleValuesAttInDict(parameterName, 'configEntry')

        if len(self.parametersDefinitions[parameterName]['possibleValues'].values()) == 0:
            self.configurationErrors.append("Parameter <%s> - The list of possible values for this configEntry parameter is empty - The filter specified through the <listOfValuesFilter> attribute is maybe too stringent - OR - The configuration section pointed by the <listOfValuesPath> and <filterPath> attributes does not exist" % parameterName)


    def checkConfigEntryDefaultValues(self, parameterName):
        if self.parametersDefinitions[parameterName].has_key('defaultValue'):
            # Get the list of default values
            defaultValuesList = self.getCleanListOfDefaultValues(parameterName)

            # Generate an error message if the list of default value is empty
            if len(defaultValuesList) == 0:
                self.configurationErrors.append("Parameter <%s> - The list of default values for this configEntry parameter is empty and this should never be the case - Please either add at least one default value in the defaultValue attribute or remove this defaultValue attribute" % parameterName)
            else:
                # Check every default values
                for value in defaultValuesList:
                    if Utils.isEmptyValue(value):
                        self.configurationErrors.append("Parameter <%s> - Empty value/sub-entry detected for the defaultValue attribute - Please check that each defined value/sub-entry have a non null value" % parameterName)
                    else:
                        # Check if the current default value is a member of the auto-generated list of possible values
                        if value not in self.parametersDefinitions[parameterName]['possibleValues'].values():
                            self.configurationErrors.append("Parameter <%s> - The following default value is not in the list of possible values: %s (Possible values are: %s)" % (parameterName, value, ', '.join(self.parametersDefinitions[parameterName]['possibleValues'].values())))


    def transformPossibleValuesAttInDict(self, parameterName, parameterType):
        if parameterType == 'configEntry':
            # Special case: transform the list return by the getListOfValues in dict
            self.parametersDefinitions[parameterName]['possibleValues'] = {}
            for index, value in enumerate(Utils.getListOfValues(parameterName, self.parametersDefinitions[parameterName])):
                self.parametersDefinitions[parameterName]['possibleValues'][index] = value
        else:
            # If the type is already dict we have nothing to do
            # But if we have a single value (empty or not), we have to create a dict
            if type(self.parametersDefinitions[parameterName]['possibleValues']) != dict:
                if Utils.isEmptyValue(self.parametersDefinitions[parameterName]['possibleValues']):
                    self.parametersDefinitions[parameterName]['possibleValues'] = {}
                else:
                    self.parametersDefinitions[parameterName]['possibleValues'] = {0: self.parametersDefinitions[parameterName]['possibleValues']}


    def getCleanListOfDefaultValues(self, parameterName):
        # Three possible case here:
        # 1) The attribute contains a dict and we return all the values
        # 2) The attribute contains an empty value (None, "", " ", etc.) and we return an empty list
        # 3) The attribute contains a single value and we return a list of 1 element
        if type(self.parametersDefinitions[parameterName]['defaultValue']) != dict:
            if Utils.isEmptyValue(self.parametersDefinitions[parameterName]['defaultValue']):
                return []
            else:
                return [self.parametersDefinitions[parameterName]['defaultValue']]
        else:
            return self.parametersDefinitions[parameterName]['defaultValue'].values()


# Import all subclasses from Tools folder
for f in glob.glob(os.path.dirname(__file__)+"/Tools/*.py"):
    name = os.path.basename(f)[:-3]
    if name != "__init__":
        __import__("Tools." + name, locals(), globals())
