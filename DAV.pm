# $Id: DAV.pm,v 0.22 2001/09/03 19:39:28 pcollins Exp $
package HTTP::DAV;

use LWP;
use XML::DOM;
use Time::Local;
use HTTP::DAV::Lock;
use HTTP::DAV::ResourceList;
use HTTP::DAV::Resource;
use HTTP::DAV::Comms;
use URI::file;
use Cwd qw(getcwd); # Can't import all of it, cwd clashes with our namespace.

# Globals
$VERSION     = sprintf("%d.%02d", q$Revision: 0.22 $ =~ /(\d+)\.(\d+)/);
$VERSION_DATE= sprintf("%s", q$Date: 2001/09/03 19:39:28 $ =~ m# (.*) $# );

$DEBUG=0;

use strict;
use vars  qw($VERSION $VERSION_DATE $DEBUG);

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
       my($self,@p) = @_;
       my ($uri,$headers,$useragent) = 
          HTTP::DAV::Utils::rearrange(['URI','HEADERS','USERAGENT'], @p);

       $self->{_lockedresourcelist} = HTTP::DAV::ResourceList->new();
       $self->{_comms} = HTTP::DAV::Comms->new(-useragent=>$useragent);
       if ( $uri ) {
          $self->set_workingresource($self->new_resource( -uri => $uri)); 
       }

       return $self;
   }
}

sub DebugLevel {
   shift if ref($_[0]) =~ /HTTP/;
   my $level = shift;
   $level =256 if !defined $level || $level eq "";

   $DEBUG=$level;
}

######################################################################
# new_resource acts as a resource factory.
# It will create a new one for you each time you ask.
# Sometimes, if it holds state information about this 
# URL, it may return an old populated object.
sub new_resource {
   my ($self) = shift;

   ####
   # This is the order of the arguments unless used as
   # named parameters
   my ($uri) = HTTP::DAV::Utils::rearrange(['URI'], @_);
   #print "new_resource: was $uri\n";
   $uri = HTTP::DAV::Utils::make_uri($uri);
   #print "new_resource: now $uri\n";

   my $resource = $self->{_lockedresourcelist}->get_member($uri);
   if ($resource) {
      print "new_resource: For $uri, returning existing resource $resource\n" if $HTTP::DAV::DEBUG>2;
      return $resource;
   } else {
      print "new_resource: For $uri, creating new resource\n" if $HTTP::DAV::DEBUG>2;
      return HTTP::DAV::Resource->new ( 
           -Comms              => $self->{_comms},
           -LockedResourceList => $self->{_lockedresourcelist},
           -uri => $uri,
           -Client => $self
           );
   }
}

###########################################################################
# ACCESSOR METHODS

# GET
sub get_user_agent  { $_[0]->{_comms}->get_user_agent(); }
sub get_last_request   { $_[0]->{_comms}->get_last_request(); }
sub get_last_response  { $_[0]->{_comms}->get_last_response(); }
sub get_workingresource{ $_[0]->{_workingresource} }
sub get_workingurl     { $_[0]->{_workingresource}->get_uri() if defined $_[0]->{_workingresource}; }
sub get_lockedresourcelist { $_[0]->{_lockedresourcelist} }

# SET
sub set_workingresource{ $_[0]->{_workingresource} = $_[1]; }
sub credentials{ shift->{_comms}->credentials(@_); }

######################################################################
# Error handling


## Error conditions
my %err = (
   'ERR_WRONG_ARGS'    => 'Wrong number of arguments supplied.',
   'ERR_UNAUTHORIZED'  => 'Unauthorized. ',
   'ERR_NULL_RESOURCE' => 'Not connected. Do an open first. ',
   'ERR_RESP_FAIL'     => 'Server response: ',
   'ERR_GENERIC'       => '',
);

sub err {
   my ($self,$error,$mesg) = @_;

   my $err_msg;
   $err_msg = "";
   $err_msg .= $err{$error} if defined $err{$error};
   $err_msg .= $mesg if defined $mesg;
   $err_msg .= "ERROR" unless defined $err_msg;

   $self->{_message} = $err_msg;
   my $callback=$self->{_callback};
   &$callback(0,$err_msg) if $callback;

   if ($self->{_multi_op}) {
      push(@{$self->{_errors}},$err_msg);
   }
   $self->{_status} = 0;

   return 0;
}

sub ok {
   my ($self,$mesg) = @_;

   $self->{_message} = $mesg;
   my $callback=$self->{_callback};
   &$callback(1,$mesg) if $callback;

   if ( $self->{_multi_op} ) {
      $self->{_status} = 1 unless $self->{_status} == 0;
   } else {
      $self->{_status} = 1;
   }
   return 1;
}

sub _start_multi_op {
   my ($self,$mesg,$callback) = @_;
   $_[0]->{_multi_mesg} = $mesg || "";
   $_[0]->{_status} = 1;
   $_[0]->{_errors} = ();
   $_[0]->{_multi_op} = 1;
   $_[0]->{_callback} = $callback if defined $callback;
}

sub _end_multi_op { 
   my ($self) = @_;
   $self->{_multi_op} = 0; 
   $self->{_callback} = undef; 
   my $message = $self->{_multi_mesg} . " ";
   $message .= ($self->{_status}) ? "succeeded" : "failed";
   $self->{_message} = $message;
   $self->{_multi_mesg} = undef;
}

sub message   {  $_[0]->{_message}||"" };
sub errors    {@{$_[0]->{_errors}}||() };
sub is_success{  $_[0]->{_status}      };

######################################################################
# Operations

# CWD
sub cwd {
   my($self,@p) = @_;
   my ($url) = HTTP::DAV::Utils::rearrange(['URL'], @p);

   return $self->err('ERR_WRONG_ARGS') if (!defined $url || $url eq "");
   return $self->err('ERR_NULL_RESOURCE') unless $self->get_workingresource();

   $url = HTTP::DAV::Utils::make_trail_slash($url);
   my $new_uri = $self->get_absolute_uri($url);
   print "Changing to $new_uri\n" if $DEBUG>2;
   return $self->open( $new_uri );
}

# DELETE
sub delete {
   my($self,@p) = @_;
   my ($url) = HTTP::DAV::Utils::rearrange(['URL'], @p);

   return $self->err('ERR_WRONG_ARGS') if (!defined $url || $url eq "");
   return $self->err('ERR_NULL_RESOURCE') unless $self->get_workingresource();

   my $new_url = $self->get_absolute_uri($url);
   my $resource = $self->new_resource( -uri => $new_url);

   my $resp = $resource->propfind(-depth=>0);
   if ($resp->is_success) {

      $resp = $resource->delete();
      if ($resp->is_success) {
         return $self->ok( "deleted $new_url successfully" );
      } else {
         return $self->err( 'ERR_RESP_FAIL',$resp->message() );
      }
   }

   # Document to delete doesn't exist.
   else {
      return $self->err('ERR_RESP_FAIL',$resp->message() );
   }
}

# GET
sub get {
   my($self,@p) = @_;
   my ($uri,$to,$callback) = 
      HTTP::DAV::Utils::rearrange(['URL','TO','CALLBACK'], @p);
   $self->_start_multi_op("get $uri",$callback);
   my $ret = $self->_get(@p);
   $self->_end_multi_op();
   return $ret || $self->is_success;
}

sub _get {
   my($self,@p) = @_;
   my ($uri,$to) = 
      HTTP::DAV::Utils::rearrange(['URL','TO'], @p);
   $to ||= "";

   return $self->err('ERR_WRONG_ARGS') if (!defined $uri || $uri eq "");
   return $self->err('ERR_NULL_RESOURCE') unless $self->get_workingresource();

   # Setup the resource based on the passed url and do a propfind.
   my $url =  $self->get_absolute_uri($uri);
   my $resource = $self->new_resource( -uri => $url);
   my $resp = $resource->propfind(-depth=>1);

   if ($resp->is_error) {
      return $self->err( 'ERR_RESP_FAIL',$resp->message() );
   } 

   # Set the working directory
   my $passed_to = $to || "";
   my $leafname = &_get_leafname($url);
   my $local_pwd;
   if (-d $to) {
      if (!$to || $to eq ".") {
         $to = getcwd();
      }

      $local_pwd = "$to/$leafname";
   } else {
      $local_pwd = "$to";
   }
   $local_pwd =~ s#//#/#g; # Fold double //'s to /'s.

   print "Am going to try and get $url to $local_pwd\n" if $DEBUG>2;

   # GET A DIRECTORY
   if ( $resource->is_collection() ) {
      if ($passed_to eq "" ) {
         return $self->err('ERR_GENERIC',
           "Won't get a collection unless you tell me where to put it.") 
      } 

      # Try and make the directory locally
      if (! mkdir $local_pwd ) {
         return $self->err('ERR_GENERIC',
           "mkdir local:$local_pwd failed: $!") 
      }

      $self->ok("mkdir $local_pwd");
   
      # This is the degenerate case for an empty dir.
      print "Made directory $local_pwd\n" if $DEBUG>2;

      my $resource_list = $resource->get_resourcelist();
      if ($resource_list) {
         # FOREACH FILE IN COLLECTION, GET IT.
         foreach my $progeny_r ( $resource_list->get_resources() ) {
   
            my $progeny_url = $progeny_r->get_uri();
            print "Found progeny:$progeny_url\n" if $DEBUG>2;
            my $progeny_local_filename = _get_leafname($progeny_url);
   
            $progeny_local_filename = 
               URI::file->new($progeny_local_filename)->abs("$local_pwd/");
   
            if ( $progeny_r->is_collection() ) {
               $self->_get(-url => $progeny_url, -to => $local_pwd);
            } else {
               $self->_do_get_tofile($progeny_r,$progeny_local_filename);
            }
         }
      }
   }

   # GET A FILE
   else 
   {
      # If they didn't specify a local name at all then retrieve the 
      # file and return it as a scalar.
      if ( $passed_to eq "" ) {
         my $response = $resource->get();
         if ($response->is_error) {
            $self->err('ERR_GENERIC',
               "get $url failed: ". $response->message);
            return undef;
         } else {
            $self->ok("get $url");
            return $response->content();
         }

      # If they did specify a local directory then save it 
      # to there using our utility function.
      } else {
         $self->_do_get_tofile($resource,$local_pwd);
      }
   }
   return 1;
}

# GET utility function.
# This routine gets a file from the server and saves it locally.
# $resource is what you want to get 
# $file is what you want to save it as
sub _do_get_tofile {
   my ($self,$resource,$file) = @_;

   my $response = $resource->get();

   if ($response->is_error) {
      return $self->err('ERR_GENERIC',
         "get $file failed: ". $response->message);
   }

   if (! CORE::open(FILE,">$file") ) {
      return $self->err('ERR_GENERIC',
         "open \">$file\" failed: $!");
   }

   print "get $file (" . $resource->get_uri() . ")\n" if ($DEBUG>2);
   print FILE $resource->get_content;
   close FILE;
   return $self->ok("get $file (" . $response->content_length() . " bytes)" );
}

# This subroutine takes a URI and gets the last portion 
# of it: the filename.
# e.g. /dir1/dir2/file.txt => file.txt
#      /dir1/dir2/         => dir2
sub _get_leafname {
   my($url) = shift;
   my $leaf_resource = $url;
   $leaf_resource =~ s#[\/\\]$##;
   my @leaf_resource = split(/[\/\\]+/,$leaf_resource);
   return pop @leaf_resource || 0;
}

# LOCK
sub lock {
   my($self,@p) = @_;
   my($url,$owner,$depth,$timeout,$scope,$type,@other) =
      HTTP::DAV::Utils::rearrange(['URL','OWNER','DEPTH',
                                   'TIMEOUT','SCOPE','TYPE'],@p);

   return $self->err('ERR_NULL_RESOURCE') unless $self->get_workingresource();

   my $resource;
   if ($url) {
      $url = $self->get_absolute_uri($url);
      $resource = $self->new_resource( -uri => $url );
   } else {
      $resource = $self->get_workingresource();
      $url= $resource->get_uri;
   }

   # Make the lock
   my $resp = $resource->lock(-owner=>$owner,-depth=>$depth,
                              -timeout=>$timeout,-scope=>$scope,
                              -type=>$type);

   if ( $resp->is_success() ) {
      return $self->ok( "lock $url succeeded" );
   } else {
      return $self->err( 'ERR_RESP_FAIL',$resp->message );
   }
}

# UNLOCK
sub unlock {
   my($self,@p) = @_;
   my ($url) = HTTP::DAV::Utils::rearrange(['URL'], @p);

   return $self->err('ERR_NULL_RESOURCE') unless $self->get_workingresource();

   my $resource;
   if ($url) {
      $url = $self->get_absolute_uri($url);
      $resource = $self->new_resource( -uri => $url );
   } else {
      $resource = $self->get_workingresource();
      $url= $resource->get_uri;
   }

   # Make the lock
   my $resp = $resource->unlock();
   if ( $resp->is_success ) {
      return $self->ok( "unlock $url succeeded" );
   } else {
      # The Resource.pm::lock routine has a gross hack 
      # where if it doesn't know the locktoken it will 
      # just return an empty response with message "Client Error".
      # Make a custom message for this case.
      my $msg = $resp->message;
      if ( $msg=~ /Client error/i ) {
          $msg = "No locks found. Try steal";
          return $self->err( 'ERR_GENERIC',$msg );
      } else {
          return $self->err( 'ERR_RESP_FAIL',$msg );
      }
   }
}

sub steal {
   my($self,@p) = @_;
   my ($url) = HTTP::DAV::Utils::rearrange(['URL'], @p);

   return $self->err('ERR_NULL_RESOURCE') unless $self->get_workingresource();

   my $resource;
   if ($url) {
      $url = $self->get_absolute_uri($url);
      $resource = $self->new_resource( -uri => $url );
   } else {
      $resource = $self->get_workingresource();
   }

   # Go the steal
   my $resp = $resource->forcefully_unlock_all();
   if ( $resp->is_success() ) {
      return $self->ok( "steal $url succeeded" );
   } else {
      return $self->err( 'ERR_RESP_FAIL',$resp->message() );
   }
}

# MKCOL
sub mkcol {
   my($self,@p) = @_;
   my ($url) = HTTP::DAV::Utils::rearrange(['URL'], @p);

   return $self->err('ERR_WRONG_ARGS') if (!defined $url || $url eq "");
   return $self->err('ERR_NULL_RESOURCE') unless $self->get_workingresource();

   $url = HTTP::DAV::Utils::make_trail_slash($url);
   my $new_url = $self->get_absolute_uri($url);
   my $resource = $self->new_resource( -uri => $new_url );

   # Make the lock
   my $resp = $resource->mkcol();
   if ( $resp->is_success() ) {
      return $self->ok( "mkcol $new_url" );
   } else {
      return $self->err( 'ERR_RESP_FAIL',$resp->message() );
   }
}

# OPTIONS
sub options {
   my($self,@p) = @_;
   my ($url) = HTTP::DAV::Utils::rearrange(['URL'], @p);

   #return $self->err('ERR_WRONG_ARGS') if (!defined $url || $url eq "");
   return $self->err('ERR_NULL_RESOURCE') unless $self->get_workingresource();

   my $resource;
   if ($url) {
      $url = $self->get_absolute_uri($url);
      $resource = $self->new_resource( -uri => $url );
   } else {
      $resource = $self->get_workingresource();
      $url = $resource->get_uri;
   }

   # Make the call
   my $resp = $resource->options();
   if ( $resp->is_success() ) {
      $self->ok( "options $url succeeded" );
      return $resource->get_options();
   } else {
      $self->err( 'ERR_RESP_FAIL',$resp->message() );
      return undef;
   }
}

# MOVE
sub move { return shift->_move_copy("move",@_); }
sub copy { return shift->_move_copy("copy",@_); }
sub _move_copy {
   my($self,$method,@p) = @_;
   my($url,$dest_url,$overwrite,$depth,$text,@other) = 
      HTTP::DAV::Utils::rearrange(['URL','DEST','OVERWRITE','DEPTH','TEXT'],@p);

   return $self->err('ERR_NULL_RESOURCE') unless $self->get_workingresource();

   if (!(defined $url && $url ne "" && defined $dest_url && $dest_url ne "")) {
      return $self->err('ERR_WRONG_ARGS',
                        "Must supply a source and destination url");
   }

   $url =      $self->get_absolute_uri($url);
   $dest_url = $self->get_absolute_uri($dest_url);
   my $resource =      $self->new_resource( -uri => $url );
   my $dest_resource = $self->new_resource( -uri => $dest_url );

   my $resp = $dest_resource->propfind(-depth=>1);
   if ($resp->is_success && $dest_resource->is_collection) {
      my $leafname = &_get_leafname($url);
      $dest_url = "$dest_url/$leafname";
      $dest_resource = $self->new_resource( -uri => $dest_url );
   }

   # Make the lock
   $resp = $resource->$method(-dest=>$dest_resource,
                              -overwrite=>$overwrite,
                              -depth=>$depth,
                              -text=>$text,
                             );

   if ( $resp->is_success() ) {
      return $self->ok( "$method $url to $dest_url succeeded" );
   } else {
      return $self->err( 'ERR_RESP_FAIL',$resp->message );
   }
}

# OPEN
# Must be a collection resource
# $dav->open( -url => http://localhost/test/ );
# $dav->open( localhost/test/ );
# $dav->open( -url => localhost:81 );
# $dav->open( localhost );
sub open {
   my($self,@p) = @_;
   my ($url) = HTTP::DAV::Utils::rearrange(['URL'], @p);

   my $resource;
   if ( defined $url && $url ne "") {
      $url = HTTP::DAV::Utils::make_trail_slash($url);
      $resource = $self->new_resource( -uri => $url );
   } else {
      $resource = $self->get_workingresource();
      $url = $resource->get_uri() if ($resource);
      return $self->err('ERR_WRONG_ARGS') if (!defined $url || $url eq "");
   }

   my $response = $resource->propfind(-depth=>0);
   #print $response->as_string;
   #print $resource->as_string;
   if ($response->is_error() ) {
      if ($response->www_authenticate) {
         return $self->err('ERR_UNAUTHORIZED');
      }
      elsif (! $resource->is_dav_compliant) {
         return $self->err('ERR_GENERIC',
            "The URL \"$url\" is not DAV enabled or not accessible.");
      }
      else {
         return $self->err('ERR_RESP_FAIL',
            "Could not access $url: ".$response->message());
      }
   }
 
   # If it is a collection but the URI doesn't 
   # end in a trailing slash.
   # Then we need to reopen with the /
   elsif ( $resource->is_collection && 
           $url !~ m#/\s*$# ) 
   {
      my $newurl = $url . "/";
      print  "Redirecting to $newurl\n" if $DEBUG > 1;
      return $self->open( $newurl );
   }

   # If it is not a collection then we 
   # can't open it.
   elsif ( !$resource->is_collection ) 
   {
      return $self->err('ERR_GENERIC',"Operation failed. You can only open a collection (directory)");
   }
   else {
      $self->set_workingresource($resource);
      return $self->ok( "Connected to $url" );
   }

   return $self->err('ERR_GENERIC');
}

# Performs a propfind and then returns the populated 
# resource. The resource will have a resourcelist if 
# it is a collection. 
sub propfind {
   my($self,@p) = @_;
   my ($url,$depth) = HTTP::DAV::Utils::rearrange(['URL','DEPTH'], @p);

   $depth||=1;

   return $self->err('ERR_NULL_RESOURCE') unless $self->get_workingresource();

   my $resource;
   if ($url) {
      $url = $self->get_absolute_uri($url);
      $resource = $self->new_resource( -uri => $url );
   } else {
      $resource = $self->get_workingresource();
   }

   # Make the call
   my $resp = $resource->propfind(-depth=>$depth);
   if ( $resp->is_success() ) {
      $resource->build_ls($resource);
      $self->ok( "propfind ". $resource->get_uri() ." succeeded" );
      return $resource;
   } else {
      return $self->err( 'ERR_RESP_FAIL',$resp->message() );
   }
}

# Set a property on the resource
sub set_prop {
   my($self,@p) = @_;
   my($url,$namespace,$propname,$propvalue) = 
      HTTP::DAV::Utils::rearrange( 
         ['URL','NAMESPACE','PROPNAME','PROPVALUE'],@p);
   $self->proppatch(
      -url=>$url,
      -namespace=>$namespace,
      -propname=>$propname,
      -propvalue=>$propvalue,
      -action=>"set"
      );
}

# Unsets a property on the resource
sub unset_prop {
   my($self,@p) = @_;
   my($url,$namespace,$propname,$propvalue) = 
      HTTP::DAV::Utils::rearrange( 
         ['URL','NAMESPACE','PROPNAME'],@p);
   $self->proppatch(
      -url=>$url,
      -namespace=>$namespace,
      -propname=>$propname,
      -action=>"remove"
      );
}

# Performs a proppatch on the resource
sub proppatch {
   my($self,@p) = @_;
   my($url,$namespace,$propname,$propvalue,$action) = 
      HTTP::DAV::Utils::rearrange( 
         ['URL','NAMESPACE','PROPNAME','PROPVALUE','ACTION'],@p);

   return $self->err('ERR_NULL_RESOURCE') unless $self->get_workingresource();

   my $resource;
   if ($url) {
      $url = $self->get_absolute_uri($url);
      $resource = $self->new_resource( -uri => $url );
   } else {
      $resource = $self->get_workingresource();
   }

   # Make the call
   my $resp = $resource->proppatch(
      -namespace=>$namespace,
      -propname=>$propname,
      -propvalue=>$propvalue,
      -action=>$action,
   );

   if ( $resp->is_success() ) {
      $resource->build_ls($resource);
      $self->ok( "proppatch ($action) ". $resource->get_uri() ." succeeded" );
      return $resource;
   } else {
      return $self->err( 'ERR_RESP_FAIL',$resp->message() );
   }
}

sub put {
   my($self,@p) = @_;
   my ($local,$url,$callback) = 
      HTTP::DAV::Utils::rearrange(['LOCAL','URL','CALLBACK'], @p);
   $self->_start_multi_op("put $local",$callback);
   $self->_put(@p);
   $self->_end_multi_op();
   return $self->is_success;
}

sub _put {
   my($self,@p) = @_;
   my ($local,$url) = 
      HTTP::DAV::Utils::rearrange(['LOCAL','URL'], @p);

   return $self->err('ERR_WRONG_ARGS')    if (!defined $local || $local eq "");
   return $self->err('ERR_NULL_RESOURCE') unless $self->get_workingresource();

   # Check if they passed a reference to content rather than a filename.
   my $content_ptr = (ref($local) eq "SCALAR" ) ? 1:0;

   # Setup the resource based on the passed url
   # Check if the remote resource exists and is a collection.
   $url = $self->get_absolute_uri($url);
   my $resource = $self->new_resource($url);
   my $response = $resource->propfind(-depth=>0);
   my $leaf_name;
   if ($response->is_success && $resource->is_collection && ! $content_ptr) {
      # Add one / to the end of the collection
      $url =~ s/\/*$//g; #Strip em
      $url .= "/";       #Add one
      $leaf_name = _get_leafname($local);
   } else {
      $leaf_name = _get_leafname($url);
   }

   my $target = $self->get_absolute_uri($leaf_name,$url);
   #print "$local => $target ($url, $leaf_name)\n";

   # PUT A DIRECTORY
   if ( !$content_ptr && -d $local ) {
      # mkcol
      # Return 0 if fail because the error will have already 
      # been set by the mkcol routine
      if ( $self->mkcol( $target ) ) {
         if (! opendir(DIR,$local) ) {
            $self->err('ERR_GENERIC',
              "chdir to \"$local\" failed: $!") 
         } else {
            my @files = readdir(DIR);
            close DIR;
            foreach my $file ( @files ) {
               next if $file eq ".";
               next if $file eq "..";
               my $progeny = "$local/$file";
               $progeny =~ s#//#/#g; # Fold down double slashes
               $self->_put( -local=>$progeny, 
                            -url=>"$target/$file",
                          );
            }
         }
      }

   # PUT A FILE
   } else {
      my $content;
      if ($content_ptr) {
         $content = $$local;
      } else {
         if (! CORE::open(F,$local) ) {
            $self->err('ERR_GENERIC', "Couldn't open local file $local: $!") 
         } else {
            while(<F>) { $content .= $_; }
            close F;
         }
      }

      if (defined $content) {
         my $resource = $self->new_resource( -uri => $target);
         my $response = $resource->put($content);
         if ($response->is_success) {
            $self->ok( "put $target (" . length($content) ." bytes)" );
         } else {
            $self->err('ERR_RESP_FAIL',"put failed " .$response->message());
         }
      }
   }
}

######################################################################
# UTILITY FUNCTION
# get_absolute_uri:
# Synopsis: $new_url = get_absolute_uri("/foo/bar")
# Takes a URI (or string)
# and returns the absolute URI based
# on the remote current working directory
sub get_absolute_uri {
   my($self,@p) = @_;
   my ($rel_uri,$base_uri) = 
      HTTP::DAV::Utils::rearrange(['REL_URI','BASE_URI'], @p);

   local $URI::URL::ABS_REMOTE_LEADING_DOTS = 1;
   if (! defined $base_uri) {
      $base_uri = $self->get_workingresource()->get_uri();
   }

   if($base_uri) {
      my $new_url = URI->new_abs($rel_uri,$base_uri);
      return $new_url;
   } else {
      $rel_uri;
   }
}

1;

__END__


=head1 NAME

HTTP::DAV - A WebDAV client library for Perl5

=head1 SYNOPSIS

   # DAV script that connects to a webserver and safely
   # uploads the homepage.
   use HTTP::DAV;
  
   $d = new HTTP::DAV;
   $url = "http://host.org:8080/dav/";
  
   $d->credentials( -user=>"pcollins",-pass =>"mypass", 
                    -url =>$url,      -realm=>"DAV Realm" );
  
   $d->open( -url=>"$url )
      or die("Couldn't open $url: " .$d->message . "\n");
  
   $d->lock( -url=>"$url/index.html", -timeout=>"10m" ) 
      or die "Won't put unless I can lock\n";
  
   if ( $d->put( -local=>"/tmp/index.html", -url=>$url ) ) {
      print "/tmp/index.html successfully uploaded to $url\n";
   } else {
      print "put failed: " . $d->message . "\n";
   }
  
   $d->unlock( -url=>"$url/index.html");

=head1 DESCRIPTION

HTTP::DAV is a Perl API for interacting with and modifying content on webservers using the WebDAV protocol. Now you can LOCK, DELETE and PUT files and much more on a DAV-enabled webserver.

HTTP::DAV is part of the PerlDAV project hosted at http://www.webdav.org/perldav/ and has the following features:

=over 4

=item *

Full RFC2518 method support. OPTIONS, TRACE, GET, HEAD, DELETE, PUT, COPY, MOVE, PROPFIND, PROPPATCH, LOCK, UNLOCK.

=item *

A fully object-oriented API.

=item *

Recursive GET and PUT for site backups and other scripted transfers.

=item *

Transparent lock handling when performing LOCK/COPY/UNLOCK sequences.

=item *

C<dave>, a fully-functional ftp-style interface written on top of the HTTP::DAV API and bundled by default with the HTTP::DAV library. (If you've already installed HTTP::DAV, then dave will also have been installed (probably into /usr/local/bin). You can see it's man page by typing "perldoc dave" or going to http://www.webdav.org/perldav/dave/.

=item *

It is built on top of the popular LWP (Library for WWW access in Perl). This means that HTTP::DAV inherits proxy support, redirect handling, basic (and digest) authorization and many other HTTP operations. https is yet to be tested but is believed to be available with LWP. See C<LWP> for more information.

=item *

Popular server support. HTTP::DAV has been tested against the following servers: mod_dav, IIS5, Xythos webfile server and mydocsonline. The library is growing an impressive interoperability suite which also serves as useful "sample scripts". See "make test" and t/*.

=back

C<HTTP::DAV> essentially has two API's, one which is accessed through this module directly (HTTP::DAV) and is a simple abstraction to the rest of the HTTP::DAV::* Classes. The other interface consists of the HTTP::DAV::* classes which if required allow you to get "down and dirty" with your DAV and HTTP interactions.

The methods provided in C<HTTP::DAV> should do most of what you want. If, however, you need more control over the client's operations or need more info about the server's responses then you will need to understand the rest of the HTTP::DAV::* interfaces. A good place to start is with the C<HTTP::DAV::Resource> and C<HTTP::DAV::Response> documentation.

=head1 METHODS

=head2 METHOD CALLING: Named vs Unnamed parameters

You can pass parameters to C<HTTP::DAV> methods in one of two ways: named or unnamed.

Named parameters provides for a simpler/easier to use interface. A named interface affords more readability and allows the developer to ignore a specific order on the parameters. (named parameters are also case insensitive) 

Each argument name is preceded by a dash.  Neither case nor order matters in the argument list.  -url, -Url, and -URL are all acceptable.  In fact, only the first argument needs to begin with a dash.  If a dash is present in the first argument, C<HTTP::DAV> assumes dashes for the subsequent ones.

Each method can also be called with unnamed parameters which often makes sense for methods with only one parameter. But the developer will need to ensure that the parameters are passed in the correct order (as listed in the docs).

 Doc:     method( -url=>$url, [-depth=>$depth] )
 Named:   $d->method( -url=>$url, -depth=>$d ); # VALID
 Named:   $d->method( -Depth=>$d, -Url=>$url ); # VALID
 Named:   $d->method( Depth=>$d,  Url=>$url );  # INVALID (needs -)
 Named:   $d->method( -Arg2=>$val2 ); # INVALID, ARG1 is not optional
 Unnamed: $d->method( $val1 );        # VALID
 Unnamed: $d->method( $val2,$val1 );  # INVALID, ARG1 must come first.

=head2 PUBLIC METHODS

=over 4

=item B<new(USERAGENT)>

Creates a new C<HTTP::DAV> client

 $d = HTTP::DAV->new()

The C<-useragent> parameter expects an C<HTTP::DAV::UserAgent> object. See the C<dave> program for an advanced example of a custom UserAgent that interactively prompts the user for their username and password.

=item B<credentials(USER,PASS,[URL],[REALM])>

sets authorization credentials for a C<URL> and/or C<REALM>.

When the client hits a protected resource it will check these credentials to see if either the C<URL> or C<REALM> match the authorization response.

Either C<URL> or C<REALM> must be provided.

returns no value

Example:

 $d->credentials( -url=>'myhost.org:8080/test/',
                  -user=>'pcollins',
                  -pass=>'mypass');

=item B<DebugLevel($val)>

sets the debug level to C<$val>. 0=off 3=noisy.

C<$val> default is 0. 

returns no value.

When the value is greater than 1, the C<HTTP::DAV::Comms> module will log all of the client<=>server interactions into /tmp/perldav_debug.txt.

=back

=head2 DAV OPERATIONS

For all of the following operations, URL can be absolute (http://host.org/dav/) or relative (../dir2/). The only operation that requires an absolute URL is open.

=over 4 

=item B<copy(URL,DEST,[OVERWRITE],[DEPTH])>

copies one remote resource to another

=over 4 

=item C<-url> 

is the remote resource you'd like to copy. Mandatory

=item C<-dest> 

is the remote target for the copy command. Mandatory

=item C<-overwrite> 

optionally indicates whether the server should fail if the target exists. Valid values are "T" and "F" (1 and 0 are synonymous). Default is T.

=item C<-depth> 

optionally indicates whether the server should do a recursive copy or not. Valid values are 0 and (1 or "infinity"). Default is "infinity" (1).

=back

The return value is always 1 or 0 indicating success or failure.

Requires a working resource to be set before being called. See C<open>.

Note: if either C<'URL'> or C<'DEST'> are locked by this dav client, then the lock headers will be taken care of automatically. If the either of the two URL's are locked by someone else, the server should reject the request.

B<copy examples:>

  $d->open(-url=>"host.org/dav_dir/");

Recursively copy dir1/ to dir2/

  $d->copy(-url=>"dir1/", -dest=>"dir2/");

Non-recursively and non-forcefully copy dir1/ to dir2/

  $d->copy(-url=>"dir1/", -dest=>"dir2/",-overwrite=>0,-depth=>0);

Create a copy of dir1/file.txt as dir2/file.txt

  $d->cwd(-url=>"dir1/");
  $d->copy("file.txt","../dir2");

Create a copy of file.txt as dir2/new_file.txt

  $d->copy("file.txt","/dav_dir/dir2/new_file.txt")

=item B<cwd(URL)>

changes the remote working directory. 

This is synonymous to open except that the URL can be relative.

  $d->open("host.org/dav_dir/dir1/");
  $d->cwd("../dir2");
  $d->cwd(-url=>"../dir1");

The return value is always 1 or 0 indicating success or failure. 

Requires a working resource to be set before being called. See C<open>.

You can not cwd to files, only collections (directories).

=item B<delete(URL)>

deletes a remote resource

  $d->open("host.org/dav_dir/");
  $d->delete("index.html");
  $d->delete("./dir1");
  $d->delete(-url=>"/dav_dir/dir2/");

This command will recursively delete directories. BE CAREFUL of uninitialised file variables in situation like this: $d->delete("$dir/$file"). This will trash your $dir if $file is not set.

The return value is always 1 or 0 indicating success or failure. 

Requires a working resource to be set before being called. See C<open>.

=item B<get(URL,[TO],[CALLBACK])>

downloads the file or directory at C<URL> to the local location indicated by C<TO>.

=over 4 

=item C<-url> 

is the remote resource you'd like to get. It can be a file or directory.

=item C<-dest> 

is where you'd like to put the remote resource. If not specified, -dest defaults to "." and should always do what you expect.

=item C<-callback>

is a reference to a callback function which will be called everytime a file is completed downloading. The idea of the callback function is that some recursive get's can take a very long time and the user may require some visual feedback. Your callback function must accept 2 arguments as follows:

   # Print a message everytime a file get completes
   sub mycallback {
      my($success,$mesg) = @_;
      if ($success) {
         print "$mesg\n" 
      } else {
         print "Failed: $mesg\n" 
      }
   }

   $d->get( -url=>$url, -to=>$to, -callback=>\&mycallback );

The C<success> argument specifies whether the get operation succeeded or not.

The C<mesg> argument is a status message. The status message could contain any string and often contains useful error messages or success messages. The error messages set during a recursive get are also retrievable via the C<errors()> function discussed further down under C<ERROR HANDLING>

=back

The return value of get is always 1 or 0 indicating whether the entire get sequence was a success or if there was ANY failures. For instance, in a recursive get, if the server couldn't open 1 of the 10 remote files, for whatever reason, then the return value will be 0. This is so that you can have your script call the C<errors()> routine to handle error conditions.

Requires a working resource to be set before being called. See C<open>.

B<get examples:>

  $d->open("host.org/dav_dir/");

Recursively get remote my_dir/ to .

  $d->get("my_dir/");

Recursively get remote my_dir/ to /tmp/my_dir/ calling &mycallback($success,$mesg) everytime a file operation is completed.

  $d->get("my_dir","/tmp",\&mycallback);

Get remote my_dir/index.html to /tmp/index.html

  $d->get(-url=>"/dav_dir/my_dir/index.html",-to=>"/tmp");

Get remote index.html to /tmp/index1.html

  $d->get("index.html","/tmp/index1.html");

=item B<lock([URL],[OWNER],[DEPTH],[TIMEOUT],[SCOPE],[TYPE])>

locks a resource. If URL is not specified, it will lock the current working resource (opened resource).

   $d->lock( -url     => "index.html",
             -owner   => "Patrick Collins",
             -depth   => "infinity",
             -scope   => "exclusive",
             -type    => "write",
             -timeout => "10h" )

See C<HTTP::DAV::Resource> lock() for details of the above parameters.

The return value is always 1 or 0 indicating success or failure. 

Requires a working resource to be set before being called. See C<open>.

When you lock a resource, the lock is held against the current HTTP::DAV object. In fact, the locks are held in a C<HTTP::DAV::ResourceList> object. You can operate against all of the locks that you have created as follows:

  ## Print and unlock all locks that we own.
  my $rl_obj = $d->get_lockedresourcelist();
  foreach $resource ( $rl_obj->get_resources() ) {
      @locks = $resource->get_locks(-owned=>1);
      foreach $lock ( @locks ) { 
        print $resource->get_uri . "\n";
        print $lock->as_string . "\n";
      }
      ## Unlock them?
      $resource->unlock;
  }

Typically, a simple $d->unlock($uri) will suffice.

B<lock example>

  $d->lock($uri, -timeout=>"1d");
  ...
  $d->put("/tmp/index.html",$uri);
  $d->unlock($uri);

=item B<mkcol(URL)>

make a remote collection (directory)

The return value is always 1 or 0 indicating success or failure. 

Requires a working resource to be set before being called. See C<open>.

  $d->open("host.org/dav_dir/");
  $d->mkcol("new_dir");                  # Should succeed
  $d->mkcol("/dav_dir/new_dir");         # Should succeed
  $d->mkcol("/dav_dir/new_dir/xxx/yyy"); # Should fail

=item B<move(URL,DEST,[OVERWRITE],[DEPTH])>

moves one remote resource to another

=over 4 

=item C<-url> 

is the remote resource you'd like to move. Mandatory

=item C<-dest> 

is the remote target for the move command. Mandatory

=item C<-overwrite> 

optionally indicates whether the server should fail if the target exists. Valid values are "T" and "F" (1 and 0 are synonymous). Default is T.

=back

Requires a working resource to be set before being called. See C<open>.

The return value is always 1 or 0 indicating success or failure.

Note: if either C<'URL'> or C<'DEST'> are locked by this dav client, then the lock headers will be taken care of automatically. If either of the two URL's are locked by someone else, the server should reject the request.

B<move examples:>

  $d->open(-url=>"host.org/dav_dir/");

move dir1/ to dir2/

  $d->move(-url=>"dir1/", -dest=>"dir2/");

non-forcefully move dir1/ to dir2/

  $d->move(-url=>"dir1/", -dest=>"dir2/",-overwrite=>0);

Move dir1/file.txt to dir2/file.txt

  $d->cwd(-url=>"dir1/");
  $d->move("file.txt","../dir2");

move file.txt to dir2/new_file.txt

  $d->move("file.txt","/dav_dir/dir2/new_file.txt")

=item B<open(URL)>

opens the directory (collection resource) at URL.

open will perform a propfind against URL. If the server does not understand the request then the open will fail. 

Similarly, if the server indicates that the resource at URL is NOT a collection, the open command will fail.

=item B<options([URL])>

Performs an OPTIONS request against the URL or the working resource if URL is not supplied.

Requires a working resource to be set before being called. See C<open>.

The return value is a string of comma separated OPTIONS that the server states are legal for URL or undef otherwise.

A fully compliant DAV server may offer as many methods as: OPTIONS, TRACE, GET, HEAD, DELETE, PUT, COPY, MOVE, PROPFIND, PROPPATCH, LOCK, UNLOCK

Note: IIS5 does not support PROPPATCH or LOCK on collections.

Example:

 $options = $d->options($url);
 print $options . "\n";
 if ($options=~ /\bPROPPATCH\b/) {
    print "OK to proppatch\n";
 }

Or, put more simply:

 if ( $d->options($url) =~ /\bPROPPATCH\b/ ) {
    print "OK to proppatch\n";
 }

=item B<propfind([URL],[DEPTH])>

Perform a propfind against URL at DEPTH depth.

C<-depth> can be used to specify how deep the propfind goes. "0" is collection only. "1" is collection and it's immediate members (This is the default value). "infinity" is the entire directory tree. Note that most DAV compliant servers deny "infinity" depth propfinds for security reasons.

Requires a working resource to be set before being called. See C<open>.

The return value is an C<HTTP::DAV::Resource> object on success or 0 on failure.

The Resource object can be used for interrogating properties or performing other operations.

 ## Print collection or content length
 if ( $r=$d->propfind( -url=>"/my_dir", -depth=>1) ) {
    if ( $r->is_collection ) {
       print "Collection\n" 
       print $r->get_resourcelist->as_string . "\n"
    } else {
       print $r->get_property("getcontentlength") ."\n";
    }
 }

Please note that although you may set a different namespace for a property of a resource during a set_prop, HTTP::DAV currently ignores all XML namespaces so you will get clashes if two properties have the same name but in different namespaces. Currently this is unavoidable but I'm working on the solution.

=item B<proppatch([URL],[NAMESPACE],PROPNAME,PROPVALUE,ACTION)>

If C<-action> equals "set" then we set a property named C<-propname> to C<-propvalue> in the namespace C<-namespace> for C<-url>. 

If C<-action> equals "remove" then we unset a property named C<-propname> in the namespace C<-namespace> for C<-url>. 

If no action is supplied then the default action is "set".

The return value is an C<HTTP::DAV::Resource> object on success or 0 on failure.

The Resource object can be used for interrogating properties or performing other operations.

Requires a working resource to be set before being called. See C<open>.

It is recommended that you use C<set_prop> and C<unset_prop> instead of proppatch for readability. 

C<set_prop> simply calls C<proppatch(-action=>set)> and C<unset_prop> calls C<proppatch(-action=>"remove")>

See C<set_prop> and C<unset_prop> for examples.

=item B<put(LOCAL,[URL],[CALLBACK])>

Requires a working resource to be set before being called. See C<open>.

The return value is always 1 or 0 indicating success or failure.

=item B<set_prop([URL],[NAMESPACE],PROPNAME,PROPVALUE)>

Sets a property named C<-propname> to C<-propvalue> in the namespace C<-namespace> for C<-url>. 

Requires a working resource to be set before being called. See C<open>.

The return value is an C<HTTP::DAV::Resource> object on success or 0 on failure.

The Resource object can be used for interrogating properties or performing other operations.

Example:

 if ( $r = $d->set_prop(-url=>$url,
              -namespace=>"dave",
              -propname=>"author",
              -propvalue=>"Patrick Collins"
             ) ) {
    print "Author property set\n";
 } else {
    print "set_prop failed:" . $d->message . "\n";
 }

See the note in propfind about namespace support in HTTP::DAV. They're settable, but not readable.



=item B<steal([URL])>

forcefully steals any locks held against URL.

steal will perform a propfind against URL and then, any locks that are found will be unlocked one by one regardless of whether we own them or not.

Requires a working resource to be set before being called. See C<open>.

The return value is always 1 or 0 indicating success or failure. If multiple locks are found and unlocking one of them fails then the operation will be aborted.

 if ($d->steal()) {
    print "Steal succeeded\n";
 } else {
    print "Steal failed: ". $d->message() . "\n";
 }

=item B<unlock([URL])>

unlocks any of our locks on URL.

Requires a working resource to be set before being called. See C<open>.

The return value is always 1 or 0 indicating success or failure.

 if ($d->unlock()) {
    print "Unlock succeeded\n";
 } else {
    print "Unlock failed: ". $d->message() . "\n";
 }

=item B<unset_prop([URL],[NAMESPACE],PROPNAME)>

Unsets a property named C<-propname> in the namespace C<-namespace> for C<-url>. 
Requires a working resource to be set before being called. See C<open>.

The return value is an C<HTTP::DAV::Resource> object on success or 0 on failure.

The Resource object can be used for interrogating properties or performing other operations.

Example:

 if ( $r = $d->unset_prop(-url=>$url,
              -namespace=>"dave",
              -propname=>"author",
             ) ) {
    print "Author property was unset\n";
 } else {
    print "set_prop failed:" . $d->message . "\n";
 }

See the note in propfind about namespace support in HTTP::DAV. They're settable, but not readable.

=back

=head2 ACCESSOR METHODS

=over 4 

=item B<get_user_agent>

Returns the clients' working C<HTTP::DAV::UserAgent> object. 

You may want to interact with the C<HTTP::DAV::UserAgent> object 
to modify request headers or provide advanced authentication 
procedures. See dave for an advanced authentication procedure.

=item B<get_last_request>

Takes no arguments and returns the clients' last outgoing C<HTTP::Request> object. 

You would only use this to inspect a request that has already occurred.

If you would like to modify the C<HTTP::Request> BEFORE the HTTP request takes place (for instance to add another header), you will need to get the C<HTTP::DAV::UserAgent> using C<get_user_agent> and interact with that.

=item B<get_workingresource>

Returns the currently "opened" or "working" resource (C<HTTP::DAV::Resource>).

The working resource is changed whenever you open a url or use the cwd command.

e.g. 
  $r = $d->get_workingresource
  print "pwd: " . $r->get_uri . "\n";

=item B<get_workingurl>

Returns the currently "opened" or "working" C<URL>.

The working resource is changed whenever you open a url or use the cwd command.

  print "pwd: " . $d->get_workingurl . "\n";

=item B<get_lockedresourcelist>

Returns an C<HTTP::DAV::ResourceList> object that represents all of the locks we've created using THIS dav client.

  print "pwd: " . $d->get_workingurl . "\n";

=item B<get_absolute_uri(REL_URI,[BASE_URI])>

This is a useful utility function which joins C<BASE_URI> and C<REL_URI> and returns a new URI.

If C<BASE_URI> is not supplied then the current working resource (as indicated by get_workingurl) is used. If C<BASE_URI> is not set and there is no current working resource the C<REL_URI> will be returned.

For instance:
 $d->open("http://host.org/webdav/dir1/");

 # Returns "http://host.org/webdav/dir2/"
 $d->get_absolute_uri(-rel_uri=>"../dir2");

 # Returns "http://x.org/dav/dir2/file.txt"
 $d->get_absolute_uri(-rel_uri  =>"dir2/file.txt",
                      ->base_uri=>"http://x.org/dav/");

Note that it subtly takes care of trailing slashes.

=back

=head2 ERROR HANDLING METHODS

=over 4

=item B<message>

C<message> gets the last success or error message.

The return value is always a scalar (string) and will change everytime a dav operation is invoked (lock, cwd, put, etc).

See also C<errors> for operations which contain multiple error messages.

=item B<errors>

Returns an @array of error messages that had been set during a multi-request operation.

Some of C<HTTP::DAV>'s operations perform multiple request to the server. At the time of writing only put and get are considered multi-request since they can operate recursively requiring many HTTP requests. 

In these situations you should check the errors array if to determine if any of the requests failed.

The C<errors> function is used for multi-request operations and not to be confused with a multi-status server response. A multi-status server response is when the server responds with multiple error messages for a SINGLE request. To deal with multi-status responses, see C<HTTP::DAV::Response>.

 # Recursive put
 if (!$d->put( "/tmp/my_dir", $url ) ) {
    # Get the overall message
    print $d->message;
    # Get the individual messages
    foreach $err ( $d->errors ) { print "  Error:$err\n" }
 }

=item B<is_success>

Returns the status of the last DAV operation performed through the HTTP::DAV interface.

This value will always be the same as the value returned from an HTTP::DAV::method. For instance:

  # This will always evaluate to true
  ($d->lock($url) eq $d->is_success) ?

You may want to use the is_success method if you didn't capture the return value immediately. But in most circumstances you're better off just evaluating as follows:
  if($d->lock($url)) { ... }

=item B<get_lastresponse>

Takes no arguments and returns the last seen C<HTTP::DAV::Response> object. 

You may want to use this if you have just called a propfind and need the individual error messages returned in a MultiStatus.

If you find that you're using get_last_response() method a lot, you may be better off using the more advanced C<HTTP::DAV> interface and interacting with the HTTP::DAV::* interfaces directly as discussed in the intro. For instance, if you find that you're always wanting a detailed understanding of the server's response headers or messages, then you're probably better off using the C<HTTP::DAV::Resource> methods and interpreting the C<HTTP::DAV::Response> directly.

To perform detailed analysis of the server's response (if for instance you got back a multistatus response) you can call get_lastresponse which will return to you the most recent response object (always the result of the last operation, PUT, PROPFIND, etc). With the returned HTTP::DAV::Response object you can handle multi-status responses.

For example:

   # Print all of the messages in a multistatus response
   if (! $d->unlock($url) ) {
      $response = $d->get_lastresponse();
      if ($response->is_multistatus() ) {
        foreach $num ( 0 .. $response->response_count() ) {
           ($err_code,$mesg,$url,$desc) =
              $response->response_bynum($num);
           print "$mesg ($err_code) for $url\n";
        }
      }
   }

=back

=head2 ADVANCED METHODS

=over 4

=item B<new_resource>

Creates a new resource object with which to play. This is the preferred way of creating an HTTP::DAV::Resource object if required. Why? Because each Resource object needs to sit within a global HTTP::DAV client. Also, because the new_resource routine checks the HTTP::DAV locked resource list before creating a new object.

 $dav->new_resource( -uri => "http://..." );

=item B<set_workingresource(URL)>

Sets the current working resource to URL.

You shouldn't need this method. Call open or cwd to set the working resource.

You CAN call set_workingresource but you will need to perform a propfind immediately following it to ensure that the working resource is valid.

=back

=head1 INSTALLATION, TODO, MAILING LISTS and REVISION HISTORY

Please see the primary HTTP::DAV webpage at (http://www.webdav.org/perldav/http-dav/) or the README file in this library.

=head1 SEE ALSO

You'll want to also read:
C<HTTP::DAV::Response>, C<HTTP::DAV::Resource>, C<dave>

and maybe if you're more inquisitive:
C<LWP::UserAgent>,C<HTTP::Request>, C<HTTP::DAV::Comms>,C<HTTP::DAV::Lock>, C<HTTP::DAV::ResourceList>, C<HTTP::DAV::Utils>

=head1 AUTHOR AND COPYRIGHT

This module is Copyright (C) 2001 by

    Patrick Collins
    G03 Gloucester Place, Kensington
    Sydney, Australia

    Email: pcollins@cpan.org
    Phone: +61 2 9663 4916

All rights reserved.

You may distribute this module under the terms of either the GNU General Public License or the Artistic License, as specified in the Perl README file.

=cut
