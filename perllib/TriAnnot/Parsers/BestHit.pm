#!/usr/bin/env perl

package TriAnnot::Parsers::BestHit;

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

## BioPerl modules
use Bio::SearchIO;
use Bio::SeqFeature::Generic;

## CPAN modules
use XML::Twig;
use File::Copy;

## TriAnnot modules
use TriAnnot::Parsers::Parsers;
use TriAnnot::Config::ConfigFileLoader;
use TriAnnot::Tools::Logger;

## Inherits
our @ISA = qw(TriAnnot::Parsers::Parsers);

##################################################
## Methods
##################################################
=head1 TriAnnot::Parsers::BestHit - Methods
=cut

################
# Constructor
################

sub new {

	# Recovers parameters
	my ($class, %attrs) = @_;

	# Call the constructor of the parent class
	my $self = $class->SUPER::new(\%attrs);

	bless $self => $class;

	return $self;
}

##################
# Method parse() #
##################

sub _parse {
	my $self = shift;

	# Initializations
	my $Cleaned_file = $self->{'fileToParse'} . '.cleaned';
	my $Query_sequence_number = 0;
	my @All_Best_hits = ();
	my @BestHit_Names = ();

	# Display a warning message when the file to parse is missing
	if (! -e $self->{'fullFileToParsePath'}) {
		$logger->logwarn('Blast (Best Hit) output file is missing (' . $self->{'fullFileToParsePath'} . ') or empty. Parse method will return an empty feature array.');
		return @All_Best_hits;
	}

	# Cleaning/Filtering of the brut Blast result file
	$logger->debug('Filtering/Cleaning file ' . $self->{'fileToParse'} . ' with XML Twig, please wait... (Start at ' . localtime() . ')');
	$self->_Filter_it_with_Twig($self->{'fullFileToParsePath'}, $Cleaned_file);

	# Creation of a new SearchIO object - BioPerl module for parsing of BLAST output file (XML format)
	$logger->debug('Parsing of the filtered/cleaned file (' . $Cleaned_file . ')... (Start at ' . localtime() . ')');
	my $searchio = Bio::SearchIO->new(-format =>'blastxml', -file => $Cleaned_file);

	# Blast iteration by Blast iteration ( $result is a Bio::Search::Result::ResultI object )
	while(my $result = $searchio->next_result()){

		# Initializations
		my ($GFF_feature_start, $GFF_feature_end) = ('', '');

		# Increases the Query_sequence_number
		$Query_sequence_number++;
		$Query_sequence_number = sprintf("%04d", $Query_sequence_number);

		# Problem of the query start and end: in the BLASTP result file, all coordinates are protein coordinates
		# However if we want to display this result in Gbrowse with other analysis results we need to use nucleic coordinates
		# Therefore the new hit feature will take the coordinates presents in the name of the query sequence (i.e the protein sequence) (Blast xml field: Iteration_query-def)
		my $Current_query_desc = $result->query_name();
		if ($Current_query_desc =~ /$self->{sequenceName}_\w+?_(\d+)_(\d+)/i) {
			$GFF_feature_start = $1;
			$GFF_feature_end = $2;
		} else {
			$logger->logwarn('Could not retrieve feature start and end from the following query description: ' . $Current_query_desc);
		}

		# Hit by Hit ( $hit is a Bio::Search::Hit::HitI object ) ( match (alias match_set))
		while (my $Blast_hit= $result->next_hit()) {

			# Initializations
			my $Hit_name = $Blast_hit->name();

			# Get the best HSP (highest score) of the current Blast Hit
			my $Best_HSP = $Blast_hit->hsp('best');

			# Get some specific information about the best HSP
			my $HSP_hit_start = $Best_HSP->start('hit');
			my $HSP_hit_end = $Best_HSP->end('hit');
			my $Coverage = (($HSP_hit_end - $HSP_hit_start) + 1) / $Blast_hit->length();
			my $Fraction_positive = $Best_HSP->frac_conserved('total');

			# Determine if the best HSP must be conserved or not (ie. if the coverage and the percentage of positive base are over the thresholds defined in configuration file + HSp query and hit start are equal to 1)
			if ($Coverage >= $self->{'coverageThreshold'} && $Fraction_positive >= $self->{'positive_threshold'} && $HSP_hit_start == 1 && $Best_HSP->start('query') == 1) {

				# Building of the new feature tag
				my $New_Feature_Tag = {};

				$New_Feature_Tag->{'Name'} = $self->getSourceTag() . '_Best_Hit_for_protein_' . $Query_sequence_number;
				$New_Feature_Tag->{'ID'} = $self->{'sequenceName'} . '_' . $New_Feature_Tag->{'Name'};
				$New_Feature_Tag->{'Target'} = [$Hit_name, $HSP_hit_start, $HSP_hit_end]; # Target Tag must be a reference to a table (anonymous or not)
				$New_Feature_Tag->{'target_length'} = $Best_HSP->length('hit');
				$New_Feature_Tag->{'Note'} = $Hit_name . ' - ' . $Blast_hit->description();
				$New_Feature_Tag->{'protein_derived_from'} = $Current_query_desc;
				$New_Feature_Tag->{'best_hsp_bit_score'} = $Best_HSP->bits();
				$New_Feature_Tag->{'best_hsp_e_value'} = $Best_HSP->evalue();
				$New_Feature_Tag->{'best_hsp_percent_identity'} = sprintf("%.2f", 100 * $Best_HSP->frac_identical());
				$New_Feature_Tag->{'best_hsp_percent_positive'} = sprintf("%.2f", 100 * $Fraction_positive);
				$New_Feature_Tag->{'best_hsp_coverage'} = sprintf("%.2f", 100 * $Coverage);
				$New_Feature_Tag->{'Query_gap_over_threshold'} = $self->_Get_gap_statistics($Best_HSP->query_string());
				$New_Feature_Tag->{'Sbjct_gap_over_threshold'} = $self->_Get_gap_statistics($Best_HSP->hit_string());

				# Creation of the new feature
				my $New_Feature = Bio::SeqFeature::Generic->new(
											-seq_id      => $self->{'sequenceName'},
											-source_tag  => $self->getSourceTag(),
											-primary_tag => 'match',
											-start       => $GFF_feature_start,
											-end         => $GFF_feature_end,
											-strand      => $Blast_hit->strand('hit'),
											-tag         => $New_Feature_Tag
										   );

				push(@All_Best_hits,$New_Feature);
				push(@BestHit_Names, $Hit_name);
				# Store alignment if needed
				if ($self->{'keep_alignment'} eq 'yes' ) { $self->_Save_alignment_to_file($Current_query_desc, $Hit_name, $Best_HSP, $New_Feature_Tag); }
			}
		}
	}

	# Closing of the file opened by the parser
	$searchio->close();
	$logger->debug('End of parsing (Stop at ' . localtime() . ')');

	# Suppression of the cleaned file to parse
	unlink($Cleaned_file);

	$self->_BuildHitListFile(\@BestHit_Names);

	return @All_Best_hits;
}

###################
## Internal Methods
###################

sub _Filter_it_with_Twig {

	# Recovers parameters
	my ($self, $file_to_clean, $cleaned_file) = @_;

	open(CLEANED, '>' . $cleaned_file) or $logger->logdie('Cannot create/open file ' . $cleaned_file);
	if (!-z $file_to_clean) {
		# Creates the Twig object
		my $twigtest = new XML::Twig( twig_handlers => {'Hit_def' =>  \&Hitdef_cleaner, '_default_' => \&ignore_me} );

		# Transfer some of the Blast object attributes to the Twig object
		$twigtest->{'keep_alignment'} = $self->{'keep_alignment'};

		# "twig-ish" parse of the file
		$twigtest->parsefile($file_to_clean);
		$twigtest->set_pretty_print('indented');

		# Creation of the cleaned file
		my $output = $twigtest->sprint();
		print CLEANED $output;
	}

	close(CLEANED);
}

sub _Save_alignment_to_file {

	# Recovers parameters
	my ($self, $Query_name, $Hit_name, $Current_HSP, $Current_feature_TAG) = @_;

	# Print the new alignment to the align file
	open(ALIGN, '>>' . $self->{'alignFile'}) or $logger->logdie('Cannot create/open file ' . $self->{'alignFile'}); # Writing mode

	print ALIGN ">" . $Query_name . " | " . $Hit_name;
	print ALIGN " | Coverage: " . $Current_feature_TAG->{'best_hsp_coverage'} . "% | Identity: " . $Current_feature_TAG->{'best_hsp_percent_identity'} . "% | Positive: " . $Current_feature_TAG->{'best_hsp_percent_positive'} . "%";
	if ($Current_feature_TAG->{'Query_gap_over_threshold'} != 0) {
		print ALIGN " | Query gap(s) over threshold (> " . $self->{'max_gap_size'} . "aa): " . $Current_feature_TAG->{'Query_gap_over_threshold'};
	}
	if ($Current_feature_TAG->{'Sbjct_gap_over_threshold'} != 0) {
		print ALIGN " | Subject gap(s) over threshold (> " . $self->{'max_gap_size'} . "aa): " . $Current_feature_TAG->{'Sbjct_gap_over_threshold'};
	}
	print ALIGN "\n";
	print ALIGN "Query: " . $Current_HSP->query_string() . "\n";
	print ALIGN "Align: " . $Current_HSP->homology_string() . "\n";
	print ALIGN "Sbjct: " . $Current_HSP->hit_string() . "\n\n";

	close(ALIGN);
}

sub _Get_gap_statistics {

	# Recovers parameters
	my ($self, $sequence) = @_;

	# Initializations
	my $Gap_over_threshold = 0;

	# Analyze of the query sequence of the alignment
	foreach my $gap_block ($sequence =~ /([^\w]+)/g) {
		if (length($gap_block) >= $self->{'max_gap_size'}) {
			$Gap_over_threshold++;
		}
	}

	return $Gap_over_threshold;
}

###################
## Twig related functions
###################

sub Hitdef_cleaner {

	# Recovers parameters
	my ($twig, $Hit_def) = @_;

	# Get the text of the Hit_def element
	my $Hit_def_text = $Hit_def->text();

	# Eliminate unauthorized characters and redundant spaces
	$Hit_def_text =~ s/[^\w\-\(\)\|]/ /g;
	$Hit_def_text =~ tr/ //s;

	# Updates the xml file
	$Hit_def->set_text($Hit_def_text);
}

sub ignore_me{

	# Recovers parameters
	my ($twig, $balise) = @_;

	# Initializations
	my $Balise_name = $balise->name();

	# Eliminates unnecessary tag
	foreach my $entity (values %{$TRIANNOT_CONF{BestHit}->{UnAuthorized_entity}}) {
		if ($Balise_name =~ /.*?$entity.*/) {
			if ($twig->{'keep_alignment'} eq 'yes' && $Balise_name =~ /^(Hsp_qseq|Hsp_hseq|Hsp_midline)/) {
				next;
			} else {
				$balise->delete();
			}
		}
	}
}


sub _BuildHitListFile {
	my $self = shift;
	my $Hit_Names = shift;

	# Write all Hit name in a temporary file / One by line (Hit list might be empty)
	open(HIT_LIST, '>' . $self->{'hitListFile'}) or $logger->logdie('Error: Cannot create/open file: ' . $self->{'hitListFile'});
	foreach my $Current_Hit_name (@{$Hit_Names}) {
		print HIT_LIST $Current_Hit_name . "\n";
	}
	close(HIT_LIST);
}

#####################
## New Files management
#####################

sub _generatedFilesManagement {

	# Recovers parameters
	my $self = shift;

	# Initializations
	my $tmp_folder = $self->{'directory'} . '/' . $self->{'tmpFolder'};
	my $keep_it_folder = $self->{'directory'} . '/' . $TRIANNOT_CONF{DIRNAME}->{'keep_files'};

	# Move the new alignment to the alignment folder
	if (-e $tmp_folder . '/' . $self->{'alignFile'}) {
		$logger->debug('');
		$logger->debug('Note: Moving of the newly generated alignment file into the ' . $TRIANNOT_CONF{DIRNAME}->{'keep_files'} . ' folder');
		move($tmp_folder . '/' . $self->{'alignFile'}, $keep_it_folder . '/' . $self->{'alignFile'}) or $logger->logdie('Error: Cannot move the newly generated alignment file: ' . $self->{'alignFile'});
	}

	# Create a symlink to the hit list file in the common tmp folder
	if (-e $self->{'directory'} . '/' . $self->{'tmpFolder'} . '/' . $self->{'hitListFile'}) {
		symlink($self->{'directory'} . '/' . $self->{'tmpFolder'} . '/' . $self->{'hitListFile'}, $self->{'directory'} . '/' . $TRIANNOT_CONF{DIRNAME}->{'tmp_files'} . '/' . $self->{'hitListFile'});
	}

}

1;
