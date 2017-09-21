#!/usr/bin/env perl

package TriAnnot::Programs::FuncAnnot_IWGSC;

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
=head1 TriAnnot::Programs::FuncAnnot_IWGSC - Methods
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

	# Prepare the paraloop input file that contains a command line to execute (i.e. a call of TAP_Program_Launcher)
	open(XML_STAGELIST, '>' . $self->{'program_launcher_stagelist'}) or $logger->logdie('Error: Cannot create/open file: ' . $self->{'program_launcher_stagelist'});

	print XML_STAGELIST '<?xml version="1.0" encoding="ISO-8859-1"?>' . "\n\n";
	print XML_STAGELIST '<analysis triannot_version="' . $TRIANNOT_CONF{VERSION} . '" description="FuncAnnot IWGSC - Stagelist">' . "\n\n";

	for (my $protein_number = 1; $protein_number <= $self->{'Number_of_sequence'}; $protein_number++) {
		print XML_STAGELIST "\t" . '<program id="' . $protein_number . '" step="' . $self->{'step'} . '" type="' . $self->{'programName'} . '" sequence="' . 'sequence_' . $protein_number . '.seq' . '">' . "\n";
		print XML_STAGELIST "\t\t" . '<dependences></dependences>' . "\n";
		print XML_STAGELIST "\t\t" . '<parameter name="database_STEP01">' . $self->{'database_STEP01'} . '</parameter>' . "\n";
		print XML_STAGELIST "\t\t" . '<parameter name="database_STEP02">' . $self->{'database_STEP02'} . '</parameter>' . "\n";
		print XML_STAGELIST "\t\t" . '<parameter name="database_STEP03">' . $self->{'database_STEP03'} . '</parameter>' . "\n";
		print XML_STAGELIST "\t\t" . '<parameter name="database_STEP04">' . $self->{'database_STEP04'} . '</parameter>' . "\n";
		print XML_STAGELIST "\t\t" . '<parameter name="database_STEP06">' . $self->{'database_STEP06'} . '</parameter>' . "\n";
		print XML_STAGELIST "\t\t" . '<parameter name="nbCore">' . $self->{'nbCore'} . '</parameter>' . "\n";
		print XML_STAGELIST "\t\t" . '<parameter name="gff_to_annotate">' . $self->{'gff_to_annotate'} . '</parameter>' . "\n";
		print XML_STAGELIST "\t\t" . '<parameter name="isSubAnnotation">yes</parameter>' . "\n";
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

	# Run Functionnal Annotation on the selected simple protein fasta file

	$self->blastAnnotation('STEP01');
	# $self->{'annotationResults'}->{'STEP01'} = '-'; # Debug
	$Conserved_annotation = $self->_rejectHypotheticalAnnotation('STEP01');

	if ( $Conserved_annotation eq '-' ) {
		$self->blastAnnotation('STEP02');
		# $self->{'annotationResults'}->{'STEP02'} = '-'; # Debug
		$Conserved_annotation = $self->_rejectHypotheticalAnnotation('STEP02');

		if ( $Conserved_annotation eq '-' ) {
			$self->hmmscanAnnotation('STEP03');
			# $self->{'annotationResults'}->{'STEP03'} = '-'; # Debug
			$Conserved_annotation = $self->{'annotationResults'}->{'STEP03'};

			if( $Conserved_annotation eq '-' ) {
				$self->blastAnnotation('STEP04');
				# $self->{'annotationResults'}->{'STEP04'} = '-'; # Debug
				$Conserved_annotation = $self->_rejectHypotheticalAnnotation('STEP04');

				if( $Conserved_annotation eq '-' ) {
					# With the current IWGSC annotation guideline the STEP05 is identical to the STEP02 but Hypothetical like results are conserved
					# Therefore the Blast analysis is not relaunched, we just recovers Hypothetical results from STEP02
					$Conserved_annotation = $self->_virtual_STEP05_execution();
					# $Conserved_annotation = '-'; # Debug

					if( $Conserved_annotation eq '-' ) {
						$self->blastAnnotation('STEP06');
						# $self->{'annotationResults'}->{'STEP06'} = 'Note=Warning - Possible Transposable Element - Ugly transposase of debug'; # Debug
						# In this step we keep a result only if the annotated protein lools like a Transposable Element
						$Conserved_annotation = $self->_keepSimilarToTransposableElementOnly('STEP06');

						if( $Conserved_annotation eq '-' ) {
							$logger->debug('');
							$logger->debug("\t" . 'All stages of annotation were unsuccessful => Hypothetical protein');
							$Conserved_annotation = 'Note=' . $TRIANNOT_CONF{$self->{'programName'}}->{AnnotationSteps}->{'NoResultMessage'};
						} # END Func Annot
					}# END step 06
				}# END step 05
			}# END step 04
		} # END step 03
	} # END step 02

	$self->{'annotationResults'}->{'Final'} = $Conserved_annotation;

	# Add all executed command lines to the debug log
	$logger->debug('');
	$logger->debug('List of all executed command lines for this annotation procedure (IWGSC guideline):');
	$logger->debug('');

	foreach my $Step_name (sort keys(%{$self->{'commandLines'}})) {
		$logger->debug("\t" . $Step_name . ': ' . $self->{'commandLines'}->{$Step_name});
		$logger->debug('');
	}

	return 0; # Success
}


sub _virtual_STEP05_execution {

	# Recovers parameters
	my $self = shift;

	# Initializations
	my $Annotation_string = '-';

	$logger->debug('');
	$logger->debug("\t" . 'STEP05: Hypothetical like results from STEP02 (Start at ' . localtime() . ')');

	# Build the correct annotation string if needed
	if (($self->{'annotationResults'}->{'STEP02'} ne '-') && ($self->{'annotationResults'}->{'STEP02'} =~ /-\s*(.+)/)) {
		$Annotation_string = 'Note=' . $TRIANNOT_CONF{$self->{'programName'}}->{AnnotationSteps}->{'STEP05'}->{'annotation_class'} . ' - ' . $1;
	}

	if( $Annotation_string ne '-' ) {
		$logger->debug("\t\t" . '=> ' . $Annotation_string . ' => ' . $TRIANNOT_CONF{$self->{'programName'}}->{AnnotationSteps}->{'STEP05'}->{'annotation_class'});
	} else{
		$logger->debug("\t\t" . '=> There were no hypothetical result at STEP02');
		$logger->debug("\t\t" . '=> No result => Next annotation stage will begin soon..');
	}

	$self->{'commandLines'}->{'STEP05'} = 'Virtual Step - Selection of the hypothetical results from STEP02';

	return $Annotation_string;
}




######################################################
## Annotation result's filtering related methods
######################################################

sub _rejectHypotheticalAnnotation {

	# Recovers parameters
	my ($self, $Picked_step) = @_;

	# Initializations
	my $Basic_annotation = $self->{'annotationResults'}->{$Picked_step};
	my ($Annotation_class, $Real_annotation) = split('-', $Basic_annotation, 2);

	# Reject or conserve "Hypothetical" like annotations depending on the value of the hypotheticalProtein in configuration file
	if ($Basic_annotation ne '-') {
		if ($TRIANNOT_CONF{$self->{'programName'}}->{AnnotationSteps}->{$Picked_step}->{'keepHypothetical'} eq 'no') {
			foreach my $keyword (values %{$TRIANNOT_CONF{FuncAnnot}->{Hypothetical_like_keywords}}) {
				if ($Real_annotation =~ /$keyword/i) {
					$logger->debug("\t\t" . '=> Hypothetical like results are rejected for this stage => Next annotation stage will begin soon..');
					return '-';
				}
			}
		}
	}

	return $Basic_annotation;
}


sub _keepSimilarToTransposableElementOnly {

	# Recovers parameters
	my ($self, $Picked_step) = @_;

	# Initializations
	my $Initial_Annotation = $self->{'annotationResults'}->{$Picked_step};
	my $Keep_it = 'no';

	# If the current annotation results looks like a TE we keep it else we reject it and consider that there are no results for this annotation step
	if ($Initial_Annotation ne '-') {
		if ($TRIANNOT_CONF{$self->{'programName'}}->{AnnotationSteps}->{$Picked_step}->{'keepTElikeOnly'} eq 'yes') {
			foreach my $TE_like_keyword (values %{$TRIANNOT_CONF{FuncAnnot}->{TE_like_keywords}}) {
				if ($Initial_Annotation =~ /Note=.*$TE_like_keyword.*/i) {
					$Keep_it = 'yes';
					last;
				}
			}

			if ($Keep_it eq 'no') {
				$logger->debug("\t\t" . '=> No Transposable Element related keyword found in the annotation result string => The original annotation is rejected..');
				return '-';
			} else {
				$logger->debug("\t\t" . '=> Transposable Element related keyword found in the annotation result string => The original annotation is conserved..');
				return $Initial_Annotation;
			}
		}
	}

	return $Initial_Annotation;
}

1;
