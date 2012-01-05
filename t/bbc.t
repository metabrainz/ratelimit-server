#!/usr/bin/env perl
# vi: set ts=4 sw=4 :

use warnings;
use strict;

use Test::More tests => 2;

require_ok("RateLimitServer");

my $t = time;
{
	package MyRLS;
	use base qw/ RateLimitServer /;
	sub now { $t }
}

# TODO, "custom" things to test:
# request munging

subtest "bbc munging" => sub {
	plan tests => 1;

	my $rls = MyRLS->new;

	note $rls->process_request("over_limit ws ip=132.185.0.0");
	note $rls->process_request("over_limit ws ip=212.58.247.149");
	my $s = $rls->get_stats("ws cust=bbc");
	note $s;
	like $s, qr/\bn_req=2\b/, "bbc has two requests";
};

