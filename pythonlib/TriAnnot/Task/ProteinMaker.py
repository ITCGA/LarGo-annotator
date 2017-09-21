#!/usr/bin/env python

import os
from TriAnnot.TriAnnotTask import *
from TriAnnot.TriAnnotConfig import *


class ProteinMaker (TriAnnotTask):

    def __init__(self):
        pass


    def postExecutionTreatments(self):
        # Abort the pipeline if required data does not exist in the abstract file or cancel dependencies if the number of generated protein sequence is equal to 0
        if self.proteinCreationStatistics is None or not self.proteinCreationStatistics.has_key('number_of_conserved_sequence'):
            self.needToAbortPipeline = True
            self.abortPipelineReason = "Could not retrieve data about the protein sequence file creation for %s" % (self.getDescriptionString())

        elif int(self.proteinCreationStatistics['number_of_conserved_sequence']) == 0:
            self.logger.info("%s didn't generate any protein sequence. Cancelling all depending tasks !" % (self.getDescriptionString().capitalize()))
            self.needToCancelDependingTasks = True
            self.cancelDependingTasksReason = "There is no protein sequence to annotate"
