#!/usr/bin/env python

import os
from TriAnnot.TriAnnotTool import *

class FuncAnnot_IWGSC (TriAnnotTool):

    def __init__(self):
        pass


    def getMandatoryDefinitionsList(self):
        return ['gffFile', 'emblFile', 'EMBLFormat']
