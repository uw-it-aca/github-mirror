#!/usr/bin/perl

my $org = $ARGV[0];
my $repos_dir = $ARGV[1];
my $token = $ARGV[2];

if (!$org || !$repos_dir) {
    print "Usage: make_mirror.pl org_name /path/to/mirror/root access_token\n";
    exit;
}

use REST::Client;
use JSON::Parse 'parse_json';

my $client = REST::Client->new({ host => "https://api.github.com" });
my $org_data = $client->GET("/orgs/$org/repos?access_token=$token");

my $data = parse_json($org_data->responseContent());

my @repositories;

close STDERR;
foreach my $repos (@$data) {
    my $name = $repos->{'name'};

    my $dir = $repos_dir."/".$name.".git";

    if (-d $dir) {
        open(READ, "-|", "git", "--git-dir", $dir, "fetch", "-q", "--all", "-p");
        while (<READ>) { print $_; }
    }
    else {
        print "Adding repository: $name\n";
        my $dest = $repos_dir."/".$name.".git";
        my $url = $repos->{'clone_url'};
        open(READ, "-|", "git", "clone", "--mirror", $url, $dest);
        while (<READ>) { print $_; }
    }
}

