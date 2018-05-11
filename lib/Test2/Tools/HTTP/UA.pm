package Test2::Tools::HTTP::UA;

use strict;
use warnings;

# ABSTRACT: User agent wrapper for Test2::Tools::HTTP
# VERSION

sub new
{
  my($class, $ua, $apps) = @_;  
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
