#!/usr/bin/env python

# Basic python modules
import logging

class TriAnnotSequenceGoals (object):

    def __init__(self, chunkInterval, chunkMaxSize, currentOffset):
        # Logger
        self.logger = logging.getLogger("TriAnnot.TriAnnotSequenceGoals")
        self.logger.addHandler(logging.NullHandler())

        #self.logger.debug("Creating a new %s object" % (self.__class__.__name__))

        # Atributes
        self.nextGoal = chunkInterval
        self.nextGoalIsAStart = True
        self.nextStartGoal = chunkInterval
        self.nextEndGoal = 0

        self.chunkInterval = chunkInterval
        self.chunkMaxSize = chunkMaxSize
        self.chunkStartOffsets = [currentOffset]
        self.chunkEndOffsets = []

        self.alreadyCountedBases = 0
