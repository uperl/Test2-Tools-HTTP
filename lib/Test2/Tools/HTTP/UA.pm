package Test2::Tools::HTTP::UA;

use strict;
use warnings;
use Carp ();

# ABSTRACT: User agent wrapper for Test2::Tools::HTTP
# VERSION

=head1 SYNOPSIS

 package Test2::Tools::HTTP::UA::MyUAWrapper;
 
 use parent 'Test2::Tools::HTTP::UA';
 
 sub instrument
 {
   my($self) = @_;
   my $ua = $self->ua;  # the user agent object
   my $apps = $self->apps;

   # instrument $ua so that when requests
   # made against URLs in $apps the responses
   # come from the apps in $apps.
   ...
 }
 
 sub request
 {
   my $self = shift;
   my $req  = shift;   # this isa HTTP::Request
   my %options = @_;
   
   my $self = $self->ua;
   my $res;
   
   if($options{follow_redirects})
   {
     # make a request using $ua, store
     # result in $res isa HTTP::Response
     # follow any redirects if $ua supports
     # that.
     my $res = eval { ... };
     
     # on a CONNECTION error, you should throw
     # an exception using $self->error.  This should
     # NOT be used for 400 or 500 responses that
     # actually come from the remote server or
     # PSGI app.
     if(my $error = $@)
     {
       $self->error(
        "connection error: " . ($res->decoded_content || $warning),
       );
     }
   }
   else
   {
     # same as the previous block, but should
     # NOT follow any redirects.
     ...
   }
   
   $res;
 }

=head1 DESCRIPTION

This is the base class for user agent wrappers used
by L<Test2::Tools::HTTP>.  The idea is to allow the
latter to work with multiple user agent classes
without having to change the way your C<.t> file
interacts with L<Test2::Tools::HTTP>.  By default
L<Test2::Tools::HTTP> uses L<LWP::UserAgent> and
in turn uses L<Test2::Tools::HTTP::UA::LWP> as its
user agent wrapper.

=cut

sub new
{
  my($class, $ua, $apps) = @_;  
  
  if($class eq __PACKAGE__)
  {
    my $class;

    # Not all of these may be installed.
    # Not all of these may even be implemented.
    if(ref($ua) eq '' && defined $ua)
    {
      if($ua eq 'AnyEvent::HTTP')
      {
        $class = 'AE';
      }
    }
    elsif(eval { $ua->isa('LWP::UserAgent') })
    {
      $class = 'LWP';
    }
    elsif(eval { $ua->isa('HTTP::Tiny') })
    {
      $class = 'HTTPTiny';
    }
    elsif(eval { $ua->isa('Mojo::UserAgent') })
    {
      $class = 'Mojo';
    }
    elsif(eval { $ua->isa('Net::Async::HTTP') })
    {
      $class = 'NetAsyncHTTP';
    }
    
    if(defined $class)
    {
      $class = "Test2::Tools::HTTP::UA::$class";
      my $pm = $class;
      $pm =~ s/::/\//g;
      $pm .= ".pm";
      require $pm;
      return $class->new($ua, $apps);
    }
    else
    {
      Carp::croak("user agent @{[ ref $ua ]} not supported ");
    }
  }
  
  bless {
    ua   => $ua,
    apps => $apps,
  }, $class;
}

=head1 METHODS

=head2 ua

 my $ua = $wrapper->ua;

Returns the actual user agent object.  This could be I<any>
user agent object, such as a L<LWP::UserAgent>, L<HTTP::Simple>,
or L<Mojo::UserAgent>, but generally your wrapper only needs
to support ONE user agent class.

=cut

sub ua
{
  shift->{ua};
}

=head2 apps

 my $apps = $wrapper->apps;

This returns an instance of L<Test2::Tools::HTTP::Apps> used
by your wrapper.  It can be used to lookup PSGI apps by
url.

=cut

sub apps
{
  shift->{apps};
}

=head2 error

 $wrapper->error($message);
 $wrapper->error($message, $response);

This throws an exception that L<Test2::Tools::HTTP> understands
to be a connection error.  This is the preferred way to handle
a connection error from within your C<request> method.

The second argument is an optional instance of L<HTTP::Response>.
In the event of a connection error, you won't have a response object
from the actual remote server or PSGI application.  Some user agents
(such as L<LWP::UserAgent>) produce a synthetic response object.
You can stick it here for diagnostic purposes.  You should NOT
create your own synthetic response object though, only use this
argument if your user agent produces a faux response object.

=cut

sub error
{
  my(undef, $message, $res) = @_;
  my $error = bless { message => $message, res => $res }, 'Test2::Tools::HTTP::UA::Error';
  die $error;
}

package Test2::Tools::HTTP::UA::Error;

use overload '""' => sub { shift->as_string };

sub message { shift->{message} }
sub res { shift->{res} }
sub as_string { shift->message }

1;

=head1 SEE ALSO

=over 4

=item L<Test2::Tools::HTTP>

=back
