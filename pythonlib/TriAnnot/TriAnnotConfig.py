#!/usr/bin/env python

import logging
import os
import xml.etree.cElementTree as etree
import subprocess
import traceback
import re
import sys
import glob
from xml.dom import minidom

import Utils


class TriAnnotConfig (object):
    # Class variables
    alreadyLoadedFiles = []
    TRIANNOT_CONF = {'Runtime': {}}
    parsingErrors = []
    logger = None

    #####################
    ###  Constructor  ###
    #####################
    def __init__(self, xmlConfigFile = None, requiredVersion = None):
        self.logger = TriAnnotConfig.logger
        self.configFilePath = os.path.realpath(xmlConfigFile)
        self.configFileName = os.path.basename(self.configFilePath)
        self.requiredVersion = requiredVersion
        self.configFileVersion = None

        #self.logger.debug("Creating a new TriAnnotConfig object to load this configuration file: %s" % (self.configFilePath))

    #######################
    ###  Class methods  ###
    #######################
    def loadConfigurationFile(self):
        if self.configFilePath in TriAnnotConfig.alreadyLoadedFiles:
            self.logger.error("%s has already been loaded. Can not load the same file twice. Please check your configuration and options." % self.configFilePath)
            return False

        try:
            xmlTree = etree.parse(self.configFilePath)
            xmlRoot = xmlTree.getroot()
            self.configFileVersion = xmlRoot.get('triannot_version', 'None')

            if self.requiredVersion is not None and self.configFileVersion != self.requiredVersion:
                self.logger.error("%s configuration file version is %s. It does not match TriAnnot version: %s" % (self.configFileName, self.configFileVersion, self.requiredVersion))
                return False

            for section in xmlTree.iter(tag='section'):
                self.readSection(section)

            TriAnnotConfig.alreadyLoadedFiles.append(self.configFilePath)

            return True
        except SyntaxError:
            self.logger.error("Syntax error in XML configuration file: %s" % self.configFilePath)
            return False


    def readSection(self, xmlSection):
        entriesCpt = 0
        sectionName = xmlSection.get('name', '').strip()
        clear = False
        if 'clear' in xmlSection.keys():
            clear = True

        if sectionName == '':
            self.logger.error("Invalid section found. All sections must have a name attribute %s" % (etree.tostring(xmlSection).split('>')[0] + '>'))
            exit(1)

        if TriAnnotConfig.TRIANNOT_CONF.has_key(sectionName):
            self.logger.info("Overriding section [%s]" % sectionName)

        if not TriAnnotConfig.TRIANNOT_CONF.has_key(sectionName) or clear:
            TriAnnotConfig.TRIANNOT_CONF[sectionName] = {}

        entriesCpt = len(TriAnnotConfig.TRIANNOT_CONF[sectionName])

        for entry in list(xmlSection):
            self.readEntry(entry, TriAnnotConfig.TRIANNOT_CONF[sectionName], sectionName, entriesCpt)
            entriesCpt += 1


    def readEntry(self, xmlEntry, dictDestination, sectionName, entryNumber):
        key = xmlEntry.get('key', str(entryNumber)).strip()
        if key == '':
            self.logger.error("Invalid empty entry key found in section [%s]" % sectionName)
            exit(1)

        value = xmlEntry.text
        if value is None:
            value = ''
        value = value.strip()
        if value != '' and list(xmlEntry):
            self.logger.error("Invalid entry [%s] found in section [%s]" % (key, sectionName))
            exit(1)

        if dictDestination.has_key(key):
            self.logger.info("Overriding value of entry [%s] in section [%s]" % (key, sectionName))

        if value != '' or (value == '' and not list(xmlEntry)): # scalar value
            dictDestination[key] = value
        else:
            subEntriesCpt = 0
            clear = False
            if 'clear' in xmlEntry.keys():
                clear = True
            if not dictDestination.has_key(key) or clear:
                dictDestination[key] = {}
            subEntriesCpt = len(dictDestination[key])

            for subEntry in list(xmlEntry):
                self.readEntry(subEntry, dictDestination[key], sectionName, subEntriesCpt)
                subEntriesCpt += 1


    ########################
    ###  Static methods  ###
    ########################
    @staticmethod
    def isConfigValueDefined(valuePath):
        chunks = valuePath.split('|')
        currentDict = TriAnnotConfig.TRIANNOT_CONF

        try:
            for key in chunks:
                if currentDict.has_key(key):
                    currentDict = currentDict[key]
                else:
                    return False
        except:
            return False

        return True


    @staticmethod
    def getConfigValue(valuePath):
        chunks = valuePath.split('|')
        currentDict = TriAnnotConfig.TRIANNOT_CONF

        try:
            while len(chunks) > 0:
                if not currentDict.has_key(chunks[0]):
                    TriAnnotConfig.logger.error("Trying to get a config value that is not defined: %s" % valuePath)
                    return None
                if len(chunks) == 1:
                    break
                currentDict = currentDict[chunks.pop(0)]

            retrievedValue = currentDict[chunks[0]]
            return retrievedValue

        except:
            TriAnnotConfig.logger.error("Trying to get an invalid config value: %s" % valuePath)
            TriAnnotConfig.logger.debug(traceback.format_exc())
            return None


    @staticmethod
    def parseSpecialValues(dictToTreat = None, path = []):
        if dictToTreat is None:
            dictToTreat = TriAnnotConfig.TRIANNOT_CONF
        for key, value in dictToTreat.items():
            if key == 'Runtime':
                continue
            if type(value) is dict:
                TriAnnotConfig.parseSpecialValues(value, path + [key])
            else:
                newValue = TriAnnotConfig._parseValue(value)
                if newValue is None:
                    TriAnnotConfig.parsingErrors.append("Invalid special value found at %s: %s" % ('|'.join(path), value))
                elif newValue != value:
                    TriAnnotConfig.logger.debug("[%s]: replacing '%s' by '%s'" % (key, value, newValue))
                    dictToTreat[key] = newValue


    @staticmethod
    def _parseValue(value):
        try:
            currentJobRunnerName = TriAnnotConfig.getConfigValue('Runtime|taskJobRunnerName')
            pattern1 = re.compile(r"(getRunnerName\(\))")
            for match in pattern1.findall(value):
                value = re.sub(re.escape(match), currentJobRunnerName, value)

            pattern1 = re.compile(r"(getValue\((.+?)\))")
            for match, newValuePath in pattern1.findall(value):
                newValue = TriAnnotConfig.getConfigValue(newValuePath)
                if newValue is None:
                    return newValue
                value = re.sub(re.escape(match), newValue, value)

            triAnnotBinPath = os.path.realpath(os.path.dirname(sys.argv[0]))
            pattern2 = re.compile(r"(getTriAnnotBinPath\(\))")
            for match in pattern2.findall(value):
                value = re.sub(re.escape(match), triAnnotBinPath, value)

            if pattern1.search(value) or pattern2.search(value):
                value = TriAnnotConfig._parseValue(value)
            return value
        except:
            TriAnnotConfig.logger.error("An unexpected error occured while parsing value: %s" % value)
            raise


    @staticmethod
    def getConfAsXMLString(encoding = 'utf-8', prettyXml = False, triAnnotVersion = None):
        root = etree.Element('triannotConf', {'triannot_version':triAnnotVersion})
        sectionNames = TriAnnotConfig.TRIANNOT_CONF.keys()
        sectionNames.sort()
        for sectionName in sectionNames:
            if sectionName == 'Runtime':
                continue
            section = etree.Element('section', {'name':sectionName})
            TriAnnotConfig._addSubEntriesToElement(section, TriAnnotConfig.TRIANNOT_CONF[sectionName])
            root.append(section)
        if prettyXml:
            TriAnnotConfig.indent(root)
        return etree.tostring(root, encoding)


    @staticmethod
    def _addSubEntriesToElement(parentXMLElt, dictToTreat):
        allKeysAreNumeric = True
        keys = dictToTreat.keys()
        for key in keys:
            try:
                int(key)
            except:
                allKeysAreNumeric = False
                break
        if allKeysAreNumeric:
            keys.sort(key=int) #sort in numeric order by calling int on each list value
        else:
            keys.sort()
        for key in keys:
            entry = etree.Element('entry', {'key':key})
            if type(dictToTreat[key]) is dict:
                TriAnnotConfig._addSubEntriesToElement(entry, dictToTreat[key])
            else:
                entry.text = dictToTreat[key]
            parentXMLElt.append(entry)


    @staticmethod
    def indent(xmlElt, level=0):
        i = "\n" + level*"\t"
        if len(xmlElt):
            if not xmlElt.text or not xmlElt.text.strip():
                xmlElt.text = i + "\t"
            if not xmlElt.tail or not xmlElt.tail.strip():
                xmlElt.tail = i
            for xmlElt in xmlElt:
                TriAnnotConfig.indent(xmlElt, level+1)
            if not xmlElt.tail or not xmlElt.tail.strip():
                xmlElt.tail = i
        else:
            if level and (not xmlElt.tail or not xmlElt.tail.strip()):
                xmlElt.tail = i


    @staticmethod
    def combineLinkedConfigurationSections():
        # Initializations
        allAdditionalSections = dict()

        # Browse the list of section and merge what needs to be merge
        for sectionName in TriAnnotConfig.TRIANNOT_CONF.keys():
            # Get the list of additional section to include in the current section
            additionalSections = TriAnnotConfig.getAdditionalConfigurationSectionsToInclude(sectionName)

            if len(additionalSections) > 0:
                for additionalSection in additionalSections:
                    # Check that there is no third layer of inheritance in the XML files
                    if len(TriAnnotConfig.getAdditionalConfigurationSectionsToInclude(additionalSection)) > 0:
                        raise AssertionError('The current TriAnnot version does not support multiple layers of inheritance between the XML configuration files !')
                    # Store the names of all sections included into other sections
                    allAdditionalSections[additionalSection] = 1
                    # Effective recursive merging
                    TriAnnotConfig.TRIANNOT_CONF[sectionName] = Utils.recursiveDictMerge(TriAnnotConfig.TRIANNOT_CONF[sectionName], TriAnnotConfig.TRIANNOT_CONF[additionalSection], ['commonParameters', 'execParameters', 'parserParameters'])

                # Now that all the additional sections to merge have been merged with the current section we could remove the "additionalConfigurationSectionsToInclude" entry
                del TriAnnotConfig.TRIANNOT_CONF[sectionName]['additionalConfigurationSectionsToInclude']

                # Remove the satisfied dependencies from the list of dependencies (ie. the "configurationDependencies" entry)
                if TriAnnotConfig.isConfigValueDefined('%s|%s' % (sectionName, 'configurationDependencies')):
                    TriAnnotConfig.removeSatisfiedDependencies(sectionName, additionalSections)

        # Delete sections fully included into other sections
        TriAnnotConfig.removeConfigurationSections(allAdditionalSections.keys())


    @staticmethod
    def removeSatisfiedDependencies(sectionName, listOfSatisfiedDependencies):
        # Initializations
        dependenciesToRemove = []

        # Get the list of identifiers of the dependencies to remove
        for dependenceId, dependenceValue in TriAnnotConfig.TRIANNOT_CONF[sectionName]['configurationDependencies'].items():
            if dependenceValue in listOfSatisfiedDependencies:
                dependenciesToRemove.append(dependenceId)

        # Effective removal
        for identifier in dependenciesToRemove:
            del TriAnnotConfig.TRIANNOT_CONF[sectionName]['configurationDependencies'][identifier]


    @staticmethod
    def removeConfigurationSections(listOfSectionsToRemove):
        for sectionName in listOfSectionsToRemove:
            if TriAnnotConfig.TRIANNOT_CONF.has_key(sectionName):
                del TriAnnotConfig.TRIANNOT_CONF[sectionName]


    @staticmethod
    def getAdditionalConfigurationSectionsToInclude(sectionName):
        # Initializations
        additionalConfigurationSections = []

        # Additional configuration sections (listed through the "additionalConfigurationSectionsToInclude" entry in the XML configuration file of the corresponding tool)
        if TriAnnotConfig.isConfigValueDefined('%s|%s' % (sectionName, 'additionalConfigurationSectionsToInclude')):
            additionalConfigurationSections.extend(TriAnnotConfig.getConfigValue('%s|%s' % (sectionName, 'additionalConfigurationSectionsToInclude')).values())

        return additionalConfigurationSections


    ###################################################
    ###  Global/Merged configuration file creation  ###
    ###################################################
    @staticmethod
    def generateGlobalConfigurationFile(destinationDirectory, triannotVersion, overwriteExistingFile = False):
        # Initializations
        filePrefix = 'TriAnnot_full_configuration'
        fileSuffix = ''
        configurationFile = None
        cpt = 1

        # Do not overwrite the existing global file if requested
        if not overwriteExistingFile:
            while os.path.exists(os.path.join(destinationDirectory, filePrefix + fileSuffix + '.xml')):
                fileSuffix = '_%s' % cpt
                cpt += 1

        # Creation of the merged file
        globalConfigurationFileFullPath = os.path.join(destinationDirectory, filePrefix + fileSuffix + '.xml')
        TriAnnotConfig.logger.info("Creation of a global XML configuration file that will contain every cleaned configuration sections: %s" % (globalConfigurationFileFullPath))

        try:
            configurationFile = open(globalConfigurationFileFullPath, 'w')
            configurationFile.write(TriAnnotConfig.getConfAsXMLString('ISO-8859-1', True, triannotVersion))
        except IOError:
            TriAnnotConfig.logger.error("Could not create the following global XML configuration file: %s" % (globalConfigurationFileFullPath))
            raise
        finally:
            if configurationFile is not None:
                configurationFile.close()
            else:
                globalConfigurationFileFullPath = None

        return globalConfigurationFileFullPath


# Logger initialization
TriAnnotConfig.logger = logging.getLogger("TriAnnot.TriAnnotConfig")
TriAnnotConfig.logger.addHandler(logging.NullHandler())
