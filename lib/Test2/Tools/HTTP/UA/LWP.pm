package Test2::Tools::HTTP::UA::LWP;

use strict;
use warnings;
use Object::Extend qw( extend );
use parent 'Test2::Tools::HTTP::UA';

# ABSTRACT: LWP user agent wrapper for Test2::Tools::HTTP
# VERSION

sub instrument
{
  my($self) = @_;
  
  unless($self->ua->can('test2_tools_http'))
  {
    require Object::Extend;
    my $original_ref = ref($self->ua);
    extend($self->ua,
      test2_tools_http => sub { 1 },
      simple_request   => sub {
        my($self, $req, $arg, $size) = @_;

        my $url = URI->new_abs($req->uri, __PACKAGE__->base_url());
        my $key = __PACKAGE__->uri_key($url);

        if(my $tester = __PACKAGE__->psgi->{$key})
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
}

sub request
{
  my($self, $req, %options) = @_;
  $options{follor_redirects}
    ? $self->ua->request($req)
    : $self->ua->simple_request($req);
}

1;
