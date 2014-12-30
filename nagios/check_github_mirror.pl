#!/usr/bin/perl

my $org = "uw-it-aca";
my $repos_dir = "/home/pmichaud/github_mirroring/repos";

use REST::Client;
use JSON::Parse 'parse_json';

use constant NAGIOS_CRITICAL => 2;
use constant NAGIOS_OK => 0;
my $error = NAGIOS_OK;

my $client = REST::Client->new({ host => "https://api.github.com" });
my $org_data = $client->GET("/orgs/$org/repos");

my $data = parse_json($org_data->responseContent());

my @repositories;

foreach my $repos (@$data) {
    push @repositories, $repos->{'name'};
}


foreach my $repos (@repositories) {
    my $dir = $repos_dir."/".$repos;

    if (!-d $dir) {
        $error = NAGIOS_CRITICAL;
        print "Missing local repository: $repos\n";
        next;
    }

    my %locals;
    my $git_dir = "$dir/.git";
    open (READ, "-|", "git", "--git-dir", $git_dir, "branch");
    while (my $local = <READ>) {
        $local =~ s/^..//;
        chomp $local;
        $locals{$local} = 1;
    }

    close READ;

    my %remotes;
    my @missing_remotes;
    open (READ, "-|", "git", "--git-dir", $git_dir, "branch", "-r");
    while (my $remote = <READ>) {
        next if $remote =~ / origin\/HEAD /;

        $remote =~ s/^..origin\///;
        chomp $remote;
        $remotes{$remote} = 1;
        if (!$locals{$remote}) {
            push @missing_remotes, $remote;
        }
    }
    close READ;

    if (@missing_remotes) {
        $error = NAGIOS_CRITICAL;
        print "Missing remotes ($repos): ".join(", ", @missing_remotes)."\n";
    }

    close STDERR;
    foreach my $key (keys %locals) {
        my $git_dir = "$dir/.git";
        my $compare = "$key...origin/$key";
        open (READ, "-|", "git", "--git-dir", $git_dir, "rev-list", "--left-right", $compare);
        my @ids;
        while (my $rev = <READ>) {
            chomp $rev;
            $rev =~ s/^.//;

            push @ids, $rev;
        }

        if (@ids) {
            $error = NAGIOS_CRITICAL;
            print "Missing commits ($repos/$key): ".join(", ", @ids)."\n";
        }
        close READ;
    }

}
exit $error;
