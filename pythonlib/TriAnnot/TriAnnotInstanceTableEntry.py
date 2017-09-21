#!/usr/bin/env python

import logging

from TriAnnot.TriAnnotStatus import *

class TriAnnotInstanceTableEntry (object):

    # Constructor
    def __init__(self, sequenceName = "", sequenceType = "", sequenceStartOffset = 0, sequenceEndOffset = 0, sequenceSize = 0):
        # Logger
        self.logger = logging.getLogger("TriAnnot.TriAnnotAnalysis")
        self.logger.addHandler(logging.NullHandler())

        #self.logger.debug("Creating a new %s object" % (self.__class__.__name__))

        # Attributes
        self.sequenceName = sequenceName
        self.sequenceType = sequenceType
        self.sequenceStartOffset = sequenceStartOffset
        self.sequenceEndOffset = sequenceEndOffset
        self.sequenceSize = sequenceSize

        self.chunkName = sequenceName + '_chunk_' + '0'
        self.chunkNumber = 0
        self.chunkStartOffset = 0
        self.chunkEndOffset = 0
        self.chunkSize = 0

        self.instanceSubmissionDate = None
        self.instanceStartDate = None
        self.instanceEndDate = None
        self.instanceStatus = TriAnnotStatus.PENDING
        self.instanceProgression = 0
        self.instanceExecutionTime = None
        self.instanceFastaFileFullPath = None
        self.instanceDirectoryFullPath = None
        self.instanceDirectorySize = 0
        self.instanceJobIdentifier = None
        self.instanceMonitoringCommand = None
        self.instanceKillCommand = None
        self.instanceBackupArchive = None


    def convertToDict(self):
        # Initializations
        cleanDict = dict()

        for attributeName in dir(self):
            attributeValue = getattr(self, attributeName)
            if not attributeName.startswith('__') and not callable(attributeValue) and not attributeName == 'logger':
                cleanDict[attributeName] = attributeValue

        return cleanDict
