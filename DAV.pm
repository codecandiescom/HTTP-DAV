# $Id: DAV.pm,v 0.4 2000/04/25 14:22:38 pcollins Exp $
package HTTP::DAV;

use LWP;
use XML::DOM;
use Time::Local;
use HTTP::DAV::Lock;
use HTTP::DAV::ResourceList;
use HTTP::DAV::Resource;
use HTTP::DAV::Comms;

$VERSION = sprintf("%d.%02d", q$Revision: 0.4 $ =~ /(\d+)\.(\d+)/);

use strict;
use vars  qw($VERSION $DEBUG);

# Globals
$DEBUG=0;

sub new {
    my $class = shift;
    my $self = bless {}, ref($class) || $class;
    $self->_init(@_);
    return $self;
}

###########################################################################
sub clone
{
    my $self = @_;
    my $class = ref($self);
    my %clone = %{$self};
    bless { %clone }, $class;
}


###########################################################################
{
   sub _init
   {
       my($self,$uri,$headers) = @_;

       #$self->{_ua} = new LWP::UserAgent;
       #$self->set_uri($uri);
       #$self->set_headers($headers);
       #$self->set_user_agent( );
 
       #$self->{_LockPolicy}      = HTTP::DAV::LockPolicy->new();
       $self->{_LockedResourceList} = HTTP::DAV::ResourceList->new();
       $self->{_comms}           = HTTP::DAV::Comms->new();

       #use Data::Dumper; print Data::Dumper->Dump( [$comms] , [ '$comms' ] );

   
       return $self;
   }
}

sub new_resource {
   my ($self) = shift;
   return HTTP::DAV::Resource->new( 
      -Comms              => $self->{_comms},
      #-LockPolicy         => $self->{_LockPolicy},
      -LockedResourceList => $self->{_LockedResourceList},
      @_
   );
}

###########################################################################
# ACCESSOR METHODS
#$dav->authorization_basic($user,$pass);
#$dav->user_agent("my dav client");
sub credentials{ my $self=shift; $self->{_comms}->credentials(@_); }

# SET
sub set_uri           { $_[0]->{_uri}     = $_[1];                       }
sub set_headers       { $_[0]->{_headers} = $_[1] || new HTTP::Headers;  }
sub set_user_agent    { $_[0]->{_headers}->header( 'User-Agent', $_[1] ) }

#sub set_locking_policy{ $_[0]->{_LockPolicy}->set_locking_policy( $_[1] ); }
#sub get_locking_policy{ $_[0]->{_LockPolicy}->get_locking_policy();        }
#sub set_lock_rule    { $_[0]->{_LockPolicy}->set_$_[1]();                 }

# GET
sub get_uri        { return $_[0]->{_uri};        }
sub get_headers    { return $_[0]->{_headers};    }

sub as_string
{
    my $self = shift;
    my @result;
    #push(@result, "---- $self -----");
    my $req_line = $self->method || "[NO METHOD]";
    my $uri = $self->uri;
    $uri = (defined $uri) ? $uri->as_string : "[NO URI]";
    $req_line .= " $uri";
    my $proto = $self->protocol;
    $req_line .= " $proto" if $proto;

    push(@result, $req_line);
    push(@result, $self->headers_as_string);
    my $content = $self->content;
    if (defined $content) {
	push(@result, $content);
    }
    #push(@result, ("-" x 40));
    join("\n", @result, "");
}

1;

__END__








=head1 NAME

HTTP::DAV - A WebDAV client library for Perl5


=head1 SYNOPSIS

 use HTTP::DAV;

 $dav = HTTP::DAV->new;
 $dav->credentials( "pcollins", "mypass", "http://localhost/" );
 $resource = $dav->new_resource( -uri => "http://localhost/dav/myfile.txt" );

 $response = $resource->lock;
 $response = $resource->put("New file contents\n");
 print "BAD PUT\n" unless $response->is_success;
 $response = $resource->unlock;

 $resource->propfind;
 print "BAD PROPFIND\n" unless $response->is_success;
 $getlastmodified = $resource->get_property( "getlastmodified" );
 print "Last modified $getlastmodified\n";

 See HTTP::DAV::Resource for all of the operations allowed against a resource.

=head1 DESCRIPTION

This is DAV.pm (or HTTP::DAV), a Perl5 library for interacting and modifying content on webservers using the WebDAV protocol. Now you can LOCK, DELETE and PUT files and much more on a DAV-enabled webserver. Learn more about WebDAV at http://www.webdav.org/

=cut

=over 4

=item B<new>

Creates a new DAV client

 $dav = HTTP::DAV->new()

=item B<new_resource>

Creates a new resource object with which to play.

 $dav->new_resource( -uri => "http://..." );

=item B<as_string>

Method returning a textual representation of the request.
Mainly useful for debugging purposes. It takes no arguments.

 e.g.
 $dav->as_string()

=back

=head1 COPYRIGHT

Copyright 2000, Patrick Collins.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

1;
