#!/usr/bin/env python

import os
from TriAnnot.TriAnnotTask import *
from TriAnnot.TriAnnotConfig import *


class InterProScan (TriAnnotTask):

    def __init__(self):
        pass


    def needToLaunchSubProcesses(self):
        if self.runner.jobType == 'execution':
            return True
        else:
            return False


    def abort(self, killOnAbort = False):
        if self.runner.jobType == 'execution':
            # We can't automatically kill execution tasks..
            self.logger.info("InterProScan runs multiple external tools during its execution process (locally or through SGE depending of the configuration).")
            self.logger.info("Therefore, TriAnnot will not automatically kill InterProScan tasks and you will have to manually track & kill all generated sub processes or jobs .. Sorry !")
        else:
            # ..but we can kill parsing tasks just fine
            super(self.__class__, self).abort(killOnAbort)
