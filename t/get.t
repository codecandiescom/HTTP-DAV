#!/usr/local/bin/perl -w

BEGIN {
    $!=1;
    print "1..3\n";
}

use strict;
use HTTP::DAV;

my $dav = HTTP::DAV->new;
$dav->credentials("pcollins","test123","http://localhost/test/");
$dav->credentials("pcollins","cppdc","http://webfolders.mydocsonline.com/");

#my $resource = $dav->new_resource( -uri => "http://webdav.zope.org:2518/users/public/" );
my $resource = $dav->new_resource( -uri => "http://localhost/test/" );
#my $resource = $dav->new_resource( -uri => "http://webfolders.mydocsonline.com/" );

my $response;

$response = $resource->options();
&handleResponse($response,1);
print $resource->get_options . "\n";

$response = $resource->get();
&handleResponse($response,2);

$response = $resource->propfind();
&handleResponse($response,3);
print $resource->as_string;


###
sub handleResponse {
   my ($response, $testnumber) = @_;

   if ( $response->is_success) {
      print "ok $testnumber\n";
   } else {
      print "not ok $testnumber\n";
   }
}


