#!/usr/bin/env python

import os
from TriAnnot.TriAnnotTask import *
from TriAnnot.TriAnnotConfig import *


class SequenceMasker (TriAnnotTask):

    def __init__(self):
        pass


    def postExecutionTreatments(self):
        if self.maskingStatistics is None or not self.maskingStatistics.has_key('percent_mask') or not self.maskingStatistics.has_key('max_successive_unmasked'):
            self.needToAbortPipeline = True
            self.abortPipelineReason = "Could not retrieve masking statistics for %s" % (self.getDescriptionString(), self.maskingStatistics['percent_mask'])

        elif float(self.maskingStatistics['percent_mask']) >= float(TriAnnotConfig.getConfigValue('Global|Max_percent_mask')):
            self.logger.info("%s has generated a sequence masked at %s%%. Cancelling tasks that use this sequence" % (self.getDescriptionString().capitalize(), self.maskingStatistics['percent_mask']))
            self.needToCancelDependingTasks = True
            self.cancelDependingTasksReason = "%s sequence is too masked" % (self.parameters['masked_sequence'])

        elif float(self.maskingStatistics['max_successive_unmasked']) <= float(TriAnnotConfig.getConfigValue('Global|Min_non_mask')):
            self.logger.info("%s has generated a sequence with a longest unmasked region of %s bp. Cancelling tasks that use this sequence" % (self.getDescriptionString().capitalize(), self.maskingStatistics['max_successive_unmasked']))
            self.needToCancelDependingTasks = True
            self.cancelDependingTasksReason = "%s sequence unmasked regions are too short" % (self.parameters['masked_sequence'])
