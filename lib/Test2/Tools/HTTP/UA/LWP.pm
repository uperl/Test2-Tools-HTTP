package Test2::Tools::HTTP::UA::LWP;

use strict;
use warnings;
use 5.014;
use URI;
use parent 'Test2::Tools::HTTP::UA';

# ABSTRACT: LWP user agent wrapper for Test2::Tools::HTTP
# VERSION

=head1 SYNOPSIS

 use Test2::Tools::HTTP;
 use LWP::UserAgent;
 
 psgi_app_add 'http://example.test' => sub { ... };
 
 my $ua = LWP::UserAgent->new;
 http_ua $ua;
 
 my $res = $ua->get('http://example.test');

=head1 DESCRIPTION

This class is not intended to be used directly.

This module provides the machinery for instrumenting
L<LWP::UserAgent> for use with L<Test2::Tools::HTTP>.
Since L<LWP::UserAgent> is the default user agent for
L<Test2::Tools::HTTP>, this is the default user agent
wrapper as well.  It is a subclass of
L<Test2::Tools::HTTP::UA>.

=head1 SEE ALSO

=over 4

=item L<Test2::Tools::HTTP>

=item L<Test2::Tools::HTTP::UA::LWPClass>

=back

=cut

sub instrument
{
  my($self) = @_;

  my $cb = $self->{request_send_cb} ||= sub {
    my($req, $ua, $h) = @_;

    if(my $tester = $self->apps->uri_to_tester($req->uri))
    {
      return $tester->request($req);
    }
    else
    {
      return;
    }
  };

  $self->ua->set_my_handler( 'request_send' => $cb );
}

sub request
{
  my($self, $req, %options) = @_;

  if($self->apps->uri_to_app($req->uri) && $req->uri =~ /^\//)
  {
    $req->uri(
      URI->new_abs($req->uri, $self->apps->base_url),
    );
  }

  my $res = $options{follow_redirects}
    ? $self->ua->request($req)
    : $self->ua->simple_request($req);

  if(my $warning = $res->header('Client-Warning'))
  {
    $self->error(
      "connection error: " . ($res->decoded_content || $warning),
      $res,
    );
  }

  $res;
}

__PACKAGE__->register('LWP::UserAgent', 'instance');

1;
