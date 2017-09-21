# Overload Bio::SeqIO::embl class to avoid truncating lines to 80 characters

package Bio::SeqIO::embltriannot;
use strict;

use base qw(Bio::SeqIO::embl);

sub _write_line_EMBL_regex {
    my ($self,$pre1,$pre2,$line,$regex,$length) = @_;
	$self->SUPER::_write_line_EMBL_regex($pre1,$pre2,$line,$regex,9999);
}
1;
