# $Id: Comms.pm,v 0.16 2001/09/02 08:46:36 pcollins Exp $
package HTTP::DAV::Comms;

use HTTP::DAV::Utils;
use HTTP::DAV::Response;
use LWP;
use URI;

$VERSION = sprintf("%d.%02d", q$Revision: 0.16 $ =~ /(\d+)\.(\d+)/);

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
   my ($headers,$useragent) = HTTP::DAV::Utils::rearrange( ['HEADERS','USERAGENT'], @p);

   # This is cached in this object here so that each http request 
   # doesn't have to invoke a new useragent.
   $self->init_user_agent($useragent);

   $self->set_headers($headers);
}

sub init_user_agent {
    my($self,$useragent) = @_;
    if ( defined $useragent ) {
       $self->{_user_agent} = $useragent;
    } else {
       $self->{_user_agent} = HTTP::DAV::UserAgent->new;
       $self->set_agent("DAV.pm/v$HTTP::DAV::VERSION");
    }
}

####
# GET/SET

# Sets a User-Agent as specified by user or as the default
sub set_agent { 
   my ($self, $agent) = @_;
   $self->{_user_agent}->agent($agent);
}

sub set_header {
   my ($self,$var,$val) = @_;
   $self->set_headers() unless defined $self->{_headers};
   $self->{_headers}->header($var,$val);
}


sub get_user_agent { $_[0]->{_user_agent}; }
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

sub _set_last_request  { $_[0]->{_last_request}  = $_[1]; }
sub _set_last_response { $_[0]->{_last_response} = $_[1]; }

# Returns an HTTP::Request object
sub get_last_request  { $_[0]->{_last_request};  }

# Returns an HTTP::DAV::Response object
sub get_last_response { $_[0]->{_last_response}; }

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
      $self->{_user_agent}->credentials($url,undef, split(':',$url_obj->userinfo) );
   }

   # Header management
   if ( $newheaders && ref($newheaders) !~ /Headers/ ){
      die "Bad headers object: " .
         Data::Dumper->Dump( [$newheaders] , [ '$newheaders' ] );    
   }

   my $headers = HTTP::DAV::Headers->new();
   $headers->add_headers( $self->{_headers} );
   $headers->add_headers( $newheaders );

   $headers->header("Host", $url_obj->host_port);
   #$headers->header("Authorization", "Basic cGNvbGxpbnM6dGVzdDEyMw==");
   #$headers->header("Connection", "TE");
   #$headers->header("TE", "trailers");

   my $length = ($content) ? length($content) : 0;
   $headers->header("Content-Length", $length);
   #print "HTTP HEADERS\n" . $self->get_headers->as_string . "\n\n";


   # It would be good if, at this stage, we could prefill the 
   # username and password values to prevent the client having 
   # to submit 2 requests, submit->401, submit->200
   # This is the same kind of username, password remembering 
   # functionality that a browser performs.
   #@userpass = $self->{_user_agent}->get_basic_credentials(undef, $url);

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
   my $resp = $self->{_user_agent}->request($req);

   if ( $HTTP::DAV::DEBUG > 1 ) {
      no warnings;
      #open(DEBUG, ">&STDOUT") || die ("Can't open STDERR");;
      open(DEBUG, ">>/tmp/perldav_debug.txt");
      print DEBUG "\n" . "-"x70 . "\n";
      print DEBUG localtime() . "\n";
      print DEBUG "$method REQUEST>>\n" . $req->as_string();

      if ( $resp->headers->header('Content-Type') =~ /xml/ ) {
         my $body = $resp->as_string();
         #$body =~ s/>\n*/>\n/g;
         print DEBUG "$method XML RESPONSE>>$body\n";
      #} elsif ( $resp->headers->header('Content-Type') =~ /text.html/ ) {
         #require HTML::TreeBuilder;
         #require HTML::FormatText;
         #my $tree = HTML::TreeBuilder->new->parse($resp->content());
         #my $formatter = HTML::FormatText->new(leftmargin => 0);
         #print DEBUG "$method RESPONSE (HTML)>>\n" . $resp->headers->as_string();
         #print DEBUG $formatter->format($tree);
      } else {

         print DEBUG "$method RESPONSE>>\n" . $resp->as_string();
      }
      close DEBUG;
   }

   ####
   # Copy the HTTP:Response into a HTTP::DAV::Response. It specifically 
   # knows details about DAV Status Codes and their associated 
   # messages.
   my $dav_resp = HTTP::DAV::Response->clone_http_resp($resp);
   $dav_resp->set_message( $resp->code );

   #### 
   # Save the req and resp objects as the "last used"
   $self->_set_last_request ($req);
   $self->_set_last_response($dav_resp);

   return $dav_resp;
}

sub credentials {
   my($self, @p) = @_;
   my ($user,$pass,$url,$realm) = HTTP::DAV::Utils::rearrange( ['USER', 'PASS','URL','REALM'], @p);
   $self->{_user_agent}->credentials($url,$realm,$user,$pass);
}

###########################################################################
# We make our own specialization of LWP::UserAgent 
# called HTTP::DAV::UserAgent.
# The variations allow us to have various levels of protection.
# Where the user hasn't specified what Realm to use we pass the 
# userpass combo to all realms of that host
# Also this UserAgent remembers a user on the next request.
# The standard UserAgent doesn't. 
{
    package HTTP::DAV::UserAgent;

    use strict;
    use vars qw(@ISA);

    @ISA = qw(LWP::UserAgent);
    #require LWP::UserAgent;

    sub new
    {
        my $self = LWP::UserAgent::new(@_);
        $self->agent("lwp-request/$HTTP::DAV::VERSION");
        $self;
    }

    sub credentials {
       my($self, $netloc, $realm,$user,$pass) = @_;
       $realm = "default" unless $realm;
       if ($netloc) {
          $netloc = "http://$netloc" unless $netloc=~/^http/;
          my $uri = URI->new($netloc);
          $netloc = $uri->host_port;
       } else {
          $netloc = "default";
       }
       { no warnings; 
       print "Setting auth details for $netloc, $realm to $user,$pass\n" if $HTTP::DAV::DEBUG > 2;
       }
       @{ $self->{'basic_authentication'}{$netloc}{$realm}}= ($user, $pass);
    }

    sub get_basic_credentials
    {
        my($self, $realm, $uri) = @_;

        $uri = HTTP::DAV::Utils::make_uri($uri);
        my $netloc = $uri->host_port;

        my $userpass;
        {
        no warnings; # SHUTUP with your silly warnings.
        $userpass=
           $self->{'basic_authentication'}{$netloc}{$realm}  ||
           $self->{'basic_authentication'}{$netloc}{default} ||
           [];

        print "Using user/pass combo: @$userpass. For $realm, $uri\n" if $HTTP::DAV::DEBUG > 2;

        }
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
      }
   }
}

1;
