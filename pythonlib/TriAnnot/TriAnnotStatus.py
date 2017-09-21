#!/usr/bin/env python

class TriAnnotStatus (object):
    # Class variables
    PENDING = 1
    SUBMITED = 2
    SUBMITED_EXEC = 3
    SUBMITED_PARSING = 4
    RUNNING = 5
    RUNNING_EXEC = 6
    RUNNING_PARSING = 7
    FINISHED_EXEC = 8
    FINISHED_PARSING = 9
    COMPLETED = 10
    ERROR = 11
    CANCELED = 12

    STATUS_NAMES = { 1: 'PENDING',
                     2: 'SUBMITED',
                     3: 'SUBMITED_EXEC',
                     4: 'SUBMITED_PARSING',
                     5: 'RUNNING',
                     6: 'RUNNING_EXEC',
                     7: 'RUNNING_PARSING',
                     8: 'FINISHED_EXEC',
                     9: 'FINISHED_PARSING',
                     10: 'COMPLETED',
                     11: 'ERROR',
                     12: 'CANCELED'
                    }

    @classmethod
    def getStatusCode(Class, statusStringToSearch):
        for statusCode, statusString in TriAnnotStatus.STATUS_NAMES.items():
            if statusString == statusStringToSearch:
                return statusCode
        raise LookupError("<%s> is not a valid status string" % (statusStringToSearch))

    @classmethod
    def getStatusName(Class, statusCodeToSearch):
        if TriAnnotStatus.STATUS_NAMES.has_key(statusCodeToSearch):
            return TriAnnotStatus.STATUS_NAMES[statusCodeToSearch]
        raise LookupError("<%s> is not a valid status code" % (statusCodeToSearch))
