# $Id: ResourceList.pm,v 0.3 2000/04/25 14:20:15 pcollins Exp $
package HTTP::DAV::ResourceList;

$VERSION = sprintf("%d.%02d", q$Revision: 0.3 $ =~ /(\d+)\.(\d+)/);

use strict;
use vars  qw($VERSION);

####
# Construct a new object and initialize it
sub new {
   my $class = shift;
   my $self = bless {}, ref($class) || $class;
   $self->_init(@_);
   return $self;
}

sub _init {
   my ($self,@p) = @_;

   ####
   # This is the order of the arguments unless used as 
   # named parameters
   my @arg_names = qw (
      RESOURCE_TYPE
   );

   my @pa = HTTP::DAV::Utils::rearrange( \@arg_names, @p);

   $self->{_resources} = ();

}

####
# List Operators

sub count_resources {
   return $#{$_[0]->{_resources}}+1;
}

sub add_resource {
   my ($self,$resource) = @_;
   $resource->set_parent_resourcelist($self);
   push (@{$self->{_resources}}, $resource);
}


# Synopsis: $list->remove_resource( uri : String or URI);
#        or $list->remove_resource( resource_obj : HTTP::DAV::Resource );
sub remove_resource {
   my ($self,$resource ) = @_;
   my $uri;

   if ( ref($resource) !~ /HTTP::DAV::Resource/ ) {
      $uri = HTTP::DAV::Utils::make_uri($resource);
      return 0 if (! $uri->scheme );
   }
   my $found_index = -1;
   foreach my $i ( 0 .. $#{$self->{_resources}} ) {
      my $this_resource = $self->{_resources}[$i];
      if ( ( $uri && $uri->eq($this_resource->get_uri) )
           || $resource eq $this_resource ) {
         $found_index = $i;
         last;
      }
   }

   if ( $found_index != -1 ) {
      $resource = splice(@{$self->{_resources}},$found_index,1);
      $resource->set_parent_resourcelist();
      return $resource;
   } else {
      return 0;
   }
}

###########################################################################
# %tokens = get_locktokens( "http://localhost/test/dir" )
# Look for all of the lock tokens given a URI:
# Returns:
# %$tokens = (
#    'http://1' => ( token1, token2, token3 ),
#    'http://2' => ( token4, token5, token6 ),
# );
#
sub get_locktokens {
   my ($self,$uri) = @_;
   my %tokens;
  
   my @uris;
   if (ref($uri) =~ /ARRAY/ ) {
      @uris = map { HTTP::DAV::Utils::make_uri($_) } @{$uri};
   } else {
      push( @uris, HTTP::DAV::Utils::make_uri($uri) );
   }


   # OK, let's say we hold three locks on 3 resources:
   #    1./a/b/c/ 2./a/b/d/ and 3./f/g
   # If you ask me for /a/b you'll get the locktokens on 1 and 2.
   # If you ask me for /a and /f you'll get 1,2 and 3.
   # If you ask me for /a/b/c/x.txt you'll get 1
   # If you ask me for /a/b/e you'll get nothing
   # So, for each locked resource, if it is a member
   #    of the uri you specify, I'll tell you what the 
   #    locked resource tokens were

   foreach my $resource ( @{$self->{_resources}} ) {

      my $resource_uri = $resource->get_uri;
      foreach my $uri ( @uris ) {

         # if $resource_uri is in $uri
         # e.g. u=/a  r=/a/b/e
         # e.g. u=/a  r=/a/b/c.txt
         my $r = $resource_uri->canonical();
         my $u = $uri->canonical();
         if ($u =~ /\Q$r/ ) {

            my @locks = $resource->get_locks();
            foreach my $lock (@locks) {
               my @lock_tokens = @{$lock->get_locktokens()};
               push(@{$tokens{$resource_uri}}, @lock_tokens);
            }

         }

      } # foreach uri
   } # foreach resource

   return \%tokens;
}

# Utility to convert lock tokens to an if header
# %$tokens = (
#    'http://1' => ( token1, token2, token3 ),
#    'http://2' => ( token4, token5, token6 ),
# )
#   to
# if tagged:
#    <http://1> (<opaquelocktoken:1234>)
# or if not tagged:
#    (<opaquelocktoken:1234>)
#
sub tokens_to_if_header {
   my ($self, $tokens, $tagged) = @_;
   my $if_header;
   foreach my $uri (keys %$tokens ) {
      $if_header .= "<$uri>" if $tagged;
      foreach my $token (@{$$tokens{$uri}}) {
         $if_header .= "(<$token>)";
      }
      #$if_header .= "\n";     
   }
   return $if_header;
}

###########################################################################
# Dump the objects contents as a string
sub as_string {
   my ($self,$space,$depth) = @_;
   my ($return) = "";
   $return .= "${space}ResourceList Object ($self)\n";
   $space  .= "   ";
   foreach my $resource ( @{$self->{_resources}} ) {
      $return .= $resource->as_string($space,$depth);
   }

   $return;
}

1;
