#!/usr/local/bin/perl
use HTTP::DAV;
use HTTP::DAV::Lock;

require "subs.pl";

my $d = HTTP::DAV->new;
$d->credentials("pcollins","test123", "http://localhost/");

$verbose = 0;
foreach $uri ( qw(  
   http://localhost/test/dir/myfile.txt 
   ) ) {

   $resource = $d->new_resource( -uri => $uri );
   print "NEW RESOURCE $uri\n";

   # FORCEFUL UNLOCK
   $resp = $resource->lockdiscovery;
   $resp = $resource->forcefully_unlock_all;
   handler($resp,$resource,"FORCEFUL UNLOCK",$verbose1);

   # LOCK
   $resp = $resource->lock();
   handler($resp,$resource,"LOCK",$verbose1);
   next unless $resp->is_success;

   print "LOCKED by me\n" if $resource->is_locked( -owned => 1 );
   print "LOCKED not by me\n" if $resource->is_locked( -owned => 0 );

   # PUT
   $resp = $resource->put("NEW FILE!!\nXX\n");
   handler($resp,$resource,"PUT",$verbose1);

   # UNLOCK
   $resp = $resource->unlock();
   handler($resp,$resource,"UNLOCK",$verbose);



   # SHARED LOCKS
   $resp = $resource->lock( -scope => "shared" );
   handler($resp,$resource,"SHARED LOCK 1",$verbose);

   $resp = $resource->lock( -scope => "shared" );
   handler($resp,$resource,"SHARED LOCK 2",$verbose1);

   $resp = $resource->unlock;
   handler($resp,$resource,"UNLOCK BOTH SHARED LOCKS",$verbose);

   $resp = $resource->propfind;
   #$resp = $resource->lockdiscovery;
   handler($resp,$resource,"PROPFIND",1);

   $resource->lock(-scope=>"shared");
   print "\n";
}
