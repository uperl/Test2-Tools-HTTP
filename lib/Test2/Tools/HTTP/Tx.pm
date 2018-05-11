package Test2::Tools::HTTP::Tx;

use strict;
use warnings;
use Test2::API ();

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

1;
