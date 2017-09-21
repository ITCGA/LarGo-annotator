#!/usr/bin/env python

from TriAnnot.TriAnnotTaskParameters import *
from TriAnnot.TriAnnotConfig import *

class Blast (TriAnnotTaskParameters):

    def __init__(self):
        pass

    # Abstract method
    def deeperDatabaseCompatibilityCheck(self):
        # Initializations and log
        errorsList = []
        self.logger.debug("Overridden deeperDatabaseCompatibilityCheck method is called for task #%s" % self.taskDescription)

        for parameterName in TriAnnotTaskParameters.getListOfDatabaseParameters(self.taskType, self.parameters.keys()):
            # Initializations
            requiredFormat = ''

            if not self.parameters.has_key('type'):
                raise AssertionError("The mandatory <%s> parameter is missing and the TriAnnotPipeline execution should have already been stopped !" % 'type')
            else:
                # Get the list of available formats for the selected database (already checked earlier in the code)
                availableFormats = TriAnnotConfig.getConfigValue("%s|%s|%s" % ('PATHS|db', self.parameters[parameterName], 'availableFormats'))

                # Get the name of the mandatory format
                if (self.parameters['type'] == 'BLASTN' or self.parameters['type'] == 'TBLASTN' or self.parameters['type'] == 'TBLASTX'):
                    requiredFormat = 'NucleicBlast'
                else:
                    # BLASTP and BLASTX needs a databank of protein
                    requiredFormat = 'ProteicBlast'

                if requiredFormat not in availableFormats.values():
                    errorsList.append("Missing mandatory format for database <%s>: the <%s> parameter is set to <%s> so the database must exist in <%s> format !" % (self.parameters[parameterName], 'type', self.parameters['type'], requiredFormat))

        return errorsList
