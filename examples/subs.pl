
sub handler {
   my ($resp, $resource, $message, $verbose) = @_;

   if ($resp->is_success) {
      print "$message succeeded (" . $resp->code . ")\n";
      print $resource->as_string if $verbose;
   } else {
      print "$message failed\n";
      print $resource->as_string if $verbose;
      print $resp->as_string if $verbose;
   }
}

1;
