=over 4

=item *

B<dave -- the new command line client>

I wrote dave (the DAV Explorer) because I needed an end-user application that allowed me to "feel" how well the HTTP::DAV API was performing. dave is quite similar to Joe Orton's C-based DAV client called cadaver (yes, imitation is the best form of flattery).

=item *

B<A new and simpler API>

This new API is accessed directly through the HTTP::DAV module and is based on the core API written in previous releases. 


=item * 

B<new methods>

The new API now supports, proppatch, recursive get and put.

=item *

B<A substantial core API overhaul>

Moving from v0.05 to v0.22 in one release might indicate the amount of work gone into this release.

=item *

B<A new interoperability test suite>

is now included in PerlDAV. The test suite is built on top of the standard Perl Test::Harness modules. Still in development, the test suite is highlighting interoperability problems with DAV-servers a lot quicker than before. See L<the test suite & interoperability> section.

=back
