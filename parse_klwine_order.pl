#!/usr/bin/perl

# perl parse_klwine_order.pl  < klwine_order_history_8-21-2012.html | iconv -f "ISO-8859-1" -t "UTF-8"

use strict;
use Data::Dumper;

#use Text::Iconv;
#my $converter = Text::Iconv->new("ISO-8859-1","UTF-8");

my $dump = 0;

if ($ARGV[0] eq '-d') {
    $dump=1;
    shift @ARGV;
}

my $skip_zero_price = 0;      # these only show the state change for pre-arrivals

my $text = join('',<>);

# delete non-xml header and footer
$text =~ s/^.+?<orderrecs>//si;
$text =~ s/<\/orderrecs>.*//s;
$text =~ s/\s+/ /gs;
$text =~ s/\222/'/gs;

my $count = 0;
my $cost  = 0;
my $items = 0;
my %records;
my %hash;

while ($text =~ s,<orec>(.+?)</orec>,,si) {
    my $record = $1;
    my %rec;
    while ($record =~ s,<([A-za-z]+)>([^<]+)<[^>]+>,,s) {
	my ($key,$value) = (lc($1),$2);
	$rec{$key} = $value;
	$hash{$key}++;
    }
    #    print "leftover = [$record]\n";

    # fixup
    my $desc = $rec{descr};
#    my $utf8_desc = $converter->convert($desc);
#    $rec{descr} = $utf8_desc;

    $rec{date} = $rec{tscreated};
    $rec{date} =~ s/\s.+$//;  # chop off time, use only date
    $rec{date} =~ s|^(\d+)/(\d+)/(\d+)$| &format_date($1,$2,$3) |e;
    $hash{date}++;

    if ($rec{descr} =~ /\s\(([^\)]+)\)\s*/) {
	my @notes = ();
	while ($rec{descr} =~ s/\s\(([^\)]+)\)\s*/ /g) {
	    push(@notes,$1);
	}
	$rec{note} = join(', ', @notes);
	$hash{note}++;
    }
    $rec{descr} =~ s/\s+$//;

    if ($rec{descr} =~ /^(\d{4})\s/) {
	$rec{year} = $1;
	$hash{year}++;
    }

#    delete $rec{location};

    my $id = $count++;
    $records{$id} = \%rec;

    print Data::Dumper::Dumper(\%rec) if ($dump);

    if ($rec{qty} > 0) {
	if ($rec{price} >= 0.01) {
	    $cost  += ($rec{price} * $rec{qty}) + $rec{tax}; 
	}
	$items += $rec{qty};
    }
}

# print STDERR "Keys: " . join(',',keys %hash) . "\n";

$cost = sprintf("%0.2f",$cost);   # fix rounding errors.

print STDERR "total orders  = $count\n";
print STDERR "total items   = $items\n";
print STDERR "total cost    = $cost\n";

my @cols =  qw (orderid sku status date location qty price descr note);

my $col_format = {
    orderid   =>  '%8d',
    sku   =>  '%7d',
    year  =>  '%4s',
    descr =>  '%s',
    qty   =>  '%3d',
    price =>  '%6.2f',
    note  =>  '%s',
    date  =>  '%10s',
    location => '%3s',
    status =>  '%1s',
};

my $header_format;
my $header_format_len;
foreach my $key (keys %$col_format) 
{
    $header_format->{$key} = $col_format->{$key};
    $header_format->{$key} =~ s/^(%\d+).+/$1s/;
    $header_format_len->{$key} = 15;
    if ($header_format->{$key} =~ /(\d+)/) 
    { 
	$header_format_len->{$key} = $1; 
    }
}

my @format_col = ();
foreach my $c (@cols) 
{
    my $fc = $c;
    $fc = "[$fc]" if ($c eq "note");
    $fc = sprintf( $header_format->{$c}, (length($fc) > $header_format_len->{$c} ? substr($fc,0,$header_format_len->{$c}) : $fc));
    # print "$c  [$fc] $header_format->{$c} $header_format_len->{$c}\n"; 
    push(@format_col, $fc);
}

print join(" ",@format_col) . "\n";
foreach my $id ( sort { record_sort($a,$b) } keys %records) {

    next if ($skip_zero_price && ( $records{$id}->{price} + 0.0 == 0.0)) ;
    my @row = ();
    foreach my $key (@cols) {
	my $item = $records{$id}->{$key}; 
	$item =~ s/\t/ /g;
#	$item =~ s/"/ /g;
#	$item = '"' . $item . '"';

	my $formatted_item = sprintf($col_format->{$key} || '%s', $item);
	$formatted_item = "[$formatted_item]" if ($key eq 'note' && $item ne '');

	push(@row, $formatted_item);
    }
    print join(" ",@row) . "\n";
}

print <<END_MSG 
N   NEW - A new order that hasn't been moved to our picking department.
P   PICKING - The order is in the process of being pulled together.
S   SHIPPING - The order is being packaged and prepared for shipment. If your order is a will-call this status indicates it's either at the will-call destination or in transit to the will-call destination. When the order has arrived at the will-call destination we send a confirmation to the email address within your account.
X   CLOSED - Your order has already been shipped out or picked up.
Z   CANCELED - Your order has been canceled.
END_MSG
;


	
sub record_sort
{
    my ($a,$b) = @_;
    return  $records{$a}->{orderid} <=> $records{$b}->{orderid} ||
            $records{$a}->{date} cmp $records{$b}->{date} ||
	    $records{$a}->{sku}  <=> $records{$b}->{sku};
}

sub format_date
{
    my ($m,$d,$y) = @_;
    return sprintf("%d-%02d-%02d",$y,$m,$d);
}
