package Test2::Require::Internet;

use strict;
use warnings;
use 5.012;
use IO::Socket::INET;
use parent qw( Test2::Require );

# ABSTRACT: Skip tests if there is no internet access
# VERSION

=head1 SYNOPSIS

 use Test2::V0;
 use Test2::Require::Internet;
 use HTTP::Tiny;
 
 # we are safe to use the internets
 ok(HTTP::Tiny->get('http://www.example.com')->{success});
 
 done_testing;

=head1 DESCRIPTION

This test requirement will skip your test if either

=over

=item The environment variable C<NO_NETWORK_TESTING> is set to a true value

=item A connection to a particular host/port cannot be made.  The default is usually reasonable, but subject to change as the author sees fit.

=back

This module uses the standard L<Test2::Require> interface.  Only TCP checks can be made at the moment.  Other protocols/methods may be added later.

=cut

sub skip
{
  my(undef, %args) = @_;
  return 'NO_NETWORK_TESTING' if $ENV{NO_NETWORK_TESTING};

  my @pairs = @{ $args{'-tcp'} || [ 'httpbin.org', 80 ] };
  while(@pairs)
  {
    my $host = shift @pairs;
    my $port = shift @pairs;

    my $sock = IO::Socket::INET->new(
      PeerAddr => $host,
      PeerPort => $port,
      Proto    => 'tcp',
    );

    return "Unable to connect to $host:$port/tcp" unless $sock;

    $sock->close;
  }

  undef;
}

1;

=head1 SEE ALSO

=over 4

=item L<Test::RequiresInternet>

This module provides similar functionality but does not use L<Test::Builder> or L<Test2::API>.

=back

=cut
