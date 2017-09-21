#!/usr/bin/env perl

package TriAnnot::Tools::GetInfo;


##################################################
## Included modules
##################################################
## Perl modules
use strict;
use Data::Dumper;
## TriAnnot modules
use TriAnnot::Tools::Logger;
use TriAnnot::Config::ConfigFileLoader;

sub new{
	my ($class, %attrs) = @_;
	my $self;
	$self->{_database} = $attrs{database};
	$logger->debug("Database for GetInfo: " . $self->{_database});
	$self->{id} = $attrs{id};
	$logger->debug("ID for GetInfo: " . $self->{id});
	$self->{_type} = $attrs{type};
	$logger->debug("Type for GetInfo: " . $self->{_type});
	bless $self => $class;
	$self->_execute();
	return $self;
}

sub _parseResult {
	my ($self, $result) = @_ ;
	my $id = '';
	my $description = '';
	my $sequence = '';
	foreach my $line (split("\n", $result)) {
		if($line =~ /^>(\S+)\s(.*)/) {
			$id = $1;
			$description = $2;
		}
		else{
			chomp $line;
			$sequence .= $line;
		}
	}
	$self->{description} = $description;
	$logger->debug("Description of the query: " . $self->{description});
	$self->{length} = length($sequence);
	$logger->debug("Length of the query: " . $self->{length});
}

sub _execute {
	my ($self) = @_;
	my $cmd = $TRIANNOT_CONF{PATHS}->{soft}->{'fastacmd'}->{'bin'} . ' -d ' . $self->{_database} . ' -p ' . $self->{_type} . ' -s ' . $self->{id};
	$logger->debug("Command line for fastacmd will be " . $cmd);
	my $result = `$cmd`;
	$self->_parseResult($result);
}
1;
