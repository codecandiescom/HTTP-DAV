#!/usr/local/bin/perl -w

BEGIN {
    print "1..1\n";

    # This will get called if there are any warnings thrown 
    # when compiling the use statements below.
    $SIG{__WARN__} = sub {
       print "not ok 1\n";
       exit;
    }
}

use strict; 
use HTTP::DAV;

print "ok 1\n";
