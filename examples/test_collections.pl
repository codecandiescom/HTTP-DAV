#!/usr/local/bin/perl

use HTTP::DAV;

require "subs.pl";

$d = HTTP::DAV->new;
$d->credentials("pcollins","test123","http://localhost/");

$resource = $d->new_resource( -uri => "http://localhost/test/dir/newdir/" );

$response = $resource->mkcol();
&handler($response,$resource,"MKDIR",1);

$response = $resource->delete();
&handler($response,$resource,"DELETE",1);

$response = $resource->propfind();
&handler($response,$resource,"PROPFIND",1);
