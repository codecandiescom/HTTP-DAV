#!/usr/local/bin/perl -w
use strict;
use HTTP::DAV;
use Test;
use Cwd;

# Tests basic copy and move functionality.

my $TESTS;
BEGIN {
    require "t/TestDetails.pm"; import TestDetails;
    $TESTS=20;
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
$url=~ s/\/$//g; # Remove trailing slash
my $cwd = getcwd(); # Remember where we started.

HTTP::DAV::DebugLevel(3);

######################################################################
# UTILITY FUNCTION: 
#    do_test <op_result>, <expected_result>, <message>
# IT was getting tedious doing the error handling so 
# I built this little routine, Makes the test cases easier to read.
sub do_test {
   my($dav,$result,$expected,$message,$resp) = @_;
   $expected = 1 if !defined $expected;
   my $ok;
   my $respobj ="";

   my $davmsg;
   if (ref($result) =~ /Response/ ) {
      $davmsg = $result->message . "\n" .
         "REQUEST>>".$result->request()->as_string() .
         "RESPONS>>".$result->as_string;
      $result=$result->is_success;
   } else {
      my $resp = $dav->get_last_response;
      $davmsg = $dav->message . "\n";# . join("\n",@{$resp->messages()});
   }

   if ($expected) {
      if ( $ok = ok($result,$expected) ) {
         print "$message succeeded\n";
      } else {
         print "$message failed: \"$davmsg\"";
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

=begin

COPY/MOVE - Test plan
-------------------------
We want to perform test functions against proppatch. 

Setup.
   OPEN
   MKCOL perldav_test
   MKCOL perldav_test/subdir
   CWD perldav_test

Test 1. 
   COPY perldav_test perldav_test_copy
   OPEN perldav_test_copy/subdir/

Test 2. 
   COPY perldav_test perldav_test_copy (no overwrite)

Test 3. 
   COPY perldav_test perldav_test_copy (with overwrite, depth 0)
   OPEN perldav_test_copy
   OPEN perldav_test_copy/subdir/ (should fail because no depth).

Cleanup
   DELETE perldav_test
   DELETE perldav_test_copy

=cut 

# Setup
# Make a directory with our process id after it 
# so that it is somewhat random
my $sourceuri = "perldav_test" .$$;
my $sourceurl = "$url/$sourceuri/";
my $targeturi = ${sourceuri} . "_copy";
my $targeturl = "$url/$targeturi/";
print "sourceuri: $sourceuri\n";
print "sourceurl: $sourceurl\n";
print "targeturi: $targeturi\n";
print "targeturl: $targeturl\n";

my $dav1 = HTTP::DAV->new();
$dav1->credentials( $user, $pass, $url );
do_test $dav1, $dav1->open ($url),    1,"OPEN $url";
do_test $dav1, $dav1->mkcol($sourceuri),    1,"MKCOL $sourceuri";
do_test $dav1, $dav1->mkcol("$sourceuri/subdir"), 1,"MKCOL $sourceuri/subdir";
do_test $dav1, $dav1->cwd  ($sourceuri),    1,"CWD $sourceuri";

print "COPY\n" . "----\n";

# Test 1 - COPY
my $resource1 = $dav1->get_workingresource();
my $resource2 = $dav1->new_resource( -uri => $targeturl );
my $resource3 = $dav1->new_resource( -uri =>"$targeturl/subdir" );

do_test $dav1, $resource1->copy( $resource2 ),1, 
        "COPY $sourceuri to $targeturi";
do_test $dav1, $dav1->open( "$targeturl/subdir" ),  1, "GET $targeturi/subdir";

# Test 2 - COPY (no overwrite)
do_test $dav1, $resource1->copy( -dest=>$resource2, -overwrite=>"F" ),0, 
        "COPY $sourceuri to $targeturi (no overwrite)";

# Test 3 - COPY (overwrite, no depth)
do_test $dav1, $dav1->lock( "$sourceurl",-timeout=>"10m" ), 1, "LOCK $sourceuri";
do_test $dav1, $dav1->lock( "$targeturl",-timeout=>"10m" ), 1, "LOCK $targeturi";
#$dav1->lock( -url=>"${targeturl}_1",-timeout=>"10m" );
#$dav1->lock( -url=>"${targeturl}_2",-timeout=>"10m" );

do_test $dav1, 
        $resource1->copy( -dest=>$resource2, -overwrite=>"T", -depth=>0 ),1, 
        "COPY $sourceuri to $targeturi (with overwrite, no depth";
do_test $dav1, $dav1->open( "$targeturl" ),         1, "GET $targeturi";
do_test $dav1, $dav1->open( "$targeturl/subdir" ),  0, "GET $targeturi/subdir";

sub getlocks {
   my $r = $dav1->get_workingresource;
   my $rl = $r->get_lockedresourcelist;
   print "rl=$rl\n";
   my $x = $rl->get_locktokens();
   foreach my $i ( $rl->get_resources() ) {
      my @locks = $i->get_locks();
      use Data::Dumper;
      print "All locks for " . $i->get_uri . ":\n";
      print Data::Dumper->Dump( [@locks] , [ '@locks' ] );
   }

#   use Data::Dumper;
#   print "All locks:\n";
#   print Data::Dumper->Dump( [$rl] , [ '$rl' ] );
}

# Re-setup
do_test $dav1, $dav1->open ( $url   ), 1,"RE-OPEN $url";
do_test $dav1, $dav1->mkcol("$targeturl/subdir"),   1,"MKCOL $targeturi/subdir";
my $resp;
#$resp = $resource1->propfind;
#print $resp->as_string, $resource1->as_string;
#$resp= $resource2->propfind;
#print $resp->as_string, $resource2->as_string;

do_test $dav1, $dav1->open( "$targeturl" ),         1, "GET $targeturi";
do_test $dav1, $dav1->open( "$sourceurl" ),  1, "GET $sourceuri/subdir";
&getlocks;
print "HERE!! " . $resource1->get_uri . "\n";
$resource1->delete;
$resource1->lock(-timeout=>"10m");
&getlocks;

print "MOVE\n" . "----\n";
# Test 4 - MOVE target(2) back to source(1)
do_test $dav1,
        $resource2->move( -dest=>$resource1 ),1, 
        "MOVE $targeturi to $sourceuri";
do_test $dav1, $dav1->open( "$targeturl" ),         0, "GET $targeturi";
do_test $dav1, $dav1->open( "$sourceurl" ),         1, "GET $sourceuri";


# This unlock should fail because MOVE eats source locks
do_test $dav1, $dav1->unlock( "$targeturl/" ),         0, "UNLOCK $targeturi";
# This should work because MOVE only eats source locks not dest locks
do_test $dav1, $dav1->unlock( "$sourceurl/" ),         1, "UNLOCK $sourceuri";

&getlocks;

# Cleanup
$dav1->cwd("..");
do_test $dav1, $dav1->delete("$sourceurl"),1,"DELETE $sourceurl";
do_test $dav1, $dav1->delete("$targeturl"),1,"DELETE $targeturl";

