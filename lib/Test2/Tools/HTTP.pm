package Test2::Tools::HTTP;

use strict;
use warnings;
use 5.008001;
use LWP::UserAgent;
use parent qw( Exporter );
use Test2::API qw( context );
use Test2::Compare;
use Test2::Compare::Wildcard;
use Test2::Compare::Custom;
use URI;
use Carp ();

our @EXPORT    = qw( 
  http_request http_ua http_base_url psgi_app_add psgi_app_del http_response http_code http_message http_content http_last http_is_success
  http_is_info http_is_success http_is_redirect http_is_error http_is_client_error http_is_server_error
  http_isnt_info http_isnt_success http_isnt_redirect http_isnt_error http_isnt_client_error http_isnt_server_error
  http_content_type http_content_type_charset http_content_length http_content_length_ok http_location http_location_uri
);

our %EXPORT_TAGS = (
  short => [qw(
    app req ua res code message content last content_type content_length content_length_ok location location_uri
  )],
);

our %EXPORT_GEN = (
  ua  => sub { \&http_ua },
  req => sub { \&http_request },
  res => sub { \&http_response },
  app => sub { \&psgi_app_add },
  map { my $name = "http_$_"; $_ => sub { \&{$name} } } qw( code message content last content_type content_length content_length_ok location location_uri ),
);

# ABSTRACT: Test HTTP / PSGI
# VERSION

=head1 SYNOPSIS

 use Test2::V0;
 use Test2::Tools::HTTP;
 use HTTP::Request::Common;
 
 psgi_add_app sub { [ 200, [ 'Content-Type' => 'text/plain;charset=utf-8' ], [ "Test Document\n" ] ] };
 
 # Internally test the app from within the .t file itself
 http_request(
   # if no host/port/protocol is given then
   # the default PSGI app above is assumed
   GET('/'),
   http_response {
 
     http_code 200;
 
     # http_response {} is a subclass of object {}
     # for HTTP::Response objects only, so you can
     # also use object {} style comparisons:
     call code => 200; 

     http_content_type match qr/^text\/(html|plain)$/;
     http_content_type_charset 'UTF-8';
     http_content match qr/Test/;
   }
 );

 use Test2::Tools::JSON::Pointer;
 
 # test an external website
 http_request(
   GET('http://example.test'),
   http_response {
     http_is_success;
     # JSON pointer { "key":"val" }
     http_content json '/key' => 'val';
   }
 );
 
 done_testing;

with short names:

 use Importer 'Test2::Tools::HTTP' => ':short';
 use HTTP::Request::Common;
 
 app { [ 200, [ 'Content-Type => 'text/plain' ], [ "Test Document\n" ] ] };
 
 req {
   GET('/'),
   res {
     code 200;
     message 'OK';
     content_type 'text/plain';
     content match qr/Test/;
   },
 };
 
 done_testing;

=head1 DESCRIPTION

This module provides an interface for testing websites and PSGI based apps with a L<Test2> style comparisons interface.
By default it uses long function names with either a C<http_> or C<psgi_app> prefix.  The intent is to make the module
usable when you are importing lots of symbols from lots of different modules while reducing the chance of collisions.
You can instead import C<:short> which will give you the most commonly used tools with short names.  The short names
are indicated below in square brackets, and were picked to not conflict with L<Test2::V0>.

=head1 FUNCTIONS

=head2 http_request [req]

 http_request($request);
 http_request($request, $check);
 http_request($request, $check, $message);
 http_request([$request, %options], ... );

Make a HTTP request.  If there is a client level error then it will fail immediately.  Otherwise you can use a
C<object {}> or C<http_request> comparison check to inspect the HTTP response and ensure that it matches what you
expect.  By default only one request is made.  If the response is a forward (has a C<Location> header) you can
use the C<http_last->location> method to make the next request.

Otions:

=over 4

=item follow_redirects

This allows the user agent to follow rediects.

=back

=cut

my %psgi;
my $last;

sub http_request
{
  my($req, $check, $message) = @_;

  my %options;

  if(ref $req eq 'ARRAY')
  {
    ($req, %options) = @$req;
  }

  $req = $req->clone;

  my $url = URI->new_abs($req->uri, http_base_url());

  $message ||= "@{[ $req->method ]} @{[ $url ]}";

  my $ctx = context();
  my $ok = 1;
  my @diag;
  my $connection_error = 0;

  if($req->uri =~ /^\//)
  {
    $req->uri(
      URI->new_abs($req->uri, http_base_url())->as_string
    );
  }
  
  my $request_method = $options{follow_redirects} ? 'request' : 'simple_request';

  my $res = http_ua()->$request_method($req);

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

  $last = bless {
    req              => $req,
    res              => $res,
    ok               => $ok,
    connection_error => $connection_error,
    location         => do {
      $res->header('Location')
        ? URI->new_abs($res->header('Location'), $res->base)
        : undef;
    },
  }, 'Test2::Tools::HTTP::Last';

  $ok;
}

=head2 http_response [res]

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

=head3 http_code [code]

 http_response {
   http_code $check;
 };

The HTTP status code should match the given check.

=cut

sub _caller
{
  my $i = 1;
  my @caller;
  while(@caller = caller $i)
  {
    last if $caller[0] ne __PACKAGE__;
    $i++;
  }
  @caller;
}

sub _build
{
  defined(my $build = Test2::Compare::get_build()) or Carp::croak "No current build!";
  Carp::croak "'$build' is not a Test2::Tools::HTTP::ResponseCompare"
    unless $build->isa('Test2::Tools::HTTP::ResponseCompare');

  my @caller = _caller;

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

=head3 http_message [message]

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

=head3 http_content [content]

 http_response {
   http_content $check;
 };

The response body content.  Attempt to decode using the L<HTTP::Message> method C<decoded_content>, otherwise use the raw
response body.  If you want specifically the decoded content or the raw content you can use C<call> to specifically check
against them:

 http_response {
   call content => $check1;
   call decoded_content => $check2;
 };

=cut

sub http_content ($)
{
  my($expect) = @_;
  #_add_call('decoded_content', $expect);
  my($build, @cmpargs) = _build;
  $build->add_http_check(
    sub {
      my($res) = @_;
      ($res->decoded_content || $res->content, 1);
    },
    [DREF => 'content'],
    Test2::Compare::Wildcard->new(
      expect => $expect,
      @cmpargs,
    )
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

sub _T()
{
  my @caller = _caller;
  Test2::Compare::Custom->new(
    code     => sub { $_ ? 1 : 0 },
    name     => 'TRUE',
    operator => 'TRUE()',
    file     => $caller[1],
    lines    => [$caller[2]],
  );
}

sub http_is_info         { _add_call('is_info',         _T()) }
sub http_is_success      { _add_call('is_success',      _T()) }
sub http_is_redirect     { _add_call('is_redirect',     _T()) }
sub http_is_error        { _add_call('is_error',        _T()) }
sub http_is_client_error { _add_call('is_client_error', _T()) }
sub http_is_server_error { _add_call('is_server_error', _T()) }

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

sub _F()
{
  my @caller = _caller;
  Test2::Compare::Custom->new(
    code     => sub { $_ ? 0 : 1 },
    name     => 'TRUE',
    operator => 'TRUE()',
    file     => $caller[1],
    lines    => [$caller[2]],
  );
}

sub http_isnt_info         { _add_call('is_info',         _F()) }
sub http_isnt_success      { _add_call('is_success',      _F()) }
sub http_isnt_redirect     { _add_call('is_redirect',     _F()) }
sub http_isnt_error        { _add_call('is_error',        _F()) }
sub http_isnt_client_error { _add_call('is_client_error', _F()) }
sub http_isnt_server_error { _add_call('is_server_error', _F()) }

=head3 http_content_type [content_type], http_content_type_charset 

 http_response {
   http_content_type $check;
   http_content_type_charset $check;
 };

Check that the C<Content-Type> header matches the given checks.  C<http_content_type> checks just the content type, not the character set, and
C<http_content_type_charset> matches just the character set.  Hence:

 http_response {
   http_content_type 'text/html';
   http_content_type_charset 'UTF-8';
 };

=cut

sub http_content_type
{
  my($check) = @_;
  _add_call('content_type', $check);
}

sub http_content_type_charset
{
  my($check) = @_;
  _add_call('content_type_charset', $check);
}

# TODO: header $key => $check
# TODO: cookie $key => $check ??

=head3 http_content_length [content_length]

 http_response {
   http_content_length $check;
 };

Check that the C<Content-Length> header matches the given check.

=cut

sub http_content_length
{
  my($check) = @_;
  _add_call('content_length', $check);
}

=head3 http_content_length_ok [content_length_ok]

 http_response {
   http_content_length_ok;
 };

Checks that the C<Content-Length> header matches the actual length of the content.

=cut

sub http_content_length_ok
{
  my($build, @cmpargs) = _build;

  $build->add_http_check(
    sub {
      my($res) = @_;

      (
        $res->content_length,
        1,
        Test2::Compare::Wildcard->new(
          expect => length($res->content),
          @cmpargs,
        ),
      )
    },
    [METHOD => 'content_length'],
    undef,
  );


}

=head3 http_location [location], http_location_uri [location_uri]

 http_response {
   http_location $check;
   http_location_uri $check;
 };

Check the C<Location> HTTP header.  The C<http_location_uri> variant converts C<Location> to a L<URI> using the base URL of the response
so that it can be tested with L<Test2::Tools::URL>.

=cut

sub http_location
{
  my($expect) = @_;
  my($build, @cmpargs) = _build;
  $build->add_http_check(
    sub {
      my($res) = @_;
      my $location = $res->header('Location');
      (
        $location,
        defined $location
      )
    },
    [DEREF => "header('Location')"],
    Test2::Compare::Wildcard->new(
      expect => $expect,
      @cmpargs,
    ),    
  );
}

sub http_location_uri
{
  my($expect) = @_;
  my($build, @cmpargs) = _build;
  $build->add_http_check(
    sub {
      my($res) = @_;
      my $location = $res->header('Location');
      defined $location
        ? (URI->new_abs($location, $res->base), 1)
        : (undef, 0);
    },
    [DEREF => "header('Location')"],
    Test2::Compare::Wildcard->new(
      expect => $expect,
      @cmpargs,
    ),    
  );
}

=head2 http_last [last]

 my $req  = http_last->req;
 my $res  = http_last->res;
 my $bool = http_last->ok;
 my $bool = http_last->connection_error;
 my $url  = http_last->location;
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

=item http_last->location

The C<Location> header converted to an absolute URL, if included in the response.

=item http_last->note

Send the request, response and ok to Test2's "note" output.  Note that the message bodies may be decoded, but
the headers will not be modified.

=item http_last->diag

Send the request, response and ok to Test2's "diag" output.  Note that the message bodies may be decoded, but
the headers will not be modified.

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

=head2 http_ua [ua]

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

  unless($ua->can('test2_tools_http'))
  {
    require Object::Extend;
    my $original_ref = ref($ua);
    Object::Extend::extend($ua,
      test2_tools_http => sub { 1 },
      simple_request   => sub {
        my($self, $req, $arg, $size) = @_;

        my $url = URI->new_abs($req->uri, http_base_url());
        my $key = _uri_key($url);

        if(my $tester = $psgi{$key})
        {
          # TODO: is it worth implementing this?
          die "simple_request method with more than one argument not supported" if defined $arg || defined $size;;
          return $tester->request($req);
        }
        else
        {
          return $original_ref->can('simple_request')->(@_);
        }
      },
    );
  }

  $ua;
}

=head2 psgi_app_add [app]

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

sub location { shift->{location} }

sub _note_or_diag
{
  my($self, $method) = @_;
  my $ctx = Test2::API::context();

  $ctx->$method($self->req->method . ' ' . $self->req->uri);
  $ctx->$method($self->req->headers->as_string);
  $ctx->$method($self->req->decoded_content || $self->req->content);
  $ctx->$method($self->res->code . ' ' . $self->res->message);
  $ctx->$method($self->res->headers->as_string);
  $ctx->$method($self->res->decoded_content || $self->res->content);
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

    my($val, $exists, $alt_check) = eval { $cb->($got) };
    my $error = $@;

    $check = $alt_check if defined $alt_check;

    $check = $convert->($check);

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
        $exists ? ( got => $val eq '' ? '[empty string]' : $val ) : (),
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
