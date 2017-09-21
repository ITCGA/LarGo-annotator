#!/usr/bin/env python

# Imports
import os
import sys
import re
import xml.etree.cElementTree as etree
import hashlib
import zipfile

from time import sleep
from resource import getrusage, RUSAGE_SELF
from copy import deepcopy

# Due to circular references with TriAnnotConfig we can't use from...import... syntax
# and need to use TriAnnot.TriAnnotConfig.TriAnnotConfig.methodname syntax to call a method from TriAnnotConfig class
import TriAnnot.TriAnnotConfig

####################################################
###  XMLlint and XML validation related methods  ###
####################################################

def isXmllintAvailable():
    # Initializations
    xmllintIsAvailable = False

    # Check if XMLlint is in the path or directly accessible
    if os.path.exists('xmllint') and os.access('xmllint', os.R_OK) and os.access('xmllint', os.X_OK):
        xmllintIsAvailable = True
    else:
        for path in os.environ["PATH"].split(os.pathsep):
            exe_file = os.path.join(path, 'xmllint')
            if os.path.exists(exe_file) and  os.access(exe_file, os.R_OK) and os.access(exe_file, os.X_OK):
                xmllintIsAvailable = True

    return xmllintIsAvailable


def determineXMLSchemaPath(schemaFileName, environmentVariable = 'TRIANNOT_ROOT'):
    # Initializations
    xmlSchemaPath = None

    # Try to get the path of the XML schema from an environment variable..
    triAnnotPath = os.getenv(environmentVariable, None)

    if triAnnotPath is not None and os.path.isfile(os.path.join(os.path.realpath(triAnnotPath), "xml", "schemas", schemaFileName)):
        xmlSchemaPath = os.path.join(os.path.realpath(triAnnotPath), "xml", "schemas", schemaFileName)

    # ..or from the path of the main executable
    elif os.path.isfile(os.path.join(os.path.realpath(os.path.dirname(sys.argv[0])), "..", "xml", "schemas", schemaFileName)):
        xmlSchemaPath = os.path.join(os.path.realpath(os.path.dirname(sys.argv[0])), "..", "xml", "schemas", schemaFileName)
    else:
        raise RuntimeError("TriAnnot did not managed to determine the path of the following XSD schema file: %s" % schemaFileName)

    return xmlSchemaPath


###################################################
###  File/Directory/Executable existence check  ###
###################################################

def isExistingFile(fileFullPath, checkOnlyOnce = True, maxCheckAttempt = 5, checkDelay = 5):
    if fileFullPath is not None:
        for i in range(maxCheckAttempt):
            if os.path.isfile(fileFullPath) and os.access(fileFullPath, os.R_OK):
                return True
            if checkOnlyOnce:
                return False
            sleep(checkDelay)
    return False


def isExistingDirectory(directoryFullPath, checkOnlyOnce = True, maxCheckAttempt = 5, checkDelay = 5):
    if directoryFullPath is not None:
        for i in range(maxCheckAttempt):
            if os.path.isdir(directoryFullPath) and os.access(directoryFullPath, os.R_OK) and os.access(directoryFullPath, os.X_OK):
                return True
            if checkOnlyOnce:
                return False
            sleep(checkDelay)
    return False


def isExecutableTool(binary):
    if binary is not None:
        if os.path.exists(binary) and os.access(binary, os.R_OK) and os.access(binary, os.X_OK):
            return True
        else:
            for path in os.environ["PATH"].split(os.pathsep):
                exe_file = os.path.join(path, binary)
                if os.path.exists(exe_file) and  os.access(exe_file, os.R_OK) and os.access(exe_file, os.X_OK):
                    return True
    return False


def isEmptyFile(fileFullPath):
    return os.stat(fileFullPath).st_size == 0


def isEmptyDirectory(directoryFullPath):
    return False if len(os.listdir(directoryFullPath)) > 0 else True


###########################
###    File checksum    ###
###########################

def getFileChecksum(fileFullPath):
    return hashlib.sha256(open(fileFullPath,'rb').read()).hexdigest()


################################################
###  Directory backup & compression methods  ###
################################################

def createDirectoryBackup(directoryFullPath, zipFileFullPath):
    # Initializations
    relpathStartPoint = os.path.abspath(os.path.join(directoryFullPath, os.pardir))

    # Create the archive (autoclosing thanks to the with statement
    with zipfile.ZipFile(zipFileFullPath, "w") as zipObject:
        # Walk down all the directory tree
        for root, folders, files in os.walk(directoryFullPath):
            # Add the directory (we want to keep empty folders)
            zipObject.write(root, os.path.relpath(root, relpathStartPoint))

            # Add the regular files
            for fileToArchive in files:
                fileToArchivePath = os.path.join(root, fileToArchive)
                if os.path.isfile(fileToArchivePath):
                    zipObject.write(fileToArchivePath, os.path.join(os.path.relpath(root, relpathStartPoint), fileToArchive))


############################################
###  Directory size computation methods  ###
############################################

def getDirectoryTreeDiskUsage(baseDirectory):
    # We can't return a directory size if the selected directory does no exists
    if not isExistingDirectory(baseDirectory):
        return None

    # Get size of the directory itself
    totalDiskUsage = os.path.getsize(baseDirectory)

    # Loop through the content of the current directory
    for element in os.listdir(baseDirectory):
        elementFullPath = os.path.join(baseDirectory, element)

        # Increase the total or make a recursive call depending on the type of element (symlink, file, directory)
        if os.path.islink(elementFullPath):
            # Note: For symlink we count the size of the symlink file itself, not the size of the file pointed by the symlink
            totalDiskUsage += os.lstat(elementFullPath).st_size
        elif os.path.isfile(elementFullPath):
            totalDiskUsage += os.path.getsize(elementFullPath)
        elif os.path.isdir(elementFullPath):
            totalDiskUsage += getDirectoryTreeDiskUsage(elementFullPath)

    return totalDiskUsage


def getHumanlyReadableDiskUsage(nbOfbytes, metricSystemName = 'iec'):
    # Define metric system
    if metricSystemName == 'iec':
        metricSystem = [ (1024 ** 4, 'Ti'), (1024 ** 3, 'Gi'), (1024 ** 2, 'Mi'), (1024 ** 1, 'Ki'), (1024 ** 0, 'Bi') ]
    elif metricSystemName == 'si':
        metricSystem = [ (1000 ** 4, 'T'), (1000 ** 3, 'G'), (1000 ** 2, 'M'), (1000 ** 1, 'K'), (1000 ** 0, 'B') ]
    else:
        raise ValueError("The metric system name (ie. the second argument) can only be set to <iec> (1024) or <si> (1000) !")

    # Get the humanly readable size based on the selected metric system
    for factor, suffix in metricSystem:
        if nbOfbytes >= factor:
            break

    amount = float(nbOfbytes)/float(factor)

    if isinstance(suffix, tuple):
        singular, multiple = suffix
        if amount == 1:
            suffix = singular
        else:
            suffix = multiple

    # Return the descriptive string
    return "%.2f %s" % (amount, suffix)


############################
###  Python dict merging ###
############################

def recursiveDictMerge(dict1, dict2, exceptionList = [], doNotOverwriteExistingKey = False):
    for k, v in dict2.iteritems():
        if k in dict1:
            if doNotOverwriteExistingKey:
                next
            else:
                if isinstance(dict1[k], dict):
                    if k in exceptionList:
                        dict1[k] = recursiveDictMerge(dict1[k], v, exceptionList, True)
                    else:
                        dict1[k] = recursiveDictMerge(dict1[k], v, exceptionList, doNotOverwriteExistingKey)
                else:
                    dict1[k] = deepcopy(v)
        else:
            dict1[k] = deepcopy(v)
    return dict1


####################################
###  From XML to dict and beyond ###
####################################

def getDictFromXmlFile(xmlFileToConvert):
    # Parse the XML file with xml.etree.cElementTree
    xmlTree = etree.parse(xmlFileToConvert)

    # Get the root element of the tree
    xmlTreeRoot = xmlTree.getroot()

    # Build the dict recursively
    return xmlTreeToDict(xmlTreeRoot)


def xmlTreeToDict(xmlTree):
    # Initialize the structure that will contains the current tag datas
    xmlContentAsDict = { xmlTree.tag: { '@attributes': dict(), '#text': '' } }

    # Manage the raw text of the tag (ie. the value of the tag)
    if xmlTree.text:
        xmlContentAsDict[xmlTree.tag]['#text'] = xmlTree.text.strip()

    # Manage the attibutes of the tag
    if xmlTree.attrib:
        for attributeName, attributeValue in xmlTree.attrib.iteritems():
            xmlContentAsDict[xmlTree.tag]['@attributes'][attributeName] = attributeValue

    # Note: the beginning of this method can be done in one line (see below) but it's really harder to understand so I use the developped form instead
    #xmlContentAsDict = { xmlTree.tag: { '@attributes': {attributeName: attributeValue for attributeName, attributeValue in xmlTree.attrib.iteritems()} if xmlTree.attrib else dict(), '#text': xmlTree.text.strip() if xmlTree.text else '' } }

    # Manage the children(s) of the tag (recursive call)
    childrens = list(xmlTree)

    if childrens:
        # Create a directory that will contains the results of all recursive call (and manage the possibility of having several times the same tag at the same level in the XML file)
        allRecursiveCallsResults = dict()

        # Recursive calls
        for recursiveCallResult in map(xmlTreeToDict, childrens):
            for key, value in recursiveCallResult.iteritems():
                if not allRecursiveCallsResults.has_key(key):
                    allRecursiveCallsResults[key] = list()
                allRecursiveCallsResults[key].append(value)

        # Update of the main dict
        xmlContentAsDict[xmlTree.tag].update({key:value[0] if len(value) == 1 else value for key, value in allRecursiveCallsResults.iteritems()})

    return xmlContentAsDict


def getAttributeValue(dictObj, attributeToFind, tagName):
    # Return the value directly if the key to find is at this hash level
    if tagName in dictObj:
        if dictObj[tagName].has_key('@attributes'):
            if attributeToFind in dictObj[tagName]['@attributes']:
                return dictObj[tagName]['@attributes'][attributeToFind]

    # Loop on the element of the current dict level
    for elementName, elementValue in dictObj.items():
        # Do not analyse attributes dict if we search for a tag value
        if '@' in elementName:
            continue

        # Recursive call if the element is a dict
        if isinstance(elementValue, dict):
            item = getAttributeValue(elementValue, attributeToFind, tagName)
            if item is not None:
                return item

    # This return statement is not mandatory since python should return None by itself
    return None


def findFirstElementOccurence(dictObj, keyToFind, returnTextValue = False):
    # Check if dictObj is really a dict and return None if its not the case
    if type(dictObj) is not dict:
        return None

    # Return the value directly if the key to find is at this hash level
    if keyToFind in dictObj:
        if returnTextValue:
            return dictObj[keyToFind]['#text']
        else:
            return dictObj[keyToFind]

    # Loop on the element of the current dict level
    for elementName, elementValue in dictObj.items():
        # Do not analyse attributes dicts since we search for a tag value
        if '@' in elementName:
            continue

        # Recursive call if the element is a dict
        if isinstance(elementValue, dict):
            item = findFirstElementOccurence(elementValue, keyToFind)
            if item is not None:
                if returnTextValue:
                    return item['#text']
                else:
                    return item

    # This return statement is not mandatory since python should return None by itself
    return None


def findAllElementOccurences(dictObj, keyToFind):
    # Check if dictObj is really a dict and return None if its not the case
    if type(dictObj) is not dict:
        return None

    # Initializations
    tagValues = list()

    # Return the value directly if the key to find is at this hash level
    if keyToFind in dictObj:
        tagValues.append(dictObj[keyToFind])

    # Loop on the element of the current dict level
    for elementName, elementValue in dictObj.items():
        # Do not analyse attributes dicts since we search for a tag value
        if '@' in elementName:
            continue

        # Recursive call if the element is a dict
        if isinstance(elementValue, dict):
            item = findAllElementOccurences(elementValue, keyToFind)
            #if len(item) > 0:
                #tagValues.extend(item)
            if item is not None:
                tagValues.extend(item)

    # This return statement is not mandatory since python should return None by itself
    if len(tagValues) == 0:
        return None
    else:
        return tagValues


#######################################
###  ConfigEntry related utilities  ###
#######################################

def getListOfValues(parameterName, parameterDefinition):
    # Initializations
    listOfValues = []

    listOfValuesEntry = TriAnnot.TriAnnotConfig.TriAnnotConfig.getConfigValue(parameterDefinition['listOfValuesPath'])
    if listOfValuesEntry is None:
        raise ValueError("Parameter <%s> - The <listOfValuesPath> entry is missing" % parameterName)
    filterDefinition = parameterDefinition.get('listOfValuesFilter', None)

    if filterDefinition is not None and not filterDefinition.has_key('filterLogicalOperator'):
        filterDefinition['filterLogicalOperator'] = 'or'
    for key in listOfValuesEntry.keys():
        if filterDefinition is None:
            if parameterDefinition['listOfValuesMode'] == 'keys':
                listOfValues.append(key)
            elif parameterDefinition['listOfValuesMode'] == 'values':
                listOfValues.append(listOfValuesEntry[key])
            continue

        keepValue = False
        allowedValues = filterDefinition.get('filterAllowedValues', {}).values()
        rejectedValues = filterDefinition.get('filterRejectedValues', {}).values()
        valuesToTest = None
        filterEntry = TriAnnot.TriAnnotConfig.TriAnnotConfig.getConfigValue("%s|%s|%s" % (parameterDefinition['listOfValuesPath'], key, filterDefinition['filterPath']))
        if filterEntry is None:
            raise ValueError("Parameter <%s> - The <filterPath> attribute does not exists: %s" % parameterName)
        if filterDefinition['filterMode'] == 'keys':
            valuesToTest = filterEntry.keys()
        elif  filterDefinition['filterMode'] == 'values':
            valuesToTest = filterEntry.values()

        if filterDefinition['filterLogicalOperator'] == 'or':
            if filterDefinition.has_key('filterAllowedValues') and set(allowedValues).intersection(valuesToTest):
                keepValue = True
            elif filterDefinition.has_key('filterRejectedValues') and set(rejectedValues).isdisjoint(valuesToTest):
                keepValue = True
        else:
            # filterLogicalOperator == 'and'
            if filterDefinition.has_key('filterAllowedValues') and set(allowedValues).issubset(valuesToTest):
                keepValue = True
            elif filterDefinition.has_key('filterRejectedValues') and set(rejectedValues).difference(valuesToTest):
                keepValue = True

        if keepValue == True:
            if parameterDefinition['listOfValuesMode'] == 'keys':
                listOfValues.append(key)
            elif parameterDefinition['listOfValuesMode'] == 'values':
                listOfValues.append(listOfValuesEntry[key])
    if parameterDefinition.has_key('additionalValues'):
        listOfValues.extend(parameterDefinition['additionalValues'].values())

    return listOfValues


#############################################
###  String manipulation related methods  ###
#############################################

def subStringGenerator(inputString, subStringLength):
    return (inputString[0+i : subStringLength+i] for i in range(0, len(inputString), subStringLength))


##############################################################
###  Basic methods based on the definition of a parameter  ###
##############################################################

def isEmptyValue(value):
    if value is None:
        return True
    elif not value.strip():
        return True
    else:
        return False


def isDefinedAsIsArrayParameter(parameterDefinition):
    # Check the definition for the current parameter to determine if it can have multiple values
    if parameterDefinition.has_key('isArray'):
        if parameterDefinition['isArray'] == 'yes':
            return True

    return False


def isDefinedAsMandatoryParameter(parameterDefinition):
    # Check the definition for the current parameter to determine if it is a mandatory parameter
    if parameterDefinition.has_key('mandatory'):
        if parameterDefinition['mandatory'] == 'yes':
            return True

    return False


def isDefinedAsIsArrayParameterAlt(definitionsHash, taskType, parameterName):
    # Initializations
    currentDefinition = None

    # Check the definition for the given task type and the given parameter name to determine if this parameter can have multiple values
    if definitionsHash.has_key(taskType):
        if definitionsHash[taskType].has_key(parameterName):
            if definitionsHash[taskType][parameterName].has_key('isArray'):
                if definitionsHash[taskType][parameterName]['isArray'] == 'yes':
                    return True

    return False


def doesParameterNeedSubstitution(parameterDefinition):
    # Check if the parameter's value must be checked for {parameterName} like substrings
    if parameterDefinition.has_key('needSubstitution'):
        if parameterDefinition['needSubstitution'] == 'yes':
            return True

    return False


def displayCurrentMemoryUsage():
    rusage_denom = 1024.
    if sys.platform == 'darwin':
        # ... it seems that in OSX the output is different units ...
        rusage_denom = rusage_denom * rusage_denom

    memoryUsage = getrusage(RUSAGE_SELF).ru_maxrss / rusage_denom

    print "Total RAM usage from the system point of view: %s MiB" % memoryUsage
