#!/usr/local/bin/perl

use HTTP::DAV;

$d = HTTP::DAV->new;
$r = $d->new_resource( -uri => "http://localhost" );

print $r->as_string;
