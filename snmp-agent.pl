#!/usr/bin/perl
# vi: set ts=4 sw=4 :

use warnings;
use strict;

use FindBin;
use lib "$FindBin::Bin/lib";

use MusicBrainz::Server::RateLimitClient;
use SNMPAgentUtil;

# exec "sudo", "-u", "exim", $0, @ARGV unless getpwnam($<) eq "exim";
# pass_persist .1.3.6.1.4.1.1532281856.1 /usr/local/bin/linux26-diskstats-agent

if ("@ARGV" eq "dump")
{
	my @r;
	sub M::set_responses { shift; @r = @_; }
	prepare_responses("M");
	while (@r)
	{
		my ($oid, $type, $value) = splice(@r, 0, 3);
		printf "$oid\t$type\t$value\n";
	}
	exit;
}

require SNMPAgentUtil;

SNMPAgentUtil->run(
	# log_to => "/dev/tty",
	# log_to => "/tmp/exim_snmp_agent.log",
	# get => \&get,
	# get_next => \&get_next,
	prepare_responses => \&prepare_responses,
);

{
    my $expire = time;

    sub prepare_responses
    {
        my ($self) = @_;

        return if defined($expire) and time() < $expire;

        my @responses;

	# .1.3.6.1.4.1.1532281856 = fake djce enterprise
	#	.77 = ratelimit-server stats
	#	  .1.X = name (string)
	#	  .2.X = keys (gauge)
	#	  .3.X = key hash ratio (0-100) (gauge)
	#	  .4.1.X = instance ID (integer)
	#	  .4.2.X = key (string)
	#	  .4.3.X = requests (counter)
	#	  .4.4.X = refusals (counter)
	#	  .4.5.X = last max rate (gauge)

	my $base = ".1.3.6.1.4.1.1532281856.77";

	my $instance_num = 0;
	my $key_num = 0;

	my $do = sub {
		my ($name, $addr, $port, $keys) = @_;
		++$instance_num;

		push @responses, "$base.1.$instance_num", "string", $name;

		{
			my $t = MusicBrainz::Server::RateLimitClient->query("get_size", "${addr}:${port}")
				or last;
			$t =~ m[\bkeys=(\d+)]
				and push @responses, "$base.2.$instance_num", "gauge", $1;
			$t =~ m[\bsize=(\d+)\/(\d+)]
				and push @responses, "$base.3.$instance_num", "gauge", int(0.5 + 100*$1/$2);
		}

		for my $key (@$keys)
		{
			++$key_num;
			push @responses, "$base.4.1.$key_num", "integer", $instance_num;
			push @responses, "$base.4.2.$key_num", "string", $key;

			my $t = MusicBrainz::Server::RateLimitClient->query("get_stats $key", "${addr}:${port}")
				or next;
			$t =~ m[\bn_req=(\d+)]
				and push @responses, "$base.4.3.$key_num", "counter", $1;
			$t =~ m[\bn_over=(\d+)]
				and push @responses, "$base.4.4.$key_num", "counter", $1;
			$t =~ m[\blast_max_rate=(\d+)]
				and push @responses, "$base.4.5.$key_num", "gauge", $1;
		}
	};

	&$do("default", "10.1.1.245", 2000, ["ws global", "ws ua=-", "ws ua=libvlc", "ws ua=nsplayer",
        "ws cust=bbc",
        "ws cust=ia",
        "ws cust=7d",
		"ws ua=python-musicbrainz/0.7.3",
		"ws ua=generic-bad-ua",
		"ws ua=python-headphones/0.7.3",
		"ws headphones",
		"googlebot",
		"banshee",
		"picard",
		"jaikoz",
		"abelssoft",
		"python-musicbrainz-ngs",
		"xbmc",
		]);

        $self->set_responses(@responses);

        $expire = time() + 10;
    }
}

# eof
