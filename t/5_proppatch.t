#!/usr/local/bin/perl -w
use strict;
use HTTP::DAV;
use Test;
use Cwd;

# Tests basic proppatch.

my $TESTS;
BEGIN {
    require "t/TestDetails.pm"; import TestDetails;
    $TESTS=14;
    plan tests => $TESTS
}

# I'll skip all the tests if you haven't set a default url
if ( TestDetails::url() !~ /http/ ) {
   print  "You need to set a test url in the t/TestDetails.pm module.\n";
   for(1..$TESTS) { skip(1,1); }
   exit;
}

my $user = TestDetails::user();
my $pass = TestDetails::pass();
my $url = TestDetails::url();
my $cwd = getcwd(); # Remember where we started.

HTTP::DAV::DebugLevel(3);

######################################################################
# UTILITY FUNCTION: 
#    do_test <op_result>, <expected_result>, <message>
# IT was getting tedious doing the error handling so 
# I built this little routine, Makes the test cases easier to read.
sub do_test {
   my($dav,$result,$expected,$message) = @_;
   $expected = 1 if !defined $expected;
   my $ok;
   my $davmsg = $dav->message;
   if ($expected) {
      if ( $ok = ok($result,$expected) ) {
         print "$message succeeded\n";
      } else {
         print "$message failed: \"$davmsg\"\n";
      }
   } else {
      if ( $ok = ok($result,$expected) ) {
         print "$message failed (as expected): \"$davmsg\"\n";
      } else {
         print "$message succeeded (unexpectedly): \"$davmsg\"\n";
      }
   }
   return $ok;
}
######################################################################

# Make a directory with our process id after it 
# so that it is somewhat random
my $newdir = "perldav_test$$";

=begin

Proppatch - Test plan
-------------------------
We want to perform test functions against proppatch. 

Setup.
   OPEN
   MKCOL perldav_test
   CWD perldav_test

Test 1. We want to test a set prop sequence.
   PROPPATCH (set patrick:test_prop=test_val)

Test 2. Then an remove prop sequence
   PROPPATCH perldav_test (remove patrick:test_prop)

Test 3. Then lock perldav_test and do a proppatch. No namespace
   3a. LOCK perldav_test
   3a. PROPPATCH perldav_test (set test_prop=test_val)
   3b. PROPPATCH perldav_test (remove DAV:test_prop)
   3b. UNLOCK perldav_test

=cut 

# Setup
my $dav1 = HTTP::DAV->new();
$dav1->credentials( $user, $pass, $url );
do_test $dav1, $dav1->open  ( $url ),  1,"OPEN $url";
do_test $dav1, $dav1->mkcol ($newdir), 1,"MKCOL $newdir";
do_test $dav1, $dav1->cwd   ($newdir), 1,"CWD $newdir";

my $resource = $dav1->get_workingresource();

# Test 1
my $resp = $resource->proppatch(-namespace=>'patrick',
                     -propname=>'test_prop',
                     -propvalue=>'test_val'
                    );
do_test $resp, $resp->is_success, 1,"proppatch set test_prop";
$resp = $resource->propfind(-depth=>0);
if ($resp->is_success) {
   do_test $resp, $resource->get_property('test_prop'),'test_val',"propfind get_property test_prop";
} else {
   print "Couldn't perform propfind\n";
   ok 0;
}
print $resource->as_string;

# Test 2
$resp = $resource->proppatch(-namespace=>'patrick',
                     -propname=>'test_prop',
                     -action=>'remove'
                    );
do_test $resp, $resp->is_success, 1,"proppatch remove test_prop";
print $resp->as_string;
$resp = $resource->propfind(-depth=>0);
if ($resp->is_success) {
   do_test $resp, $resource->get_property('test_prop'),'',"propfind get_property test_prop";
} else {
   print "Couldn't perform propfind\n";
   ok 0;
}
print $resource->as_string;

######################################################################
# Test 3a
do_test $dav1, $dav1->lock  (),          1,"LOCK";

$resp = $resource->proppatch(
                     -propname=>'test_prop',
                     -propvalue=>'test_value2'
                    );

do_test $resp, $resp->is_success, 1,"proppatch set DAV:test_prop";

$resp = $resource->propfind(-depth=>0);

if ($resp->is_success) {
   do_test $resp, $resource->get_property('test_prop'),'test_value2',"propfind get_property DAV:test_prop";
} else {
   print "Couldn't perform propfind\n";
   ok 0;
}

# Test 3b
$resp = $resource->proppatch(-namespace=>'DAV',
                     -propname=>'test_prop',
                     -action=>'remove'
                    );

do_test $resp, $resp->is_success, 1,"proppatch remove DAV:test_prop";
$resp = $resource->propfind(-depth=>0);
if ($resp->is_success) {
   do_test $resp, $resource->get_property('test_prop'),'',"propfind get_property test_prop";
} else {
   print "Couldn't perform propfind\n";
   ok 0;
}

print $resource->as_string;
do_test $dav1, $dav1->unlock(),          1,"UNLOCK";

# Cleanup
$dav1->cwd("..");
do_test $dav1, $dav1->delete($newdir),      1,"DELETE $newdir";
