#!/usr/bin/env python

import os
from TriAnnot.Task.FuncAnnot import *

class FuncAnnot_ORF (FuncAnnot):

    def __init__(self):
        # Call parent class constructor
        super(self.__class__, self).__init__()


    def preExecutionTreatments(self):
        # Do not execute pre-execution treatments several time
        if self.preExecutionTreatmentsCompleted:
            return

        # Determine the number of ORF to annotate to adapt the number of thread to use
        self._analyzeSequenceFile()
        self.logger.info("Number of ORF to annotate: %s" % self.numberOfSequenceToAnnotate)

        # No ORF case -> Cancel all tasks that depends on FuncAnnot and run FuncAnnot with only 1 thread
        if self.numberOfSequenceToAnnotate == 0:
            self.logger.info("%s didn't have any ORF sequence to annotate. All depending tasks will be canceled !" % (self.getDescriptionString().capitalize()))
            self.needToCancelDependingTasks = True
            self.cancelDependingTasksReason = "There is no ORF sequence to annotate"
            self.parameters['nbCore'] = 1

        elif (self.numberOfSequenceToAnnotate == 1):
            # Very unlikely event protection - Sanity check
            assert (self.parameters.has_key('nbCore')), 'nbCore parameter is not set ! This should never happened !'

        # Several ORFs to annotate
        # Display an error if we are on a subAnnotation with more than 1 ORF to annotate
        # Runners (ie. Batch queueing systems) that does not support job submission from computing nodes (Qsub of Qsub for SGE) are not compatible
        # -> We will have to switch to the fallback runner and then we could reduce the number of thread to 1
        elif self.numberOfSequenceToAnnotate > 1:
            if self.parameters['isSubAnnotation'] == 'yes':
                self.needToAbortPipeline = True
                self.abortPipelineReason = "%s has more than one ORF to annotate in subAnnotation mode !" % (self.getDescriptionString().capitalize())
            else:
                self.parameters['nbCore'] = 1

        self.preExecutionTreatmentsCompleted = True
