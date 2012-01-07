#!/usr/bin/env perl
# vi: set ts=4 sw=4 :

use warnings;
use strict;

use Test::More 0.94; # need subtest
use Test::More tests => 2;

require_ok("RateLimitServer");

my $t = time;
{
	package MyRLS;
	use base qw/ RateLimitServer /;
	sub now { $t }
}

subtest "headphones stats only" => sub {
	plan tests => 2;

	my $rls = MyRLS->new;

	for (1..100) {
		note $rls->process_request("over_limit ws ua=python-headphones/0.7.3");
		note $rls->process_request("over_limit ws ua=python-musicbrainz/0.7.3");
	}

	my $s = $rls->get_stats("ws ua=python-headphones/0.7.3");
	note $s;
	is $s, "n_req=100 n_over=0 last_max_rate=0 key=ws ua=python-headphones/0.7.3", "has 100 requests";

	$s = $rls->get_stats("ws ua=python-musicbrainz/0.7.3");
	note $s;
	is $s, "n_req=200 n_over=0 last_max_rate=0 key=ws ua=python-musicbrainz/0.7.3", "has 200 requests";
};

