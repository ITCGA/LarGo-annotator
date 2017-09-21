#!/usr/bin/env perl

use strict;
use warnings;
use diagnostics;

## TriAnnot modules
use TriAnnot::ParserLauncher;

my $launcher = TriAnnot::ParserLauncher->new();
$launcher->getOptions();
$launcher->checkOptions();
$launcher->createAllSubDirectories();
$launcher->initFileLoggers(sprintf("%03s", $launcher->{Program_id}) . '_parsing.log', sprintf("%03s", $launcher->{Program_id})  . '_parsing.debug');
$launcher->checkConfigurationInPython('_' . sprintf("%03s", $launcher->{Program_id}) . '_parsing');
$launcher->main();
# Creation of an informative file that summarizes the analysis
$launcher->prepareAbstractFile(sprintf("%03s", $launcher->{Program_id}) . '_' . $launcher->{programName} . '_parsing_result.xml');
