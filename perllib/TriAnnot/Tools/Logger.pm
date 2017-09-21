#!/usr/bin/env perl

package TriAnnot::Tools::Logger;

##################################################
## Included modules
##################################################
## Perl modules
use strict;
use warnings;
use diagnostics;
use Log::Log4perl;
use Log::Log4perl::Layout;
use Log::Log4perl::Level;
use Exporter 'import';
use TriAnnot::Config::ConfigFileLoader;


our $logger;
our @EXPORT = qw($logger);

$logger = Log::Log4perl->get_logger('');

# Define stdout Appender, by default messages will only be logged to stdout
# In order to log messages to a file, you need to call the initFileLoggers
# method with the name of folder where to create the log files
my $stdout_layout = Log::Log4perl::Layout::PatternLayout->new("%m%n");
my $stdout_appender =  Log::Log4perl::Appender->new(
		"Log::Log4perl::Appender::Screen",
		name      => 'screenlog',
		stderr    => 0);
$stdout_appender->layout($stdout_layout);
#$stdout_appender->threshold($INFO);
$logger->add_appender($stdout_appender);
$logger->level($INFO);

sub initFileLoggers {
	my ($path, $std_log, $debug_log) = @_;

	my $file_layout = Log::Log4perl::Layout::PatternLayout->new("%m%n");
	my $file_appender = Log::Log4perl::Appender->new(
			"Log::Log4perl::Appender::File",
			name      => 'filelog',
			mode      => 'append',
			filename  => $path . '/' . $std_log);
	$file_appender->layout($file_layout);
	$file_appender->threshold($INFO);
	$logger->add_appender($file_appender);

	if ($TriAnnot::Config::ConfigFileLoader::TRIANNOT_CONF_VERBOSITY == 3) {
		my $debug_layout = Log::Log4perl::Layout::PatternLayout->new("%d %5p> %F{1}:%L %M - %m%n");
		my $debug_appender = Log::Log4perl::Appender->new(
				"Log::Log4perl::Appender::File",
				name      => 'debuglog',
				mode      => 'append',
				filename  => $path . '/' . $debug_log);
		$debug_appender->layout($debug_layout);
		$logger->add_appender($debug_appender);
		#$stdout_appender->threshold($DEBUG);
		$logger->level($DEBUG);
	}
}

1;
