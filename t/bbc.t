#!/usr/bin/env perl
# vi: set ts=4 sw=4 :

use warnings;
use strict;

use Test::More tests => 2;

require_ok("RateLimitServer");

no warnings qw( redefine once );
our $t = time();
local *RateLimitServer::now = sub { $t };

# TODO, "custom" things to test:
# request munging

subtest "bbc munging" => sub {
	plan tests => 1;

	local %RateLimitServer::hash = ();

	note RateLimitServer::process_request("over_limit ws ip=132.185.0.0");
	note RateLimitServer::process_request("over_limit ws ip=212.58.247.149");
	my $s = RateLimitServer::get_stats("ws cust=bbc");
	note $s;
	like $s, qr/\bn_req=2\b/, "bbc has two requests";
};

