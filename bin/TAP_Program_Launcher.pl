#!/usr/bin/env perl

use strict;
use warnings;
use diagnostics;

## TriAnnot modules
use TriAnnot::ProgramLauncher;

my $launcher = TriAnnot::ProgramLauncher->new();
$launcher->getOptions();
$launcher->checkOptions();
$launcher->createAllSubDirectories();
$launcher->initFileLoggers(sprintf("%03s", $launcher->{Program_id}) . '_execution.log', sprintf("%03s", $launcher->{Program_id})  . '_execution.debug');
$launcher->checkConfigurationInPython('_' . sprintf("%03s", $launcher->{Program_id}) . '_execution');
$launcher->main();
# Creation of an informative file that summarizes the analysis
$launcher->prepareAbstractFile(sprintf("%03s", $launcher->{Program_id}) . '_' . $launcher->{programName} . '_execution_result.xml');
