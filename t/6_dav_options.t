#!/usr/local/bin/perl -w
use strict;
use HTTP::DAV;
use Test;

# Tests dav options functionality.

my $TESTS;
BEGIN {
    require "t/TestDetails.pm"; import TestDetails;
    $TESTS=6;
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

DAV.pm::options() - Test plan
-------------------------
We want to perform test functions against proppatch. 
   OPEN
   MKCOL perldav
   OPTIONS
   OPTIONS perldav
   OPTIONS http://...perldav

=cut 

# Setup
# Make a directory with our process id after it 
# so that it is somewhat random
my $perldav_test_uri = "perldav_test" .$$;
my $perldav_test_url = "$url/$perldav_test_uri/";

my $dav = HTTP::DAV->new();
$dav->credentials( $user, $pass, $url );
do_test $dav, $dav->open ($url),          1,"OPEN $url";
do_test $dav, $dav->mkcol($perldav_test_uri),    1,"MKCOL $perldav_test_uri";

print "OPTIONS\n" . "----\n";
do_test $dav, $dav->options( "$url" ),              '/MKCOL/', "OPTIONS $url (looking for MKCOL)";
do_test $dav, $dav->options( "$perldav_test_uri" ), '/MKCOL/', "OPTIONS $perldav_test_uri (looking for MKCOL)";
do_test $dav, $dav->options( "$perldav_test_url" ), '/MKCOL/', "OPTIONS $perldav_test_url (looking for MKCOL)";

# Cleanup
do_test $dav, $dav->delete("$perldav_test_url"),1,"DELETE $perldav_test_url";
