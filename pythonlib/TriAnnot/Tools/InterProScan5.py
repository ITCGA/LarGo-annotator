#!/usr/bin/env python

import os
from TriAnnot.TriAnnotTool import *

class InterProScan5 (TriAnnotTool):

    def __init__(self):
        pass


    def getMandatoryDefinitionsList(self):
        return ['gffFile', 'emblFile', 'EMBLFormat']
