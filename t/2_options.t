#!/usr/local/bin/perl -w
use strict;
use HTTP::DAV;
use Test;

my $TESTS;
BEGIN { 
   require "t/TestDetails.pm"; import TestDetails;
   $TESTS = 6;
   plan tests => $TESTS; 
}

my $dav = HTTP::DAV->new;
$dav->DebugLevel(3);

if ( TestDetails::url() !~ /http/ ) {
   print  "You need to set a test url in the t/TestDetails.pm module.\n";
   for(1..$TESTS) { skip(1,1); }
   exit;
}

$dav->credentials(
        TestDetails::user(),
        TestDetails::pass(),
        TestDetails::url() 
      );

my $resource = $dav->new_resource( -uri => TestDetails::url() );
my $response = $resource->options();
if ( ! ok($response->is_success) ) {
   print $response->message() ."\n";
}

print "DAV compliancy: ". $resource->is_dav_compliant(). "\n";
ok($resource->is_dav_compliant());

my $options = $resource->get_options || "";
print "$options\n";
ok($options,'/PROPFIND/');
ok($resource->is_option('PROPFIND'),1);
ok($resource->is_option('JUNKOPTION'),0);
   
ok($resource->get_username(),TestDetails::user());
