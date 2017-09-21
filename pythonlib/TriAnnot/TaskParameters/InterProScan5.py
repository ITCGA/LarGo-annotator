#!/usr/bin/env python

from TriAnnot.TriAnnotTaskParameters import *

class InterProScan5 (TriAnnotTaskParameters):

    def __init__(self):
        pass


    def checkTaskParameters(self):
        # Call the checkTaskParameters method of the parent class
        errorsList = super(self.__class__, self).checkTaskParameters()

        # Check task specific parameters
        if self.parameters.has_key('useGeneModelData') and self.parameters['useGeneModelData'] == 'yes':
            if not self.parameters.has_key('geneModelGffFile') or self.parameters['geneModelGffFile'] is None:
                errorsList.append("Task %s - Gene Model data must be used (useGeneModelData parameter set to yes) but there is no Gene Model GFF file defined (with the geneModelGffFile parameter).." % self.taskDescription)

        if self.parameters.has_key('geneModelGffFile') and self.parameters['geneModelGffFile'] is not None:
            if not self.parameters.has_key('useGeneModelData') or self.parameters['useGeneModelData'] == 'no':
                errorsList.append("Task %s - A Gene Model GFF file has been selected but the useGeneModelData switch is set to no (or not defined) !" % self.taskDescription)

        return errorsList
