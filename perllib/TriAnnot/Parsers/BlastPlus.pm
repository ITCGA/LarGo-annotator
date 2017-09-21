#!/usr/bin/env perl

package TriAnnot::Parsers::BlastPlus;

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

# CPAN or Perl modules
use XML::Twig;

## TriAnnot modules
use TriAnnot::Config::ConfigFileLoader;
use TriAnnot::Tools::MergeHits;
use TriAnnot::Tools::Logger;

## Inherits
use base ("TriAnnot::Parsers::Parsers");


##################################################
## Methods
##################################################
=head1 TriAnnot::Parsers::BlastPlus - Methods
=cut

################
# Constructor
################

sub new {

	# Recovers parameters
	my ($class, $attrs_ref) = @_;

	# Check the type of the second argument
	if (ref($attrs_ref) ne 'HASH') {
		$logger->logdie('Error: BlastPlus.pm constructor is expecting a hash reference as second argument !');
	}

	# Call the constructor of the parent class (TriAnnot::Programs::Programs)
	my $self = $class->SUPER::new($attrs_ref);

	# addMatchFeatures Must be 1 in TriAnnotPipeline v3+
	$self->{addMatchFeatures} = 1; #True

	bless $self => $class;

	return $self;
}

##################
# Method parse() #
##################

sub _parse {

	# Recovers parameters
	my $self = shift;

	# Display a warning message when the file to parse is missing
	if (! -e $self->{'fullFileToParsePath'} || -z $self->{'fullFileToParsePath'} ) {
		$logger->logwarn('Blast output file is missing or empty (' . $self->{'fullFileToParsePath'} . '). Parse method will return an empty feature array.');
		my @Blast_features = ();
		return @Blast_features;
	}

	# Create new Twig object
	my $twig = new XML::Twig( TwigRoots => {'Hit' =>  \&_HitParser} );

	# Transfer Blast object attributes to the Twig object and initialize some new attributes
	$twig->{'Blast_object'} = $self;
	$twig->{'gffFeatures'} = [];
	$twig->{'HitList'} = [];
	$twig->{'coordinates'} = [];
	$twig->{'matchCount'}  = 0;
	$twig->{'hspCount'}  = 0;

	# Parse Blast XML output file via XML Twig
	$twig->parsefile($self->{'fullFileToParsePath'});

	# Build the hit list for future use in MinibankBuilder.pm (Note: In TAP V3 and superior the hit list is always builded)
	$self->_BuildHitListFile($twig);

	# Merge Blast hits
	$self->_addRegionsFeatures($twig);

	return @{$twig->{'gffFeatures'}};
}


sub _HitParser {

	# Recovers parameters
	my ($twig, $hitTwig) = @_;

	# Initializations
	my $match = undef;
	my $Hit_over_thresholds = '';

	# Get all HSPs information of the current Hit and sort them depending on their strand
	my $hspsHashRef = _getHspsForHit($hitTwig);

	# Treat HSPs of the current hit depending on their strand
	if (scalar(@{$hspsHashRef->{'plusStrand'}}) > 0) {
		# Initialization of the match
		$match = _initMatch($twig, $hitTwig, '+');

		# Determine if the current hit have to be added to the hit list and the list of Blast features
		$Hit_over_thresholds = _isGreaterThanThresholds($match, $hspsHashRef, $twig->{'Blast_object'}->{'coverageThreshold'}, $twig->{'Blast_object'}->{'identity_threshold'});

		# Add hit and hsps to the list of feature if needed
		if ($twig->{'Blast_object'}->{'remove_hit_below_thresholds'} eq 'no' || ($twig->{'Blast_object'}->{'remove_hit_below_thresholds'} eq 'yes' && $Hit_over_thresholds eq 'yes')) {
			_TreatHsps($twig, $hspsHashRef->{'plusStrand'}, $match);
		}
	}

	if (scalar(@{$hspsHashRef->{'minusStrand'}}) > 0) {
		# Initialization of the match
		$match = _initMatch($twig, $hitTwig, '-');

		# Determine if the current hit have to be added to the hit list and the list of Blast features
		$Hit_over_thresholds = _isGreaterThanThresholds($match, $hspsHashRef, $twig->{'Blast_object'}->{'coverageThreshold'}, $twig->{'Blast_object'}->{'identity_threshold'});

		# Add hit and hsps to the list of feature if needed
		if ($twig->{'Blast_object'}->{'remove_hit_below_thresholds'} eq 'no' || ($twig->{'Blast_object'}->{'remove_hit_below_thresholds'} eq 'yes' && $Hit_over_thresholds eq 'yes')) {
			_TreatHsps($twig, $hspsHashRef->{'minusStrand'}, $match);
		}
	}

	# If the current hit have a coverage and an identity over the defined thresholds we add it to the hit list
	if ($Hit_over_thresholds eq 'yes') {
		push(@{$twig->{'HitList'}}, $match->{'Name'});
	} else {
		$logger->info("Ignoring match with coverage below threshold (" . sprintf("%.2f", $match->{'coverage'} * 100) . " < " . sprintf("%.1f", $twig->{'Blast_object'}->{'coverageThreshold'} * 100) . " %) or identity below threshold (" . sprintf("%.2f", $match->{'identity'} * 100) . " < " . sprintf("%.1f", $twig->{'Blast_object'}->{'identity_threshold'} * 100) . " %): " . $match->{'Name'});
	}

	$hitTwig->purge;
}


sub _getHspsForHit {

	# Recovers parameters
	my $hitTwig = shift;

	# Initializations
	my $hsps = { minusStrand => [],	plusStrand  => [] };

	# Collect HSP information
	foreach my $hspTwig ($hitTwig->first_child('Hit_hsps')->children('Hsp')) {
		my $hsp = {
			'QueryStart'   => $hspTwig->first_child_text('Hsp_query-from'),
			'QueryEnd'     => $hspTwig->first_child_text('Hsp_query-to'),
			'HitStart'     => $hspTwig->first_child_text('Hsp_hit-from'),
			'HitEnd'       => $hspTwig->first_child_text('Hsp_hit-to'),
			'TotalLength'  => $hspTwig->first_child_text('Hsp_align-len'),
			'GapsInHitSeq' => ($hspTwig->first_child_text('Hsp_hseq') =~ tr/-//),
			'eValue'       => $hspTwig->first_child_text('Hsp_evalue'),
			'identity'     => $hspTwig->first_child_text('Hsp_identity'),
			'positive'     => $hspTwig->first_child_text('Hsp_positive'),
			'bitScore'     => $hspTwig->first_child_text('Hsp_bit-score')
		};
		$hsp->{'HitLength'} = $hsp->{'TotalLength'} - $hsp->{'GapsInHitSeq'};

		# The strand recovery in a blast output in XML format is very very confusing !
		# Blast N : in standard output format the strand is displayed like this : Strand = Plus / Minus | in XML output format we get <Hsp_query-frame>1</Hsp_query-frame> and <Hsp_hit-frame>-1<Hsp_hit-frame>
		# Blast X : in standard output format the strand is not displayed, we only have a frame like this : Frame = -3 | in XML output format there is no <Hsp_hit-frame> balise, there is only <Hsp_query-frame>-3</Hsp_query-frame>
		# Therefore, here, to get the strand of an HSP we have to look at the <Hsp_hit-frame> balise for a Blast N or the <Hsp_query-frame> balise for a Blast X
		if ($hspTwig->has_child('Hsp_hit-frame')) {
			$hsp->{'Strand'} = ($hspTwig->first_child_text('Hsp_hit-frame') < 0) ? '-' : '+';
		} else {
			$hsp->{'Strand'} = ($hspTwig->first_child_text('Hsp_query-frame') < 0) ? '-' : '+';
		}

		if ($hsp->{'QueryStart'} > $hsp->{'QueryEnd'}) {
			my $tmpStart = $hsp->{'QueryStart'};
			$hsp->{'QueryStart'} = $hsp->{'QueryEnd'};
			$hsp->{'QueryEnd'} = $tmpStart;
		}

		if ($hsp->{'HitStart'} > $hsp->{'HitEnd'}) {
			my $tmpStart = $hsp->{'HitStart'};
			$hsp->{'HitStart'} = $hsp->{'HitEnd'};
			$hsp->{'HitEnd'} = $tmpStart;
		}

		if ($hsp->{'Strand'} eq '+') {
			push(@{$hsps->{'plusStrand'}}, $hsp);
		} else {
			push(@{$hsps->{'minusStrand'}}, $hsp);
		}
	}

	# Sort HSPs on the minus strand
	my @minusTmpArray = sort { $b->{'QueryStart'} <=> $a->{'QueryStart'}  } @{$hsps->{'minusStrand'}};
	$hsps->{'minusStrand'} = \@minusTmpArray;

	# Sort HSPs on the plus strand
	my @plusTmpArray = sort { $a->{'QueryStart'} <=> $b->{'QueryStart'}  } @{$hsps->{'plusStrand'}};
	$hsps->{'plusStrand'} = \@plusTmpArray;

	return $hsps;
}


sub _initMatch {

	# Recovers parameters
	my ($twig, $hitTwig, $strand) = @_;

	# Increase the number of match
	$twig->{'matchCount'}++;

	# Store match/Hit information into a hash table
	my $match = {
		'Name'      => $hitTwig->first_child_text('Hit_accession'),
		'Length'    => $hitTwig->first_child_text('Hit_len'),
		'Note'      => $hitTwig->first_child_text('Hit_def'),
		'Start'     => undef,
		'End'       => undef,
		'Strand'    => $strand,
		'Number'    => sprintf("%04d", $twig->{'matchCount'})
	};

	if ($match->{'Name'} eq '') {
		$logger->logwarn('Unlikely event: Match Name is empty !');
	}


	return $match;
}


sub _TreatHsps {

	# Recovers parameters
	my ($twig, $hsps, $match) = @_; # $hsps is a ref to an array of hsps

	# Intializations
	my $parentId = undef;

	# Build and Add the match feature to the global list of feature for the current analysis
	if ($twig->{'Blast_object'}->{'addMatchFeatures'}) {
		_determineMatchStartAndEndFromHsps($match, $hsps);
		$parentId = _addMatchFeature($twig, $match);
		$twig->{'hspCount'} = 0;
	}

	# Build and Add all the match_part features to the global list of feature for the current analysis
	foreach my $hsp (@{$hsps}) {
		$twig->{'hspCount'}++;
		$hsp->{'Number'} = sprintf("%04d", $twig->{'hspCount'});
		$hsp->{'Parent'} = $parentId;

		_addHspFeature($twig, $match, $hsp);
	}
}


sub _determineMatchStartAndEndFromHsps {

	# Recovers parameters
	my ($match, $hsps) = @_;

	# Determine the start and end of the match feature from HSP information
	foreach my $hsp (@{$hsps}) {
		if (!defined($match->{'Start'}) || $hsp->{'QueryStart'} < $match->{'Start'}) {
			$match->{'Start'} = $hsp->{'QueryStart'};
		}
		if (!defined($match->{'End'}) || $hsp->{'QueryEnd'} > $match->{'End'}) {
			$match->{'End'} = $hsp->{'QueryEnd'};
		}
	}
}


sub _addMatchFeature {

	# Recovers parameters
	my ($twig, $match) = @_;

	# Initializations
	my $gffTag = {};

	#  Build all attributes (GFF field 9) of the new feature
	$gffTag->{'ID'} = $twig->{'Blast_object'}->{'sequenceName'} . '_' . $twig->{'Blast_object'}->getSourceTag() . '_' . $match->{'Start'} . '_' . $match->{'End'} . '_' . $match->{'Name'} . '_Match_' . $match->{'Number'};
	$gffTag->{'Name'} = $twig->{'Blast_object'}->getSourceTag() . '_' . $match->{'Start'} . '_' . $match->{'End'} . '_' . $match->{'Name'} . '_Match_' . $match->{'Number'};
	$gffTag->{'length'} = $match->{'Length'};
	$gffTag->{'identity'} = sprintf("%.2f" ,$match->{'identity'} * 100);
	$gffTag->{'coverage'} = sprintf("%.2f" ,$match->{'coverage'} * 100);
	if (defined($match->{'Note'}) && $match->{'Note'} ne '') {
		$gffTag->{'Note'} = $match->{'Note'};
	}

	# Creation of the new feature
	my $gffFeature = Bio::SeqFeature::Generic->new(
		-seq_id      => $twig->{'Blast_object'}->{'sequenceName'},
		-source_tag  => $twig->{'Blast_object'}->getSourceTag(),
		-primary_tag => 'match',
		-start       => $match->{'Start'},
		-end         => $match->{'End'},
		-score       => undef,
		-strand      => $match->{'Strand'},
		-frame       => undef, # GFF phase is for CDS/polypetide only
		-tag         => $gffTag
	);

	push(@{$twig->{'gffFeatures'}}, $gffFeature);

	return $gffTag->{'ID'};
}

sub _addHspFeature {

	# Recovers parameters
	my ($twig, $match, $hsp) = @_;

	# Initializations
	my $gffTag = {};

	# Build all attributes (GFF field 9) of the new feature
	if ($twig->{'Blast_object'}->{'addMatchFeatures'}) {
		$gffTag->{'ID'} = $twig->{'Blast_object'}->{'sequenceName'} . '_' . $twig->{'Blast_object'}->getSourceTag() . '_' . $hsp->{'QueryStart'} . '_' . $hsp->{'QueryEnd'} . '_' . $match->{'Name'} . '_Match_' . $match->{'Number'} . '_Match_part_' . $hsp->{'Number'};
		$gffTag->{'Parent'} = $hsp->{'Parent'};
		$gffTag->{'Name'} = $twig->{'Blast_object'}->getSourceTag() . '_' . $hsp->{'QueryStart'} . '_' . $hsp->{'QueryEnd'} . '_' . $match->{'Name'} . '_Match_' . $match->{'Number'} . '_Match_part_' . $hsp->{'Number'};

	} else {
		$gffTag->{'ID'} = $twig->{'Blast_object'}->{'sequenceName'} . '_' . $twig->{'Blast_object'}->getSourceTag() . '_' . $hsp->{'QueryStart'} . '_' . $hsp->{'QueryEnd'} . '_' . $match->{'Name'} . '_Match_part_' . $hsp->{'Number'};
		$gffTag->{'Name'} = $twig->{'Blast_object'}->getSourceTag() . '_' . $hsp->{'QueryStart'} . '_' . $hsp->{'QueryEnd'} . '_' . $match->{'Name'} . '_Match_part_' . $hsp->{'Number'};
	}

	$gffTag->{'Target'} = [$match->{'Name'}, $hsp->{'HitStart'}, $hsp->{'HitEnd'}]; # Target Tag must be a reference to a table (anonymous or not)

	$gffTag->{'target_length'} = $hsp->{'HitLength'};
	$gffTag->{'e_value'} = $hsp->{'eValue'};
	$gffTag->{'percent_identity'} = sprintf("%.2f", $hsp->{'identity'} * 100 / $hsp->{'TotalLength'});

	if ($twig->{'Blast_object'}->{'programName'} ne 'BlastN') {
		$gffTag->{'percent_positive'} = sprintf("%.2f", $hsp->{'positive'} * 100 / $hsp->{'TotalLength'});
	}

	# Creation of the new feature
	my $gffFeature = Bio::SeqFeature::Generic->new(
		-seq_id      => $twig->{'Blast_object'}->{'sequenceName'},
		-source_tag  => $twig->{'Blast_object'}->getSourceTag(),
		-primary_tag => 'match_part',
		-start       => $hsp->{'QueryStart'},
		-end         => $hsp->{'QueryEnd'},
		-score       => $hsp->{'bitScore'},
		-strand      => $hsp->{'Strand'},
		-frame		 => undef, # GFF phase is for CDS/polypetide only
		-tag         => $gffTag
	);

	push(@{$twig->{'gffFeatures'}}, $gffFeature);

	push(@{$twig->{'coordinates'}}, $hsp->{'QueryStart'} . "\t" . $hsp->{'QueryEnd'});
}


sub _isGreaterThanThresholds {

	# Recovers parameters
	my ($Current_match, $Ref_to_HSPs, $coverageThreshold, $identity_threshold) = @_;

	# Initializations
	my ($Cumulative_length, $Cumulative_identity, $Min_Hsp_hit_from, $Max_Hsp_hit_to) = (0, 0, -1, -1);

	# Browse the two HSP lists to collect cumulative data
	foreach my $Current_HSP (@{$Ref_to_HSPs->{'plusStrand'}}) {
		$Cumulative_length += $Current_HSP->{'TotalLength'}; # Gaps are included
		$Cumulative_identity += $Current_HSP->{'identity'};

		if ($Min_Hsp_hit_from == -1 || $Current_HSP->{'HitStart'} < $Min_Hsp_hit_from) { $Min_Hsp_hit_from = $Current_HSP->{'HitStart'}; }
		if ($Max_Hsp_hit_to == -1 || $Current_HSP->{'HitEnd'} > $Max_Hsp_hit_to) { $Max_Hsp_hit_to = $Current_HSP->{'HitEnd'}; }
	}

	foreach my $Current_HSP (@{$Ref_to_HSPs->{'minusStrand'}}) {
		$Cumulative_length += $Current_HSP->{'TotalLength'}; # Gaps are included
		$Cumulative_identity += $Current_HSP->{'identity'};

		if ($Min_Hsp_hit_from == -1 || $Current_HSP->{'HitStart'} < $Min_Hsp_hit_from) { $Min_Hsp_hit_from = $Current_HSP->{'HitStart'}; }
		if ($Max_Hsp_hit_to == -1 || $Current_HSP->{'HitEnd'} > $Max_Hsp_hit_to) { $Max_Hsp_hit_to = $Current_HSP->{'HitEnd'}; }
	}

	# Compute identity and coverage
	my $Hit_Coverage = (($Max_Hsp_hit_to - $Min_Hsp_hit_from) + 1) / $Current_match->{'Length'};
	$Current_match->{'coverage'} = $Hit_Coverage ;
	my $Hit_Identity = $Cumulative_identity/$Cumulative_length;
	$Current_match->{'identity'} = $Hit_Identity;
	# Compare to threshold
	if ($Hit_Coverage >= $coverageThreshold && $Hit_Identity >= $identity_threshold) {
		return 'yes';
	} else {
		return 'no';
	}
}


sub _BuildHitListFile {
	my ($self, $XML_twig) = @_;

	# Write all Hit name in a temporary file / One by line (Hit list might be empty)
	open(HIT_LIST, '>' . $XML_twig->{'Blast_object'}->{'hitListFile'}) or $logger->logdie('Error: Cannot create/open file: ' . $XML_twig->{'Blast_object'}->{'hitListFile'});
	foreach my $Current_Hit_name (@{$XML_twig->{'HitList'}}) {
		print HIT_LIST $Current_Hit_name . "\n";
	}
	close(HIT_LIST);
}


sub _addRegionsFeatures {
	my ($self, $twig) = @_;

	# Add region features (merging of match/match_part features with their coordinates) to the global list of feature for the current analysis
	if( scalar(@{$twig->{'coordinates'}}) > 0) {
		push(@{$twig->{'gffFeatures'}}, @{TriAnnot::Tools::MergeHits::Merge_all_hit($twig->{'coordinates'}, $twig->{'Blast_object'}->{'sequenceName'}, $twig->{'Blast_object'}->getSourceTag())});
	}
}


sub _removeUnauthorizedCharactersFromHitDef {
	my $hitDef = shift;

	# Eliminate unauthorized characters
	$hitDef =~ s/[^\w\-\(\)\|]/ /g;

	# Eliminate redundant spaces
	$hitDef =~ tr/ //s;

	return $hitDef;
}

#####################
## New Files management
#####################

sub _generatedFilesManagement {
	my $self = shift;

	# Create a symlink to the hit list file in the common tmp folder
	if (-e $self->{'directory'} . '/' . $self->{'tmpFolder'} . '/' . $self->{'hitListFile'}) {
		symlink($self->{'directory'} . '/' . $self->{'tmpFolder'} . '/' . $self->{'hitListFile'}, $self->{'directory'} . '/' . $TRIANNOT_CONF{DIRNAME}->{'tmp_files'} . '/' . $self->{'hitListFile'});
	}
}

1;
