#!/usr/bin/env perl

package TriAnnot::Tools::MergeHits;

##################################################
## Documentation POD
##################################################
=head1 Name
TriAnnot::Tools::MergeHits;
=head2 Description
Use this package to merge hits from various modules of the TriAnnot pipeline
Program input: a table of couples of coordinates of hit and informations to build Bio::SeqFeature::Generic objects
Program output: a table containing all the merged hit from the input table
=head3 Included modules
## Perl modules
use strict;
use warnings;
use diagnostics;
## Bioperl modules
## TriAnnot modules
=head4 Authors
Copyrigth A. Bernard, F. Giacomoni, P. Leroy
=cut

# Basic Perl modules
use strict;
use warnings;
use diagnostics;

# Bioperl modules
# GPI modules

##################################################
#                                                       Functions                                                          #
##################################################
=head1 TriAnnot::Tools::MergeHits - Functions
=cut

#################
#  Function Merge_all_hit()   #
#################

=head2 Merge_all_hit
 Title    : Merge_all_hit()
 Usage    : Merge_all_hit($input_table_reference,$seq_name,$source_tag);
 Function : This function analyses a list of couples of coordinates to create merged couples of coordinates
 Args     : The reference to a table of coordinates
 Returns  : The reference to a table of merged coordinates
=cut

sub Merge_all_hit {

	# Recovers parameters
	my ($input_table_reference,$seq_name,$source_tag) = @_;

	# Transforms the table reference in a real table
	my @Coordinates = @{$input_table_reference};

	# Initilizations
	my (@Uniq_sort, @final_couples, @All_merged_hit) = ((), (), ());
	my ($old_start, $old_stop, $MergeNumber)= (-100, -100, 0);
	my ($new_line, $line);

	# Use a hash table allow us to eliminate duplicate lines
	my %tampon = map { $_ => 1 } @Coordinates; # Note: map execute a same operation on each element of a tab

	# Sorts of lines
	# Note: use of a special numerical comparison in the sort function ( Only the first element of each lines are compared )
	@Uniq_sort = sort {(split(/\t/, $a))[0] <=> (split(/\t/, $b))[0]} keys %tampon;

	foreach $line (@Uniq_sort){

		my ($start, $stop) = split(/\t/, $line);

		# Merging case
		if ( ($start == $old_stop+1) or ( ($start <= $old_stop) && ($stop > $old_stop) ) ) {

			# If explanation:
			# Case 1:  1----108 et 109----200 --> fusion: 1----200
			# Case 2: 1----108 et 100----150 --> fusion: 1----150
			# Rejected case: 1----1000 et 50----625 --> No merging because the second élément is fully integrated in the first element

			$new_line = $old_start . "\t" . $stop;
			pop(@final_couples); # Remove the last element of the final table
			push(@final_couples, $new_line); # Add the new "fusion element" to the final table

			# Updates of $old_stop ( $old start don't have to be updated)
			$old_stop = $stop;
		}

		# New element case
		if ($start > $old_stop+1) {

			# If explanation:
			# Only one case:  1----108 et 500----700 --> Adding of 500----700 to the final table

			push(@final_couples, $line);

			# $old variable update
			$old_start = $start;
			$old_stop = $stop;
		}

		# Nothing to do if the current line is a repeat included in another repeat already inserted in the final table ( No adding, no merging)
	}

	# Creation of the merged hit features
	foreach (@final_couples) {

		# Gets start et stop of the merged hit
		my ($neo_start, $neo_stop) = split("\t", $_);

		# Increases the number of merged hit
		$MergeNumber++;
		$MergeNumber = sprintf("%04d", $MergeNumber);

		my $merged_hit_Tag = {};
		$merged_hit_Tag->{'ID'} = $seq_name . '_' . $source_tag . '_Merged_Hit_' . $MergeNumber;
		$merged_hit_Tag->{'Name'} = $source_tag . '_Merged_Hit_' . $MergeNumber;
		$merged_hit_Tag->{'Note'} = 'Merged hits';

		my $merged_hit = Bio::SeqFeature::Generic->new(
				 -seq_id      => $seq_name,
				 -source_tag  => $source_tag,
				 -primary_tag => 'region',
				 -start       => $neo_start,
				 -end         => $neo_stop,
				 -tag         => $merged_hit_Tag
				);

		push(@All_merged_hit, $merged_hit);
	}

	return(\@All_merged_hit);
}

1;
