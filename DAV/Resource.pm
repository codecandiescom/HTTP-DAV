# $Id: Resource.pm,v 0.6 2001/07/24 15:56:01 pcollins Exp $
package HTTP::DAV::Resource;

use HTTP::DAV;
use HTTP::DAV::Utils;
use HTTP::DAV::Lock;
use HTTP::DAV::ResourceList;

$VERSION = sprintf("%d.%02d", q$Revision: 0.6 $ =~ /(\d+)\.(\d+)/);

use strict;
use vars  qw($VERSION); 

###########################################################################

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
   my ($uri,$lockedresourcelist,$comms) = 
      HTTP::DAV::Utils::rearrange( 
         ['URI', 'LOCKEDRESOURCELIST', 'COMMS'], @p);

   $self->{ "_uri" }                = $uri;
   $self->{ "_lockedresourcelist" } = $lockedresourcelist;
   $self->{ "_comms" }              = $comms;

   #$self->{ "_lockpolicy" }         = $lockpolicy; # OLD

   ####
   # Set the _uri
   $self->{_uri} = HTTP::DAV::Utils::make_uri($self->{_uri});
   die "Bad URL: \"$self->{_uri}\"\n" if ( ! $self->{_uri}->scheme );

   ####
   # Check that the required objects exist

   die("Comms object required when creating a Resource object")
      unless ( defined $self->{_comms} && 
               $self->{_comms} =~ /HTTP::DAV::Comms/ );

   die("Locked ResourceList object required when creating a Resource object")
      unless ( defined $self->{_lockedresourcelist} && 
               $self->{_lockedresourcelist} =~ /HTTP::DAV::ResourceList/ );

   #   die("Locking policy required when creating a Resource object")
   #   unless ( defined $self->{_lockpolicy} && 
   #            $self->{_lockpolicy} =~ /HTTP::DAV::LockPolicy/ );

}

###########################################################################

# GET/SET
#sub set_lockpolicy { cluck("Can't reset the lockpolicy on a Resource"); 0; }
#sub set_uri        { cluck("Can't reset the uri on a Resource"); 0; }

sub set_parent_resourcelist { $_[0]->{_parent_resourcelist} = $_[1]; }
sub set_property   { $_[0]->{_properties}{$_[1]} = $_[2];  }

# PRIVATE SUBROUTINES
sub _set_content    { $_[0]->{_content} = $_[1]; }
sub _set_options    { $_[0]->{_options} = $_[1]; }

sub add_locks {
   my ($self,@locks) = @_;
   foreach my $lock ( @locks ) {
      my $token = $lock->get_locktoken();
      $self->{_locks}{$token} = $lock;
   }
}

sub is_option { 
   my ($self,$option) = @_;
   $self->options if (! defined $self->{_options});
   return ( $self->{_options} =~ /\b$option\b/i ) ? 1 : 0;
}

sub get_options    { $_[0]->{_options}; }
sub get_content    { $_[0]->{_content}; }
sub get_content_ref{ \$_[0]->{_content}; }


#sub get_lockpolicy { $_[0]->{_lockpolicy}; }
sub get_lockedresourcelist { $_[0]->{_lockedresourcelist}; }
sub get_comms      { $_[0]->{_comms}; }
sub get_property   { $_[0]->{_properties}{$_[1]};  }
sub get_uri        { $_[0]->{_uri};  }
sub get_uristring  { $_[0]->{_uri}->as_string;  }
sub get_parent_resourcelist { $_[0]->{_parent_resourcelist}; }

# $self->get_locks( -owned => [0|1] );
#  1  = return any locks owned be me
#  0  = return any locks NOT owned be me
#  not 1 or 0 = return all locks
#
sub get_locks { 
   my ($self,@p) = @_;
   my($owned) = "";
   $owned = HTTP::DAV::Utils::rearrange(['OWNED'],@p) || "";
   $owned = "" unless $owned =~ /\d/;

   my @return_locks = ();

   if ( $owned eq "1" ) {
      foreach my $token ( sort keys %{$self->{_locks}} ) {
         my $lock = $self->{_locks}{$token};
         #print "$owned " . $lock->get_locktoken . " " . $lock->is_owned . "\n";
         push(@return_locks, $lock) if ( $lock->is_owned );
      }
   }
   elsif ( $owned eq "0" ) {
      foreach my $token ( sort keys %{$self->{_locks}} ) {
         my $lock = $self->{_locks}{$token};
         push(@return_locks, $lock) unless ( $lock->is_owned );
      }
   }
   else {
      @return_locks = values %{$_[0]->{_locks}}; 
   }

   return @return_locks;
}

sub get_lock {
   my ($self,$token) = @_;
   return $self->{_locks}{$token} if ($token);
}

# Just pass through to get_locks all of our parameters.
# Then count how many we get back. >1 lock returns 1.
sub is_locked {
   my ($self,@p) = @_;
   return scalar $self->get_locks( @p );
}

sub is_collection { 
   return ( $_[0]->get_property("resource_type") =~ /collection/ )? 1:0;
}

sub _unset_properties { $_[0]->{_properties} = (); }
sub _unset_lock       { delete $_[0]->{_locks}{$_[1]} if $_[1]; }
sub _unset_locks      { $_[0]->{_locks} = (); }

###########################################################################
sub lock {
   my($self, @p) = @_;

   my $lock = HTTP::DAV::Lock->new( -owned => 1 );

   my($owner,$depth,$timeout,$scope,$type,@other) =
      HTTP::DAV::Utils::rearrange(['OWNER','DEPTH','TIMEOUT','SCOPE','TYPE'],@p);

   ####
   # Set the defaults

   # 'owner' default is DAV.pm/v0.1 (ProcessId)
   $owner   ||= "DAV.pm/v$HTTP::DAV::VERSION ($$)";

   # 'depth' default is Infinity
   $depth = ( defined $depth && $depth eq "0" ) ? 0 : "Infinity";

   # 'scope' default is exclusive
   $scope   ||= "exclusive";

   # 'type' default is write
   $type    ||= "write";

   ####
   # Setup the headers for the lock request
   my $headers = HTTP::DAV::Headers->new;
   $headers->header("Content-type", "text/xml; charset=\"utf-8\"");
   $headers->header("Depth", $depth);
   my $timeoutval = $lock->timeout($timeout);
   $headers->header("Timeout", $timeoutval) if ( $timeoutval );

   ####
   # Setup the XML content for the lock request
   my $xml_request = HTTP::DAV::Lock->make_lock_xml ( 
         -owner =>   $owner,
         -timeout => $timeout,
         -scope =>   $scope,
         -type =>    $type,
      );

   #print "$xml_request\n";

   ####
   # Put the lock request to the remote server
   my $resp= $self->{_comms}->do_http_request (
          -method  => "LOCK",
          -url     => $self->{_uri},
          -headers => $headers,
          -content    =>$xml_request,
      );

   ###
   # Handle the lock response

   if ( $resp->content_type =~ m#text/xml# ) {

      # use XML::DOM to parse the result.
      my $parser = new XML::DOM::Parser;
      my $doc = $parser->parse($resp->content);

      ###
      # Multistatus response. Generally indicates a failure
      if ( $resp->code == 207 ) { 
         # We're only interested in the error codes that come 
         # out of the multistatus $resp.
         eval { $self->_XML_parse_multistatus( $doc, $resp ) };
         print "XML error: " . $@ if $@;
      }
   
      ###
      # Lock succeeded  
      # 1. I assume from RFC2518 that if it successsfully locks
      # then we will only get back the lockdiscover element 
      # for MY lock. If not, I will warn the user.
      #
      # 2. I am fairly sure that my client should only ever be able to 
      # take out one lock on a resource. As such this program assumes 
      # that a resource can only have one lock held against it (locks 
      # owned by other people do not get stored here).
      #
      elsif ( $resp->code == 200 ) {
         my $node_prop = HTTP::DAV::Utils::get_only_element($doc,"D:prop");
         my $lock_discovery = 
            HTTP::DAV::Utils::get_only_element($node_prop,"D:lockdiscovery");
         my @locks   = HTTP::DAV::Lock->XML_lockdiscovery_parse( $lock_discovery ); 

         if ( $#locks > 0 ) {
             warn("Serious protocol error, expected 1 lock back from request ".
                  "but got more than one. Don't know which one is mine");
         } else {
            $self->add_locks( @locks );
            foreach my $lock ( @locks ) { $lock->set_owned(1); }
            $self->{_lockedresourcelist}->add_resource($self);
         }
      }

   }

   return $resp;
}

###########################################################################
sub unlock {
   my($self,@p) = @_;
   my($force,$opaquelocktoken) = HTTP::DAV::Utils::rearrange(['FORCE','TOKEN'],@p);
   my $resp;

   if ( ! $opaquelocktoken ) {
      my @locks = $self->get_locks( -owned => 1 );
      foreach my $lock (@locks ) {
         $resp = $self->unlock( -token => $lock->get_locktoken );
      }
      return $resp;
   }

   if ( $opaquelocktoken ) {
      my $headers = HTTP::DAV::Headers->new;
      $headers->header("Lock-Token", "<${opaquelocktoken}>");

      ####
      # Put the unlock request to the remote server
      $resp= $self->{_comms}->do_http_request (
             -method  => "UNLOCK",
             -url     => $self->get_uri,
             -headers => $headers,
            #-content => no content required
         );
      
      if ($resp->is_success) {
         $self->_unset_lock($opaquelocktoken); 
      }
   }

   ###
   # If this object is NOT locked by me and you haven't given 
   # me a locktoken to use then, then we can try and 
   # forcefully unlock it if you asked me to -force.
#   else {
#      # Just return unless you asked me to steal the lock 
#      # with a force parameter
#      if ($force) {
#         $resp = $self->forcefully_unlock_all();
#         if ($resp->is_success) {
#             $self->_unset_locks();
#         }
#      } else {
#         $resp = HTTP::DAV::Response->new;
#      }
#   }

   return $resp;
}

###########################################################################
sub forcefully_unlock_all {
   my ($self) = @_;
   my $resp;

   my $discovery_resp = $self->lockdiscovery;
   if ( $discovery_resp->is_success ) {
      my @locks = $self->get_locks();
      foreach my $lock ( @locks ) {
         my $token = $lock->get_locktoken;
         $resp = $self->unlock(-force=>0, -token => $token) if $token;
         return $resp unless $resp->is_success;
      }
   } else {
      $resp = HTTP::DAV::Response->new;
   }

   return $resp;
}

###########################################################################
sub steal_lock {
   my ($self) = @_;

   $self->forcefully_unlock_all;
   return $self->lock;
}

###########################################################################
sub lockdiscovery {
   my($self,@p) = @_;
   my($depth,@other) = HTTP::DAV::Utils::rearrange(['DEPTH'],@p);

   return $self->propfind( 
             -depth => $depth, 
             -text  => "<D:prop><D:lockdiscovery/></D:prop>");
}

###########################################################################
sub propfind {
   my ($self,@p) = @_;

   my($depth,$text,@other) = HTTP::DAV::Utils::rearrange(['DEPTH','TEXT'],@p);

   # 'depth' default is 1
   $depth = 1 unless ( defined $depth && $depth ne "" );
    
   ####
   # Setup the headers for the lock request
   my $headers = new HTTP::Headers;
   $headers->header("Content-type", "text/xml; charset=\"utf-8\"");
   $headers->header("Depth", $depth);

   # Create a new XML document
   #   <D:propfind xmlns:D="DAV:">
   #       <D:allprop/>
   #   </D:propfind>
   my $xml_request = qq{<?xml version="1.0" encoding="utf-8"?>};
   $xml_request .= "<D:propfind xmlns:D='DAV:'>";
   $xml_request .= $text || "<D:allprop/>";
   $xml_request .= "</D:propfind>";
   
   ####
   # Put the propfind request to the remote server
   my $resp= $self->{_comms}->do_http_request (
          -method  => "PROPFIND",
          -url     => $self->{_uri},
          -headers => $headers,
          -content => $xml_request,
      );


   if ( $resp->content_type !~ m#text/xml# ) {
      $resp->add_status_line("HTTP/1.1 422 Unprocessable Entity, no XML body.",
                             "", $self->{_uri});
   } else {
      # use XML::DOM to parse the result.
      my $parser = new XML::DOM::Parser;
      my $doc = $parser->parse($resp->content);
   
      # Setup a ResourceList in which to pump all of the collection 
      # TODO... this should probably be eval'led so that broken or 
      # incorrectly handled XML doesn't dump the program.
      my $resource_list;
      eval { $resource_list = $self->_XML_parse_multistatus( $doc, $resp ) };
      print "XML error: " . $@ if $@;

      if ($resource_list && $resource_list->count_resources() ) {
         $self->{_resource_list} = $resource_list;
      }
   }

   return $resp;
}


###########################################################################
# get/GET the body contents
sub get {
   my ($self) = @_;

   my $resp = $self->{_comms}->do_http_request ( 
      -method => "GET", 
      -uri    =>  $self->get_uri,
      ); 

   # What to do with all of the headers in the response. Put 
   # them into this object? If so, which ones?
   if ($resp->is_success) {
      $self->_set_content( $resp->content );
   }

   return $resp;
}
sub GET { my $self=shift; $self->get( @_ ); }

###########################################################################
# put/PUT the body contents

sub put {
   my ($self,$content) = @_;
   my $resp;

   # Setup the If: header if it is locked
   my $headers = HTTP::DAV::Headers->new();
   $self->_setup_if_headers($headers);

   if ( ! $content ) {
      $content = $self->get_content();
      if ( ! $content ) {
         #$resp = HTTP::DAV::Response->new;
         #$resp->code("400"); ??
         return $resp;
      }
   }

   $resp = $self->{_comms}->do_http_request ( 
      -method => "PUT", 
      -uri    =>  $self->get_uri,
      -headers=>  $headers,
      -content=>  $content,
      ); 

   #my $unlockresp = $self->unlock;

   # What to do with all of the headers in the response. Put 
   # them into this object? If so, which ones?
   # $self->_set_content( $resp->content );

   return $resp;
}
sub PUT { my $self=shift; $self->put( @_ ); }

###########################################################################
# Make a collection
sub mkcol {
   my ($self) = @_;

   # Setup the If: header if it is locked
   my $headers = HTTP::DAV::Headers->new();
   $self->_setup_if_headers($headers);

   my $resp = $self->{_comms}->do_http_request( 
      -method => "MKCOL", 
      -uri    => $self->get_uri,
      -headers=> $headers,
      );

   return $resp;
}

###########################################################################
# Get OPTIONS available on a resource/collection
sub options {
   my ($self, $entire_server) = @_;

   my $uri = $self->get_uri;
   # Doesn't work properly. Sets it as /*
   # How do we get LWP to send through just 
   # OPTIONS * HTTP/1.1
   # ??
   #$uri->path("*") if $entire_server;

   my $resp = $self->{_comms}->do_http_request ( 
      -method => "OPTIONS", 
      -uri    => $uri,
      );

   if ($resp->header("Allow")) {
      $self->_set_options($resp->header("Allow"));
   }

   return $resp;
}

sub OPTIONS { my $self=shift; $self->options( @_ ); }

###########################################################################
# Move a resource/collection
sub move {
   my ($self) = @_;
}

###########################################################################
# Copy a resource/collection
sub copy {
   my ($self) = @_;
}

###########################################################################
# proppatch a resource/collection
sub proppatch {
   my ($self,$namespace,$propname,$propvalue,@p) = @_;

   my($depth,$text,@other) = HTTP::DAV::Utils::rearrange(['DEPTH','TEXT'],@p);

   # 'depth' default is 0
   $depth = 1;
    
   ####
   # Setup the headers for the lock request
   my $headers = new HTTP::Headers;
   $headers->header("Content-type", "text/xml; charset=\"utf-8\"");
   $headers->header("Depth", $depth);

   my $xml_request = qq{<?xml version="1.0" encoding="utf-8"?>};
   $xml_request .= "<D:propertyupdate xmlns:D=\"DAV:\">";
   $xml_request .= "<D:set>";
   if ($namespace eq "DAV" || $namespace eq "dav" || $namespace eq "") {
     $xml_request .= "<D:prop>";
     $xml_request .= "<D:".$propname.">".$propvalue."</D:".$propname.">";
   }
   else {
     $xml_request .= "<D:prop xmlns:R=\"".$namespace."\">";
     $xml_request .= "<R:".$propname.">".$propvalue."</R:".$propname.">";
   }
   $xml_request .= "</D:prop>";
   $xml_request .= "</D:set>";
   $xml_request .= "</D:propertyupdate>";
    
   ####
   # Put the proppatch request to the remote server
   my $resp= $self->{_comms}->do_http_request (
          -method  => "PROPPATCH",
          -url     => $self->{_uri},
          -headers => $headers,
          -content => $xml_request,
      );


   if ( $resp->content_type !~ m#text/xml# ) {
      $resp->add_status_line("HTTP/1.1 422 Unprocessable Entity, no XML body.",
                             "", $self->{_uri});
   } else {
      # use XML::DOM to parse the result.
      my $parser = new XML::DOM::Parser;
      my $doc = $parser->parse($resp->content);
   
      my $resource_list;
      eval { $resource_list = $self->_XML_parse_multistatus( $doc, $resp ) };
      print "XML error: " . $@ if $@;

      if ($resource_list && $resource_list->count_resources() ) {
         $self->{_resource_list} = $resource_list;
      }
   }

   return $resp;
}

###########################################################################
# Delete a resource/collection
sub delete {
   my ($self) = @_;

   # Setup the If: header if it is locked
   my $headers = HTTP::DAV::Headers->new();
   $self->_setup_if_headers($headers);

   # Setup the Depth for the delete request
   # The only valid depth is Infinity.
   $headers->header("Depth", "Infinity");

   my $resp = $self->{_comms}->do_http_request( 
      -method => "DELETE", 
      -uri    => $self->get_uri,
      -headers=> $headers,
      );

   #my $resp = $self->unlock( $u );

   # Handle a multistatus response
   if ( $resp->content_type =~ m#text/xml# && # XML body
        $resp->code == "207"                  # Multistatus
      ) {
      # use XML::DOM to parse the result.
      my $parser = new XML::DOM::Parser;
      my $doc = $parser->parse($resp->content);
   
      # We're only interested in the error codes that come out of $resp.
      eval { $self->_XML_parse_multistatus( $doc, $resp ) };
      print "XML error: " . $@ if $@;
   }

   return $resp;
}

###########################################################################
###########################################################################
# parses a <D:multistatus> element.
# This is the root level element for a 
# PROPFIND body or a failed DELETE body.
# For example. The following is the result of a DELETE operation 
# with a locked progeny (child).
#
# >> DELETE /test/dir/newdir/ HTTP/1.1
# << HTTP/1.1 207 Multistatus
# <?xml version="1.0" encoding="utf-8"?>
# <D:multistatus xmlns:D="DAV:">
#   <D:response>
#      <D:href>/test/dir/newdir/locker/</D:href>
#      <D:status>HTTP/1.1 423 Locked</D:status>
#   </D:response>
#   <D:response>
#      <D:href>/test/dir/newdir/</D:href>
#      <D:propstat>
#         <D:prop><D:lockdiscovery/></D:prop>
#         <D:status>HTTP/1.1 424 Failed Dependency</D:status>
#      </D:propstat>
#   </D:response>
# </D:multistatus>
#
sub _XML_parse_multistatus {
   my ($self,$doc, $resp) = @_;
   my $resource_list = HTTP::DAV::ResourceList->new;

   # <!ELEMENT multistatus (response+, responsedescription?) >
   # Parse     I            II         III

   ###
   # Parse I
   my $node_multistatus=HTTP::DAV::Utils::get_only_element($doc,"D:multistatus");

   ###
   # Parse III
   # Get the overarching responsedescription for the 
   # multistatus and set it into the DAV:Response object.
   my $node_rd = HTTP::DAV::Utils::get_only_element($node_multistatus,"D:responsedescription");
   if ($node_rd) {
      my $rd = $node_rd->getFirstChild->getNodeValue();
      $resp->set_responsedescription($rd) if $rd;
   }

   ###
   # Parse II
   # Get all the responses in the multistatus element
   # <!ELEMENT multistatus (response+,responsedescription?) >
   my @nodes_response= HTTP::DAV::Utils::get_elements_by_tag_name($node_multistatus,"D:response");

   # Process each response object
   #<!ELEMENT  response (href, ((href*, status)|(propstat+)), responsedescription?) >
   # Parse     1         2       2a     3        4            5

   ###
   # Parse 1.
   for my $node_response (@nodes_response) {

       ###
       # Parse 2 and 2a (one or more hrefs)
       my @nodes_href= HTTP::DAV::Utils::get_elements_by_tag_name($node_response,"D:href");

       # Get href <!ELEMENT href (#PCDATA) >
       my ($href,$resource);
       #for (my $k = 0; $k < $href_count; $k++) {
       foreach my $node_href ( @nodes_href ) {

          #my $node_href = $nodes_href->item($k);
          $href      = $node_href->getFirstChild->getNodeValue();

          # The href may be relative. If so make it absolute.
          # With the uri data "/mydir/myfile.txt"
          # And the uri of "this" object, "http://site/dir",
          # return "http://site/mydir/myfile.txt"
          # See the rules of URI.pm
          my $href_uri = HTTP::DAV::Utils::make_uri($href);
          my $res_url = $href_uri->abs( $self->get_uri );
   
           # Create a new Resource to put into the list
          if ($res_url->eq($self->get_uri)) {
             $resource = $self;
   
          } else {
             $resource = HTTP::DAV::Resource->new(
                -uri=>        $res_url,
                #-lockpolicy=> $self->get_lockpolicy(),
                -comms=>      $self->get_comms(),
                -lockedresourcelist=> $self->get_lockedresourcelist(),
             );
      
             $resource_list->add_resource($resource);
          }
       }

       ###
       # Parse 3 and 5
       # Get the values out of each Element
       # <!ELEMENT status (#PCDATA) >
       # <!ELEMENT responsedescription (#PCDATA) >
       $self->_XML_parse_status($node_response,$resp,"$href:response:$node_response");


       ###
       # Parse 4.
       # Get the propstat+ list to be processed below
       # Process each propstat object within this response
       #
       # <!ELEMENT propstat (prop, status, responsedescription?) >
       # Parse     a         b     c       d

       ### 
       # Parse a
       my @nodes_propstat= HTTP::DAV::Utils::get_elements_by_tag_name($node_response,"D:propstat");
       foreach my $node_propstat ( @nodes_propstat ) {

          ### 
          # Parse b
          my $node_prop   = HTTP::DAV::Utils::get_only_element($node_propstat,"D:prop");
          my $prop_hashref = $resource->_XML_parse_and_store_props($node_prop);

          ### 
          # Parse c and d
          $self->_XML_parse_status($node_propstat,$resp,"$href:propstat:$node_propstat");

      } # foreach propstat


   } # foreach response

   return $resource_list;
}

###
# This routine takes an XML node and:
# Extracts the D:status and D:responsedescription elements.
# If either of these exists, sets messages into the passed HTTP::DAV::Response object.
# The handle should be unique.
sub _XML_parse_status {
   my ($self,$node,$resp,$handle) = @_;

   # <!ELEMENT status (#PCDATA) >
   # <!ELEMENT responsedescription (#PCDATA) >
   my $node_status = HTTP::DAV::Utils::get_only_element($node,"D:status");
   my $node_rd=      HTTP::DAV::Utils::get_only_element($node,"D:responsedescription");
   my $status = $node_status->getFirstChild->getNodeValue() if ($node_status);
   my $rd =     $node_rd    ->getFirstChild->getNodeValue() if ($node_rd);
 
   if ( $status || $rd ) {
      # Put this status-line detail into the DAV:Response object. 
      # The last argument is just a "handle". It can be 
      # anything, but it should be unique.
      $resp->add_status_line($status,$rd, $handle);
   }
}

###
# Pass in the XML::DOM prop node Element and it will 
# parse and store all of the properties. These ones 
# are specifically dealt with:
# creationdate
# getcontenttype
# getcontentlength
# displayname
# getetag
# getlastmodified
# resourcetype
# supportedlock
# lockdiscovery

sub _XML_parse_and_store_props {
   my ($self,$node) = @_;
   my %return_props = ();

   return unless ($node && $node->hasChildNodes() );

   # Clear the old properties
   $self->_unset_properties();

   # These elements will just get copied straight into our properties hash.
   my @raw_copy = qw( 
      creationdate         
      getlastmodified
      getetag 
      displayname  
      getcontentlength     
      getcontenttype
      );

   my $props = $node->getChildNodes;
   my $n = $props->getLength;
   for (my $i = 0; $i < $n; $i++) {

      my $prop = $props->item($i);

      # Ignore anything in the <prop> element which is  
      # not an Element. i.e. ignore comments, text, etc...
      next if ($prop->getNodeTypeName() ne "ELEMENT_NODE" );

      my $prop_name = $prop->getNodeName();

      $prop_name = HTTP::DAV::Utils::XML_remove_namespace( $prop_name );

      if ( grep ( /^$prop_name$/i, @raw_copy ) ) {
         my $cdata = HTTP::DAV::Utils::get_only_cdata($prop);
         $self->set_property($prop_name, $cdata);
      }

      elsif ( $prop_name eq "lockdiscovery" ) {
         my @locks   = HTTP::DAV::Lock->XML_lockdiscovery_parse( $prop ); 
         $self->add_locks( @locks);
      }

      elsif ( $prop_name eq "supportedlock" ) {
         my $supportedlock_hashref= 
            HTTP::DAV::Lock::get_supportedlock_details( $prop );
         $self->set_property( "supportedlocks", $supportedlock_hashref );
      }

      #resourcetype and others
      else {
         my $node_name = HTTP::DAV::Utils::XML_remove_namespace( $prop->getNodeName() );
         my $str = "";
         my @nodes = $prop->getChildNodes;
         foreach my $node ( @nodes ) { $str .= $node->toString; }
         $self->set_property( $node_name, $str);
      }
   }

   ###
   # Cleanup work

   # set collection based on resourcetype
   #my $getcontenttype = $self->get_property("getcontenttype");
   #($getcontenttype && $getcontenttype =~ /directory/i  ) ||  
   my $resourcetype = $self->get_property("resourcetype");
   if ( 
         ($resourcetype   && $resourcetype   =~ /collection/i ) 
      ) {
      $self->set_property( "resourcetype", "collection" );
   }

   # Clean up the date work.
   my $creationdate = $self->get_property( "creationdate" );
   if ( $creationdate ) {
      #my ($epochgmt,undef) = ISO8601_to_epochgmt($creationdate);
      my ($epochgmt) = HTTP::Date::str2time($creationdate);
      $self->set_property( "creationepoch", $epochgmt );
      $self->set_property( "creationdate", HTTP::Date::time2str( $epochgmt) );
   }

   my $getlastmodified = $self->get_property( "getlastmodified" );
   if ( $getlastmodified ) {
      my ($epochgmt) = HTTP::Date::str2time($getlastmodified);
      $self->set_property( "lastmodifiedepoch", $epochgmt);
      $self->set_property( "lastmodifieddate",   HTTP::Date::time2str($epochgmt));
   }

}

###########################################################################
# $self->_get_if_headers( $headers_obj );
# used by at least PUT,MKCOL and DELETE
sub _setup_if_headers {
   my ($self,$headers) = @_;

   # Setup the If: header if it is locked
   my $tokens = $self->{_lockedresourcelist}->get_locktokens( $self->get_uri );
   my $if = $self->{_lockedresourcelist}->tokens_to_if_header( $tokens );
   $headers->header( "If", $if ) if $if;
}

###########################################################################
# Dump the objects contents as a string
sub as_string {
   my ($self,$space,$depth) = @_;

   $depth = 1 if (! defined $depth || $depth eq "");
   $space = "" unless $space;

   my $return .= "${space}Resource Object ($self)\n";
   $space  .= "   ";
   $return .= "${space}'_uri': ";
   $return .= $self->{_uri}->as_string. "\n";

   $return .= "${space}'_options': " . $self->{_options} . "\n" if $self->{_options};

   #$return .= "${space}'_lockpolicy': " . $self->{_lockpolicy}->get_locking_policy() . "\n";

   $return .= "${space}'properties'\n";
   foreach my $prop (sort keys %{$self->{_properties}} ) {
      my $prop_val;
      if ($prop eq "supportedlocks" && $depth>1 ) {
         use Data::Dumper;
         $prop_val = $self->get_property($prop); 
         $prop_val = Data::Dumper->Dump( [$prop_val] , [ '$prop_val' ] );
      } else {
         $prop_val = $self->get_property($prop); 
         $prop_val =~ s/\n/\\n/g;
      }
      $return .= "${space}   '$prop': $prop_val\n";
   }

   if ( defined $self->{_content} ) {
      $return .= "${space}'_content':" . substr($self->{_content},0,50) .  "...\n";
   }


   # DEEP PRINT
   if ($depth ) {
      $return .= "${space}'_locks':\n";
      foreach my $lock ( $self->get_locks() ) {
         $return .= $lock->as_string("$space   ");
      }

      $return .= $self->{_resource_list}->as_string($space) if $self->{_resource_list};
   } 

   # SHALLOW PRINT
   else {
      $return .= "${space}'_locks': ";
      foreach my $lock ( $self->get_locks() ) {
         my $locktoken = $lock->get_locktoken();
         my $owned     = ($lock->is_owned) ? "owned":"not owned";
         $return .= "${space}   $locktoken ($owned)\n";
      }
      $return .= "${space}'_resource_list': " . $self->{_resource_list} . "\n";
   }

   $return;
}

1;

__END__





















=head1 NAME

HTTP::DAV::Resource - Represents and interfaces with WebDAV Resources

=head1 SYNOPSIS

Sample

=head1 DESCRIPTION

Description here

=head1 CONSTRUCTORS

=over 4

=item B<new>

Returns a new resource represented by the URI.

$r = HTTP::DAV::Resource->new( 
        -uri => $uri, 
        -LockedResourceList => $locks, 
        -Comms => $comms 
     );

On creation a Resource object needs 2 other objects passed in:

1. a C<ResourceList> Object. This list will be added to if you lock this Resource.

2. a C<Comms> Object. This object will be used for HTTP communication.

=back

=head1 METHODS

=over 4 


=item B<get/GET>

Performs an HTTP GET and returns a DAV::Response object.        

 $response = $resource->get;
 print $resource->get_content if ($response->is_success);

=item B<put/PUT>

Performs an HTTP PUT and returns a DAV::Response object.        

$response = $resource->put( $string );

$string is be passed as the body.

 e.g.
 $response = $resource->put($string);
 print $resource->get_content if ($response->is_success);

Will use a Lock header if this resource was previously locked.

=item B<copy>

Not implemented 

=item B<move>

Not implemented 

=item B<delete>

Performs an HTTP DELETE and returns a DAV::Response object.

 $response = $resource->delete;
 print "Delete successful" if ($response->is_success);

Will use a Lock header if this resource was previously locked.

=item B<options>

Performs an HTTP OPTIONS and returns a DAV::Response object.

 $response = $resource->options;
 print "Yay for PUT!" if $resource->is_option("PUT");

=item B<mkcol>

Performs a WebDAV MKCOL request and returns a DAV::Response object.

 $response = $resource->mkcol;
 print "MKCOL successful" if ($response->is_success);

Will use a Lock header if this resource was previously locked.

=item B<proppatch>

Not implemented 

=item B<propfind>

Performs a WebDAV PROPFIND request and returns a DAV::Response object.

 $response = $resource->propfind;
 if ($response->is_success) {
    print "PROPFIND successful\n";
    print $resource->get_property("displayname") . "\n";
 }

A successful PROPFIND fills the object with much data about the Resource.  
Including:
   displayname
   ...
   TODO


=item B<lock>

Performs a WebDAV LOCK request and returns a DAV::Response object.

 $resource->lock(
        -owner   => "Patrick Collins",
        -depth   => "Infinity"
        -scope   => "exclusive",
        -type    => "write" 
        -timeout => TIMEOUT',
     )

lock takes the following arguments.


B<owner> - Indicates who locked this resource

The default value is: 
 DAV.pm/v$DAV::VERSION ($$)

 e.g. DAV.pm/v0.1 (123)

If you use a URL as the owner, the module will
automatically indicate to the server that is is a 
URL (<D:href>http://...</D:href>)


B<depth> - Indicates the depth of the lock. 

Legal values are 0 or Infinity. (1 is not allowed).

The default value is Infinity.

A lock value of 0 on a collection will lock just the collection but not it's members, whereas a lock value of Infinity will lock the collection and all of it's members.


B<scope> - Indicates the scope of the lock.

Legal DAV values are "exclusive" or "shared".

The default value is exclusive. 

See section 6.1 of RFC2518 for a description of shared vs. exclusive locks.


B<type> - Indicates the type of lock (read, write, etc)

The only legal DAV value currently is "write".

The default value is write.


B<timeout> - Indicates when the lock will timeout

The timeout value may be one of, an Absolute Date, a Time Offset from now, or the word "Infinity". 

The default value is "Infinity".

The following are all valid timeout values:

Time Offset:
    30s          30 seconds from now
    10m          ten minutes from now
    1h           one hour from now
    1d           tomorrow
    3M           in three months
    10y          in ten years time

Absolute Date:

    timeout at the indicated time & date (UTC/GMT)
       2000-02-31 00:40:33   

    timeout at the indicated date (UTC/GMT)
       2000-02-31            

You can use any of the Absolute Date formats specified in HTTP::Date (see perldoc HTTP::Date)

Note: the DAV server may choose to ignore your specified timeout. 


=item B<unlock>

Performs a WebDAV UNLOCK request and returns a DAV::Response object.

 $response = $resource->unlock()
 $response = $resource->unlock( -force => 1 )
 $response = $resource->unlock( 
    -token => "opaquelocktoken:1342-21423-2323" )

This method will automatically use the correct locktoken If: header if this resource was previously locked.

B<force> - Synonymous to calling $resource->forcefully_unlock_all.

=item B<forcefully_unlock_all>

Remove all locks from a resource and return the last DAV::Response object. This method take no arguments.

$response = $resource->forcefully_unlock_all;

This method will perform a lockdiscovery against the resource to determine all of the current locks. Then it will UNLOCK them one by one. unlock( -token => locktoken ). 

This unlock process is achievable because DAV does not enforce any security over locks.

Note: this method returns the LAST unlock response (this is sufficient to indicate the success of the sequence of unlocks). If an unlock fails, it will bail and return that response.  For instance, In the event that there are 3 shared locks and the second unlock method fails, then you will get returned the unsuccessful second response. The 3rd unlock will not be attempted.

Don't run with this knife, you could hurt someone (or yourself).

=item B<steal_lock>

Removes all locks from a resource, relocks it in your name and returns the DAV::Response object for the lock command. This method takes no arguments.

$response = $resource->steal_lock;

Synonymous to forcefully_unlock_all() and then lock().

=item B<lockdiscovery>

Discover the locks held against this resource and return a DAV::Response object. This method take no arguments.

 $response = $resource->lockdiscovery;
 @locks = $resource->get_locks if $response->is_success;

This method is in fact a simplified version of propfind().

=item B<as_string>

Returns a string representation of the object. Mainly useful for debugging purposes. It takes no arguments.

print $resource->as_string

=back

=head1 ACCESSOR METHODS (get, set and is)

=over 4 

=item B<is_option>

Returns a boolean indicating whether this resource supports the option passed in as a string. The option match is case insensitive so, PUT and Put are should both work.

 if ($resource->is_option( "PUT" ) ) {
    $resource->put( ... ) 
 }

Note: this routine automatically calls the options() routine which makes the request to the server. Subsequent calls to is_option will use the cached option list. To force a rerequest to the server call options()

=item B<is_locked>

Returns a boolean indicating whether this resource is locked.

  @lock = $resource->is_locked( -owned=>[0|1] );

B<owned> - this parameters is used to ask, locked by who?

Note: You must have already called propfind() or lockdiscovery()

e.g. 
Is the resource locked at all?
 print "yes" if $resource->is_locked();

Is the resource locked by me?
 print "yes" if $resource->is_locked( -owned=>1 );

Is the resource locked by someone other than me?
 print "yes" if $resource->is_locked( -owned=>0 );

=item B<is_collection>

Returns a boolean indicating whether this resource is a collection. 

 print "Directory" if ( $resource->is_collection );

You must first have performed a propfind.

=item B<get_uri>

Returns the URI object for this resource.

 print "URL is: " . $resource->get_uri()->as_string . "\n";

See the URI manpage from the LWP libraries (perldoc URI)

=item B<get_property>

Returns a property value. Takes a string as an argument.

 print $resource->get_property( "displayname" );

You must first have performed a propfind.

=item B<get_options>

Returns an array of options allowed on this resource.
Note: If $resource->options has not been called then it will return an empty array.

@options = $resource->get_options

=item B<get_content>

Returns the resource's content/body as a string.
The content is typically the result of a GET. 

$content = $resource->get_content

=item B<get_content_ref>

Returns the resource's content/body as a reference to a string.
This is useful and more efficient if the content is large.

${$resource->get_content_ref} =~ s/\bfoo\b/bar/g;

Note: You must have already called get()

=item B<get_lock>

Returns the DAV::Lock object if it exists. Requires opaquelocktoken passed as a parameter.

 $lock = $resource->get_lock( "opaquelocktoken:234214--342-3444" );

=item B<get_locks>

Returns a list of any DAV::Lock objects held against the resource.

  @lock = $resource->get_locks( -owned=>[0|1] );

B<owned> - this parameter indicates which locks you want.
 - 1, requests any of my locks. (Locked by this DAV instance).
 - 0 ,requests any locks not owned by us.
 - any other value or no value, requests ALL locks.

Note: You must have already called propfind() or lockdiscovery()

e.g. 
 Give me my locks
  @lock = $resource->get_locks( -owned=>1 );

 Give me all locks
  @lock = $resource->get_locks();

=item B<get_lockedresourcelist>

=item B<get_parentresourcelist>

=item B<get_comms>

=item B<set_parent_resourcelist>

$resource->set_parent_resourcelist( $resourcelist )

Sets the parent resource list (ask the question, which collection am I a member of?). See L<HTTP::DAV::ResourceList>.

=cut

