#!/usr/bin/env perl

package TriAnnot::Programs::FuncAnnot_ORF;

##################################################
## Documentation POD
##################################################

##################################################
## Modules
##################################################
## Perl modules
use strict;
use warnings;
use diagnostics;

## TriAnnot modules
use TriAnnot::Config::ConfigFileLoader;
use TriAnnot::Tools::Logger;

## Inherits
use base ("TriAnnot::Programs::FuncAnnot");


##################################################
## Methods
##################################################
=head1 TriAnnot::Programs::FuncAnnot_ORF - Methods
=cut

################
# Constructor
################

sub new {
	my ($class, %attrs) = @_;

	# Call the constructor of the parent class (TriAnnot::Programs::FuncAnnot)
	my $self = $class->SUPER::new(\%attrs);

	bless $self => $class;

	return $self;
}


#####################
## Method _execute()
#####################

sub _execute {

	# Recovers parameters
	my $self = shift;

	# Call the _execute method of the parent class (FuncAnnot)
	$self->SUPER::_execute();
}


############################
## Stage list creation
############################

sub _createXMLStageList {

	# Recovers parameters
	my $self = shift;

	$logger->debug('');
	$logger->debug('Creation of the XML stagelist: ' . $self->{'program_launcher_stagelist'});

	# Prepare the step file for the Sub-TriAnnot pipeline
	open(XML_STAGELIST, '>' . $self->{'program_launcher_stagelist'}) or $logger->logdie('Error: Cannot create/open file: ' . $self->{'program_launcher_stagelist'});

	print XML_STAGELIST '<?xml version="1.0" encoding="ISO-8859-1"?>' . "\n\n";
	print XML_STAGELIST '<analysis triannot_version="' . $TRIANNOT_CONF{VERSION} . '" description="FuncAnnot ORF - Stagelist">' . "\n\n";

	for (my $sequenceNumber = 1; $sequenceNumber <= $self->{'Number_of_sequence'}; $sequenceNumber++) {
		print XML_STAGELIST "\t" . '<program id="' . $sequenceNumber . '" step="' . $self->{'step'} . '" type="' . $self->{'programName'} . '" sequence="' . 'sequence_' . $sequenceNumber . '.seq' . '">' . "\n";
		print XML_STAGELIST "\t\t" . '<dependences></dependences>' . "\n";
		print XML_STAGELIST "\t\t" . '<parameter name="database_STEP01">' . $self->{'database_STEP01'} . '</parameter>' . "\n";
		print XML_STAGELIST "\t\t" . '<parameter name="isSubAnnotation">yes</parameter>' . "\n";
		print XML_STAGELIST "\t\t" . '<parameter name="nbCore">' . $self->{'nbCore'} . '</parameter>' . "\n";
		print XML_STAGELIST "\t\t" . '<parameter name="gff_to_annotate">' . $self->{'gff_to_annotate'} . '</parameter>' . "\n";
		print XML_STAGELIST "\t" . '</program>' . "\n\n";
	}
	print XML_STAGELIST '</analysis>' . "\n";

	close(XML_STAGELIST);

	return 0; # Success
}


############################
## Annotation steps
############################

sub _executeAnnotationSteps {

	# Recovers parameters
	my $self = shift;

	# Initializations
	my ($Step_result, $Conserved_annotation) = ('', '');

	# Run Functionnal Annotation on the selected ORF file
	$self->blastAnnotation('STEP01');
	# $self->{'annotationResults'}->{'STEP01'} = '-'; # Debug

	if ($self->{'annotationResults'}->{'STEP01'} eq '-') {
		$self->{'annotationResults'}->{'Final'} = 'Note=' . $TRIANNOT_CONF{$self->{'programName'}}->{'AnnotationSteps'}->{'NoResultMessage'};
	} else {
		$self->{'annotationResults'}->{'Final'} = $self->{'annotationResults'}->{'STEP01'};
	}

	# Add all executed command lines to the debug log
	$logger->debug('');
	$logger->debug('List of all executed command lines for this annotation procedure (Pseudogene search):');
	$logger->debug('');

	foreach my $Step_name (sort keys(%{$self->{'commandLines'}})) {
		$logger->debug("\t" . $Step_name . ': ' . $self->{'commandLines'}->{$Step_name});
		$logger->debug('');
	}

	return 0; # Success
}


1;
