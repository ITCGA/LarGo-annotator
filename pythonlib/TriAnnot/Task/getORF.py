#!/usr/bin/env python

import os
from TriAnnot.TriAnnotTask import *
from TriAnnot.TriAnnotConfig import *


class getORF (TriAnnotTask):

    def __init__(self):
        pass


    def postParsingTreatments(self):
        # Abort the pipeline if required data does not exist in the abstract file or cancel dependencies if the number of discovered ORF is equal to 0
        if self.orfDiscoveryStatistics is None or not self.orfDiscoveryStatistics.has_key('number_of_discovered_ORF'):
            self.needToAbortPipeline = True
            self.abortPipelineReason = "Could not retrieve data about the generated ORF file for %s" % (self.getDescriptionString())

        elif int(self.orfDiscoveryStatistics['number_of_discovered_ORF']) == 0:
            self.logger.info("%s didn't find any ORF. Cancelling all depending tasks !" % (self.getDescriptionString().capitalize()))
            self.needToCancelDependingTasks = True
            self.cancelDependingTasksReason = "No ORF found by getORF in the input sequence"
