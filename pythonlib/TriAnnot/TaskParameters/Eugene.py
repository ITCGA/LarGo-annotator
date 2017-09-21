#!/usr/bin/env python

from TriAnnot.TriAnnotTaskParameters import *
import TriAnnot.Utils

class Eugene (TriAnnotTaskParameters):

    def __init__(self):
        pass


    def checkTaskParameters(self):
        # Call the checkTaskParameters method of the parent class
        errorsList = super(self.__class__, self).checkTaskParameters()

        # Special treatment for some Eugene parameters
        # 1) Check the existence, the access rights and the version of the provided .par file
        errorsList.extend(self.checkEugeneParameterFile('eugeneParFileFullPath'))

        # 2) Check the format of the "evidenceFile" parameters
        errorsList.extend(self.checkEvidenceFileParameter('evidenceFile'))

        # Return all errors
        return errorsList


    def checkEugeneParameterFile(self, parameterName):
        # Initializations
        errorsList = []

        # Check the existence, the access rights and the version of the provided .par file
        if self.parameters.has_key(parameterName):
            if not Utils.isExistingFile(self.parameters[parameterName]):
                errorsList.append("The value of the <%s> parameter does not correspond to a full path to an existing and accessible Eugene parameter file (Collected value: %s)" % (parameterName, self.parameters[parameterName]))
            else:
                try:
                    parFileHandle = open(self.parameters[parameterName], 'r')
                except IOError:
                    errorsList.append("Could not open/read this Eugene parameter file: %s" % (self.parameters[parameterName]))

                # Get the list of volume files
                for line in parFileHandle:
                    if line.startswith('EuGene.version'):
                        parFileVersionNumber = line.rstrip().split()[-1]
                        if TriAnnotConfig.isConfigValueDefined('PATHS|soft|Eugene|version'):
                            eugeneVersion = TriAnnotConfig.getConfigValue('PATHS|soft|Eugene|version')
                            if parFileVersionNumber != eugeneVersion:
                                errorsList.append("The version of the selected Eugene parameter file (%s) does not correspond to the version of the installed Eugene executable (%s)" % (parFileVersionNumber, eugeneVersion))
                        else:
                            raise AssertionError("The <%s> configuration value does not exists but it should be defined at the step of the check procedure" % 'PATHS|soft|Eugene|version')

                parFileHandle.close()

        return errorsList


    def checkEvidenceFileParameter(self, evidenceFileParameterName):
        # Initializations
        errorsList = []

        # Check the format of all values of the parameters that collect the names of the evidence file
        if self.parameters.has_key(evidenceFileParameterName):
            # Build regexp pattern
            regexpPattern = re.compile(r'([\w\.-]+)\|(\w[\w\.-]*)', re.IGNORECASE)

            # Check every value
            if type(self.parameters[evidenceFileParameterName]) == list:
                for index, parameterValue in enumerate(self.parameters[evidenceFileParameterName]):
                    match = regexpPattern.search(parameterValue)
                    if match is None:
                        errorsList.append("The format of the value <%s> of the occurence number #%d of the <%s> parameter is not valid (Valid example: 3_AUGUSTUS_wheat.gff|predictor0.gff3)" % (parameterValue, index, evidenceFileParameterName))
            else:
                match = regexpPattern.search(self.parameters[evidenceFileParameterName])
                if match is None:
                    errorsList.append("The format of the value <%s> of the <%s> parameter is not valid (Valid format example: 3_AUGUSTUS_wheat.gff|predictor0.gff3)" % (parameterValue, index, evidenceFileParameterName))

        return errorsList
