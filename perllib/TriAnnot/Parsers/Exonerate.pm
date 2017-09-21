#!/usr/bin/env perl

package TriAnnot::Parsers::Exonerate;

##################################################
## Documentation POD
##################################################

##################################################
## Included modules
##################################################
## Perl modules
use strict;
use warnings;
use diagnostics;
use Data::Dumper;

## BioPerl modules
use Bio::SeqFeature::Generic;

## TriAnnot modules
use TriAnnot::Parsers::Parsers;
use TriAnnot::Tools::MergeHits;
use TriAnnot::Config::ConfigFileLoader;
use TriAnnot::Tools::Logger;
use TriAnnot::Tools::GetInfo;

## Inherits
our @ISA = qw(TriAnnot::Parsers::Parsers);


##################################################
## Methods
##################################################
=head1 TriAnnot::Parsers::Exonerate - Methods
=cut

################
# Constructor
################

sub new{
	my ($class, %attrs) = @_;

	# Call the constructor of the parent class
	my $self = $class->SUPER::new(\%attrs);

	$self->{_nbMatches} = 0;
	$self->{_nbMatchParts} = 0;
	$self->{_currentMatch} = undef;
	$self->{_currentMatchPart} = undef;
	$self->{_events} = undef;

	# Define $self as a $class type object
	bless $self => $class;

	return $self;
}

##################
# Method parse() #
##################

sub _parse {
	my $self = shift;

	# Initializations
	my @allFeats = ();
	$self->{_nbMatches} = 0;

	# Display a warning message when the file to parse is missing
	if (! -e $self->{'fullFileToParsePath'}) {
		$logger->logwarn('Exonerate output file is missing (' . $self->{'fullFileToParsePath'} . '). Parse method will return an empty feature array.');
		return @allFeats;
	}

	# Open EXONERATE brut output file
	open(EXONERATE_OUT, '<' . $self->{'fullFileToParsePath'}) or $logger->logdie('Error: Cannot open/read file: ' . $self->{'fullFileToParsePath'});

	while (my $exoLine = <EXONERATE_OUT>) {

		if ($exoLine =~ /^vulgar:\s+(.+)$/) {
			# Store previous result in the final tab
			if ($self->{_nbMatches} > 0) {
				if (defined($self->{_currentMatch})) {
					push(@allFeats, $self->{_currentMatch});
					push(@allFeats, $self->_createAllMatchPartFeatures($self->{_currentMatch}->{queryID}));
				}

				$self->{_currentMatch} = undef;
				$self->{_events} = undef;
			}

			# Split vulgar data
			my ($queryID, $queryStart, $queryEnd, $queryStrand, $targetID, $targetStart, $targetEnd, $targetStrand, $score, $eventsString) = split(/\s/, $1, 10);

			# Clean the Query ID
			$queryID =~ s/^lcl\|//;

			##############################################################################################################
			## CRITICAL WARNING: Exonerate display good coordinates on its alignment but make a mistake in the Vulgar ! ##
			##############################################################################################################
			# Change strand (+/-) value to numerical value (+1/-1).
			if( $queryStrand eq '-' ) {
				$queryStrand = -1;
				$queryEnd++;
			} else {
				$queryStrand = 1;
				$queryStart++;
			}
			# Change strand (+/-) value to numerical value (+1/-1).
			if( $targetStrand eq '-' ) {
				$targetStrand = -1;
				$targetEnd++;
			} else {
				$targetStrand = 1;
				$targetStart++;
			}

			# Increase match counter
			$self->{_nbMatches}++;

			# Create the match feature
			$self->{_currentMatch} = $self->_createFeature('match', $targetStart, $targetEnd, $targetStrand);
			$self->{_currentMatch}->{queryID} = $queryID;

			# Collect data of the current sequence in the database with fastcmd
			my $info;
			if($self->{queryType} eq 'protein'){
				$info = TriAnnot::Tools::GetInfo->new(database => $TRIANNOT_CONF{PATHS}->{db}->{$self->{database}}->{path}, type => 'T' , id => $queryID);
			} else{
				$info = TriAnnot::Tools::GetInfo->new(database => $TRIANNOT_CONF{PATHS}->{db}->{$self->{database}}->{path}, type => 'F' , id => $queryID);
			}

			$self->_addTagsToFeatures($self->{_currentMatch}, $queryID, $score, $info);

			# Exclude match with coverage below the defined threshold
			if (!$self->_isCurrentMatchCoverageAboveThreshold($queryStart, $queryEnd)) {
				$logger->info("Ignoring match with coverage below threshold (" . ($self->{_currentMatch}->get_tag_values('query_coverage'))[0] . " < " . sprintf("%.2f", $self->{coverageThreshold} * 100) . "): " . ($self->{_currentMatch}->get_tag_values('ID'))[0]);
				$self->{_nbMatches}--;
				$self->{_currentMatch} = undef;
				next;
			}

			# Analyse the last part of the Vulgar line to collect match_part data
			$self->_parseEvents($eventsString, $queryStart, $queryEnd, $queryStrand, $targetStart, $targetEnd, $targetStrand);

		} elsif ($exoLine =~ /^identity_percentage:\s+([\w\.]+)$/) {
			$self->{_currentMatch}->add_tag_value('identity_percentage', $1) if (defined($self->{_currentMatch}));
		} elsif ($exoLine =~ /^similarity_percentage:\s+([\w\.]+)$/) {
			$self->{_currentMatch}->add_tag_value('similarity_percentage', $1) if (defined($self->{_currentMatch}));
		}
	}
	close(EXONERATE_OUT);

	# Store last result in the final tab
	if (defined($self->{_currentMatch})) {
		push(@allFeats, $self->{_currentMatch});
		push(@allFeats, $self->_createAllMatchPartFeatures($self->{_currentMatch}->{queryID}));
	}

	return @allFeats;
}

######################
## Internal Methods
######################
sub _isCurrentMatchCoverageAboveThreshold {
	my ($self, $queryStart, $queryEnd) = @_;

	my $queryLength = ($self->{_currentMatch}->get_tag_values('length'))[0];
	if ($queryLength !~ /\d+/ || $queryLength == 0) {
		$logger->logwarn("Can not check coverage because length is missing in the database for feature: " . ($self->{_currentMatch}->get_tag_values('ID'))[0]);
		return 1; #TRUE
	}
	my $coverage = (abs($queryEnd - $queryStart)+1) / $queryLength;
	$self->{_currentMatch}->add_tag_value('query_coverage',  sprintf("%.2f", $coverage * 100));
	if ($coverage < $self->{coverageThreshold}) {
		return 0; #FALSE
	}
	else{
		return 1; #TRUE
	}
}


# Some Explanations on the last part of the Vulgar
# A triplet is <label, query_length, target_length>
# M = Match
# C = Codon
# G = Gap
# N = Non-equivalenced region
# 5 = 5' splice site
# 3 = 3' splice site
# I = Intron
# S = Split codon
# F = Frameshift

sub _parseEvents {
	my ($self, $eventsString, $queryStart, $queryEnd, $queryStrand, $targetStart, $targetEnd, $targetStrand) = @_;
	my ($laststate, $gaps) = ( '' );
	$self->{_events} = [];

	my @rest = split(' ', $eventsString);
	while( @rest >= 3 ) {
		my ($state, $len1, $len2) = (shift @rest, shift @rest, shift @rest);
		#
		# HSPs are only the Match cases; otherwise we just
		# move the coordinates on by the correct amount
		#
		if ( $state eq 'M' ) {
			if ( $laststate eq 'G' ) {
			# Merge gaps across Match states so the HSP goes across
				$self->{_events}->[-1]->{'query-to'} = $queryStart + $len1 * $queryStrand - $queryStrand;
				$self->{_events}->[-1]->{'hit-to'}   = $targetStart + $len2 * $targetStrand - $targetStrand;
				$self->{_events}->[-1]->{'gaps'} = $gaps;
			}
			# Adjusting coordinates for 5' splicing site.
			elsif ( $laststate eq 'S' ) {
				push @{$self->{_events}},
					{ 'align-len'    => $len1,
					  'query-strand' => $queryStrand,
					  'query-from'   => ($queryStart - $self->{_events}->[-1]->{'qsplit'} * $queryStrand),
					  'query-to'     => ($queryStart + $len1 * $queryStrand - $queryStrand),
					  'hit-from'     => ($targetStart- $self->{_events}->[-1]->{'hsplit'} * $targetStrand),
					  'hit-to'       => ($targetStart + $len2 * $targetStrand - $targetStrand),
					  'hit-strand'   => $targetStrand,
					};

			}
			## end modif
			else {
				push @{$self->{_events}},
					{ 'align-len'    => $len1,
					  'query-strand' => $queryStrand,
					  'query-from'   => $queryStart,
					  'query-to'     => ($queryStart + $len1 * $queryStrand - $queryStrand),
					  'hit-from'     => $targetStart,
					  'hit-to'       => ($targetStart + $len2 * $targetStrand - $targetStrand),
					  'hit-strand'   => $targetStrand,
					};
			}
			$gaps = 0;
		}
		# Using 'S'plice event to.
		elsif ( $state eq 'S' ) {
			# Adjusting coordinates for 3' splicing site.
			if ( $laststate eq 'M') {
				$self->{_events}->[-1]->{'query-to'} = $queryStart + $len1 * $queryStrand - $queryStrand;
				$self->{_events}->[-1]->{'hit-to'}   = $targetStart + $len2 * $targetStrand - $targetStrand;
			}
			# Storing the 'S'plice event for 5' futur.
			push @{$self->{_events}}, { 'qsplit' => $len1, 'hsplit' => $len2};
		}
		else {
			$gaps = $len1 + $len2 if $state eq 'G';
		}
		$queryStart += $len1 * $queryStrand;
		$targetStart += $len2 * $targetStrand;
		$laststate = $state;
	}
}

# Creates all features from a unique exonerate hit. Returning an array of features.
sub _createAllMatchPartFeatures {
	my ($self, $queryID) = @_;
	my @features;

	$self->{_nbMatchParts} = 0;
	#my @sortedEvents = sort {$a->{'query-from'} <=> $b->{'query-from'}} @{$self->{_events}};

	foreach my $event ( @{$self->{_events}} ) {
		# Skipping the 'S' events.
		if ( defined $event->{'qsplit'} ) {next;}
		# Increases the number of match_part feature
		$self->{_nbMatchParts}++;
		# Creation of each match_part.
		$self->{_currentMatchPart} = $self->_createFeature('match_part', $event->{'hit-from'}, $event->{'hit-to'}, $event->{'hit-strand'});
		$self->_addTagsToFeatures($self->{_currentMatchPart}, $queryID);
		$self->{_currentMatchPart}->add_tag_value('Target', ($queryID, $event->{'query-from'}, $event->{'query-to'}));
		push(@features, $self->{_currentMatchPart});
	}
	$self->{_currentMatchPart} = undef;
	return @features;
}


# Creates a generic Bio::SeqFeature. Returning a Bio::SeqFeature object.
sub _createFeature {
	my ($self, $type, $start, $end, $strand, $tag) = @_ ;
	if ($start > $end) {
		($start, $end) = $self->_dealWithMinusStrand($start, $end);
	}
	my $feat = Bio::SeqFeature::Generic->new(
								-seq_id      => $self->{sequenceName},
								-source_tag  => $self->getSourceTag(),
								-primary_tag => $type,
								-start       => $start,
								-end         => $end,
								-strand      => $strand,
								);
	return $feat;
}


# Reverse Start/End for minus strand.
sub _dealWithMinusStrand{
	my ($self, $start, $end) = @_;
	my $temp = $start;
	$start = $end;
	$end = $temp;
	return ($start, $end);
}


# Creates of the specfic source tag for each feature type.
sub _addTagsToFeatures {
	my ($self, $feature, $queryID, $score, $info) = @_ ;

	my $name = $self->getSourceTag() . '_' . $feature->start . '_' . $feature->end . '_' . $queryID . '_Match_' . sprintf("%04d", $self->{_nbMatches});
	if($feature->primary_tag() eq 'match'){
		$feature->add_tag_value('Name', $name);
		$feature->add_tag_value('ID', $self->{'sequenceName'}. '_' . $name);
		$feature->add_tag_value('length', $info->{length});
		$feature->add_tag_value('score', $score);
		$feature->add_tag_value('Note', $info->{description});
	}
	else{
		$feature->add_tag_value('Name', $name . '_Match_part_' . sprintf("%04d", $self->{_nbMatchParts}));
		$feature->add_tag_value('ID', $self->{'sequenceName'}. '_' . $name . '_Match_part_' . sprintf("%04d", $self->{_nbMatchParts}));
		$feature->add_tag_value('Parent', ($self->{_currentMatch}->get_tag_values('ID'))[0]);
	}
}

sub _addSequenceOntology {
	# Recovers parameters
	my ($self, $hitFeatures) = @_;
	# Initializations
	my $Number_of_element = scalar(@{$hitFeatures});
	my $Strand = $hitFeatures->[0]->strand();

	# Warning on an unlikely event
	if (scalar(@{$hitFeatures}) < 1) {
		$logger->logwarn('Unlikely event: Empty list of ' . 'CDS' . ' features in _addSequenceOntology method !');
		return;
	}

	# Browse the list of sub features and recover the appropriate Sequence Ontology identifier for each feature
	for (my $i = 0; $i < scalar(@{$hitFeatures}) ; $i++) {
		# Initializations
		my ($Ontology, $Sub_type) = ('', '');

		if (scalar(@{$hitFeatures}) == 1) {
				$Sub_type = 'Single';
				$Ontology = $self->getSOTermId('CDS', $Sub_type);

			} elsif ($i == 0) {
				if ($Strand == -1) {
					$Sub_type = 'Terminal';
					$Ontology = $self->getSOTermId('CDS', $Sub_type);
				} else {
					$Sub_type = 'Initial';
					$Ontology = $self->getSOTermId('CDS', $Sub_type);
				}

			} elsif ($i == $Number_of_element - 1) {
				if ($Strand == -1) {
					$Sub_type = 'Initial';
					$Ontology = $self->getSOTermId('CDS', $Sub_type);
				} else {
					$Sub_type = 'Terminal';
					$Ontology = $self->getSOTermId('CDS', $Sub_type);
				}

			} else {
				$Sub_type = 'Internal';
				$Ontology = $self->getSOTermId('CDS', $Sub_type);
			}
		# Complete current feature tag list
		$hitFeatures->[$i]->add_tag_value('Ontology_term', $Ontology);
		if ($Sub_type ne '') {
			$hitFeatures->[$i]->add_tag_value('CDS' . '_type', $Sub_type);
		}
	}
}

1;
