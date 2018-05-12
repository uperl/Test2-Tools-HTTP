package Test2::Tools::HTTP::UA;

use strict;
use warnings;
use Carp ();

# ABSTRACT: User agent wrapper for Test2::Tools::HTTP
# VERSION

sub new
{
  my($class, $ua, $apps) = @_;  
  
  if($class eq __PACKAGE__)
  {
    my $class;

    # Not all of these may be installed.
    # Not all of these may even be implemented.
    if(eval { $ua->isa('LWP::UserAgent') })
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
    elsif(eval { $ua->isa->('AnyEvent::HTTP') })
    {
      $class = 'AE';
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

sub ua
{
  shift->{ua};
}

sub apps
{
  shift->{apps};
}

1;
