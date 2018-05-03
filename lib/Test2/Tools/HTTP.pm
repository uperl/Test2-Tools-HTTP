package Test2::Tools::HTTP;

use strict;
use warnings;
use 5.008001;
use LWP::UserAgent;
use parent qw( Exporter );
use Test2::API qw( context );
use Test2::Compare;
use Test2::Compare::Wildcard;
use Test2::Tools::Compare ();
use JSON::MaybeXS qw( decode_json );
use JSON::Pointer;
use URI;
use Carp ();

our @EXPORT    = qw( 
  http_request http_ua http_base_url psgi_app_add psgi_app_del http_response http_code http_message http_content http_json http_last http_is_success
  http_is_info http_is_success http_is_redirect http_is_error http_is_client_error http_is_server_error
  http_isnt_info http_isnt_success http_isnt_redirect http_isnt_error http_isnt_client_error http_isnt_server_error
);
our @EXPORT_OK = (@EXPORT);

# ABSTRACT: Test HTTP / PSGI
# VERSION

=head1 SYNOPSIS

 use Test2::V0;
 use Test2::Tools::HTTP;
 use HTTP::Request::Common;
 
 psgi_add_app sub { [ 200, [ 'Content-Type' => 'text/plain;charset=utf-8' ], [ 'Test Document' ] ] };
 
 # Internally test the app from within the .t file itself
 http_request(
   # if no host/port/protocol is given then
   # the default PSGI app above is assumed
   GET('/'),
   http_response {
 
     http_code '200';
 
     # http_response {} is a subclass of object {}
     # for HTTP::Response objects only, so you can
     # also use object {} style comparisons:
     call code => 200; 

     http_content_type match qr/plain$/;
     http_content_type_charset 'utf-8';
     http_content qr/Test/;
   }
 );
 
 # test an external website
 http_request(
   GET('http://httpbin.org'),
   http_response {
     http_is_success;
     # JSON pointer
     http_json '/method' => 'GET';
   }
 );
 
 done_testing;

=head1 DESCRIPTION

This module provides an interface for testing websites and PSGI based apps with a L<Test2> style comparisons interface.

=head1 FUNCTIONS

=head2 http_request

 http_request($request);
 http_request($request, $check);
 http_request($request, $check, $message);

Make a HTTP request.  If there is a client level error then it will fail immediately.  Otherwise you can use a
C<object {}> or C<http_request> comparison check to inspect the HTTP response and ensure that it matches what you
expect.

=cut

my %psgi;
my $last;

sub http_request
{
  my($req, $check, $message) = @_;

  $req = $req->clone;

  my $url = URI->new_abs($req->uri, http_base_url());
  my $key = _uri_key($url);

  $message ||= "@{[ $req->method ]} @{[ $url ]}";

  my $ctx = context();
  my $ok = 1;
  my @diag;
  my $res;
  my $connection_error = 0;

  if(my $tester = $psgi{$key})
  {
    $res = $tester->request($req);
  }
  else
  {
    if($req->uri =~ /^\//)
    {
      $req->uri(
        URI->new_abs($req->uri, http_base_url())->as_string
      );
    }
    $res = http_ua()->simple_request($req);
  }

  if(my $warning = $res->header('Client-Warning'))
  {
    $ok = 0;
    $connection_error = 1;
    push @diag, "connection error: " . ($res->decoded_content || $warning);
  }

  if($ok && defined $check)
  {
    my $delta = Test2::Compare::compare($res, $check, \&Test2::Compare::strict_convert);
    if($delta)
    {
      $ok = 0;
      push @diag, $delta->diag;
    }
  }

  $ctx->ok($ok, $message, \@diag);
  $ctx->release;

  $last = bless { req => $req, res => $res, ok => $ok, connection_error => $connection_error }, 'Test2::Tools::HTTP::Last';
  
  $ok;
}

=head2 http_response

 my $check = http_response {
   ... # object or http checks
 };

This is a comparison check specific to HTTP::Response objects.  You may include these subchecks:

=cut

sub http_response (&)
{
  Test2::Compare::build(
    'Test2::Tools::HTTP::ResponseCompare',
    @_,
  );
}

=head3 http_code

 http_response {
   http_code $check;
 };

The HTTP status code should match the given check.

=cut

sub _build
{
  defined(my $build = Test2::Compare::get_build()) or Carp::croak "No current build!";
  Carp::croak "'$build' is not a Test2::Tools::HTTP::ResponseCompare"
    unless $build->isa('Test2::Tools::HTTP::ResponseCompare');

  my $i = 1;
  my @caller;
  while(@caller = caller $i)
  {
    last if $caller[0] ne __PACKAGE__;
    $i++;
  }

  my $func_name = $caller[3];
  $func_name =~ s/^.*:://;
  Carp::croak "'$func_name' should only ever be called in void context"
    if defined $caller[5];

  ($build, file => $caller[1], lines => [$caller[2]]);
}

sub _add_call
{
  my($name, $expect, $context) = @_;
  $context ||= 'scalar';
  my($build, @cmpargs) = _build;
  $build->add_call(
    $name,
    Test2::Compare::Wildcard->new(
      expect => $expect,
      @cmpargs,
    ),
    undef,
    $context
  );
}

sub http_code ($)
{
  my($expect) = @_;
  _add_call('code', $expect);
}

=head3 http_message

 http_response {
   http_message $check;
 };

The HTTP status message ('OK' for 200, 'Not Found' for 404, etc) should match the given check.

=cut

sub http_message ($)
{
  my($expect) = @_;
  _add_call('message', $expect);
}

=head3 http_content

 http_response {
   http_content $check;
 };

The decoded response body content.  This is the I<decoded> content, as for most application testing this is what you will be interested in.
If you want to test the undecoded content you can use call instead:

 http_response {
   call content => $check;
 };

=cut

sub http_content ($)
{
  my($expect) = @_;
  _add_call('decoded_content', $expect);
}

=head3 http_json

 http_response {
   http_json $json_pointer, $check;
   http_json $check;
 };

This matches the value at the given JSON pointer with the given check.  If C<$json_pointer> is omitted, then the comparison is made against the
whole JSON response.

=cut

sub http_json
{
  my($pointer, $expect) = @_ == 1 ? ('', $_[0]) : (@_);
  my($build, @cmpargs) = _build;
  $build->add_http_check(
    sub {
      my($res) = @_;
      
      my $object = eval {
        decode_json($res->decoded_content)
      };
      if(my $error = $@)
      {
        # this is terrible!
        $error =~ s/ at \S+ line [0-9]+\.//;
        die "error decoding JSON: $error\n";
      }
      (
        JSON::Pointer->get($object, $pointer),
        JSON::Pointer->contains($object, $pointer),
      )
    },
    [DEREF => $pointer eq '' ? 'json' : "json $pointer"],
    Test2::Compare::Wildcard->new(
      expect => $expect,
      @cmpargs,
    ),
  );
}

=head3 http_is_info, http_is_success, http_is_redirect, http_is_error, http_is_client_error, http_is_server_error

 http_response {
   http_is_info;
   http_is_success;
   http_is_redirect;
   http_is_error;
   http_is_client_error;
   http_is_server_error;
 };

Checks that the response is of the specified type.  See L<HTTP::Status> for the meaning of each of these.

=cut

sub http_is_info         { _add_call('is_info',         Test2::Tools::Compare::T()) }
sub http_is_success      { _add_call('is_success',      Test2::Tools::Compare::T()) }
sub http_is_redirect     { _add_call('is_redirect',     Test2::Tools::Compare::T()) }
sub http_is_error        { _add_call('is_error',        Test2::Tools::Compare::T()) }
sub http_is_client_error { _add_call('is_client_error', Test2::Tools::Compare::T()) }
sub http_is_server_error { _add_call('is_server_error', Test2::Tools::Compare::T()) }

=head3 http_isnt_info, http_isnt_success, http_isnt_redirect, http_isnt_error, http_isnt_client_error, http_isnt_server_error

 http_response {
   http_isnt_info;
   http_isnt_success;
   http_isnt_redirect;
   http_isnt_error;
   http_isnt_client_error;
   http_isnt_server_error;
 };

Checks that the response is NOT of the specified type.  See L<HTTP::Status> for the meaning of each of these.

=cut

sub http_isnt_info         { _add_call('is_info',         Test2::Tools::Compare::F()) }
sub http_isnt_success      { _add_call('is_success',      Test2::Tools::Compare::F()) }
sub http_isnt_redirect     { _add_call('is_redirect',     Test2::Tools::Compare::F()) }
sub http_isnt_error        { _add_call('is_error',        Test2::Tools::Compare::F()) }
sub http_isnt_client_error { _add_call('is_client_error', Test2::Tools::Compare::F()) }
sub http_isnt_server_error { _add_call('is_server_error', Test2::Tools::Compare::F()) }

# TODO: content_type, content_type_charset, content_length, content_length_ok, location
# TODO: header $key => $check
# TODO: cookie $key => $check ??

=head2 http_last

 my $req  = http_last->req;
 my $res  = http_last->res;
 my $bool = http_last->ok;
 my $bool = http_last->connection_error;
 http_last->note;
 http_last->diag;

This returns the last transaction object, which you can use to get the last request, response and status information
related to the last C<http_request>.

=over 4

=item http_last->req

The L<HTTP::Request> object.

=item http_last->res

The L<HTTP::Response> object.

Warning: In the case of a connection error, this may be a synthetic response produced by L<LWP::UserAgent>, rather
than an actual message from the remote end.

=item http_last->ok

True if the last call to C<http_request> passed.

=item http_last->connection_error.

True if there was a connection error during the last C<http_request>.

=item http_last->note

Send the request, response and ok to Test2's "note" output.

=item http_last->diag

Send the request, response and ok to Test2's "diag" output.

=back

=cut

sub http_last
{
  $last;
}

=head2 http_base_url

 http_base_url($url);
 my $url = http_base_url;

Sets the base URL for all requests made by C<http_request>.  This is used if you do not provide a fully qualified URL.  For example:

 http_base_url 'http://httpbin.org';
 http_request(
   GET('/status/200') # actually makes a request against http://httpbin.org
 );

If you use C<psgi_add_app> without a URL, then this is the URL which will be used to access your app.  If you do not specify a base URL,
then localhost with a random unused port will be picked.

=cut

my $base_url;

sub http_base_url
{
  my($new) = @_;

  if($new)
  {
    $base_url = ref $new ? $new : URI->new($new);
  }
  
  unless(defined $base_url)
  {
    $base_url = URI->new('http://localhost/');
    require IO::Socket::INET;
    $base_url->port(IO::Socket::INET->new(Listen => 5, LocalAddr => "127.0.0.1")->sockport);
  }

  $base_url;
}

=head2 http_ua

 http_ua(LWP::UserAgent->new);
 my $ua = http_ua;

Gets/sets the L<LWP::UserAgent> object used to make requests against real web servers.  For tests against a PSGI app, this will NOT be used.
If not provided, the default L<LWP::UserAgent> will call C<env_proxy> and add an in-memory cookie jar.

=cut

my $ua;

sub http_ua
{
  my($new) = @_;

  $ua = $new if $new;

  unless(defined $ua)
  {
    $ua = LWP::UserAgent->new;
    $ua->env_proxy;
    $ua->cookie_jar({});
  }

  $ua;
}

=head2 psgi_app_add

 psgi_app_add $app;
 psgi_app_add $url, $app;

Add the given PSGI app to the testing environment.  If you provide a URL, then requests to that URL will be intercepted by C<http_request> and routed to the app
instead of making a real HTTP request via L<LWP::UserAgent>.

=cut

sub _uri_key
{
  my($uri) = @_;
  $uri = URI->new($uri) unless ref $uri;
  join ':', map { $uri->$_ } qw( scheme host port );
}

sub psgi_app_add
{
  my($url, $app) = @_ == 1 ? (http_base_url, @_) : (@_);
  require Plack::Test;
  my $key = _uri_key $url;
  $psgi{$key} = Plack::Test->create($app);
  return;
}

=head2 psgi_app_del

 psgi_app_del;
 psgi_app_del $url;

Remove the app at the given (or default) URL.

=cut

sub psgi_app_del
{
  my($url) = @_;
  $url ||= http_base_url;
  my $key = _uri_key $url;
  delete $psgi{$key};
  return;
}

package Test2::Tools::HTTP::Last;

sub req { shift->{req} }
sub res { shift->{res} }
sub ok  { shift->{ok}  }
sub connection_error { shift->{connection_error} }

sub _note_or_diag
{
  my($self, $method) = @_;
  my $ctx = Test2::API::context();

  $ctx->$method($self->req->as_string);

  if(length $self->res->content > 200)
  {
    $ctx->$method($self->res->headers->as_string . "[large body removed]");
  }
  else
  {
    $ctx->$method($self->res->as_string);
  }

  $ctx->$method("ok = " . $self->ok);
  
  $ctx->release;
}

sub note
{
  my($self) = shift;
  my $ctx = Test2::API::context();
  $self->_note_or_diag('note');
  $ctx->release;
}

sub diag
{
  my($self) = shift;
  my $ctx = Test2::API::context();
  $self->_note_or_diag('diag');
  $ctx->release;
}

package Test2::Tools::HTTP::ResponseCompare;

use parent 'Test2::Compare::Object';

sub name { '<HTTP::Response>' }
sub object_base { 'HTTP::Response' }

sub init
{
  my($self) = @_;
  $self->{HTTP_CHECK} ||= [];
  $self->SUPER::init();
}

sub add_http_check
{
  my($self, $cb, $id, $expect) = @_;

  push @{ $self->{HTTP_CHECK} }, [ $cb, $id, $expect ];
}

sub deltas
{
  my $self = shift;
  my @deltas = $self->SUPER::deltas(@_);
  my %params = @_;

  my ($got, $convert, $seen) = @params{qw/got convert seen/};

  foreach my $pair (@{ $self->{HTTP_CHECK} })
  {
    my($cb, $id, $check) = @$pair;

    $check = $convert->($check);

    my($val, $exists) = eval { $cb->($got) };
    my $error = $@;

    if($error)
    {
      push @deltas => $self->delta_class->new(
        verified  => undef,
        id        => $id,
        got       => undef,
        check     => $check,
        exception => $error,
      );
    }
    else
    {
      push @deltas => $check->run(
        id      => $id,
        convert => $convert,
        seen    => $seen,
        exists  => $exists,
        $exists ? ( got => $val) : (),
      );
    }
  }

  @deltas;
}

1;

=head1 SEE ALSO

=over 4

=item L<Test::Mojo>

This is a very capable web application testing module.  Definitely worth checking out, even if you aren't developing a L<Mojolicious> app since it can be used
(with L<Test::Mojo::Role::PSGI>) to test any PSGI application.

=back

=cut
