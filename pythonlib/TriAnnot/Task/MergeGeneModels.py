#!/usr/bin/env python

import os
from TriAnnot.TriAnnotTask import *
from TriAnnot.TriAnnotConfig import *
from TriAnnot import *

class MergeGeneModels (TriAnnotTask):

    def __init__(self):
        pass


    def abort(self, killOnAbort = False):
        if self.runner.jobType == 'execution':
            # We can't automatically kill execution tasks..
            self.logger.info("MergeGeneModels executes some external tools during it's execution process.")
            self.logger.info("Therefore, TriAnnot will not automatically kill MergeGeneModels tasks and you will have to manually track & kill all generated sub processes or jobs.. Sorry !")
        else:
            # ..but we can kill parsing tasks just fine
            super(self.__class__, self).abort(killOnAbort)
