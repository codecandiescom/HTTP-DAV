# $Id: TestDetails.pm.empty,v 1.1 2001/09/02 19:26:32 pcollins Exp $
package TestDetails;
use strict;
use vars qw($VERSION);

# This package is designed to simplify testing.
# It allows you to enter multiple URL's (and 
# credentials) for the different tests.

# You need to manually edit the %details hash below.

# A test script may tell us that it is about to do a propfind.
# It would do this by calling TestDetails::method('PROPFIND');
# Then when the test script calls TestDetails::url() you will 
# get the URL specificed in the PROPFIND hash below.
# But, if you haven't specified any details in the hash below 
# specific for PROPFIND it will use the DEFAULT entries instead.

$VERSION = sprintf("%d.%02d", q$Revision: 1.1 $ =~ /(\d+)\.(\d+)/);

# Configure these details:

my %details = (
   'DEFAULT' => {
      #'user' => 'myuser',
      #'pass' => 'mypass',
      #'url'=> 'http://host.org/dav_dir/',

      'url'  => '',
      'user' => '',
      'pass' => '',

      },

);

# End of configuration section
######################################################################

my $method = "";

sub user { 
   no warnings; 
   $details{$_[0]}{'user'} || 
   $details{$method}{'user'} || 
   $details{'DEFAULT'}{'user'} || 
   '' 
};
sub pass { 
   no warnings; 
   $details{$_[0]}{'pass'} || 
   $details{$method}{'pass'} || 
   $details{'DEFAULT'}{'pass'} ||
   '' 
};
sub url  { 
   no warnings; 
   $details{$_[0]}{'url'} || 
   $details{$method}{'url'} || 
   $details{'DEFAULT'}{'url'}  || 
   '' 
};

sub method { 
   my ($m) = @_;
   return $method unless defined $m;

   if (defined $details{$m} ) {
      $method = $m;
   } elsif ( defined $details{'DEFAULT'} ) {
#      use Carp qw(cluck);
#      cluck "No test details for $m Using defaults instead. Check t/TestDetails.pm\n";
   }
}

1;
