#!/usr/bin/env python

import os
import logging


from TriAnnot.TriAnnotConfig import *
from TriAnnot.TriAnnotTool import *
import Utils

class TriAnnotConfigurationChecker (object):
    # Class variables initializations
    allParametersDefinitions = {}

    #####################
    ###  Constructor  ###
    #####################
    def __init__(self, commandLineConfigFile, useCommandLineConfigFileOnly):
        # Logger
        self.logger = logging.getLogger("TriAnnot.TriAnnotConfigurationChecker")
        self.logger.addHandler(logging.NullHandler())

        self.logger.debug("Creating a new %s object" % (self.__class__.__name__))

        # Attributes
        self.bypassSyntaxValidation = False

        self.xmlFilesToCheck = None

        self.invalidConfigurationFiles = None
        self.xmlSyntaxErrors = None
        self.missingMandatoryConfigurationSections = None
        self.missingMandatoryConfigurationEntries = None
        self.brokenConfigurationDependencies = None
        self.parametersDefinitionsErrors = None
        self.invalidPathErrors = None

        # Hardcoded lists of mandatory configuration sections and entries
        # Note: in addition, the configuration file of each tool must contains a section with the same name than the tool (ie. RepeatMasker section for Repeatmasker tool)
        self.mandatoryConfigurationSectionsList = ['Global', 'DIRNAME', 'SubFeaturesOrder', 'AminoNames', 'EMBL', 'DatabaseFilesExtensions', 'GeneticCode', 'PATHS', 'Runners']
        self.mandatoryConfigurationEntriesList = ['EMBL|formats', 'PATHS|db', 'PATHS|soft', 'PATHS|matrices', 'PATHS|config', 'PATHS|index', 'Runners|Local']

        # Hardcoded list of the first level entries of the PATHS section:
        self.pathsSectionFirstLevelEntriesList = ['db', 'soft', 'matrices', 'config', 'index']

        # Determine if the syntax of the XML files can be checked with XMLlint or need to be bypassed because XMLlint is not available on the machine
        self.checkIfXmlSyntaxCanBeControled()

        # Get the exhaustive list of XML files to check
        self.getConfigurationFilesFullList(commandLineConfigFile, useCommandLineConfigFileOnly);


    ############################
    ###  Tools availability  ###
    ############################
    def checkIfXmlSyntaxCanBeControled(self):
        # Activate the bypass if XMLlint is not available
        if not Utils.isXmllintAvailable():
            self.bypassSyntaxValidation = True
            self.logger.warning("XMLlint is not available on your system ! TriAnnot will not be able to validate the syntax of the XML configuration files from their XML schemas !")


    ##########################################
    ###  Configuration file list recovery  ###
    ##########################################
    def getConfigurationFilesFullList(self, commandLineConfigFile, useCommandLineConfigFileOnly):
        # Initializations
        self.xmlFilesToCheck = []

        # Build the list
        if useCommandLineConfigFileOnly:
            if commandLineConfigFile is not None:
                # Only the XML configuration file given to TriAnnot through the -c/--config argument will be considered
                self.xmlFilesToCheck.append({'path': commandLineConfigFile, 'name': os.path.basename(commandLineConfigFile), 'type': 'cmd'})
        else:
            # Add every XML configuration file located in the conf directory to the list (if they are not disabled by the .disabled suffix)
            configurationDirectoryFullPath = TriAnnotConfigurationChecker.determineConfigurationDirectoryFullPath()
            activatedXmlFiles = TriAnnotConfigurationChecker.getListOfActivatedXmlConfigurationFiles(configurationDirectoryFullPath)
            self.xmlFilesToCheck.extend(activatedXmlFiles)

            # Add the custom XML configuration file given to TriAnnot through the -c/--config to the list
            if commandLineConfigFile is not None:
                self.xmlFilesToCheck.append({'path': commandLineConfigFile, 'name': os.path.basename(commandLineConfigFile), 'type': 'cmd'})


    @staticmethod
    def getListOfActivatedXmlConfigurationFiles(xmlDirectoryFullPath, globalConfigFilePrefix = 'TriAnnotConfig'):
        # Initializations
        listOfActivatedXmlConfigurationFiles = []

        # Reject all files that are not activated XML configuration files
        if xmlDirectoryFullPath is not None:
            activatedXmlFiles = glob.glob( "%s/*.xml" % xmlDirectoryFullPath)
            for activatedXmlFile in activatedXmlFiles:
                if globalConfigFilePrefix in activatedXmlFile:
                    xmlType = 'global'
                else:
                    xmlType = 'tool'
                listOfActivatedXmlConfigurationFiles.append({'path': activatedXmlFile, 'name': os.path.basename(activatedXmlFile), 'type': xmlType})

        return listOfActivatedXmlConfigurationFiles


    @staticmethod
    def determineConfigurationDirectoryFullPath(environmentVariable = 'TRIANNOT_ROOT', configurationDirectoryName = 'conf'):
        # Initializations
        configurationDirectoryFullPath = None

        # Try to determine the path to the configuration directory from an environment variable..
        triAnnotPath = os.getenv(environmentVariable, None)

        if triAnnotPath is not None and os.path.isdir(os.path.join(os.path.realpath(triAnnotPath), configurationDirectoryName)):
            configurationDirectoryFullPath = os.path.join(os.path.realpath(triAnnotPath), configurationDirectoryName)

        # ..or from the path of the main TriAnnot executable
        elif os.path.isdir(os.path.join(os.path.realpath(os.path.dirname(sys.argv[0])), "..", configurationDirectoryName)):
            configurationDirectoryFullPath = os.path.join(os.path.realpath(os.path.dirname(sys.argv[0])), "..", configurationDirectoryName)
        else:
            raise RuntimeError('TriAnnot did not managed to determine the configuration directory path.. Please make sure that TriAnnot is fully configured for your environment.')

        return configurationDirectoryFullPath


    ####################################################################################
    ###  Check the existence and access right of every configuration files to check  ###
    ####################################################################################
    def checkConfigurationFilesExistence(self):
        # Initializations & Log
        self.invalidConfigurationFiles = []
        self.nbInvalidConfigurationFiles = 0

        self.logger.info('The existence and access rights of each XML configuration file will now be checked')

        # Check if the mandatory configuration entries of the global configuration files exists
        for configurationFile in self.xmlFilesToCheck:
            self.logger.debug("Checking <%s> configuration file" % configurationFile['name'])
            if not Utils.isExistingFile(configurationFile['path']):
                self.invalidConfigurationFiles.append(configurationFile['path'])
                self.nbInvalidConfigurationFiles += 1


    def displayInvalidConfigurationFiles(self):
        # Errors can be displayed if they haven't been collected
        if self.invalidConfigurationFiles is None:
            self.logger.warning("The list of missing/unreadable configuration files can't be displayed if the existence of the files haven't been checked")
            return 1

        # Display the list of missing entries by configuration section
        if self.nbInvalidConfigurationFiles > 0:
            self.logger.info("Total number of missing/unreadable configuration files: %d !" % self.nbInvalidConfigurationFiles)
            self.logger.info('Please check the path and the access rights of every of the following files before executing TriAnnot again !')
            self.logger.error('List of missing/unreadable configuration files:')
            for invalidFile in self.invalidConfigurationFiles:
                self.logger.error(invalidFile)
        else:
            self.logger.info('All the XML configuration files exists and are readable')

        return 0


    ###############################
    ###  XML syntax validation  ###
    ###############################
    def checkXmlSyntaxOfConfigurationFiles(self):
        # Initializations
        self.xmlSyntaxErrors = dict()
        self.nbErrorContainingXmlFiles = 0

        self.logger.info('The syntax of the various XML configuration files will now be checked')

        if self.bypassSyntaxValidation:
            self.logger.warning('Bypassing XML syntax validation (XMLlint is not installed)')
        else:
            # Get the XML schema file
            xmlSchemaFullPath = Utils.determineXMLSchemaPath('TriAnnotConfig.xsd')

            if xmlSchemaFullPath is not None:
                # Run xmllint to check the syntax of each configuration file against the schema
                for configurationFile in self.xmlFilesToCheck:
                    self.logger.debug("Checking <%s> configuration file" % configurationFile['name'])
                    try:
                        cmd = ['xmllint', '--noout', '--schema', xmlSchemaFullPath, configurationFile['path']]
                        validationResult = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT).communicate()[0]
                        pattern = re.compile(configurationFile['name'] + ' validates')
                        if not pattern.search(validationResult):
                            self.xmlSyntaxErrors[configurationFile['name']] = validationResult
                            self.nbErrorContainingXmlFiles += 1
                    except:
                        self.logger.debug(traceback.format_exc())
                        raise RuntimeError("An unexpected error occured during the syntax validation procedure of the following configuration file: %s" % configurationFile['path'])
            else:
                self.logger.warning('Bypassing XML syntax validation (XML schema is missing)')


    def displayXmlSyntaxErrors(self):
        # Errors can be displayed if they haven't been collected
        if self.xmlSyntaxErrors is None:
            self.logger.warning("XML syntax errors can't be listed if they haven't been collected")
            return 1

        # Display XML syntax errors for each tool
        if self.nbErrorContainingXmlFiles > 0:
            self.logger.info("Total number of XML configuration files that contains at least one syntax error: %d" % self.nbErrorContainingXmlFiles)
            self.logger.info('Please fix every error described below before executing TriAnnot again !')
            for xmlFile, errorLines in self.xmlSyntaxErrors.items():
                self.logger.error("Error(s) reported by XMLlint in <%s>:" % xmlFile)
                self.logger.error("\n****************************************\n%s****************************************" % errorLines)
        else:
            self.logger.info('No syntax error has been detected')

        return 0


    #####################################################################
    ###  Check the existence of the mandatory sections & subsections  ###
    #####################################################################
    def checkMandatoryConfigurationSections(self):
        # Initializations & Log
        self.missingMandatoryConfigurationSections = {'global': [], 'tool': []}
        self.nbMissingMandatoryConfigurationSections = 0

        self.logger.info('The existence of every mandatory configuration sections will now be checked')

        # Check if the mandatory configuration sections of the global configuration files exists
        for mandatorySection in self.mandatoryConfigurationSectionsList:
            if not TriAnnotConfig.isConfigValueDefined(mandatorySection):
                self.missingMandatoryConfigurationSections['global'].append(mandatorySection)
                self.nbMissingMandatoryConfigurationSections += 1

        # Check if each tool configuration file has its own section
        for configurationFile in self.xmlFilesToCheck:
            sectionName = os.path.splitext(configurationFile['name'])[0]
            if configurationFile['type'] == 'tool' and not TriAnnotConfig.isConfigValueDefined(sectionName):
                self.missingMandatoryConfigurationSections['tool'].append(sectionName)
                self.nbMissingMandatoryConfigurationSections += 1


    def displayMissingMandatoryConfigurationSections(self):
        # Errors can be displayed if they haven't been collected
        if self.missingMandatoryConfigurationSections is None:
            self.logger.warning("Missing mandatory configuration sections can't be listed if they haven't been collected")
            return 1

        # Display the list of missing entries by configuration section
        if self.nbMissingMandatoryConfigurationSections > 0:
            self.logger.info("Total number of missing mandatory configuration sections in your configurations files: %d !" % self.nbMissingMandatoryConfigurationSections)
            self.logger.info('Please create/add the missing configuration sections before running triAnnot again !')

            if len(self.missingMandatoryConfigurationSections['global']) > 0:
                self.logger.info('Missing configuration sections in the global configuration files (TriAnnotConfig_* files):')
                for missingSection in self.missingMandatoryConfigurationSections['global']:
                    self.logger.error(missingSection)

            if len(self.missingMandatoryConfigurationSections['tool']) > 0:
                self.logger.info('Missing configuration sections in the tools configuration files:')
                for missingSection in self.missingMandatoryConfigurationSections['tool']:
                    self.logger.error("The <%s> section should be defined in <%s>" % (missingSection, missingSection + '.xml'))
        else:
            self.logger.info('All mandatory configuration sections are present in your configuration files')

        return 0


    def checkMandatoryConfigurationEntries(self):
        # Initializations & Log
        self.missingMandatoryConfigurationEntries = []
        self.nbMissingMandatoryConfigurationEntries = 0

        self.logger.info('The existence of every mandatory configuration entries of the global configuration files will now be checked')

        # Check if the mandatory configuration entries of the global configuration files exists
        for mandatoryEntry in self.mandatoryConfigurationEntriesList:
            if not TriAnnotConfig.isConfigValueDefined(mandatoryEntry):
                self.missingMandatoryConfigurationEntries.append(mandatoryEntry)
                self.nbMissingMandatoryConfigurationEntries += 1


    def displayMissingMandatoryConfigurationEntries(self):
        # Errors can be displayed if they haven't been collected
        if self.missingMandatoryConfigurationEntries is None:
            self.logger.warning("Missing mandatory configuration entries can't be listed if they haven't been collected")
            return 1

        # Display the list of missing entries by configuration section
        if self.nbMissingMandatoryConfigurationEntries > 0:
            self.logger.info("Total number of missing mandatory configuration entries in your global configurations files (TriAnnotConfig_* files): %d !" % self.nbMissingMandatoryConfigurationEntries)
            self.logger.info('Please create/add the missing configuration entries listed below before running triAnnot again !')
            self.logger.error('List of missing mandatory configuration entries:')
            for missingEntry in self.missingMandatoryConfigurationEntries:
                self.logger.error(missingEntry)
        else:
            self.logger.info('All mandatory configuration entries are present in your configuration files')

        return 0


    #########################################################################
    ###  Check if dependencies between configuration files are fulfilled  ###
    #########################################################################
    def checkConfigurationDependencies(self):
        # Initializations & Log
        self.brokenConfigurationDependencies = dict()
        self.nbBrokenConfigurationDependencies = 0

        self.logger.info('The validity of every configuration dependencies will now be checked')

        # Loop through the various configuration sections and check if every dependencies (ie. configuration path like PATHS|soft|fastacmd|bin for example) correspond to a well defined configuration entry
        for sectionName in TriAnnotConfig.TRIANNOT_CONF.keys():
            if TriAnnotConfig.TRIANNOT_CONF[sectionName].has_key('configurationDependencies') and type(TriAnnotConfig.TRIANNOT_CONF[sectionName]['configurationDependencies']) == dict:
                for pathToCheck in TriAnnotConfig.TRIANNOT_CONF[sectionName]['configurationDependencies'].values():
                    if not TriAnnotConfig.isConfigValueDefined(pathToCheck):
                        if not self.brokenConfigurationDependencies.has_key(sectionName):
                            self.brokenConfigurationDependencies[sectionName] = []
                        self.brokenConfigurationDependencies[sectionName].append(pathToCheck)
                        self.nbBrokenConfigurationDependencies += 1


    def displayBrokenConfigurationDependencies(self):
        # Errors can be displayed if they haven't been collected
        if self.brokenConfigurationDependencies is None:
            self.logger.warning("Broken configuration dependencies can't be listed if they haven't been collected")
            return 1

        # Display the list of missing entries by configuration section
        if self.nbBrokenConfigurationDependencies > 0:
            self.logger.info("Total number of broken dependencies in the various sections of your configuration files: %d !" % self.nbBrokenConfigurationDependencies)
            self.logger.info('Please check the configuration paths described below before executing TriAnnot again !')
            for sectionName, listOfMissingEntries in self.brokenConfigurationDependencies.items():
                self.logger.error("Broken dependencies for <%s>:" % sectionName)
                for missingEntry in listOfMissingEntries:
                    self.logger.error(missingEntry)
        else:
            self.logger.info('All dependencies are fulfilled')

        return 0


    #####################################################
    ###  Parameters definitions recovery and control  ###
    #####################################################
    def checkAllParametersDefinitions(self):
        # Initializations & Log
        self.parametersDefinitionsErrors = dict()
        self.nbParametersDefinitionsErrors = 0

        self.logger.info('The definition of every parameters of each supported tool will now be checked')

        # Launch the retrieval + check of the parametersDefinitions for all configuration sections associated to a tool
        for sectionName in TriAnnotConfig.TRIANNOT_CONF.keys():
            if TriAnnotConfigurationChecker.isToolSection(sectionName):
                # Raise an exception if a section is present multiple times in the section list
                if TriAnnotConfigurationChecker.allParametersDefinitions.has_key(sectionName):
                    raise AssertionError('There should never be any duplicates in the list of sections during parameters definitions recovery ')
                else:
                    newToolObject = TriAnnotTool(sectionName)
                    newToolObject.retrieveParametersDefinitions()
                    newToolObject.checkParametersDefinitions()

                    self.parametersDefinitionsErrors[sectionName] = newToolObject.configurationErrors
                    self.nbParametersDefinitionsErrors += len(newToolObject.configurationErrors)

                    TriAnnotConfigurationChecker.allParametersDefinitions[sectionName] = newToolObject.parametersDefinitions


    def displayParametersDefinitionsErrors(self):
        # Errors can be displayed if they haven't been collected
        if self.parametersDefinitionsErrors is None:
            self.logger.warning("Badly defined parameters can't be listed if they haven't been collected")
            return 1

        # Display the list of badly defined parameters
        if self.nbParametersDefinitionsErrors > 0:
            self.logger.info("Total number of badly defined parameters in the various configuration files of the supported tools: %d !" % self.nbParametersDefinitionsErrors)
            self.logger.info('Please check the configuration entries described below before executing TriAnnot again !')
            for toolName, listOfdefinitionErrors in self.parametersDefinitionsErrors.items():
                if len(listOfdefinitionErrors) > 0:
                    self.logger.error("Invalid parameters definitions found in the <%s> XML configuration file:" % toolName)
                    for definitionError in listOfdefinitionErrors:
                        self.logger.error(definitionError)
        else:
            self.logger.info("All parameter's definitions are valid")

        return 0


    @staticmethod
    def isToolSection(sectionName):
        # The current section is a tool section if it contains at least one of the following entry: commonParameters, execParameters, parserParameters
        for mainEntry in ('commonParameters', 'execParameters', 'parserParameters'):
            if TriAnnotConfig.isConfigValueDefined('%s|%s' % (sectionName, mainEntry)):
                return True

        return False


    ###############################################
    ###  Check files and directories existence  ###
    ###############################################
    def checkPathsDefinedInConfigurationFiles(self):
        # Initializations & Log
        self.invalidPathErrors = dict()
        self.nbInvalidPathErrors = 0

        self.logger.info('The existence of every database, soft, matrix, etc. referenced in the TriAnnotConfig_PATHS XML configuration file will now be checked')

        self.checkDbsPaths()
        self.checkSoftsPaths()
        self.checkMatricesPaths()
        self.checkExternalConfigurationPaths()
        self.checkIndexesPaths()


    def displayInvalidPathErrors(self):
        # Errors can be displayed if they haven't been collected
        if self.invalidPathErrors is None:
            self.logger.warning("Invalid paths can't be listed if they haven't been collected")
            return 1

        # Display the list of badly defined parameters
        if self.nbInvalidPathErrors > 0:
            self.logger.info("Total number of invalid paths in the TriAnnotConfig_PATHS XML configuration file: %d !" % self.nbInvalidPathErrors)
            self.logger.info('Please check the configuration entries described below before executing TriAnnot again !')

            for firstlevelEntry in self.pathsSectionFirstLevelEntriesList:
                if len(self.invalidPathErrors[firstlevelEntry]) > 0:
                    self.logger.error("Invalid paths of the <%s> category:" % firstlevelEntry)
                    for errorInThisCategory in self.invalidPathErrors[firstlevelEntry]:
                        self.logger.error(errorInThisCategory)
        else:
            self.logger.info('All defined paths point towards existing and readable files or directories')

        return 0


    ##################
    ###  Database  ###
    def checkDbsPaths(self):
        # Initializations and Log
        self.invalidPathErrors['db'] = []

        self.logger.info('Checking all the databases described in the XML configuration file')

        # Check if there is at least one database defined
        if not type(TriAnnotConfig.TRIANNOT_CONF['PATHS']['db']) is dict or len(TriAnnotConfig.TRIANNOT_CONF['PATHS']['db']) == 0:
            self.logger.warning("It seems that you have no database defined in your <PATHS|db> configuration entry. You will probably need to edit your configuration before running a real analysis with TriAnnot.")
            TriAnnotConfig.TRIANNOT_CONF['PATHS']['db'] = {}

        # Check the definition of the database entry + Check the existence and access rights of every files that composed this database
        for dbName in TriAnnotConfig.TRIANNOT_CONF['PATHS']['db'].keys():
            dbDefinition = TriAnnotConfig.TRIANNOT_CONF['PATHS']['db'][dbName]

            if self.isValidDatabaseDefinition(dbDefinition, dbName):
                for databaseFormat in dbDefinition['availableFormats'].values():
                    if not TriAnnotConfig.isConfigValueDefined("DatabaseFilesExtensions|%s" % databaseFormat):
                        self.invalidPathErrors['db'].append("The following format is not defined in the TriAnnotConfig_FileExtensions XML configuration file: %s" % databaseFormat)
                    elif not TriAnnotConfig.isConfigValueDefined("DatabaseFilesExtensions|%s|MandatoryFiles" % databaseFormat):
                        self.invalidPathErrors['db'].append("No <MandatoryFiles> entry found for the following format: %s" % databaseFormat)
                    else:
                        self.checkDbPath(dbName, databaseFormat, dbDefinition['path'])

        self.nbInvalidPathErrors += len( self.invalidPathErrors['db'])


    def isValidDatabaseDefinition(self, definitionToCheck, databaseName):
        # Initialization
        mandatoryAttributesList = ['version', 'path', 'availableFormats']

        self.logger.debug("Checking the definition of the <%s> database entry" % databaseName)

        # Check if the existence of the mandatory sub-entries
        if type(definitionToCheck) is not dict:
            self.invalidPathErrors['db'].append("Database <%s> - All the mandatory entries (%s) are not defined !" % (databaseName, ', '.join(mandatoryAttributesList)))
            return False

        for mandatoryAttribute in mandatoryAttributesList:
            if not definitionToCheck.has_key(mandatoryAttribute) or definitionToCheck[mandatoryAttribute] == '' or (type(definitionToCheck[mandatoryAttribute]) is dict and len(definitionToCheck[mandatoryAttribute].values()) < 1):
                self.invalidPathErrors['db'].append("Database <%s> - The mandatory <%s> entry is not defined or is empty !" % (databaseName, mandatoryAttribute))
                return False

        return True


    def checkDbPath(self, databaseName, databaseFormat, databaseFilePathWithoutExtension):
        # Initializations
        databaseFilePathToCheck = []

        self.logger.debug("Checking the paths of the files of the <%s> database (in <%s> format)" % (databaseName, databaseFormat))

        # Get the list of path to check from a Blast volume file if it exists
        if TriAnnotConfig.isConfigValueDefined("DatabaseFilesExtensions|%s|BlastVolumeFileExtension" % databaseFormat):
            volumeFileFullPath = databaseFilePathWithoutExtension + TriAnnotConfig.getConfigValue("DatabaseFilesExtensions|%s|BlastVolumeFileExtension" % databaseFormat)
            if os.path.isfile(volumeFileFullPath) and os.access(volumeFileFullPath, os.R_OK):
                databaseFilePathToCheck.extend(self.getVolumesFromBlastAliasFile(volumeFileFullPath))

        # When there is no volume file (small Blast database or other format) we only have one path to check
        if len(databaseFilePathToCheck) == 0:
            databaseFilePathToCheck.append(databaseFilePathWithoutExtension)

        # Check the existence of every mandatory file for the current database
        for pathToCheck in databaseFilePathToCheck:
            mandatoryFileDict = TriAnnotConfig.getConfigValue("DatabaseFilesExtensions|%s|MandatoryFiles" % databaseFormat)
            
            for element in mandatoryFileDict.keys():
                mandatoryFileExistenceSwitch = 0;
                possibleExtensionList = mandatoryFileDict[element]['PossibleExtensions'].values()

                for extension in possibleExtensionList:
                    if Utils.isExistingFile(pathToCheck + extension):
                        mandatoryFileExistenceSwitch = 1
                        if element == 'main':
                            TriAnnotConfig.TRIANNOT_CONF['PATHS']['db'][databaseName][databaseFormat + 'Extension'] = extension

                if mandatoryFileExistenceSwitch == 0:
                    self.invalidPathErrors['db'].append("Database <%s> - Format <%s> - One of the mandatory file for this database is missing or unreadable ! The authorized extensions for this file are: %s" % (databaseName, databaseFormat, ', '.join(possibleExtensionList)))


    def getVolumesFromBlastAliasFile(self, aliasFilePath):
        # Initializations
        volumes = []
        aliasFile = None
        dbFilesFolder = os.path.dirname(aliasFilePath)

        # Try to open the file that contains the list of volume files
        try:
            aliasFile = open(aliasFilePath, 'r')
        except IOError:
            self.logger.error("Could not open/read this Blast alias file: %s" % (aliasFilePath))
            raise

        # Get the list of volume files
        for line in aliasFile:
            if line.startswith('DBLIST'):
                volumes = line.rstrip().split(' ')
                volumes.pop(0)
                volumes = [os.path.join(dbFilesFolder, volume) for volume in volumes]
        aliasFile.close()

        return volumes

    ##################
    ###  Software  ###
    def checkSoftsPaths(self):
        # Initializations and Log
        self.invalidPathErrors['soft'] = []

        self.logger.info('Checking all the programs/softwares described in the XML configuration file')

        # Check if there is at least one database defined
        if not type(TriAnnotConfig.TRIANNOT_CONF['PATHS']['soft']) is dict or len(TriAnnotConfig.TRIANNOT_CONF['PATHS']['soft']) == 0:
            self.invalidPathErrors['soft'].append("It seems that you have no program/software defined in your <PATHS|soft> configuration entry. This should never be the case and it indicates that your configuration is broken. Please double check your configuration files and try to run TriAnnot again.")
            TriAnnotConfig.TRIANNOT_CONF['PATHS']['soft'] = {}

        # Check the definition of the software entry + Check the existence and the rights (access + execution) of the executable file
        for softName in TriAnnotConfig.TRIANNOT_CONF['PATHS']['soft'].keys():
            softDefinition = TriAnnotConfig.TRIANNOT_CONF['PATHS']['soft'][softName]

            if self.isValidSoftDefinition(softDefinition, softName):
                self.logger.debug("Checking the path of the <%s> software executable" % softName)
                if not Utils.isExecutableTool(softDefinition['bin']):
                    self.invalidPathErrors['soft'].append("Software <%s> - The following path defined through the <bin> entry does not correspond to a valid executable program: %s" % (softName, softDefinition['bin']))

        self.nbInvalidPathErrors += len( self.invalidPathErrors['soft'])


    def isValidSoftDefinition(self, definitionToCheck, softwareName):
        # Initialization
        mandatoryAttributesList = ['version', 'bin']

        self.logger.debug("Checking the definition of the <%s> software entry" % softwareName)

        # Check if the existence of the mandatory sub-entries
        if type(definitionToCheck) is not dict:
            self.invalidPathErrors['soft'].append("Software <%s> - All the mandatory entries (%s) are not defined !" % (softwareName, ', '.join(mandatoryAttributesList)))
            return False

        for mandatoryAttribute in mandatoryAttributesList:
            if not definitionToCheck.has_key(mandatoryAttribute) or definitionToCheck[mandatoryAttribute] == '':
                self.invalidPathErrors['soft'].append("Software <%s> - The mandatory <%s> entry is not defined or is empty !" % (softwareName, mandatoryAttribute))
                return False

        return True


    ################
    ###  Matrix  ###
    def checkMatricesPaths(self):
        # Initializations and Log
        self.invalidPathErrors['matrices'] = []

        self.logger.info('Checking all the matrices described in the XML configuration file')

        # Check if there is at least one matrix defined
        if not type(TriAnnotConfig.TRIANNOT_CONF['PATHS']['matrices']) is dict or len(TriAnnotConfig.TRIANNOT_CONF['PATHS']['matrices']) == 0:
            self.logger.warning("It seems that you have no matrix defined in your <PATHS|matrices> configuration entry. You will probably need to edit your configuration before running a real analysis with TriAnnot.")
            TriAnnotConfig.TRIANNOT_CONF['PATHS']['matrices'] = {}

        for programName in TriAnnotConfig.TRIANNOT_CONF['PATHS']['matrices'].keys():
            for matrixName in TriAnnotConfig.TRIANNOT_CONF['PATHS']['matrices'][programName].keys():
                matrixDefinition = TriAnnotConfig.TRIANNOT_CONF['PATHS']['matrices'][programName][matrixName]

                if self.isValidMatrixDefinition(matrixDefinition, programName, matrixName):
                    self.logger.debug("Checking the path of the <%s> matrix file for program <%s>" % (matrixName, programName))
                    if matrixDefinition['type'] == 'file':
                        if not Utils.isExistingFile(matrixDefinition['path']):
                            self.invalidPathErrors['matrices'].append("Matrix <%s> for program <%s> - The following matrix file is missing or unreadable: %s" % (matrixName, programName, matrixDefinition['path']))
                    elif matrixDefinition['type'] == 'directory':
                        if not Utils.isExistingDirectory(matrixDefinition['path']):
                            self.invalidPathErrors['matrices'].append("Matrix <%s> for program <%s> - The following matrix containing directory is missing or unreadable: %s" % (matrixName, programName, matrixDefinition['path']))

        self.nbInvalidPathErrors += len(self.invalidPathErrors['matrices'])


    def isValidMatrixDefinition(self, definitionToCheck, programName, matrixName):
        # Initialization
        mandatoryAttributesList = ['type', 'path']
        validTypes = ['file', 'directory']

        self.logger.debug("Checking the definition of the <%s> matrix entry for program <%s>" % (programName, matrixName))

        # Check if the existence of the mandatory sub-entries
        if type(definitionToCheck) is not dict:
            self.invalidPathErrors['matrices'].append("Matrix <%s> for program <%s> - All the mandatory entries (%s) are not defined !" % (matrixName, programName, ', '.join(mandatoryAttributesList)))
            return False

        for mandatoryAttribute in mandatoryAttributesList:
            if not definitionToCheck.has_key(mandatoryAttribute) or definitionToCheck[mandatoryAttribute] == '':
                self.invalidPathErrors['matrices'].append("Matrix <%s> for program <%s> - The mandatory <%s> entry is not defined or is empty !" % (matrixName, programName, mandatoryAttribute))
                return False
            else:
                if mandatoryAttribute == 'type' and definitionToCheck['type'] not in validTypes:
                    self.invalidPathErrors['matrices'].append("Matrix <%s> for program <%s> - The value of the <%s> entry is not valid ! Possible values are: %s" % (matrixName, programName, mandatoryAttribute, ', '.join(validTypes)))
                    return False

        return True


    #########################
    ###  External Config  ###
    def checkExternalConfigurationPaths(self):
        # Initializations and Log
        self.invalidPathErrors['config'] = []

        self.logger.info('Checking all the external configuration files/directories described in the XML configuration file')

        # Check if there is at least one database defined
        if not type(TriAnnotConfig.TRIANNOT_CONF['PATHS']['config']) is dict or len(TriAnnotConfig.TRIANNOT_CONF['PATHS']['config']) == 0:
            self.logger.warning("It seems that you have no external configuration file or directory defined in your <PATHS|config> configuration entry. You will probably need to edit your configuration before running a TriAnnot analysis that includes Eugene or Augustus for example.")
            TriAnnotConfig.TRIANNOT_CONF['PATHS']['config'] = {}

        # Check the definition of the software entry + Check the existence and the rights (access + execution) of the executable file
        for extConfigName in TriAnnotConfig.TRIANNOT_CONF['PATHS']['config'].keys():
            extConfigDefinition = TriAnnotConfig.TRIANNOT_CONF['PATHS']['config'][extConfigName]

            if self.isValidExternalConfigDefinition(extConfigDefinition, extConfigName):
                self.logger.debug("Checking the path of the external configuration entry for program <%s>" % extConfigName)
                if extConfigDefinition['type'] == 'file':
                    if not Utils.isExistingFile(extConfigDefinition['path']):
                        self.invalidPathErrors['config'].append("External configuration for program <%s> - The following external configuration file is missing or unreadable: %s" % (extConfigName, extConfigDefinition['path']))
                elif extConfigDefinition['type'] == 'directory':
                    if not Utils.isExistingDirectory(extConfigDefinition['path']):
                        self.invalidPathErrors['config'].append("External configuration for program <%s> - The following external configuration containing directory is missing or unreadable: %s" % (extConfigName, extConfigDefinition['path']))

        self.nbInvalidPathErrors += len( self.invalidPathErrors['config'])


    def isValidExternalConfigDefinition(self, definitionToCheck, extConfigName):
        # Initialization
        mandatoryAttributesList = ['type', 'path']
        validTypes = ['file', 'directory']

        self.logger.debug("Checking the definition of the external configuration entry for program <%s>" % extConfigName)

        # Check if the existence of the mandatory sub-entries
        if type(definitionToCheck) is not dict:
            self.invalidPathErrors['config'].append("External configuration for program <%s> - All the mandatory entries (%s) are not defined !" % (extConfigName, ', '.join(mandatoryAttributesList)))
            return False

        for mandatoryAttribute in mandatoryAttributesList:
            if not definitionToCheck.has_key(mandatoryAttribute) or definitionToCheck[mandatoryAttribute] == '':
                self.invalidPathErrors['config'].append("External configuration for program <%s> - The mandatory <%s> entry is not defined or is empty !" % (extConfigName, mandatoryAttribute))
                return False
            else:
                if mandatoryAttribute == 'type' and definitionToCheck['type'] not in validTypes:
                    self.invalidPathErrors['config'].append("External configuration for program <%s> - The value of the <%s> entry is not valid ! Possible values are: %s" % (extConfigName, mandatoryAttribute, ', '.join(validTypes)))
                    return False

        return True


    ###############
    ###  Index  ###
    def checkIndexesPaths(self):
        # Initializations and Log
        self.invalidPathErrors['index'] = []

        self.logger.info('Checking all the indexes described in the XML configuration file')

        # Check if there is at least one matrix defined
        if not type(TriAnnotConfig.TRIANNOT_CONF['PATHS']['index']) is dict or len(TriAnnotConfig.TRIANNOT_CONF['PATHS']['index']) == 0:
            self.logger.warning("It seems that you have no index file defined in your <PATHS|index> configuration entry. You will probably need to edit your configuration before running a TriAnnot analysis that includes GTtallymer.")
            TriAnnotConfig.TRIANNOT_CONF['PATHS']['index'] = {}

        for programName in TriAnnotConfig.TRIANNOT_CONF['PATHS']['index'].keys():
            for indexName in TriAnnotConfig.TRIANNOT_CONF['PATHS']['index'][programName].keys():
                indexDefinition = TriAnnotConfig.TRIANNOT_CONF['PATHS']['index'][programName][indexName]

                if self.isValidIndexDefinition(indexDefinition, programName, indexName):
                    self.checkIndexPath(indexName, programName, indexDefinition['path'])

        self.nbInvalidPathErrors += len(self.invalidPathErrors['index'])


    def checkIndexPath(self, indexName, programName, indexFilePathWithoutExtension):
        # Initializations
        databaseFilePathToCheck = []

        self.logger.debug("Checking the path of the <%s> index file for program <%s>" % (indexName, programName))

        #
        if TriAnnotConfig.isConfigValueDefined("IndexFilesExtensions|%s|MandatoryFiles" % programName):
            mandatoryFileDict = TriAnnotConfig.getConfigValue("IndexFilesExtensions|%s|MandatoryFiles" % programName)

            for element in mandatoryFileDict.keys():
                mandatoryFileExistenceSwitch = 0;
                possibleExtensionList = mandatoryFileDict[element]['PossibleExtensions'].values()

                for extension in possibleExtensionList:
                    if Utils.isExistingFile(indexFilePathWithoutExtension + extension):
                        mandatoryFileExistenceSwitch = 1

                if mandatoryFileExistenceSwitch == 0:
                    self.invalidPathErrors['index'].append("Index <%s> for program <%s> - One of the mandatory file for this index is missing or unreadable ! The authorized extensions for this file are: %s" % (indexName, programName, ', '.join(possibleExtensionList)))
        else:
            self.invalidPathErrors['index'].append("Index <%s> for program <%s> - The list of file extensions for this type of index is not defined in the TriAnnotConfig_FileExtensions XML configuration file ! Please edit this global configuration file before running TriAnnot again." % (indexName, programName))


    def isValidIndexDefinition(self, definitionToCheck, programName, indexName):
        # Initialization
        mandatoryAttributesList = ['creationDate', 'path']

        self.logger.debug("Checking the definition of the <%s> index entry for program <%s>" % (indexName, programName))

        # Check if the existence of the mandatory sub-entries
        if type(definitionToCheck) is not dict:
            self.invalidPathErrors['index'].append("Index <%s> for program <%s> - All the mandatory entries (%s) are not defined !" % (indexName, programName, ', '.join(mandatoryAttributesList)))
            return False

        for mandatoryAttribute in mandatoryAttributesList:
            if not definitionToCheck.has_key(mandatoryAttribute) or definitionToCheck[mandatoryAttribute] == '':
                self.invalidPathErrors['index'].append("Index <%s> for program <%s> - The mandatory <%s> entry is not defined or is empty !" % (indexName, programName, mandatoryAttribute))
                return False

        return True
