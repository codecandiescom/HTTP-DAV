#!/usr/local/bin/perl -w
use strict;
use HTTP::DAV;
use Test;

my $TESTS;
BEGIN {
    require "t/TestDetails.pm"; import TestDetails;
    $TESTS = 6;
    plan tests => $TESTS
}


my $dav = HTTP::DAV->new;
HTTP::DAV::DebugLevel(3);

if ( TestDetails::url() !~ /http/ ) {
   print  "You need to set a test url in the t/TestDetails.pm module.\n";
   for(1..$TESTS) { skip(1,1); }
   exit;
}

$dav->credentials( TestDetails::user(), TestDetails::pass(), TestDetails::url());

my $collection = TestDetails::url();
$collection=~ s#/$##g; # Remove trailing slash. We'll put it on.
my $new_file = "$collection/dav_test_file.txt";
print "File: $new_file\n";
my $resource = $dav->new_resource( -uri => $new_file );

my $response;

$response = $resource->put("DAV.pm test content ");
if (! ok($response->is_success) ) {
   print $response->message() ."\n";
}

$response = $resource->get();
if (! ok($response->is_success) ) {
   print $response->message() ."\n";
}

my $content1 = $resource->get_content();
my $content2 = $resource->get_content_ref();
ok( $content1, '/\w/');
ok( $$content2, '/\w/');
print $content1 ."\n";
print $$content2 ."\n";
ok( $content1 eq $$content2 );

$response = $resource->delete();
if (! ok($response->is_success) ) {
   print $response->message() ."\n";
}

