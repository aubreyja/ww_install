#!/usr/bin/env perl
#The Chromatic.pm perl module is used in several pg files in setGraphTheory.
#The perl module calls a C program to do the actual work.
#Three steps are required for the installation :

#1. The files should be copied here:

#/opt/webwork/pg/lib/Chromatic.pm
#/opt/webwork/pg/lib/chromatic/color.c

#Apache restart is needed after editing Chromatic.pm

#2. color.c needs to be compiled with the command

#gcc -O3 color.c -o color

#3. The module Chromatic.pm needs to be loaded in global.conf.
#Follow the syntax of other perl modules loaded. Search for
#'PG modules to load' in global.conf to find the location.

use strict;
use warnings;

use File::Find;
use File::Basename;

use Cwd;
use File::Path qw(make_path);
use File::Copy;
use File::Spec;
use IPC::Cmd qw(can_run run);
use constant IPC_CMD_TIMEOUT => 6000; #Sets maximum time system commands will 
use constant IPC_CMD_VERBOSE => 1;    #Controls whether all output of a command
                                      #should be printed to STDOUT/STDERR
                                      #

BEGIN {
        die "WEBWORK_ROOT not found in environment.\n"
                unless exists $ENV{WEBWORK_ROOT};
	# Unused variable, but define it to avoid an error message.
	$WeBWorK::Constants::WEBWORK_DIRECTORY = '';
}

use lib "$ENV{WEBWORK_ROOT}/lib";
use WeBWorK::CourseEnvironment;

#Set things up, find files we need.

my $cwd = getcwd;
my $ce = new WeBWorK::CourseEnvironment({webwork_dir=>$ENV{WEBWORK_ROOT}});

my $libraryRoot = $ce->{problemLibrary}->{root};
$libraryRoot = File::Spec->canonpath($libraryRoot);
my $nau = File::Spec->canonpath("$libraryRoot/NAU");
my $chromatic = File::Spec->canonpath("$nau/lib/Chromatic.pm");
my $color_dot_c = File::Spec->canonpath("$nau/lib/chromatic/color.c");
#should now check that these really exist 

my $pg_dir = $ce->{pg_dir};
$pg_dir = File::Spec->canonpath($pg_dir);

my $conf_dir = File::Spec->canonpath("$ENV{WEBWORK_ROOT}/conf");

my $gcc = can_run('gcc')
  or die "Can't find gcc - please install it and try again.";

#1. The files should be copied here:
#/opt/webwork/pg/lib/Chromatic.pm
#/opt/webwork/pg/lib/chromatic/color.c
copy($chromatic,"$pg_dir/lib/")
  or die "Couldn't copy $chromatic to $pg_dir/lib/:$!";
$chromatic = File::Spec->canonpath("$pg_dir/lib/Chromatic.pm");

make_path("$pg_dir/lib/chromatic");
copy($color_dot_c,"$pg_dir/lib/chromatic/")
  or die "Couldn't copy $color_dot_c to $pg_dir/lib/chromatic/:$!";
$color_dot_c = File::Spec->canonpath("$pg_dir/lib/chromatic/color.c");


#gcc -O3 color.c -o color
chdir("$pg_dir/lib/chromatic/");

my $cmd = ['gcc','-O3',$color_dot_c,'-o','color']; #should be an array reference

my (  $success, $error_message, $full_buf,
        $stdout_buf, $stderr_buf) 
      = run(
        command => $cmd,
        verbose => IPC_CMD_VERBOSE,
        timeout => IPC_CMD_TIMEOUT
   );


copy("$conf_dir/localOverrides.conf","$conf_dir/localOverrides.conf.bak");
open(my $in,"<","$conf_dir/localOverrides.conf.bak");
open(my $out,">","$conf_dir/localOverrides.conf");
while(<$in>) {
  if(/^1;/) {
    print $out "push(\@{\$pg{modules}},[qw(Chromatic)]);\n1;\n";
  } else {
    print $out $_;
  }
}
#push(@{$ce->{pg}->{modules}},[qw(Chromatic)]);
#foreach(@{$ce->{pg}->{modules}}) {
# print "@{$_}\n";
# }

chdir($cwd);
