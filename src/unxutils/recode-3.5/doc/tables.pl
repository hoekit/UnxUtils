#!/usr/bin/perl -w
# Automatically derive `recode' table files from various sources.
# Copyright ? 1993, 1994, 1997, 1998, 1999 Free Software Foundation, Inc.
# Fran?ois Pinard <pinard@iro.umontreal.ca>, 1993.

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2, or (at your option)
# any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software Foundation,
# Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

use strict;

# Generated file names.
my $CHARNAME = 'charname.h';
my $MNEMONIC = 'rfc1345.h';
my $EXPLODE = 'explode.c';
my $POOL = 'strip-pool.c';
my $DATA = 'strip-data.c';
my $TEXINFO = 'charset.texi';

# Usage clause.
my $USAGE = <<EOF;
\`tables.pl\' derives \`recode\' table files from various sources.

Usage: $0 [OPTION]... DATA-FILE...

  -e  produce C source file for explode data ($EXPLODE)
  -m  produce inclusion file for short mnemonics ($MNEMONIC)
  -n  produce inclusion file for character names ($CHARNAME)
  -p  produce C source files for strip data ($POOL and $DATA)
  -t  produce inclusion file for Texinfo ($TEXINFO)
  -F  produce French versions for -n or -t

DATA-FILEs may be rfc1345.txt, mnemonic[.,]ds, Unicode maps, or .def files
from Keld\'s chset* packages.  The digesting order is usually important.
When \`-F\' and \`-n\' are used, process Alain\'s tables.
EOF

# Generated copyright clause.
my $OVERALL_HEADER = <<END_OF_TEXT;
/* DO NOT MODIFY THIS FILE!  It was generated by \`recode/doc/tables.pl\'.  */

/* Conversion of files between different charsets and surfaces.
   Copyright ? 1999 Free Software Foundation, Inc.
   This file is part of the GNU C Library.
   Contributed by Fran?ois Pinard <pinard\@iro.umontreal.ca>, 1993, 1997.

   The \`recode\' Library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Library General Public License
   as published by the Free Software Foundation; either version 2 of the
   License, or (at your option) any later version.

   The \`recode\' Library is distributed in the hope that it will be
   useful, but WITHOUT ANY WARRANTY; without even the implied warranty
   of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.

   You should have received a copy of the GNU Library General Public
   License along with the \`recode\' Library; see the file \`COPYING.LIB\'.
   If not, write to the Free Software Foundation, Inc., 59 Temple Place -
   Suite 330, Boston, MA 02111-1307, USA.  */
END_OF_TEXT

# Ignore any mnemonic whose length is greater than $MAX_MNEMONIC_LENGTH.
my $MAX_MNEMONIC_LENGTH = 3;

# Character constants.
my $REPLACEMENT_CHARACTER = 0xFFFD;
my $NOT_A_CHARACTER = 0xFFFF;

# Change STRIP_SIZE in `src/recode.h' if you change the value here.
# See the accompanying documentation there, as needed.
my $STRIP_SIZE = 8;

# Argument decoding.

my $French_option = 0;
my $charname_option = 0;
my $explode_option = 0;
my $mnemonic_option = 0;
my $strip_option = 0;
my $texinfo_option = 0;

while (@ARGV > 0 && $ARGV[0] =~ /^(-.*)/) {
    ($French_option = 1, shift, next) if $1 eq '-F';
    ($charname_option = 1, shift, next) if $1 eq '-n';
    ($explode_option = 1, shift, next) if $1 eq '-e';
    ($mnemonic_option = 1, shift, next) if $1 eq '-m';
    ($strip_option = 1, shift, next) if $1 eq '-p';
    ($texinfo_option = 1, shift, next) if $1 eq '-t';
    die $USAGE;
}
die $USAGE if @ARGV < 1;

if ($explode_option) {
    &produce_explode_init ($EXPLODE);
} elsif ($strip_option) {
    &produce_strip_init ($DATA);
}

# Prepare to read various tables.

my $charset_ordinal = 0;
my $discard_charset = 0;
my $alias_count = 0;
my $description = '';

# Read all data tables.

my $INPUT;
foreach (@ARGV) {
    $INPUT = $_;
    open INPUT, $INPUT or die "Cannot read $INPUT\n";
    warn "Reading $INPUT\n";
    while (<INPUT>) {
	next if /^$/;

	if (/^\#    Name:/) {
	    &digest_unimap;
	    last;
	}

	next if /^\#/;

	if (/^escape_char/) {
	    &digest_mnemonics;
	    last;
	}

	if (/^Network Working Group +K\. Simonsen$/) {
	    if ($charname_option && ! $French_option) {
		$_ = <INPUT> until /^   3rd field is the long descriptive/;
		&digest_rfc1345_names;
	    }
	    if ($explode_option || $strip_option) {
		$_ = <INPUT> until /^5\.  CHARSET TABLES$/;
		&digest_rfc1345_tables;
	    }
	    last;
	}

	if (/^;Titre :/) {
	    if ($charname_option && $French_option) {
		$_ = <INPUT> until /^; SOUSCRIT/;
		$_ = <INPUT> until /^ *$/;
		&digest_french_names;
	    }
	    last;
	}

	if (/^&referenceset$/) {
	    $_ = <INPUT> until /^$/;
	    &digest_rfc1345_tables;
	    last;
	}

	if (/^   Repertoire according to ISO\/IEC 10646-1:1993$/) {
	    $_ = <INPUT> until /^   Plane 000$/;
	    &digest_iso10646_def;
	    last;
	}

	die "$INPUT:$.: Data file with unknown contents\n";
    }
    close INPUT;
}

if ($explode_option) {
    &produce_explode_term ($EXPLODE);
} elsif ($strip_option) {
    &produce_strip_term ($DATA, $POOL);
}
if ($charname_option) {
    &produce_charname ($French_option ? "fr-$CHARNAME" : $CHARNAME);
}
if ($mnemonic_option) {
    &produce_mnemonic ($MNEMONIC);
}
if ($texinfo_option) {
    &produce_texinfo ($French_option ? "fr-$TEXINFO" : $TEXINFO);
}

exit 0;

# Data readers.

## ----------------------------------------- ##
## Read in Keld's list of 10646 characters.  ##
## ----------------------------------------- ##

my $row;
my $cell;

sub digest_iso10646_def {
    my ($code, $mnemonic, $charname, $flag);

    while (<INPUT>) {
	next if /^$/;

	next if /^ $/;		# happens three times
	next if /^   \.\.\./;
	next if /^   Presentation forms$/;
	next if /^   naming: first vertical /;

	if (/^   row ([0-9][0-9][0-9])$/ && $1 < 256) {
	    $row = $1;
	    $cell = 0;
	    next;
	}

	if (/^   cell 00$/) {
	    $cell = 0;
	    next;
	}

	if (/^   cell ([0-9][0-9][0-9])$/ && $1 < 256) {
	    $cell = $1;
	    next;
	}

	if (/^   ([^ ]+)/) {
#	    s/^   // unless /^   [A-Z][A-Z][A-Z]/;
	    next unless /^   [A-Z][A-Z][A-Z]/;
	}

	if (/^   ([^ ].*)/) {
	    warn "$INPUT:$.: Over 256 cells in row $row\n" if $cell == 256;
	    $cell++;
	    next;
	}

	if (/^([^ ])  ([^ ].*)/ || /^([^ ][^ ]+) ([^ ].*)/) {
	    warn "$INPUT:$.: Over 256 cells in row $row\n" if $cell == 256;
	    &declare_mnemonic ($1, 256*$row + $cell++);
	    next;
	}

	warn "$INPUT:$.: Unrecognised line\n";
    }
}

## -------------------------- ##
## Read in a mnemonics file.  ##
## -------------------------- ##

sub digest_mnemonics {
    my ($mnemonic, $ucs2);

    while (<INPUT>) {
	if (/^<([^ \t\n]+)>\t<U(....)>/) {
	    ($mnemonic, $ucs2) = ($1, hex $2);
	    $mnemonic =~ s,/(.),$1,g;
	    &declare_mnemonic ($mnemonic, $ucs2);
	}
    }
}

## ------------------------------------------------------------------- ##
## Read the text of RFC 1345, saving all character names it declares.  ##
## ------------------------------------------------------------------- ##

my %ucs2;			# num. value of a character, given its mnemonic
my %charname;			# name of character, given its numerical value
my %code;			# frequency of each word, then its crypt code
my $max_length;			# maximum printable length of a character name

sub digest_rfc1345_names {
    sub read_line {
	my $line;

	while (defined ($line = <INPUT>)) {	# FIXME?
	    next if $line =~ /^Simonsen/ .. $line =~ /^RFC 1345/;
	    last if $line =~ /^4.  CHARSETS/;
	    next if $line =~ /^$/;
	    if ($line =~ s/^ //) {
		chop $line;
		return $line;
	    }
	}
	'';
    }

    $max_length = 0;

    # Read the character comments.  Count words in charnames.

    my $next;
    for ($_ = &read_line; $_; $_ = $next) {
	# Look ahead one line and merge it if it should.

	$next = &read_line;
	if ($next =~ /^             *( .*)/) {
	    $_ .= $1;
	    $next = &read_line;
	}

	# Separate fields and save needed information.

	if (/([^ ]+) +[0-9a-f]+ +(.*)/) {
	    my $mnemo = $1;
	    my $text = lc $2;

	    if (defined $ucs2{$mnemo}) {
		$charname{$ucs2{$mnemo}} = $text;
		if (length $text > $max_length) {
		    $max_length = length $text;
		}

		my $word;
		foreach $word (split (/ /, $text)) {
		    $code{$word}++;
		}
	    } elsif (length $mnemo <= $MAX_MNEMONIC_LENGTH) {
		warn "$INPUT:$.: No known UCS-2 code for \`$mnemo'\n";
	    }
	} elsif (!/ +e000/) {
	    warn "$INPUT:$.: What about <<$_>>?\n";
	}
    }
}

sub digest_french_names {
    my $ucs;
    my $text;

    $max_length = 0;

    $ucs = 0x0000;
    foreach $text (('nul (nul)',					# 0000
		    'd?but d\'en-t?te (soh)',				# 0001
		    'd?but de texte (stx)',				# 0002
		    'fin de texte (etx)',				# 0003
		    'fin de transmission (eot)',			# 0004
		    'demande (enq)',					# 0005
		    'accus? de r?ception positif (ack)',		# 0006
		    'sonnerie (bel)',					# 0007
		    'espace arri?re (bs)',				# 0008
		    'tabulation horizontale (ht)',			# 0009
		    'interligne (lf)',					# 000A
		    'tabulation verticale (vt)',			# 000B
		    'page suivante (ff)',				# 000C
		    'retour de chariot (cr)',				# 000D
		    'hors code (so)',					# 000E
		    'en code (si)',					# 000F
		    '?chappement transmission (dle)',			# 0010
		    'commande d\'appareil un (dc1)',			# 0011
		    'commande d\'appareil deux (dc2)',			# 0012
		    'commande d\'appareil trois (dc3)',			# 0013
		    'commande d\'appareil quatre (dc4)',		# 0014
		    'accus? de r?ception n?gatif (nak)',		# 0015
		    'synchronisation (syn)',				# 0016
		    'fin de transmission de bloc (etb)',		# 0017
		    'annulation (can)',					# 0018
		    'fin de support (em)',				# 0019
		    'caract?re de substitution (sub)',			# 001A
		    '?chappement (esc)',				# 001B
		    's?parateur de fichier (fs)',			# 001C
		    's?parateur de groupe (gs)',			# 001D
		    's?parateur d\'article (rs)',			# 001E
		    's?parateur de sous-article (us)')) {		# 001F
	$charname{$ucs++} = $text;
	if (length $text > $max_length) {
	    $max_length = length $text;
	}
	foreach my $word (split (/ /, $text)) {
	    $code{$word}++;
	}
    }

    $ucs = 0x007F;
    foreach $text (('suppression (del)',				# 007F
		    'caract?re de bourre (pad)',			# 0080
		    'octet sup?rieur pr?d?fini (hop)',			# 0081
		    'arr?t permis ici (bph)',				# 0082
		    'aucun arr?t ici (nbh)',				# 0083
		    'index (ind)',					# 0084
		    '? la ligne (nel)',					# 0085
		    'd?but de zone s?lectionn?e (ssa)',			# 0086
		    'fin de zone s?lectionn?e (esa)',			# 0087
		    'arr?t de tabulateur horizontal (hts)',		# 0088
		    'tabulateur horizontal avec justification (htj)',	# 0089
		    'arr?t de tabulateur vertical (vts)',		# 008A
		    'interligne partiel vers le bas (pld)',		# 008B
		    'interligne partiel vers le haut (plu)',		# 008C
		    'index invers? (ri)',				# 008D
		    'remplacement unique deux (ss2)',			# 008E
		    'remplacement unique trois (ss3)',			# 008F
		    'cha?ne de commande d\'appareil (dcs)',		# 0090
		    'usage priv? un (pu1)',				# 0091
		    'usage priv? deux (pu2)',				# 0092
		    'mise en mode transmission (sts)',			# 0093
		    'annulation du caract?re pr?c?dent (cch)',		# 0094
		    'message en attente (mw)',				# 0095
		    'd?but de zone prot?g?e (sga)',			# 0096
		    'fin de zone prot?g?e (ega)',			# 0097
		    'd?but de cha?ne (sos)',				# 0098
		    'introducteur de caract?re graphique unique (sgci)',# 0099
		    'introducteur de caract?re unique (sci)',		# 009A
		    'introducteur de s?quence de commande (csi)',	# 009B
		    'fin de cha?ne (st)',				# 009C
		    'commande de syst?me d\'exploitation (osc)',	# 009D
		    'message priv? (pm)',				# 009E
		    'commande de progiciel (apc)')) {			# 009F
	$charname{$ucs++} = $text;
	if (length $text > $max_length) {
	    $max_length = length $text;
	}
	foreach my $word (split (/ /, $text)) {
	    $code{$word}++;
	}
    }

    while (<INPUT>) {
	chomp;
	s/ +$//;
	if (/^([0-9A-F]{4}) ([^\(]+)( \(.*\))?$/) {
	    $ucs = hex $1;
	    ($text = $2) =~ tr/A-Z????????????/a-z????????????/;
	    $text =~ s/ +\*$//;

	    $charname{$ucs} = $text;
	    if (length $2 > $max_length) {
		$max_length = length $2;
	    }
	    foreach my $word (split (/ /, $text)) {
		$code{$word}++;
	    }
	} else {
	    warn "$INPUT:$.: What about $1 ?\n";
	}
    }
}

## ------------------------------------------------------------ ##
## Read the text of RFC 1345, saving all charsets it declares.  ##
## UCS-2 mnemonics files should have been read in already.      ##
## ------------------------------------------------------------ ##

my %used;
my @table;
my $codedim;
my $code;
my $list;
my $body;

my @declare_alias;
my %implied_surface;
my $charset;
my $hashname;

sub digest_rfc1345_tables {
    # Informal canonical order of presentation.
    my ($CHARSET, $REM, $ALIAS, $ESC, $BITS, $CODE) = (1, 2, 3, 4, 5, 6);
    my $status;

    while (<INPUT>) {
	next if /^Simonsen/ .. /^RFC 1345/;
	next if /^$/;
	last if /^ACKNOWLEDGEMENTS$/;
	next unless s/^  ?//;

	# Recognize `&charset'.

	if (/^&charset (.*)/) {
	    # Before beginning a new charset, process the previous one.
	    my $incoming_charset = $1;
	    &complete_charset;

	    $charset = $incoming_charset;

	    # Prepare for processing a new charset: save the charset
	    # name for further declaration; announce this charset in
	    # the array initialization section; and initialize its
	    # processing.

	    warn sprintf ("  %d) %s\n", $charset_ordinal + 1, $charset);
	    $status = $CHARSET;

	    $description = "\n/* $charset\n";

	    $hashname = lc $charset;
	    $hashname =~ s/[^a-z0-9]//g;
	    if ($used{$hashname}) {
		warn "$INPUT:$.: Duplicate of $used{$hashname} (discarded)\n";
		$discard_charset = 1;
		next;
	    }
	    $used{$hashname} = $charset;

	    $alias_count = 0;
	    @table = ($NOT_A_CHARACTER) x 256;
	    $codedim = 0;
	    $code = 0;
	    $list = '';
	    $body = '';

	    if ($charset =~ /^(CP|IBM)([0-9]+)$/) {
		$implied_surface{$2} = 'crlf';
		$implied_surface{"CP$2"} = 'crlf';
		$implied_surface{"IBM$2"} = 'crlf';
		push (@declare_alias, "$charset,$charset");
		$alias_count++;
#FIXME		  } elsif ($charset =~ /^windows-([0-9]+)$/) {
#FIXME		      $implied_surface{$1} = 'crlf';
#FIXME		      $implied_surface{"CP$1"} = 'crlf';
#FIXME		      $implied_surface{"IBM$1"} = 'crlf';
#FIXME		      push (@declare_alias, "$charset,$charset");
#FIXME		      $alias_count++;
	    } elsif ($charset =~ /^macintosh(_ce)?$/) {
		$implied_surface{$charset} = 'cr';
		push (@declare_alias, "$charset,$charset");
		$alias_count++;
	    }
	    next;
	}

	# Recognize other `&' directives.

	if (/^&rem (.*)/ && ! /^&rem &alias/) {
	    # Keld now prefers `&rem' to be allowed everywhere.
	    #warn "$INPUT:$.: \`&rem' out of sequence\n" if $status > $REM;
	    #$status = $REM;

	    if ($texinfo_option) {
		# Save C comments for Texinfo.

		my $string = $1;
		$string = (uc $1) . $2 if $string =~ /^([a-z])(.*)/;
		$string .= '.' if $string !~ /\.$/;
		$string =~ s/@/@@/g;
		$body .= $string . "\n";
	    }
	    next;
	}

	if (/^(&rem )?&alias (.*)/) {
	    warn "$INPUT:$.: \`&alias' out of sequence\n" if $status > $ALIAS;
	    $status = $ALIAS;

	    # Save synonymous charset names for later declarations.

	    my $alias = $2;
	    if ($alias =~ s/ +$//) {
		warn "$INPUT:$.: Spurious trailing whitespace\n";
	    }
	    $description .= "   $alias\n";

	    $hashname = lc $alias;
	    $hashname =~ s/[^a-z0-9]//g;
	    if ($used{$hashname} && $used{$hashname} ne $charset) {
		warn "$INPUT:$.: Duplicate of $used{$hashname}\n";
		next;
	    }
	    $used{$hashname} = $charset;

	    $list .= ',' if $list;
	    $list .= $alias;

	    if ($alias =~ /^(CP|IBM)([0-9]+)$/) {
		$implied_surface{$2} = 'crlf';
		$implied_surface{"CP$2"} = 'crlf';
		$implied_surface{"IBM$2"} = 'crlf';
	    } elsif ($alias =~ /^mac(ce)?$/) {
		$implied_surface{$alias} = 'cr';
	    }
	    push (@declare_alias, "$alias,$charset");
	    $alias_count++;
	    next;
	}

	if (/^&g[0-4]esc/) {
	    warn "$INPUT:$.: \`&esc' out of sequence\n" if $status > $ESC;
	    $status = $ESC;

	    next;
	}

	if (/^&bits ([0-9]+)$/) {
	    warn "$INPUT:$.: \`&bits' out of sequence\n" if $status > $BITS;
	    $status = $BITS;

	    if ($1 > 8) {
		warn "$INPUT:$.: \`&bits $1' not accepted (charset discarded)\n";
		$discard_charset = 1;
	    }
	    next;
	}

	if (/^&code (.*)/) {
	    warn "$INPUT:$.: \`&code' out of sequence\n" if $status > $CODE;
	    $status = $CODE;

	    # Save the code position.

	    $code = $1;
	    next;
	}

	# Other lines cause the charset to be discarded.

	if (/^&([^ ]+)/) {
	    unless ($discard_charset) {
		warn "$INPUT:$.: \`&$1' not accepted (charset discarded)\n";
		$discard_charset = 1;
	    }
	}

	next if $discard_charset;

	# Save all other tokens into the double table.

	if ($explode_option || $strip_option) {
	    my $token;
	    foreach $token (split) {
		if ($token eq '??') {
		    $table[$code] = $NOT_A_CHARACTER;
		} elsif ($token eq '__') {
		    $table[$code] = $REPLACEMENT_CHARACTER;
		} elsif (defined $ucs2{$token}) {
		    $table[$code] = $ucs2{$token};
		    if (length $token > $codedim) {
			$codedim = length $token;
		    }
		} else {
		    warn "$INPUT:$.: Unknown mnemonic for $code: $token\n";
		    $table[$code] = $REPLACEMENT_CHARACTER;
		}
		$code++;
	    }
	}
    }

    # Push the last charset out.
    &complete_charset;
}

## ---------------------------------------------------------------- ##
## Read a Unicode map, as found in ftp://ftp.unicode.com/MAPPINGS.  ##
## ---------------------------------------------------------------- ##

sub digest_unimap {
    my @name;

    if (/^\# +Name: +([^ ]+) to Unicode table$/) {
	@name = split (/_/, $1);
	$charset = shift @name;
	$description = "\n/* $charset\n";

	$hashname = lc $charset;
	$hashname =~ s/[^a-z0-9]//g;
	if ($used{$hashname}) {
	    warn "$INPUT:$.: \`$hashname' duplicates \`$used{$hashname}'"
		. " (charset discarded)\n";
	    $discard_charset = 1;
	    next;
	}
	$used{$hashname} = $charset;

	$alias_count = 0;
	@table = ($NOT_A_CHARACTER) x 256;
	$codedim = 0;
	$code = 0;
	$list = '';
	$body = '';
    }
    return if $discard_charset;

    my $alias;
    while ($alias = shift @name) {
	$description .= "   $alias\n";

	$hashname = lc $alias;
	$hashname =~ s/[^a-z0-9]//g;
	if ($used{$hashname} && $used{$hashname} ne $charset) {
	    warn "$INPUT:$.: \`$hashname' duplicates \`$used{$hashname}'\n";
	    next;
	}
	$used{$hashname} = $charset;

	$list .= ',' if $list;
	$list .= $alias;
	push (@declare_alias, "$alias,$charset");
	$alias_count++;
    }

    while (<INPUT>) {
	next if /^$/;
	next if /^\#/;
	next if /^0x([0-9A-F]+)\t\t\#UNDEFINED$/;
	last if /\032/;		# old MS-DOS C-Z !! :-)

	if (/^0x([0-9A-F]+)\t0x([0-9A-F]+)\t\#/) {
	    $table[hex $1] = hex $2;
	} else {
	    warn "$INPUT:$.: Unrecognised input line\n";
	}
    }

    &complete_charset;
}

# Reader services.

## ---------------------------------------------------------------- ##
## Declare a correspondence between a mnemonic and an UCS-2 value.  ##
## ---------------------------------------------------------------- ##

my $table_length = 0;
my %mnemonic;

sub declare_mnemonic {
    my ($mnemonic, $ucs2) = @_;

    return if length $mnemonic > $MAX_MNEMONIC_LENGTH;

    if ($mnemonic_option) {
	if (defined $mnemonic{$ucs2}) {
	    if ($mnemonic{$ucs2} ne $mnemonic) {
		warn sprintf ("$INPUT:$.: U+%04X \`%s' known as \`%s'\n",
			      $ucs2, $mnemonic, $mnemonic{$ucs2});
		$mnemonic{$ucs2} = $mnemonic
		    if length $mnemonic < length $mnemonic{$ucs2};
	    }
	} else {
	    $mnemonic{$ucs2} = $mnemonic;
	    $table_length++;
	}
    }

    if ($charname_option || $explode_option || $strip_option) {
	if (defined $ucs2{$mnemonic}) {
	    if ($ucs2{$mnemonic} ne $ucs2) {
		warn sprintf ("$INPUT:$.: `%s' U+%04X known as U+%04X\n",
			      $mnemonic, $ucs2, $ucs2{$mnemonic});
		$cell = $ucs2{$mnemonic} - 256*$row;
	    }
	} else {
	    $ucs2{$mnemonic} = $ucs2;
	}
    }
}

## ---------------------------------------------------------- ##
## Print all accumulated information for the charset.  If the ##
## charset should be discarded, adjust tables.                ##
## ---------------------------------------------------------- ##

my %list;
my %body;
my @declare_charset;
my @strip;

sub complete_charset {
    my $count;

    if ($discard_charset) {
	while ($alias_count-- > 0) {
	    pop @declare_alias;
	}
	$discard_charset = 0;
	$description = '';
    }
    return unless $description;

    if ($texinfo_option) {
	# Save the documentation.

	$list{$charset} = $list;
	$body{$charset} = $body;
    }

    if ($explode_option) {
	# Make introductory C comments.

	print OUTPUT $description;
	print OUTPUT "*/\n";

	# Make the table for this charset.

	print OUTPUT "\n";
	print OUTPUT
	    "static const unsigned short data_$charset_ordinal\[\] =\n";
	print OUTPUT "  {\n";
	for ($code = 0; $code < 256; $code++) {
	    if ($code != $table[$code]) {
		printf OUTPUT
		    "    %3d, 0x%.4X, DONE,\n", $code, $table[$code];
	    }
	}
	print OUTPUT "    DONE\n";
	print OUTPUT "  };\n";

	# Register the table.

	push (@declare_charset, $charset);
    }

    if ($strip_option) {
	# Make introductory C comments.

	print OUTPUT $description;
	print OUTPUT "*/\n";

	# Make the table for this charset.

	print OUTPUT "\n";
	print OUTPUT
	    "static struct strip_data data_$charset_ordinal =\n";
	print OUTPUT "  {\n";
	print OUTPUT "    ucs2_data_pool,\n";
	print OUTPUT "    {\n";
	$count = 0;
	for ($code = 0; $code < 256; $code += $STRIP_SIZE) {
	    if ($count % 12 == 0) {
		print OUTPUT ",\n" if $count != 0;
		print OUTPUT '      ';
	    } else {
		print OUTPUT ', ';
	    }

	    @strip = @table[$code .. $code + $STRIP_SIZE - 1];
	    printf OUTPUT '%4d', &pool_index;
	    $count++;
	}
	print OUTPUT "\n";
	print OUTPUT "    }\n";
	print OUTPUT "  };\n";

	# Register the table.

	push (@declare_charset, $charset);
    }

    $charset_ordinal++;
    $description = '';
}

## ---------------------------------------------------------------- ##
## Return the pool index for @strip.  Add to the pool as required.  ##
## ---------------------------------------------------------------- ##

my %pool;
my $pool;
my $pool_refs;
my $pool_size;

sub pool_index {
    my $strip = join ('', map (sprintf ('%04X', $_), @strip));

    $pool_refs++;

    if (! defined $pool{$strip}) {
	$pool{$strip} = $pool_size;
	$pool .= $strip;
	$pool_size += @strip;
    }
    $pool{$strip};
}

# Table writers.

## -------------------------------------------- ##
## Write a compressed list of character names.  ##
## -------------------------------------------- ##

sub produce_charname {
    my ($output_name) = @_;
    my (@word, @ucs2, $count, $singles, $char1, $char2, $word, $ucs2, $code);

    open OUTPUT, ">$output_name" or die "Cannot write $output_name\n";
    warn "Writing $output_name\n";
    print OUTPUT $OVERALL_HEADER;

    # Establish a mild compression scheme.  Words @word[0] to
    # @word[$singles-1] will be represented by a single byte running from
    # 1 to $singles.  All remaining words will be represented by two
    # bytes, the first one running slowly from $singles+1 to 255, the
    # second cycling faster from 1 to 255.

    print STDERR '  sorting words...';
    @word = sort descending keys %code;
    printf STDERR " %d of them\n", 0 + @word;
    $count = 0 + @word;
    $singles = int ((255 * 255 - $count) / 254);

    # Transmit a few values for further usage by the C code.

    print STDERR '  sorting names...';
    @ucs2 = sort { $a <=> $b } keys %charname;
    printf STDERR " %d of them\n", 0 + @ucs2;

    print OUTPUT "\n";
    printf OUTPUT "#define NUMBER_OF_SINGLES %d\n", $singles;
    printf OUTPUT "#define MAX_CHARNAME_LENGTH %d\n", $max_length;
    printf OUTPUT "#define NUMBER_OF_CHARNAMES %d\n", (0 + @ucs2);

    # Establish a mild compression scheme (one or two bytes per word).

    warn "  writing words\n";
    print OUTPUT "\n";
    print OUTPUT "static const char *const word[$count] =\n";
    print OUTPUT "  {\n";

    $char1 = 1;
    $char2 = 1;

    my $counter;
    for ($counter = 0; $counter < $singles; $counter++) {
	$word = $word[$counter];
	$word =~ s/\"/\\\"/;
	printf OUTPUT "    %-28s/* \\%0.3o */\n", "\"$word\",", $char1;
	$code{$word[$counter]} = $char1;
	$char1++;
    }

    for (; $counter < $count; $counter++) {
	$word = $word[$counter];
	$word =~ s/\"/\\\"/;
	printf OUTPUT
	    "    %-28s/* \\%0.3o\\%0.3o */\n", "\"$word\",", $char1, $char2;
	$code{$word[$counter]} = 256 * $char1 + $char2;
	if ($char2 == 255) {
	    $char1++;
	    $char2 = 1;
	} else {
	    $char2++;
	}
    }
    print OUTPUT "  };\n";

    warn "  writing names\n";
    print OUTPUT "\n";
    print OUTPUT "struct charname\n";
    print OUTPUT "  {\n";
    print OUTPUT "    recode_ucs2 code;\n";
    print OUTPUT "    const char *crypted;\n";
    print OUTPUT "  };\n";

    print OUTPUT "\n";
    print OUTPUT
	"static const struct charname charname[NUMBER_OF_CHARNAMES] =\n";
    print OUTPUT "  {\n";

    foreach $ucs2 (@ucs2) {
	printf OUTPUT "    {0x%04X, \"", $ucs2;
	foreach $word (split (' ', $charname{$ucs2})) {
	    $code = $code{$word};
	    print "??? $word\n" unless defined $code;
	    if ($code < 256) {
		printf OUTPUT "\\%0.3o", $code;
	    } else {
		printf OUTPUT "\\%0.3o\\%0.3o", int ($code / 256), $code % 256;
	    }
	}
	print OUTPUT "\"},\n";
    }

    print OUTPUT "  };\n";
    close OUTPUT;
}

## ------------------------------------------- ##
## Write an UCS-2 to RFC 1345 mnemonic table.  ##
## ------------------------------------------- ##

sub produce_mnemonic {
    my ($output_name) = @_;
    my ($count, $ucs2, $string, %inverse);

    open OUTPUT, ">$output_name" or die "Cannot create $output_name\n";
    warn "Writing $output_name\n";

    print OUTPUT $OVERALL_HEADER;
    print OUTPUT "\n";
    print OUTPUT "#define TABLE_LENGTH $table_length\n";
    print OUTPUT "#define MAX_MNEMONIC_LENGTH $MAX_MNEMONIC_LENGTH\n";
    print OUTPUT "\n";
    print OUTPUT "struct entry\n";
    print OUTPUT "  {\n";
    print OUTPUT "    recode_ucs2 code;\n";
    print OUTPUT "    const char *rfc1345;\n";
    print OUTPUT "  };\n";
    print OUTPUT "\n";
    print OUTPUT "static const struct entry table[TABLE_LENGTH] =\n";
    print OUTPUT "  {\n";
    $count = 0;
    foreach $ucs2 (sort {$a <=> $b} keys %mnemonic) {
	$string = $mnemonic{$ucs2};
	$inverse{$string} = $count;
	$string =~ s/([\"])/\\$1/g;
	printf OUTPUT
	    "    /* %4d */ {0x%04X, \"%s\"},\n", $count, $ucs2, $string;
	$count++;
    }
    print OUTPUT "  };\n";
    print OUTPUT "\n";
    print OUTPUT "static const unsigned short inverse[TABLE_LENGTH] =\n";
    print OUTPUT '  {';
    $count = 0;
    foreach $string (sort keys %inverse) {
	if ($count % 10 == 0) {
	    print OUTPUT ',' if $count != 0;
	    printf OUTPUT "\n    /* %4d */ ", $count;
	} else {
	    print OUTPUT ', ';
	}
	printf OUTPUT '%4d', $inverse{$string};
	$count++;
    }
    print OUTPUT "\n";
    print OUTPUT "  };\n";

    close OUTPUT;
}

## ------------------------------- ##
## Write the explode source file.  ##
## ------------------------------- ##

sub produce_explode_init {
    my ($output_name) = @_;

    # Prepare the production of tables.

    open OUTPUT, ">$output_name";
    warn "Starting $output_name\n";
    print OUTPUT $OVERALL_HEADER;
    print OUTPUT "\n";
    print OUTPUT "#include \"common.h\"\n";
}

# [...] Table fragments will be produced while reading data tables.

sub produce_explode_term {
    my ($output_name) = @_;
    my ($count, $string);

    # Print the collectable initialization function.

    warn "Completing $output_name\n";
    print OUTPUT "\n";
    print OUTPUT "bool\n";
    printf OUTPUT "module_explodes (struct recode_outer *outer)\n";
    print OUTPUT "{\n";
    $count = 0;
    while ($string = shift @declare_charset) {
	print OUTPUT
	    "  if (!declare_explode_data (outer, &data_$count, \"$string\"))\n";
	print OUTPUT "    return false;\n";
	$count++;
    }
    print OUTPUT "\n";
    while ($string = shift @declare_alias) {
	$string =~ s/,/", "/;
	print OUTPUT "  if (!declare_alias (outer, \"$string\"))\n";
	print OUTPUT "    return false;\n";
    }
    print OUTPUT "\n";
    print OUTPUT "  return true;\n";
    print OUTPUT "}\n";
    close OUTPUT;
}

## --------------------------------- ##
## Write the pool and index tables.  ##
## --------------------------------- ##

sub produce_strip_init {
    my ($output_name) = @_;

    # Prepare the production of tables.

    $pool_size = 0;
    $pool_refs = 0;
    %pool = ();
    $pool = '';

    open OUTPUT, ">$output_name";
    warn "Starting $output_name\n";
    print OUTPUT $OVERALL_HEADER;
    print OUTPUT "\n";
    print OUTPUT "#include \"common.h\"\n";
}

# [...] Table fragments will be produced while reading data tables.

sub produce_strip_term {
    my ($output_name, $pool_name) = @_;
    my ($count, $string);

    # Give memory statistics.

    warn sprintf ("Table memory = %d bytes (pool %d, refs %d)\n",
		  $pool_size * 2 + $pool_refs * 2,
		  $pool_size * 2, $pool_refs * 2);

    # Print the collectable initialization function.

    warn "Completing $output_name\n";
    print OUTPUT "\n";
    print OUTPUT "bool\n";
    printf OUTPUT "module_strips (struct recode_outer *outer)\n";
    print OUTPUT "{\n";
    print OUTPUT "  RECODE_SYMBOL symbol;\n";
    print OUTPUT "\n";
    $count = 0;
    while ($string = shift @declare_charset) {
	print OUTPUT
	    "  if (!declare_strip_data (outer, &data_$count, \"$string\"))\n";
	print OUTPUT "    return false;\n";
	$count++;
    }
    print OUTPUT "\n";
    while ($string = shift @declare_alias) {
	my ($alias, $charset) = $string =~ /^(.*),(.*)$/;
	if (defined $implied_surface{$alias}) {
	    print OUTPUT "  if (symbol = declare_alias (outer, \"$alias\", \"$charset\"), !symbol)\n";
	    print OUTPUT "    return false;\n";
	    print OUTPUT "  if (!declare_implied_surface (outer, symbol, outer->$implied_surface{$alias}_surface))\n";
	    print OUTPUT "    return false;\n";
	} else {
	    print OUTPUT "  if (!declare_alias (outer, \"$alias\", \"$charset\"))\n";
	    print OUTPUT "    return false;\n";
	}
    }
    print OUTPUT "\n";
    print OUTPUT "  return true;\n";
    print OUTPUT "}\n";
    close OUTPUT;

    # Write the pool file.

    open OUTPUT, ">$pool_name" or die "Cannot create $pool_name\n";
    warn "Writing $pool_name\n";
    print OUTPUT $OVERALL_HEADER;
    print OUTPUT "\n";
    print OUTPUT "#include \"common.h\"\n";
    print OUTPUT "\n";
    print OUTPUT "const recode_ucs2 ucs2_data_pool[$pool_size] =\n";
    print OUTPUT '  {';
    for ($count = 0; $count < $pool_size; $count++) {
	if ($count % 8 == 0) {
	    print OUTPUT ',' if $count != 0;
	    printf OUTPUT "\n    /* %4d */ ", $count;
	} else {
	    print OUTPUT ', ';
	}
	print OUTPUT '0x', substr ($pool, $count * 4, 4);
    }
    print OUTPUT "\n";
    print OUTPUT "  };\n";
    close OUTPUT;
}

## ------------------------------ ##
## Write the documentation file.  ##
## ------------------------------ ##

sub produce_texinfo {
    my ($output_name) = @_;
    my ($charset, @list, $string);

    open OUTPUT, ">$output_name" or die "Cannot create $output_name\n";
    warn "Writing $output_name\n";
    for $charset (sort keys %body) {
	print OUTPUT "\n\@item $charset\n";
	@list = sort (split (/,/, $list{$charset}));
	if (@list == 1) {
	    print OUTPUT
		'@code{', $list[0], "} is an alias for this charset.\n";
	} elsif (@list > 0) {
	    $string = '@code{' . join ('}, @code{', @list) . '}';
	    $string =~ s/,([^,]+)$/ and$1/;
	    print OUTPUT $string, " are aliases for this charset.\n";
	}
	print OUTPUT $body{$charset};
    }
    close OUTPUT;
}

# Writer services.

# Comparison routine for descending sort on frequencies.

sub descending {
    my $result = $code{$b} - $code{$a};

    $result == 0 ? $a cmp $b : $result;
}
