# $Id: Comms.pm,v 0.5 2001/07/24 15:56:00 pcollins Exp $
package HTTP::DAV::Comms;

use HTTP::DAV::Utils;
use HTTP::DAV::Response;
use LWP;
use URI;

$VERSION = sprintf("%d.%02d", q$Revision: 0.5 $ =~ /(\d+)\.(\d+)/);

use strict;
use vars  qw($VERSION $DEBUG);

####
# Construct a new object and initialize it
sub new {
   my $class = shift;
   my $self = bless {}, ref($class) || $class;
   #print Data::Dumper->Dump( [$self] , [ '$self' ] );
   $self->_init(@_);
   return $self;
}

# Requires a reusable HTTP Agent.
# and some default headers, like, the user agent
sub _init {
   my ($self,@p) = @_;

   my ($headers,$agent) = HTTP::DAV::Utils::rearrange( ['HEADERS', 'AGENT'], @p);

   # This is cached in this object here so that each http request 
   # doesn't have to invoke a new useragent.
   $self->init_ua();

   $self->set_headers($headers);
   $self->set_agent($agent);
}

sub init_ua {
   $_[0]->{_ua} = HTTP::DAV::RequestAgent->new;
}

####
# GET/SET

# Sets a User-Agent as specified by user or as the default
sub set_agent { 
   my ($self, $agent) = @_;
   $self->init_ua() unless defined $self->{_ua};

   $agent = "DAV.pm/$HTTP::DAV::VERSION" unless $agent;

   $self->{_ua}->agent($agent);
}

sub set_header {
   my ($self,$var,$val) = @_;
   $self->set_headers() unless defined $self->{_headers};
   $self->{_headers}->header($var,$val);
}


sub get_headers { $_[0]->{_headers}; }
sub set_headers {
   my ($self,$headers) = @_;

   if ( defined $headers && ref($headers) eq "HTTP::Headers" ) {
      $headers = HTTP::DAV::Headers->clone( $headers );
   } else {
      $headers = HTTP::DAV::Headers->new;
   }

   $self->{_headers} = $headers;
}

####
# Ensure there is a Host: header based on the URL
#
sub do_http_request {
   my ($self, @p ) = @_;

   my ($method,$url,$newheaders,$content) = 
      HTTP::DAV::Utils::rearrange( ['METHOD', ['URL','URI'], 'HEADERS', 'CONTENT'],@p );

   # Method management
   if (! defined $method || $method eq "" || $method !~ /^\w+$/ ) {
      die "Incorrect HTTP Method specified in do_http_request: \"$method\"";
   }
   $method = uc($method);

   # URL management
   my $url_obj;
   $url_obj = (ref($url) =~ /URI/)? $url : URI->new($url);

   die "Comms: Bad HTTP Url: \"$url_obj\"\n" if ($url_obj->scheme ne "http" );

   # If you see user:pass detail embedded in the URL. Then get it out.
   if ( $url_obj->userinfo ) {
      $self->{_ua}->credentials($url,undef, split(':',$url_obj->userinfo) );
   }

   # Header management
   if ( $newheaders && ref($newheaders) !~ /Headers/ ){
      die "Bad headers object: " .
         Data::Dumper->Dump( [$newheaders] , [ '$newheaders' ] );    
   }

   my $headers = HTTP::DAV::Headers->new();
   $headers->add_headers( $self->{_headers} );
   $headers->add_headers( $newheaders );

   $headers->header("Host", $url_obj->host);

   #print "HTTP HEADERS\n" . $self->get_headers->as_string . "\n\n";

   # It would be good if, at this stage, we could prefill the 
   # username and password values to prevent the client having 
   # to submit 2 requests, submit->401, submit->200
   # This is the same kind of username, password remembering 
   # functionality that a browser performs.
   #@userpass = $self->{_ua}->get_basic_credentials(undef, $url);
   #print "HEY THERE!! @userpass\n";

   # Add a Content-type of text/xml if the body has <?xml in it
   if ( $content && $content =~ /<\?xml/i ) {
      $headers->header("Content-Type", "text/xml");
   }

   ####
   # Do the HTTP call
   my $req = HTTP::Request->new( 
         $method, 
         $url_obj, 
         $headers->to_http_headers, 
         $content 
      );
   # It really bugs me, but libwww-perl doesn't honour this call.
   # I'll leave it here anyway for future compatibility.
   $req->protocol("HTTP/1.1");

   print "$method REQUEST>>\n" . $req->as_string() if $HTTP::DAV::DEBUG > 1;
   my $resp = $self->{_ua}->request($req);
   print "$method RESPONSE>>\n" . $resp->as_string() if $HTTP::DAV::DEBUG > 1;     

   ####
   # Copy the HTTP:Response into a HTTP::DAV::Response. It specifically 
   # knows details about DAV Status Codes and their associated 
   # messages.
   my $dav_resp = HTTP::DAV::Response->clone_http_resp($resp);
   $dav_resp->set_message( $resp->code );

   return $dav_resp;
}

sub credentials {
   my($self, $user, $pass, $netloc, $realm) = @_;
   $self->{_ua}->credentials($netloc,$realm,$user,$pass);
}

###########################################################################
# We make our own specialization of LWP::UserAgent 
# called HTTP::DAV::RequestAgent.
# The variations allow us to have various levels of protection.
# Where the user hasn't specified what Realm to use we pass the 
# userpass combo to all realms of that host
{
    package HTTP::DAV::RequestAgent;

    use strict;
    use vars qw(@ISA);

    @ISA = qw(LWP::UserAgent);
    require LWP::UserAgent;

    sub new
    {
        my $self = LWP::UserAgent::new(@_);
        $self->agent("lwp-request/$HTTP::DAV::VERSION");
        $self;
    }

    sub credentials {
       my($self, $netloc, $realm,$user,$pass) = @_;
       $realm = "default" unless $realm;
       my ($uri, $host_port) = "";
       if ($netloc){
          $uri = URI->new($netloc);
          $host_port = $uri->host_port;
       } else {
          $host_port = "default";
       }
       #print "Setting auth details for $host_port, $realm to $user,$pass\n" if $HTTP::DAV::DEBUG > 1;
       @{ $self->{'basic_authentication'}{$host_port}{$realm}}= ($user, $pass);
    }

    sub get_basic_credentials
    {
        my($self, $realm, $uri) = @_;
        my $netloc;
        if ( ref($uri) =~ /URI/ ) {
           $netloc = $uri->host_port;
        } elsif ( $uri=~ /^http/ ) { 
           $uri = URI->new($uri);
           $netloc = $uri->host_port;
        }

        #print "Looking for user details at $netloc, realm $realm\n";
        #print Data::Dumper->Dump( [$self] , [ '$self' ] );    
        my $userpass= 
           $self->{'basic_authentication'}{$netloc}{$realm} ||
           $self->{'basic_authentication'}{$netloc}{default} ||
           #$self->{'basic_authentication'}{default}{default} ||
           [];

        print "Userpass: @$userpass\n" if $HTTP::DAV::DEBUG > 1;
        return @$userpass;
    }
}

###########################################################################
# We make our own special version of HTTP::Headers 
# called HTTP::DAV::Headers. This is because we want to add
# a new method called add_headers
{
   package HTTP::DAV::Headers; 

   use strict;
   use vars qw(@ISA);

   @ISA = qw( HTTP::Headers );
   require HTTP::Headers;
   
   # $dav_headers = HTTP::DAV::Headers->clone( $http_headers );
   
   sub to_http_headers {
      my ($self) = @_;
      my %clone = %{$self};
      bless { %clone }, "HTTP::Headers";
   }
   
   sub clone
   {
       my ($class,$headers) = @_;
       my %clone = %{$headers};
       bless { %clone }, ref($class) || $class;
   }
   
   sub add_headers {
      my ($self,$headers) = @_;
      return unless (defined $headers && ref($headers) =~ /Headers/ );
   
      #print "About to add headers!!\n";
      #print Data::Dumper->Dump( [$headers] , [ '$headers' ] );    
      foreach my $key ( sort keys %$headers ) {
         $self->header( $key, $headers->{$key} );
         #print "HEADER: $key, $headers->{$key}\n";
         #return 0 unless $key;
         #delete $self->{$key};
         #return [ $key, $val ];
      }
   }
}

1;
