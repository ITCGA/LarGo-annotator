#!/usr/bin/env python

import logging
from copy import copy

class ColoredFormatter (logging.Formatter):
    # Class variables
    SET_BOLD_COLOR = "\033[1;%dm"
    RESET_COLOR = "\033[0m"

    Black = 30 # foreground black
    Red = 31 # foreground red
    Green = 32 # foreground green
    Yellow = 33 # foreground yellow
    Blue = 34 # foreground blue
    Magenta = 35 # foreground magenta
    Cyan = 36 # foreground cyan
    White = 97 # foreground white

    MSG_COLORS = {
        'INFO': White,
        'DEBUG': Yellow,
        'WARNING': Magenta,
        'ERROR': Red,
        'CRITICAL': Red,
    }

    # Constructor
    def __init__(self, customFormat):
        logging.Formatter.__init__(self, customFormat)

    # Override format method
    def format(self, record):
        # Records are passed to each handlers (they are cached) so if we want to have colored log on screen but plain log in files we can't change the record directly
        recordCopy = copy(record)

        # Change the level name of the record copy
        if recordCopy.levelname in ColoredFormatter.MSG_COLORS:
            recordCopy.levelname = ColoredFormatter.SET_BOLD_COLOR % ColoredFormatter.MSG_COLORS[record.levelname] + record.levelname + ColoredFormatter.RESET_COLOR

        # Call the format method of the parent class with the record copy as parameter
        return logging.Formatter.format(self, recordCopy)
