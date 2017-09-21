#!/usr/bin/env python

import os
from TriAnnot.TriAnnotTask import *
from TriAnnot.TriAnnotConfig import *
from TriAnnot import *

class SIMsearch (TriAnnotTask):

    def __init__(self):
        pass

    def abort(self, killOnAbort = False):
        if self.runner.jobType == 'execution':
        # We can't automatically kill execution tasks..
            self.logger.info("SIMsearch is a complete pipeline that runs multiple external tools during its execution process.")
            self.logger.info("Therefore, TriAnnot will not automatically kill SIMsearch tasks and you will have to manually track & kill all generated sub processes or jobs .. Sorry !")
        else:
            # ..but we can kill parsing tasks just fine
            super(self.__class__, self).abort(killOnAbort)
