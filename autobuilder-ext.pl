#!/usr/bin/perl -w
# kate: space-indent on; indent-width 4; mixedindent off; indent-mode cstyle; 

my $MAKE = "make -C buildroot";
# Three main data:
#   %cfgs iterator: $c
#   %pkgs iterator: $p $dep $depdep
#   @jobs iterator: $j


#package {
#  dir =>
#  name =>
#  ctime =>
#  cfgs => ( $cfg{name} => {
#             cfg =>
#             depends =>
#             rdepends =>
#             depends_recurs =>
#             rdepends_recurs =>
#             modified => TODO
#             forced => TODO
#             status => TODO
#  }
#)
# cfg {
#   name =>
#   dir =>
#   inhibit =>
#   pkgs => ( )
# }

$ENV{LANG} = "C";

use strict;
use File::Basename;
use POSIX qw(strftime);
use MIME::Lite;
my $report = "";
my $reporttime = time;
$ENV{LANG} = "C";

# FIXME: Use Perl Template Toolkit
my $html_header = <<'EOF';
<?xml version="1.0"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
<html>
  <head>
    <title>Buildroot - Autobuilder</title>
    <meta http-equiv="content-type" content="text/html; charset=utf-8" />
    <meta name="robots" content="noindex">
    <link rel="stylesheet" type="text/css" href="css/jquery.dataTables.css">
    <script type="text/javascript" language="javascript" src="js/jquery.min.js"></script>
    <script type="text/javascript" language="javascript" src="js/jquery.dataTables.min.js"></script>
    <script type="text/javascript" language="javascript" src="js/FixedHeader.min.js"></script>
    <script type="text/javascript" charset="utf-8">
$(document).ready(function() {
    var table = $('#data').dataTable({
        "bPaginate": false,
        "bLengthChange": false,
        "bFilter": true,
        "bSort":true,
        "bInfo": false,
        "bAutoWidth": true
    } );
    new FixedHeader(table);
} );
    </script>
    <style type="text/css">
        html      { text-align: center; } 
        body      { font-family: sans-serif;  /*width: 50em; */ margin: auto;  }
        h1        {
            border-top: 1px solid rgb(208, 208, 208);
            border-bottom: 1px solid rgb(208, 208, 208);
            clear: both;
        }
        a         {
            text-decoration: none;
            color: rgb(90, 90, 90);
        }
        .sha1     { font-family: monospace; }
        table     { margin-left: auto; margin-right: auto; text-align: left; }
        thead     { vertical-align: middle; text-align: center; }
        table.dataTable tr.odd, tr:nth-child(odd)   { background-color:#eee; }
        table.dataTable tr.odd td.sorting_1  { background-color: #ddd; }
        table.dataTable tr.odd td.sorting_2  { background-color: #ccc; }
        table.dataTable tr.odd td.sorting_3  { background-color: #bbb; }
        table.dataTable tr.even, tr:nth-child(even) { background-color:#fff; }
        table.dataTable tr.even td.sorting_1 { background-color: #eee; }
        table.dataTable tr.even td.sorting_2 { background-color: #ddd; }
        table.dataTable tr.even td.sorting_3 { background-color: #ccc; }
        table.dataTable thead th, table.dataTable td {
            padding: 0px 1px;
        }
        table#data {
            width: 50em;
        }
    </style>
  </head>
  <body>
    <h1>Buildroot - Continuous integration results</h1>
EOF

my $html_header_pkg = <<'EOF';
<html>
  <head>
    <title>Buildroot - Autobuilder package details</title>
    <meta http-equiv="content-type" content="text/html; charset=utf-8" />
    <meta name="robots" content="noindex">
    <style type="text/css">
        html      { text-align: center; } 
        body      { font-family: sans-serif;  width: 50em; margin: auto; text-align: justify; }
        h1        {
            border-top: 1px solid rgb(208, 208, 208);
            border-bottom: 1px solid rgb(208, 208, 208);
            clear: both;
        }
        a         {
            text-decoration: none;
            color: rgb(90, 90, 90);
        }
        .sha1     { font-family: monospace; }
        table     { margin-left: auto; margin-right: auto; text-align: left; width: 50em; }
        thead     { vertical-align: middle; text-align: center; }
        tr:nth-child(odd)   { background-color:#eee; }
        tr:nth-child(even) { background-color:#fff; }
    </style>
  </head>
  <body>
EOF

# Return modification time of one file
sub mtime($) {
    return 0 if (!-e $_[0]);    
    return (stat $_[0])[9];
}

# Return first line of one file
sub firstLine {
    return undef if (! -e $_[0]);
    my $FILE;
    open ($FILE, '<', $_[0]) || die "$_[0]: $!";
    my $line = <$FILE>;
    close $FILE;
    chomp $line || print "Cannot chomp $line";
    return $line
}

# Write a line in a file
sub writeLine {
    my $FILE;
    open ($FILE, '>', $_[0]) || die "$_[0]: $!";
    print { $FILE } $_[1] . "\n";
    close $FILE;
}

sub sendReport {
    $reporttime = time; 
    my $msg = MIME::Lite->new(
        From     => 'autobuilder@sysmic.org',
        To       => 'jezz@sysmic.org',
        # Cc       => 'list@buildroot.net',
        Subject  => "Autobuild report of " . (strftime "%F", gmtime $reporttime),
        Data     => $report
    );

    $msg->send;
    $report = "";
}

sub getPkgList() {
  my %list;
  for my $file (<buildroot/*/*.mk buildroot/*/*/*.mk buildroot/package/*/*/*.mk>) {
     my $filepattern = $file;
     $filepattern =~ tr|-|_|;
     next if ($filepattern !~ m|(.*)/\1.mk$|);
     $file =~ m|(.*)/\1.mk$|;
     my $name = $1;
     my $FILE;
     open $FILE, $file;
     while (<$FILE>) {
        if (/\$\(eval \$\(host-[a-z]*-package\)\)/) {
           $list{"host-$name"}{dir} = dirname $file;
           $list{"host-$name"}{dir} =~ s|^buildroot/||;
           $list{"host-$name"}{name} = "host-$name";
           $list{"host-$name"}{cfgs} = { };
           $list{"host-$name"}{ctime} = 0;
        }
        if (/\$\(eval \$\([a-z]*-package\)\)/) {
	   $list{"$name"}{dir} = dirname $file;
           $list{"$name"}{dir} =~ s|^buildroot/||;
	   $list{"$name"}{name} = $name;
           $list{"$name"}{cfgs} = { };
           $list{"$name"}{ctime} = 0;
	}
     }
     close $FILE;
  }
  return \%list;
}

sub getCfgList() {
    my %list;
    for (<cfgs/*/.config>) {
        my ($name) = m|cfgs/(.*)/.config|;
        $list{$name}{name} = "$name";
        $list{$name}{dir} = "../cfgs/$name";
        $list{$name}{inhibit} = (-e "cfgs/$name/inhibit") ? 1 : 0;
        $list{$name}{mtime} = mtime "cfgs/$name/.config";
        $list{$name}{packages} = [ ];
        my $FILE;
        open $FILE, "cfgs/$name/.config";
        while (<$FILE>) {
            $list{$name}{arch} = $1 if /^BR2_ARCH="(.*)"$/;
            $list{$name}{libc} = "glibc" if /^BR2_TOOLCHAIN_USES_GLIBC=y$/;
            $list{$name}{libc} = "uclibc" if /^BR2_TOOLCHAIN_USES_UCLIBC=y$/;
            $list{$name}{toolchain} = "external" if /^BR2_TOOLCHAIN_EXTERNAL=y$/;
            $list{$name}{toolchain} = "buildroot" if /^BR2_TOOLCHAIN_BUILDROOT=y$/;
        }
        close $FILE;
    }
    return \%list;
}

# Travailler sur les commitData
# Update Commit time of each package directories
#... Long... around 3min. Necessary only if git pull returned something.
sub updateCTimes($) {
    my %pkgs = %{$_[0]};
    for my $name (keys %pkgs) {
        next if ($name =~ /^host-(.*)$/ && $pkgs{$1});
        my $time = qx(cd buildroot && git log --pretty="%ct" -1 $pkgs{$name}{dir});
        chomp $time;
        $pkgs{"$name"}{ctime} = $time if $pkgs{"$name"};
        $pkgs{"host-$name"}{ctime} = $time if $pkgs{"host-$name"};
    }
}

# Long : around 20s per config (4min for all configurations)
# Split target and depends
sub updateTargetsAndDeps($$) {
    # Link a configuration with a Package
    sub addPkgConfig($$) {
        my $cfg = $_[0];
        my $pkg = $_[1];
        print "$pkg->{name} name is invalid" if (!$pkg->{name});
        push @{$cfg->{packages}}, $pkg;
        $pkg->{cfgs}{$cfg->{name}} = {
            pkg => $pkg,
            cfg => $cfg,
            rdepends => [ ],
            depends => [ ],
            depends_recurs => [ ],
            rdepends_recurs => [ ]
        };
    }

    sub getTargets($) {
        my $cfg = $_[0];
        print ((strftime "%T", localtime(time)) . " run (take around 4s): make -s O=$cfg->{dir} show-targets\n");
        my @packages = split / /, qx($MAKE -s O=$cfg->{dir} show-targets);
        @packages = grep {!/^target-/} @packages;  
        @packages = grep {!/^rootfs-/} @packages;  
        return @packages;
    }
  
    sub getDepends($$) {
        my $cfg = $_[0];
        my $packages = $_[1];
        my @args;
        for my $pkg (@{$packages}) {
            push @args, "$pkg-show-depends"
        }
        print ((strftime "%T", localtime(time)) . " run (take around 15s): make -s O=$cfg->{dir} ...-show-depends\n");
        return split /\n/, qx($MAKE -s O=$cfg->{dir} @args), -1;
    }
  
    sub computeRecursiveDepends($$) {
        my $cfg = $_[0];
        my $type = $_[1]; # Should be depends_recurs or rdepends_recurs
        my $modified = 1;
        my $cname = $cfg->{name};
        while ($modified == 1) {
            print ((strftime "%T", localtime(time)) . " Compute recursive depends ($type)\n");
            $modified = 0;
            for my $pkg (@{$cfg->{packages}}) {
                my $depends = $pkg->{cfgs}{$cname}{$type};
                for my $dpkg (@$depends) {
                    my $ddepends = $dpkg->{cfgs}{$cname}{$type};
                    for my $ddpkg (@$ddepends) {
                        if (!(grep { $_ == $ddpkg } @{$depends})) {
                            push @{$pkg->{cfgs}{$cname}{$type}}, $ddpkg;
                            $modified = 1;
                        }
                    }
                }
            }
        }
    }
  
    my $cfg = $_[0];
    my $pkgs = $_[1];

    my @packages =  grep { if (defined $pkgs->{$_}) { 1; } else { print "Warning $_ unknown but referenced by $cfg->{name}. Drop it\n"; 0; } } getTargets($cfg);
    $cfg->{packages} = [ ];
    for my $pkg (@packages) {
        if (! defined $pkgs->{$pkg} || ! $pkgs->{$pkg}{name}) {
            print "$cfg->{name} reference a a non registered package $pkg\n";
        }
        addPkgConfig $cfg, $pkgs->{$pkg};
    }
    my @all_deps = getDepends($cfg, \@packages);
   
    for my $pkg (@packages) {
        my @pkg_deps = split / /, shift @all_deps;
        for my $dep (@pkg_deps) {
            if (!defined $pkgs->{$dep}{cfgs}{$cfg->{name}}) {
                if (!defined $pkgs->{$dep} || ! $pkgs->{$dep}{name}) {
                    print "Error: $pkg depends of $dep, but $dep does not exist!?\n";
                    next;
                } else {
                    #print "Warning $pkg depends of $dep, but $dep was not in targets. Add it\n";
                    addPkgConfig $cfg, $pkgs->{$dep};
                }
            }
            my $pconf = $pkgs->{$pkg}{cfgs}{$cfg->{name}};
            my $rpconf = $pkgs->{$dep}{cfgs}{$cfg->{name}};
            push @{$pconf->{depends}},          $pkgs->{$dep};
            push @{$pconf->{depends_recurs}},   $pkgs->{$dep};
            push @{$rpconf->{rdepends}},        $pkgs->{$pkg};
            push @{$rpconf->{rdepends_recurs}}, $pkgs->{$pkg};
        }
    }

    computeRecursiveDepends $cfg, "depends_recurs";
    computeRecursiveDepends $cfg, "rdepends_recurs";
}

sub updateInhibit($) {
    my $cfgs = $_[0];
    my $ret = 0;
    for my $c (values %{$cfgs}) {
        my $newvalue = (-e "cfgs/$c->{name}/inhibit") ? 1 : 0;
        if (!defined $c->{inhibit} || $c->{inhibit} != $newvalue) {
            $c->{inhibit} = $newvalue;
            $ret = 1;
        }
    }
    return $ret;
}

sub updateForce($) {
    my $pkgs = $_[0];
    my $ret = 0;
    for my $p (values %{$pkgs}) {
        for my $j (values %{$p->{cfgs}}) {
            my $dir = "context/$j->{cfg}{name}/$j->{pkg}{name}";
            if (-e $dir && defined $j->{last_build}) {
                my $newvalue = (-e "$dir/force-rebuild") ? 1 : 0;
                if ($j->{last_build}{forcerebuilt} != $newvalue) {
                    $j->{last_build}{forcerebuilt} = $newvalue;
                    $ret = 1;
                }
            }
        }
    }
    return $ret;
}

sub updateStatus($) {
    my $pkgs = $_[0];
    for my $p (values %{$pkgs}) {
        for my $j (values %{$p->{cfgs}}) {
            print "BUG context/$j->{cfg}{name} / $j->{pkg}{name} / $p->{name}\n" if (! $p->{name} || ! $j->{pkg}{name});
            next if (! $p->{name} || ! $j->{pkg}{name});
            my $dir = "context/$j->{cfg}{name}/$j->{pkg}{name}";
            if (-e $dir) {
                #print "Detect context/$cfg{cfg}/$pkg{name}\n";
                $j->{last_build}{id}       = basename (readlink $dir);
                $j->{last_build}{date}     = firstLine "$dir/date";
                $j->{last_build}{duration} = firstLine "$dir/duration";
                $j->{last_build}{gitid}    = firstLine "$dir/gitid";
                $j->{last_build}{result}   = firstLine "$dir/result";
                $j->{last_build}{outdirid} = firstLine "$dir/outdirid";
                $j->{last_build}{forcerebuilt} = ((-e "$dir/force-rebuild") ? 1 : 0);
                $j->{last_build}{details}  = firstLine "$dir/details";
            }
        }
    }
}

sub getJobs($) {
    sub computePriority {
        my %p =  %{$_[0]};
        return 100 if ($p{forcerebuilt});
        return 80 if (defined $p{last_build} && $p{last_build}{result} eq "Failed" && $p{pkg}{ctime} > $p{last_build}{date});
        return 60 if (!defined $p{last_build});
        return 40 if ($p{pkg}{ctime} > $p{last_build}{date});
        for my $d (@{$p{depends_recurs}}) {
            return 30 if $d->{ctime} > $p{last_build}{date};
        }
        return 0;
    }
    sub sortJobs {
        my $prioa = $a->{priority};
        my $priob = $b->{priority};
        return $priob <=> $prioa if ($priob != $prioa);
        # Try to build package without deps in first.
        # TODO: Make a real topologic sort
        if (@{$a->{depends_recurs}} > 0 && @{$b->{depends_recurs}} == 0) {
            return 1;
        }
        if (@{$b->{depends_recurs}} > 0 && @{$a->{depends_recurs}} == 0) {
            return -1;
        }
        if (grep { $_ == $a->{pkg} } @{$b->{depends_recurs}}) {
            return 1;
        }
        if (grep { $_ == $b->{pkg} } @{$a->{depends_recurs}}) {
            return -1;
        }
        
        if ($a->{last_build} && $b->{last_build} && $a->{last_build}{date} != $b->{last_build}{date}) {
            return $a->{last_build}{date} <=> $b->{last_build}{date};
        }
        return $a->{cfg}{name} cmp $b->{cfg}{name} if $a->{cfg}{name} cmp $b->{cfg}{name};
        return $a->{pkg}{name} cmp $b->{pkg}{name};
    }
    
    my %pkgs = %{$_[0]};
    my @jobs;
    for my $p (values %pkgs) {
        for my $c (values $p->{cfgs}) {
            if (!$c->{inhibit}) {
                $c->{priority} = computePriority $c;
                push @jobs, $c;
            }
        }
    }
    @jobs = sort sortJobs @jobs;
    return \@jobs;
}

############# HTML #############
sub dumpPkg($) {
    my %pkg = %{$_[0]};
    mkdir "html" if (! -e "html");
    my $FILE;
    open $FILE, '>', "html/$pkg{name}.html" || die "html/$pkg{name}.html: $!";
    print $FILE $html_header_pkg;
    print $FILE "<h1>$pkg{name}</h1>\n";
    for my $c (sort keys %{$pkg{cfgs}}) {
        print $FILE "<h2>$c</h2>\n";
        print $FILE "<p><table>\n";
        print $FILE "<tr><td>Direct Dependencies</td><td>"             . (join " ", map { "<a href='$_->{name}.html'>$_->{name}</a>" } @{$pkg{cfgs}{$c}{depends}})         . "</td></tr>\n";
        print $FILE "<tr><td>Recursives Dependencies</td><td>"         . (join " ", map { "<a href='$_->{name}.html'>$_->{name}</a>" } @{$pkg{cfgs}{$c}{depends_recurs}})  . "</td></tr>\n";
        print $FILE "<tr><td>Direct Reverse Dependencies</td><td>"     . (join " ", map { "<a href='$_->{name}.html'>$_->{name}</a>" } @{$pkg{cfgs}{$c}{rdepends}})        . "</td></tr>\n";
        print $FILE "<tr><td>Recursives Reverse Dependencies</td><td>" . (join " ", map { "<a href='$_->{name}.html'>$_->{name}</a>" } @{$pkg{cfgs}{$c}{rdepends_recurs}}) . "</td></tr>\n";
        print $FILE "</table></p>\n";
        if (defined $pkg{cfgs}{$c}{last_build}) {
            print $FILE "<p>Last results:<br/><table><tr><th>Place</th><th>Status</th><th>Build date</th><th>Git id</th><th>Duration</th></tr>\n";
            my $dir = "context/$c/$pkg{name}";
            my $idx = 0;
            while (-e "$dir") {
                print $FILE "<td>$idx</td>";
                $dir = "results/" . basename (readlink $dir);
                my $result = firstLine "$dir/result";
                if ($result eq "OK" || $result eq "Ok") {
                    print $FILE "<td style='background-color:LightGreen;'><a href='../$dir'>OK</a></td>";
                } elsif ($result eq "KO" || $result eq "Failed") {
                    print $FILE "<td style='background-color:LightCoral;'><a href='../$dir'>KO</a></td>";
                } elsif  ($result eq "Dep") {
                    my $details = firstLine "$dir/details";
                    print $FILE "<td style='background-color:SandyBrown;'><a href='../$dir'>Dep</a><br/><font size='1'><a href='$details.html'>$details</a></font></td>";
                } else {
                    print $FILE "<td style='background-color:LightCoral;'><a href='../$dir'>$result</a></td>";
                }
                print $FILE "<td>" . (strftime "%F", gmtime (firstLine "$dir/date")) . "</td>";
                my $gitid = firstLine "$dir/gitid";
                print $FILE "<td><a href='http://git.buildroot.net/buildroot/commit/?id=$gitid'>" . (substr $gitid, 0, 8) . "</td>";
                print $FILE "<td>" . (firstLine "$dir/duration") . "</td></tr>\n";
                $dir = "$dir/previous_build";
                $idx++;
            }
            print $FILE "</table><p>\n";
        } else {
            print $FILE "<p>Never build</p>\n";
        }
    }
    print $FILE <<EOF;
</body></html>
EOF
}

sub dumpResults($$) {
    my %cfgs = %{$_[0]};
    my %pkgs = %{$_[1]};
   
    mkdir "html" if (! -e "html");
    my $FILE;
    open $FILE, '>', "html/index.html" || die "html/index.html: $!";
    print $FILE $html_header;
    print $FILE "<p><table id='data'>\n";
    print $FILE "<thead><tr><th>Configuration</th><th>" . (join "</th><th>", sort keys %cfgs) . "</th></tr></thead>\n";
   
    for my $p (sort keys %pkgs) {
        print $FILE "<tr><th><a href='$p.html'>$p</a></th>";
        for my $c (sort keys %cfgs) {
            my $dir = "../context/$c/$p";
            if (!defined $pkgs{$p}{cfgs}{$c}) {
                print $FILE "<td style='background-color:LightSteelBlue;'>N/A</td>";
            } elsif (!(defined $pkgs{$p}{cfgs}{$c}{last_build})) {
                print $FILE "<td style='background-color:LightSteelBlue;'>Wait</td>";
            } elsif ($pkgs{$p}{cfgs}{$c}{last_build}{result} eq "Ok" || $pkgs{$p}{cfgs}{$c}{last_build}{result} eq "OK") {
                print $FILE "<td style='background-color:LightGreen;'><a href='$dir'>OK</a></td>";
            } elsif ($pkgs{$p}{cfgs}{$c}{last_build}{result} eq "Failed" || $pkgs{$p}{cfgs}{$c}{last_build}{result} eq "KO") {
                print $FILE "<td style='background-color:LightCoral;'><a href='$dir'>KO</a></td>";
            } elsif ($pkgs{$p}{cfgs}{$c}{last_build}{result} eq "Dep") {
                print $FILE "<td style='background-color:SandyBrown;'><a href='$dir'>Dep</a><br/><font size='1'><a href='$pkgs{$p}{cfgs}{$c}{last_build}{details}.html'>$pkgs{$p}{cfgs}{$c}{last_build}{details}</a></font></td>";
            } else {
                print $FILE "<td style='background-color:LightCoral;'><a href='$dir'>BUG</a></td>";
            }
        }
        print $FILE "</tr>\n";
    }
    print $FILE <<EOF;
</table></p>
</body>
</html>
EOF
    close $FILE;
}


sub dumpJobQueue($$) {
    my @jobs = @{$_[0]};
    my $current_idx = $_[1];

    my $FILE;
    open $FILE, '>', "html/jobqueue.html" || die "jobqueue.html: $!";
    print $FILE $html_header;
    print $FILE "<p><table>\n";
    print $FILE "<thead><tr><th>Place</th><th>Package</th><th>Config</th><th>Status</th><th>Buildreason</th><th>Date</th><th>Git id</th><th>Build duration</th></tr></thead>\n";
    my $idx = 0;
    for my $r (@jobs) {
        print $FILE "<tr>";
        if ($idx == $current_idx) {
            print $FILE "<td><bold>&lt; $idx &gt;</bold></td>";
        } else {
            print $FILE "<td>$idx</td>";
        }
        print $FILE "<td><a href='$r->{pkg}{name}.html'>$r->{pkg}{name}</td>";
        print $FILE "<td>$r->{cfg}{name}</td>";
        my $dir = "../context/$r->{cfg}{name}/$r->{pkg}{name}";
        if (!(defined $r->{last_build})) {
            print $FILE "<td style='background-color:LightSteelBlue;'>Wait</td>";
        } elsif ($r->{last_build}{result} eq "Ok" ||  $r->{last_build}{result} eq "OK") {
            print $FILE "<td style='background-color:LightGreen;'><a href='$dir'>OK</a></td>";
        } elsif ($r->{last_build}{result} eq "Failed" || $r->{last_build}{result} eq "KO") {
            print $FILE "<td style='background-color:LightCoral;'><a href='$dir'>KO</a></td>";
        } elsif ($r->{last_build}{result} eq "Dep") {
            print $FILE "<td style='background-color:SandyBrown;'><a href='$dir'>Dep</a><br/><font size='1'><a href='$r->{last_build}{details}.html'>$r->{last_build}{details}</a></font></td>";
        } else {
            print $FILE "<td style='background-color:LightSteelBlue;'><a href='$dir'>$r->{last_build}{result}</a></td>";
        }
        
        if ($r->{forcerebuilt}) {
            print $FILE "<td>Force rebuild</td>";
        } elsif (!(defined $r->{last_build})) {
            print $FILE "<td>Never built</td>";
        } elsif ($r->{pkg}{ctime} > $r->{last_build}{date}) {
            print $FILE "<td>Modified</td>";
        } else {
            my $done = 0;
            print $FILE "<td>";
            for my $d (@{$r->{depends_recurs}}) {
                if ($d->{ctime} > $r->{last_build}{date}) {
                    print $FILE "Dep ($d->{name}) modified<br/>";
                    $done = 1; 
                }
            }
            if (!$done) {
                print $FILE "Normal";
            }
            print $FILE "</td>";
        }
        if ($r->{last_build}) {
            print $FILE "<td>" . (strftime "%F", gmtime $r->{last_build}{date}) . "</td>";
            print $FILE "<td><a href='http://git.buildroot.net/buildroot/commit/?id=$r->{last_build}{gitid}'>" . (substr $r->{last_build}{gitid}, 0, 8) . "</td>";
            print $FILE "<td>$r->{last_build}{duration}</td></tr>\n";
        } else {
            print $FILE "<td>N/A</td>";
            print $FILE "<td>N/A</td>";
            print $FILE "<td>N/A</td></tr>\n";
        }
        $idx++;
    }
    print $FILE <<EOF;
</table></p>
</body>
</html>
EOF
    close $FILE;
}


############# BUILD #############
sub buildPkg($$$) {
    my ($cfg, $pkg, $out) = @_; 
    my $ret;
    $ret = system "$MAKE O=$cfg $pkg-dirclean > $out/build_log 2>&1";
    if (!$ret) {
        $ret = system "$MAKE O=$cfg toolchain $pkg >> $out/build_log 2>&1";
    }
    if ($ret >> 8) {
        my $FILE;
        open $FILE, "$out/build_log";
        my $reason = (grep /^\[7m>>> .*\[27m$/, <$FILE>)[-1];
        $reason =~  /^\[7m>>> ([^ ]*) ([^ ]*) (.*)\[27m/;
        close $FILE;
        print "Build of $pkg failed because of $1 while $3\n";
        if ($1 ne $pkg) {
            writeLine "$out/details", "$1";
            writeLine "$out/result", "Dep";
        } else {
            writeLine "$out/result", "KO";
        }
    } elsif ($ret == 2) {
        print "Build of $pkg interrupted\n";
        writeLine "$out/result", "Interrupted";
    } elsif ($ret) {
        print "Build of $pkg had a strange end\n";
        writeLine "$out/result", "BUG";
    } else {
        print "Build of $pkg success\n";
        writeLine "$out/result", "OK";
    }
    return $?;
}

sub build($$$) {
    my $CMD;
    my ($j, $jobs, $jobidx) = @_; 
    my $cname = $j->{cfg}{name};
    my $pname = $j->{pkg}{name};
    my $new_id = qx(uuidgen | cut -f 1 -d '-');
    chomp $new_id;
    my $old_id;;
    $old_id = $j->{last_build}{id} if $j->{last_build};
    print "Building: $cname/$pname " . ($old_id ? $old_id : "") . "->$new_id\n";
    my $time = time;
    mkdir "results" if (! -e "results");
    mkdir "context" if (! -e "context");
    mkdir "context/$cname" if (! -e "context/$cname");
    mkdir "results/$new_id";
    symlink "../$old_id", "results/$new_id/previous_build" if $old_id;
    
    my $outdir = "context/$cname/$pname";
    unlink "$outdir";
    symlink "../../results/$new_id", "$outdir" || die $!;
        
    writeLine "cfgs/$cname/dirid", qx(uuidgen | cut -f 1 -d '-')  if (! -e "cfgs/$cname/dirid");

    if ($j->{priority} == 0 && $j->{last_build} && $j->{last_build}{outdirid} && $j->{last_build}{outdirid} eq firstLine "cfgs/$cname/dirid") {
        print "run: $MAKE O=../cfgs/$cname clean\n";
        system "$MAKE O=../cfgs/$cname clean";
        writeLine "cfgs/$cname/dirid", qx(uuidgen | cut -f 1 -d '-');
    }
    my $prev_result = ($j->{last_build}{result} || "Wait");
    $j->{last_build}{id}       = $new_id;
    $j->{last_build}{date}     = $time;
    $j->{last_build}{duration} = "N/A";
    $j->{last_build}{gitid}    = qx(cd buildroot && git rev-parse HEAD);
    $j->{last_build}{result}   = "Cur";
    $j->{last_build}{outdirid} = firstLine "cfgs/$cname/dirid";
    $j->{last_build}{forcerebuilt} = 0;
    delete $j->{last_build}{details};

    writeLine "$outdir/long_id", "$cname $pname $time";
    writeLine "$outdir/date", $j->{last_build}{date};
    writeLine "$outdir/result", $j->{last_build}{result};
    writeLine "$outdir/outdirid", $j->{last_build}{outdirid};
    writeLine "$outdir/gitid", $j->{last_build}{gitid};
    writeLine "$outdir/duration", $j->{last_build}{duration};
    dumpPkg $j->{pkg};
    dumpJobQueue($jobs, $jobidx);

    my $exit_status;
    if (-x "cfgs/$cname/buildPkg") {
        $exit_status = system "cfgs/$cname/buildPkg cfgs/$cname $pname $outdir";
    } else {
        $exit_status = buildPkg "../cfgs/$cname", $pname, $outdir;
    }
    $j->{last_build}{duration} = (time - $time);
    writeLine "$outdir/duration", $j->{last_build}{duration};
    $j->{last_build}{result}   = firstLine "$outdir/result";
    $j->{last_build}{details}  = firstLine "$outdir/details" if (-e "$outdir/details");

    dumpPkg $j->{pkg};
    dumpJobQueue($jobs, $jobidx);
}

my $lastchecktime = time;
my $redumpkgs = 0;
my $rebuilddb = 1;
my $pkgs;
my $cfgs;
my $jobidx = 0;
my $jobs;

print ((strftime "%T", localtime(time)) . " Get config list\n");
$cfgs = getCfgList;

while (1) {
    if (time > $reporttime + (3600 * 24)) {
        print ((strftime "%T", localtime(time)) . " Send report\n");
        sendReport;
    }
    print ((strftime "%T", localtime(time)) . " Check changes on git\n");
    my $changes = qx(cd buildroot && git pull --rebase 2>&1);
    if ($changes !~ /^Current branch .* is up to date.$/) {
        $rebuilddb = 1;
        print $changes;
    }
    if ($rebuilddb) {
        print ((strftime "%T", localtime(time)) . " Get package list\n");
        $pkgs = getPkgList;
        print ((strftime "%T", localtime(time)) . " Update configurations\n");
        for my $c (values %$cfgs) {
            my $changes = qx(yes | $MAKE -s O=../cfgs/$c->{name} oldconfig 2>&1);
            print $changes;
        }
        print ((strftime "%T", localtime(time)) . " Update packets modification times (take 5min)\n");
        updateCTimes $pkgs;    
    }
    
    my $newtime = time;
    for my $c (values %$cfgs) {
        if (mtime "cfgs/$c->{name}/.config" > $lastchecktime || $rebuilddb) {
            print ((strftime "%T", localtime(time)) . " Update targets and dependencies of $c->{name}\n");
            updateTargetsAndDeps $c, $pkgs;
            $rebuilddb = 1;
        }
    }
    $lastchecktime = $newtime;

    if ($rebuilddb) {
        print ((strftime "%T", localtime(time)) . " Update build status (take 5min)\n");
        updateStatus $pkgs;    
    }
    
    print ((strftime "%T", localtime(time)) . " Dump global status\n");
    dumpResults $cfgs, $pkgs;    
    if ($redumpkgs && $rebuilddb) {
        print ((strftime "%T", localtime(time)) . " Dump packages result (take 20min)\n");
        for my $p (values %$pkgs) {
            dumpPkg $p;
        }
    }

    print ((strftime "%T", localtime(time)) . " Update forced packages\n");
    $rebuilddb += updateForce $pkgs;
    print ((strftime "%T", localtime(time)) . " Update inhibit configs\n");
    $rebuilddb += updateInhibit $cfgs; # TODO: also check new configurations

    if ($rebuilddb) {
        print ((strftime "%T", localtime(time)) . " Compute job list\n");
        $jobs = getJobs $pkgs;
        $jobidx = 0;
    } else {
        $jobidx++;
    }
    if ( $jobidx <  @$jobs) {
        print ((strftime "%T", localtime(time)) . " Dump job list\n");
        dumpJobQueue($jobs, $jobidx);
        print ((strftime "%T", localtime(time)) . " Build $jobidx: $jobs->[$jobidx]{cfg}{name}/$jobs->[$jobidx]{pkg}{name}\n");
        build $jobs->[$jobidx], $jobs, $jobidx;
        print ((strftime "%T", localtime(time)) . " Rebuild result for $jobs->[$jobidx]{pkg}{name}\n");
        dumpPkg $jobs->[$jobidx]{pkg};
    } else {
        print ( "Waiting for an update....\n");
        sleep(10);
    }
    $rebuilddb = 0;
}
