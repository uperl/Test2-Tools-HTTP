package Test2::Tools::HTTP::Apps;

use strict;
use warnings;
use URI;

# ABSTRACT: App container class for Test2::Tools::HTTP
# VERSION

=head1 SYNOPSIS

=head1 DESCRIPTION

This acts as a container for zero or more PSGI applications
that have been added using L<Test2::Tools::HTTP>'s
C<psgi_app_add> method.  It is used by a user agent wrapper
(L<Test2::Tools::HTTP::UA>) class to dispatch requests to
the correct PSGI app.

=head1 CONSTRUCTOR

=head2 new

 my $apps = Test2::Tools::HTTP::Apps->new;

This class is a singleton, so this always returns the same
instance.

=cut

{
  my $self;
  sub new
  {
    $self ||= bless {
      psgi     => {},
      base_url => undef,
    }, __PACKAGE__;
  }
}

=head1 METHODS

=head2 uri_key

 my $key = $apps->uri_key($url);

This function returns the URI key given a fully qualified
URL.  The key usually contains the schema, host and port
but not the path or other components of the URI.  The
actual key format is subject to change and you should not
depend on it.

=cut

sub uri_key
{
  my(undef, $uri) = @_;
  $uri = URI->new($uri) unless ref $uri;
  join ':', map { $uri->$_ } qw( scheme host port );
}

=head2 add_psgi

 $apps->add_psgi($uri, $app) = @_;

Add the given PSGI app to the container.  The URI should
specify the URL used to access the app.

=cut

sub add_psgi
{
  my($self, $uri, $app) = @_;
  my $key = $self->uri_key($uri);
  $self->{psgi}->{$key} = {
    app => $app,
  };
}

=head2 del_psgi

 $apps->del_psgi($uri);

Remove the app with the given URI from the container.

=cut

sub del_psgi
{
  my($self, $uri) = @_;
  my $key = $self->uri_key($uri);
  delete $self->{psgi}->{$key};
}

=head2 base_url

 my $url = $apps->base_url;

This is the base URL used to qualify relative URLs.
It is an instance of L<URI>.

=cut

sub base_url
{
  my($self, $new) = @_;

  if($new)
  {
    $self->{base_url} = ref $new ? $new : URI->new($new);
  }

  unless(defined $self->{base_url})
  {
    $self->{base_url} = URI->new('http://localhost/');
    require IO::Socket::INET;
    $self->{base_url}->port(IO::Socket::INET->new(Listen => 5, LocalAddr => "127.0.0.1")->sockport);
  }

  $self->{base_url};
}

=head2 uri_to_app

 my $app = $apps->uri_to_app($uri);

Given a URL (possibly relative) this function returns the
PSGI app for it.  If there are no apps registered for the
URL then it will return C<undef>.

=cut

sub uri_to_app
{
  my($self, $uri) = @_;
  my $url = URI->new_abs($uri, $self->base_url);
  my $key = $self->uri_key($url);
  $self->{psgi}->{$key}->{app};
}

=head2 uri_to_tester

 my $tester = $apps->uri_to_tester;

Same as C<uri_to-tester> except it returns the a L<Plack::Test>
wrapped around the PSGI application.

=cut

sub uri_to_tester
{
  my($self, $uri) = @_;
  my $url = URI->new_abs($uri, $self->base_url);
  my $key = $self->uri_key($url);
  my $app = $self->{psgi}->{$key}->{app};
  return unless $app;

  $self->{psgi}->{$key}->{tester} ||= do {
    require Plack::Test;
    Plack::Test->create($app);
  };
}

1;

=head1 SEE ALSO

=over 4

=item L<Test2::Tools::HTTP>

=item L<Test2::Tools::HTTP::UA>

=back

=cut
