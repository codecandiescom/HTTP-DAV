# $Id: Response.pm,v 0.4 2001/07/24 15:56:01 pcollins Exp $
package HTTP::DAV::Response;

$VERSION = sprintf("%d.%02d", q$Revision: 0.4 $ =~ /(\d+)\.(\d+)/);

use strict;
use vars qw(@ISA);
use vars qw($VERSION);

require HTTP::Response;
@ISA = qw( HTTP::Response );

my %dav_status_codes = (
   102 => "Processing. Server has accepted the request, but has not yet completed it",
   207 => "Multistatus",
   422 => "Unprocessable Entity. Bad client XML sent?",
   423 => "Locked. The source or destination resource is locked",
   424 => "Failed Dependency",
   507 => "Insufficient Storage. The server is unable to store the request",
);

sub clone_http_resp {
   my ($class,$http_resp) = @_;
   my %clone = %{$http_resp};
   my $self = \%clone;
   bless $self, (ref($class) || $class); 
}
# This routine resets the base
# message in the 
# object based on the 
# code and the status_codes above.
# set_message('207');
sub set_message {
   my ($self,$code) = @_;

   # Set the status code
   if ( defined $dav_status_codes{$code} ) {
      $self->message( $dav_status_codes{$code} );
   }
}

sub set_responsedescription {
   $_[0]->{'_dav_responsedescription'} = $_[1] if $_[1];
}
sub get_responsedescription { $_[0]->{'_dav_responsedescription'}; }

sub add_status_line {
   my($self,$message,$responsedescription,$handle) = @_;
   
   # Parse "status-line". See section 6.1 of RFC 2068
   # Status-Line= HTTP-Version SP Status-Code SP Reason-Phrase CRLF
   if ( $message =~ /^(.*?)\s(.*?)\s(.*?)$/ ) {
      my ($http_version,$status_code,$reason_phrase) = ($1,$2,$3);
      my $http_status = HTTP::Status::status_message($status_code);
      my $dav_status = $dav_status_codes{$status_code};
      $self->{_dav_multistatus}{$handle} = {
         'code' => $status_code,
         'message' => $reason_phrase,
         'description' => $responsedescription,
      };
      #print "$handle: " . $self->{'_dav_multistatus'}{$handle}{'code'} . "\n";

      return 1;
   } else {
      return 0;
   }
}

sub is_success {
   my ($self) = @_;

   if ($self->code eq "207" ) {
      foreach my $handle ( keys %{$self->{_dav_multistatus}} ) {
         my $code = $self->{_dav_multistatus}{$handle}{'code'};
         return 0 if ( HTTP::Status::is_error($code) );
      }
   } else {
      return $self->SUPER::is_success();
   }

   return 1;
}

sub get_bad_statuslines {
}

sub as_string {
   my ($self) = @_;
   my ($ms, $returnstr) = "";
   foreach my $handle ( sort keys %{$self->{_dav_multistatus}} ) {
      my %h = %{$self->{_dav_multistatus}{$handle}};
      $ms .= "     $h{code} "   if $h{code};
      $ms .= "$h{message} "     if $h{message}; 
      $ms .= "$h{description} " if $h{description};
      $ms .= " " . $handle;
      $ms .= "\n";
   }

   my $rd = $self->get_responsedescription();

   $returnstr .= "Multistatus lines:\n$ms\n" if $ms;
   $returnstr .= "Overall responsedescription:\n$rd\n" if $rd;
   $returnstr .= $self->SUPER::as_string;
   $returnstr;
}
