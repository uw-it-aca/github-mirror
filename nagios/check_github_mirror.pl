#!/usr/bin/perl

use strict;
use warnings;

my $org = $ARGV[0];
my $repos_dir = $ARGV[1];
my $token = $ARGV[2];

if (!$org || !$repos_dir || !$token) {
    print "Usage: check_github_mirror.pl org_name /path/to/mirror/root access_token\n";
    exit 1;
}

use REST::Client;
use JSON::Parse 'parse_json';
use Date::Parse;


use constant NAGIOS_CRITICAL => 2;
use constant NAGIOS_OK => 0;

# OK with being 4 hours behind github
use constant OK_DELAY => 60 * 60 * 4;

my $error = NAGIOS_OK;

my $client = REST::Client->new({ host => "https://api.github.com" });
my $org_data = $client->GET("/orgs/$org/repos?access_token=$token");

my $data = parse_json($org_data->responseContent());

my @repositories;

foreach my $repos (@$data) {
    push @repositories, $repos->{'name'};
}


my $now = time();

close STDERR;
foreach my $repos (@repositories) {
    my $dir = $repos_dir."/".$repos.".git";

    # Easy one - no directory, we're not mirroring it.
    if (!-d $dir) {
        $error = NAGIOS_CRITICAL;
        print "Missing local repository: $repos\n";
        next;
    }

    # Get all of the branches in our local mirror.
    my %locals;
    open (READ, "-|", "git", "--git-dir", $dir, "branch");
    while (my $local = <READ>) {
        $local =~ s/^..//;
        chomp $local;
        $locals{$local} = 1;
    }

    close READ;

    my %remotes;
    my @missing_remotes;
    my %last_commit_per_branch;

    # Getting the remotes through the github api - seemed more straightforward than worrying about fetching remote branches
    my $remotes = parse_json($client->GET("/repos/$org/$repos/branches?access_token=$token")->responseContent());

    # Checks for missing branches
    foreach my $branch (@$remotes) {
        my $remote = $branch->{'name'};
        my $last_commit = $branch->{'commit'}->{'sha'};

        $last_commit_per_branch{$remote} = $last_commit;
        $remotes{$remote} = 1;
        if (!$locals{$remote}) {
            my $commit_url = $branch->{'commit'}->{'url'};
            my $remote_data;
            eval {
                $commit_url =~ s/^https:\/\/api.github.com//;
                my $content = $client->GET("$commit_url?access_token=$token")->responseContent();
                $remote_data = parse_json($content);

            };
            if ($@) {
                print "AAA: $@";
            }

            my $commit_time = str2time($remote_data->{'commit'}->{'author'}->{'date'});

            my $diff = $now - $commit_time;

            if ($diff > OK_DELAY) {
                push @missing_remotes, $remote;
            }
        }
    }
    close READ;

    if (@missing_remotes) {
        $error = NAGIOS_CRITICAL;
        print "Missing remotes ($repos): ".join(", ", @missing_remotes)."\n";
    }

    # Check for missing commits in the branches we do have.
    foreach my $key (keys %locals) {
        open (READ, "-|", "git", "--git-dir", $dir, "log", "-p", "-1", $key);
        my $id;
        while (my $rev = <READ>) {
            if ($rev =~ /commit (.*)$/) {
                $id = $1;
            }
            else {
                last;
            }
        }

        my $is_missing = 0;
        if ($id ne $last_commit_per_branch{$key}) {
            my $last = $last_commit_per_branch{$key};
            my $commit_url = "/repos/$org/$repos/commits/$last";
            my $content = $client->GET("$commit_url?access_token=$token")->responseContent();

            my $remote_data = parse_json($content);

            my $commit_time = str2time($remote_data->{'commit'}->{'author'}->{'date'});

            my $diff = $now - $commit_time;

            if ($diff > OK_DELAY) {
                $is_missing = 1;
            }
        }

        if ($is_missing) {
            $error = NAGIOS_CRITICAL;
            my $commit_url = "/repos/$org/$repos/commits/$id";
            my $content = $client->GET("$commit_url?access_token=$token")->responseContent();

            my $remote_data = parse_json($content);

            my $commit_time = $remote_data->{'commit'}->{'author'}->{'date'};

            print "Missing commits ($repos/$key) after $id ($commit_time).\n";
        }
        close READ;
    }

}
exit $error;
