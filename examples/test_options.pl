#!/usr/local/bin/perl

use HTTP::DAV::Resource;
use HTTP::DAV::Comms;

$comm = HTTP::DAV::Comms->new;
$comm->credentials("pcollins","test123","http://localhost");

$resource = HTTP::DAV::Resource->new(
    -uri => "http://www.webdav.org/perldav/test.txt",
    -comms => $comm,
    -lockedresourcelist => HTTP::DAV::ResourceList->new,
    );

foreach $i ( qw(PUT p P X DEL DELETE PROP propfind) ) {
   if ($resource->is_option($i)) {
      print "$i available\n";
   } else {
      print "$i NOT available\n";
   }
}
