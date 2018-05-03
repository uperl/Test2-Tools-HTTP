# Test2::Tools::HTTP [![Build Status](https://secure.travis-ci.org/plicease/Test2-Tools-HTTP.png)](http://travis-ci.org/plicease/Test2-Tools-HTTP)

Test HTTP / PSGI

# FUNCTIONS

## http\_request

    http_request($request, $check, $message);

## http\_response

    my $check = http_response {
      ... # object or http checks
    };

## http\_code

## http\_message

## http\_content

## http\_json

## http\_is\_success

## http\_last

## http\_base\_url

    http_base_url($url);
    my $url = http_base_url;

## http\_ua

    http_ua(LWP::UserAgent->new);
    my $ua = http_ua;

## psgi\_app\_add

    psgi_app_add $app;
    psgi_app_add $url, $app;

## psgi\_app\_del

    psgi_app_del;
    psgi_app_del $url;

# AUTHOR

Graham Ollis <plicease@cpan.org>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2018 by Graham Ollis.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
