#!/usr/bin/env perl

use strict;
use warnings;
use version; 

use lib 'lib';

use Config;
use Cwd;

use Data::Dumper;
use DateTime;
use DateTime::TimeZone;    #non-core!
use DBI;

use File::Path qw(make_path remove_tree);
use File::Spec;
use File::Copy;
#use File::CheckTree;

use Getopt::Long;

use IPC::Cmd qw(can_run run);

use List::Util qw(max);

use Pod::Usage;

use Sys::Hostname;

use Term::UI;
use Term::ReadLine;
use Term::ReadPassword; #to be found in lib/

use User::pwent;

use IO::Handle qw();
STDOUT->autoflush(1);
STDERR->autoflush(1);

#########################################################
#
# Process Options
#
#########################################################

my $interactive = 1;
my $mysql_root_password = '';
my $webwork_db_password = '';

GetOptions(
  'interactive!'=>\$interactive,
  'mysql_root_pw=s' => \$mysql_root_password,
  'webwork_db_pw=s' => \$webwork_db_password,
);

if(!$interactive) {
  die "To run non-interactively you must specify both the mysql root ".
      "password (--mysql_root_pw) and the webwork database password ".
      "(--webwork_db_pw)"
      unless $mysql_root_password && $webwork_db_password;
  Term::UI::AUTOREPLY = 1;
}


#########################################################
#
# Create a new Term::Readline object for interactivity
#Don't worry people with spurious warnings.
#
#########################################################

$Term::UI::VERBOSE = 0;
my $term = Term::ReadLine->new('');

#########################################################################################
#
# Defaults - each of these values is passed as a default to some config question
#
########################################################################################

use constant WEBWORK2_REPO => 'https://github.com/openwebwork/webwork2.git';
use constant PG_REPO       => 'https://github.com/openwebwork/pg.git';
use constant OPL_REPO =>
  'https://github.com/openwebwork/webwork-open-problem-library.git';
use constant MATHJAX_REPO => "https://github.com/mathjax/MathJax.git";

use constant WW_PREFIX => '/opt/webwork/';
use constant ROOT_URL  => 'http://localhost';
use constant WW_URL    => '/webwork2';

use constant SMTP_SERVER => 'localhost';
use constant SMTP_SENDER => 'webwork@localhost';

use constant WW_DB     => 'webwork';
use constant WWDB_USER => 'webworkWrite';

#########################################################################################
#
# Prerequisites - keep in sync with webwork2/bin/check_modules.pl
#		- right now we die if these aren't present, but later we'll offer
#		  to intall missing prereqs
#
########################################################################################

my @apacheBinaries = qw(
  apache2
  apachectl
);

my @applicationsList = qw(
  mv
  cp
  rm
  mkdir
  tar
  gzip
  latex
  pdflatex
  dvipng
  mysql
  giftopnm
  ppmtopgm
  pnmtops
  pnmtopng
  pngtopnm
  lwp-request
  mysql
  mysqldump
  svn
  git
);

my @apache1ModulesList = qw(
  Apache
  Apache::Constants
  Apache::Cookie
  Apache::Log
  Apache::Request
);

my @apache2ModulesList = qw(
  Apache2::Request
  Apache2::Cookie
  Apache2::ServerRec
  Apache2::ServerUtil
  
);

my @apache2SharedModules  = qw(
  mpm_prefork
  fcgid_module
  perl_module
  apreq_module
);

my @modulesList = qw(
  Benchmark
  Carp
  CGI
  Data::Dumper
  Data::UUID
  Date::Format
  Date::Parse
  DateTime
  DBD::mysql
  DBI
  Digest::MD5
  Email::Address
  Errno
  Exception::Class
  File::Copy
  File::Find
  File::Path
  File::Spec
  File::stat
  File::Temp
  GD
  Getopt::Long
  Getopt::Std
  HTML::Entities
  HTML::Scrubber
  HTML::Tagset
  HTML::Template
  IO::File
  Iterator
  Iterator::Util
  JSON
  Locale::Maketext::Lexicon
  Locale::Maketext::Simple
  Mail::Sender
  MIME::Base64
  Net::IP
  Net::LDAPS
  Net::OAuth
  Net::SMTP
  Opcode
  PadWalker
  PHP::Serialization
  Pod::Usage
  Pod::WSDL
  Safe
  Scalar::Util
  SOAP::Lite
  Socket
  SQL::Abstract
  String::ShellQuote
  Text::CSV
  Text::Wrap
  Tie::IxHash
  Time::HiRes
  Time::Zone
  URI::Escape
  UUID::Tiny
  XML::Parser
  XML::Parser::EasyTree
  XML::Writer
  XMLRPC::Lite
);

###########################################################
#
# Logging
#
###########################################################

# Globals: filehandle LOG is global.
if (!open(LOG,">> ../webwork_install.log")) {
    die "Unable to open log file.\n";
} else {
    print LOG 'This is ww_install.pl '.DateTime->now."\n\n";
}

sub writelog {
    while ($_ = shift) {
        chomp();
        print LOG "$_\n";
    }
}

sub print_and_log {
    while ($_=shift) {
        chomp();
        print "$_\n";
        print LOG "$_\n";
    }
}

#######################################################################################
#
# Constants that control behavior IPC::Cmd::run
#
# ####################################################################################

use constant IPC_CMD_TIMEOUT =>
  6000;    #Sets maximum time system commands will be allowed to run
use constant IPC_CMD_VERBOSE => 1;    #Controls whether all output of a command
                                      #should be printed to STDOUT/STDERR

sub run_command {
    my $cmd = shift; #should be an array reference
    my (
        $success, $error_message, $full_buf,
        $stdout_buf, $stderr_buf
      )
      = run(
        command => $cmd,
        verbose => IPC_CMD_VERBOSE,
        timeout => IPC_CMD_TIMEOUT
      );
      my $cmd_string = join(' ',@$cmd);
      writelog("Running [".$cmd_string."]:\n");
      writelog("STDOUT: ",@$stdout_buf) if @$stdout_buf;
      writelog("STDERR: ",@$stderr_buf) if @$stderr_buf;
      if (!$success) {
        writelog($error_message) if $error_message;
        my $print_me = "Warning! The last command exited with an error: $error_message\n\n".
            "We have logged the error message, if any. We suggest that you exit now and ".
            "report the error at https://github.com/aubreyja/ww_install ".
            "If you are certain the error is harmless, then you may continue the installation ".
            "at your own risk.";
        my $choices = ["Continue the installation", "Exit"];
        my $prompt = "What would you like to do about this?";
        my $default = "Exit";
        my $continue = get_reply({
            print_me=>$print_me,
            prompt=>$prompt,
            default=>$default,
            });
        if ($continue eq "Exit") {
            print_and_log("Bye. Please report this error asap.");
            die "Exiting..."
        } else {
            print_and_log("You chose to continue in spite of an error. There is a very good".
                          " chance this will end badly.\n");
        }
      } else {
        return 1;
      }
}

####################################################################################################
#
# Platform specific data - these data structures are to help with identifying our platform and
# eventually will be used for specifying prerequisite packages, likely locations of binaries we can't find
# with can_run(), and doing other platform specific processing. Such as
# (1) Disabling SELinux on RH/Fedora
# Others....
# ##################################################################################################

my %release_files = (
    'gentoo-release'        => 'gentoo',
    'fedora-release'        => 'fedora',
    'centos-release'        => 'centos',
    'enterprise-release'    => 'oracle enterprise linux',
    'turbolinux-release'    => 'turbolinux',
    'mandrake-release'      => 'mandrake',
    'mandrakelinux-release' => 'mandrakelinux',
    'debian_version'        => 'debian',
    'debian_release'        => 'debian',
    'SuSE-release'          => 'suse',
    'knoppix-version'       => 'knoppix',
    'yellowdog-release'     => 'yellowdog',
    'slackware-version'     => 'slackware',
    'slackware-release'     => 'slackware',
    'redflag-release'       => 'redflag',
    'redhat-release'        => 'redhat',
    'redhat_version'        => 'redhat',
    'conectiva-release'     => 'conectiva',
    'immunix-release'       => 'immunix',
    'tinysofa-release'      => 'tinysofa',
    'trustix-release'       => 'trustix',
    'adamantix_version'     => 'adamantix',
    'yoper-release'         => 'yoper',
    'arch-release'          => 'arch',
    'libranet_version'      => 'libranet',
    'va-release'            => 'va-linux',
    'pardus-release'        => 'pardus',
);

my %version_match = (
    'gentoo'  => 'Gentoo Base System release (.*)',
    'debian'  => '(.+)',
    'suse'    => 'VERSION = (.*)',
    'fedora'  => 'Fedora(?: Core)? release (\d+) \(',
    'redflag' => 'Red Flag (?:Desktop|Linux) (?:release |\()(.*?)(?: \(.+)?\)',
    'redhat'  => 'Red Hat(?: Enterprise)? Linux(?: Server)? release (.*) \(',
    'oracle enterprise linux' => 'Enterprise Linux Server release (.+) \(',
    'slackware'               => '^Slackware (.+)$',
    'pardus'                  => '^Pardus (.+)$',
    'centos'     => '^CentOS(?: Linux)? release (.+)(?:\s\(Final\))',
    'scientific' => '^Scientific Linux release (.+) \(',
);

#Apache 2.2 locations for various operating systems
#From http://wiki.apache.org/httpd/DistrosDefaultLayout
#Note that the above url may not contain current information
#double checking it with the docs for your favorite distro would
#be helpful

my $apache22Layouts = {
    httpd22 => {    #Apache 2.2 default layout
        MPMDir       => 'server/mpm/prefork',
        ServerRoot   => '/usr/local/apache2',
        DocumentRoot => '/usr/local/apache2/htdocs',
        ConfigFile   => '/usr/local/apache2/conf/httpd.conf',
        OtherConfig  => '/usr/local/apache2/conf/extra',
        SSLConfig    => '/usr/local/apache2/conf/extra/httpd-ssl.conf',
        ErrorLog     => '/usr/local/apache2/logs/error_log',
        AccessLog    => '/usr/local/apache2/logs/access_log',
        Binary          => '/usr/local/apache2/bin/apachectl',
        User         => '',
        Group        => '',
    },
    debian => {    #Checked 7.1 (mostly)
        MPMDir       => 'server/mpm/prefork',
        ServerRoot   => '/etc/apache2',
        DocumentRoot => '/var/www',
        ConfigFile   => '/etc/apache2/apache2.conf',
        OtherConfig  => '/etc/apache2/conf.d',
        SSLConfig    => '',
        Modules      => '/etc/apache2/mods_enabled',
        ErrorLog     => '/var/log/apache2/error.log',
        AccessLog    => '/var/log/access.log',
        Binary       => '/usr/sbin/apache2ctl',
        User         => 'www-data',
        Group        => 'www-data',
    },
    ubuntu => {    #Checked 12.04
        MPMDir       => 'server/mpm/prefork',
        ServerRoot   => '/etc/apache2',
        DocumentRoot => '/var/www',
        ConfigFile   => '/etc/apache2/apache2.conf',
        OtherConfig  => '/etc/apache2/conf.d',
        SSLConfig    => '',
        Modules      => '/etc/apache2/mods_enabled',
        ErrorLog     => '/var/log/apache2/error.log',
        AccessLog    => '/var/log/access.log',
        Binary       => '/usr/sbin/apache2ctl',
        User         => 'www-data',
        Group        => 'www-data',
    },
    rhel => {    
        MPMDir       => 'server/mpm/prefork',
        ServerRoot   => '/etc/httpd',
        DocumentRoot => '/var/www/html',
        ConfigFile   => '/etc/httpd/conf/httpd.conf',
        OtherConfig  => '/etc/httpd/conf.d',
        SSLConfig    => '',
        Modules      => '/etc/httpd/modules',           #symlink
        ErrorLog     => '/var/log/httpd/error_log',
        AccessLog    => '/var/log/httpd/access_log',
        Binary       => '/usr/sbin/apachectl',
        User         => 'apache',
        Group        => 'apache',
    },
    centos => {    
        MPMDir       => 'server/mpm/prefork',
        ServerRoot   => '/etc/httpd',
        DocumentRoot => '/var/www/html',
        ConfigFile   => '/etc/httpd/conf/httpd.conf',
        OtherConfig  => '/etc/httpd/conf.d',
        SSLConfig    => '',
        Modules      => '/etc/httpd/modules',           #symlink
        ErrorLog     => '/var/log/httpd/error_log',
        AccessLog    => '/var/log/httpd/access_log',
        Binary       => '/usr/sbin/apachectl',
        User         => 'apache',
        Group        => 'apache',
    },
    freebsd => {                                        #Checked on freebsd 8.2
        MPMDir       => '',
        ServerRoot   => '/usr/local',
        DocumentRoot => '/usr/local/www/apache22/data',
        ConfigFile   => '/usr/local/etc/apache22/httpd.conf',
        OtherConfig  => '/usr/local/etc/apache22/extra',
        SSLConfig    => '/usr/local/etc/apache22/extra/httpd-ssl.conf',
        Modules      => '',
        ErrorLog     => '/var/log/httpd-error.log',
        AccessLog    => '/var/log/httpd-access.log',
        Binary       => '/usr/sbin/apachectl',
        User         => 'www',
        Group        => 'www',
    },
    osx => {    #Checked on OSX 10.7
        MPMDir       => 'server/mpm/prefork',
        ServerRoot   => '/usr',
        DocumentRoot => '/Library/WebServer/Documents',
        ConfigFile   => '/etc/apache2/httpd.conf',
        OtherConfig  => '/etc/apache2/extra',
        SSLConfig    => '/etc/apache2/extra/httpd-ssl.conf',
        Modules      => '/usr/libexec/apache2',
        ErrorLog     => '/var/log/apache2/error_log',
        AccessLog    => '/var/log/apache2/access_log',
        Binary       => '/usr/sbin/apachectl',
        User         => '_www',
        Group        => '_www',
    },
    suse => {
        MPMDir       => '',
        ServerRoot   => '/srv/www',
        DocumentRoot => '/srv/www/htdocs',
        ConfigFile   => '/etc/apache2/httpd.conf',
        OtherConfig  => '/etc/sysconfig/apache2',
        SSLConfig    => '/etc/apache2/ssl-global.conf',
        ErrorLog     => '/var/log/apache2/httpd-error.log',
        AccessLog    => '/var/log/apache2/httpd-access.log',
        Binary       => '/usr/sbin/apachectl',
        User         => 'wwwrun',
        Group        => 'www',
    },
};

my $apache24Layouts = {
    httpd24 => {    #Apache 2.4 default layout
        MPMDir       => '',
        ServerRoot   => '/usr/local/apache2',
        DocumentRoot => '/usr/local/apache2/htdocs',
        ConfigFile   => '/usr/local/apache2/conf/httpd.conf',
        OtherConfig  => '/usr/local/apache2/conf/extra',
        SSLConfig    => '/usr/local/apache2/conf/extra/httpd-ssl.conf',
        ErrorLog     => '/usr/local/apache2/logs/error_log',
        AccessLog    => '/usr/local/apache2/logs/access_log',
        Binary          => '/usr/local/apache2/bin/apachectl',
        User         => '',
        Group        => '',
    },
    ubuntu => {    #Checked 13.10
        MPMDir       => '',
	MPMConfFile  => '/etc/apache2/mods-available/mpm_prefork.conf',
        ServerRoot   => '/etc/apache2',
        DocumentRoot => '/var/www',
        ConfigFile   => '/etc/apache2/apache2.conf',
        OtherConfig  => '/etc/apache2/conf-enabled',
        SSLConfig    => '',
        Modules      => '/etc/apache2/mods-enabled',
        ErrorLog     => '/var/log/apache2/error.log',
        AccessLog    => '/var/log/apache2/access.log',
        Binary       => '/usr/sbin/apache2ctl',
        User         => 'www-data',
        Group        => 'www-data',
    },
    fedora => {
	MPMDir       => '',
	MPMConfFile  => '/etc/httpd/conf.modules.d/00-mpm.conf',
        ServerRoot   => '/etc/httpd',
        DocumentRoot => '/var/www/html',
        ConfigFile   => '/etc/httpd/conf/httpd.conf',
        OtherConfig  => '/etc/httpd/conf.d',
        SSLConfig    => '',
        Modules      => '/etc/httpd/modules',           #symlink
        ErrorLog     => '/var/log/httpd/error_log',
        AccessLog    => '/var/log/httpd/access_log',
        Binary       => '/usr/sbin/apachectl',
        User         => 'apache',
        Group        => 'apache',
    },
};

my %linux = (
    'DISTRIB_ID'          => '',
    'DISTRIB_RELEASE'     => '',
    'DISTRIB_CODENAME'    => '',
    'DISTRIB_DESCRIPTION' => '',
    'release_file'        => '',
    'pattern'             => ''
);

sub get_os {
    my $os;
    if ( $^O eq "darwin" ) {
        $os->{type} = "unix";
        $os->{name} = "darwin";
        chomp( $os->{version} = `sw_vers -productVersion` );
        chomp( $os->{arch}    = `uname -p` );
        print_and_log("Great, you're on Mac running OS X $$os{version} on $$os{arch} hardware.");
    } elsif ( $^O eq "freebsd" ) {
        $os->{type} = "unix";
        $os->{name} = "freebsd";
        chomp( $os->{version} = `uname -r` );
        chomp( $os->{arch}    = `uname -p` );
        print_and_log("I see - rocking it on FreeBSD $$os{version} on $$os{arch} hardware.");
    } elsif ( $^O eq "linux" )
    {    #Now we're going to have to look more closely to get specific distro
        $os->{type}    = "linux";
        $os->{name}    = distribution_name();
        $os->{version} = distribution_version();
        chomp( $os->{arch} = `uname -p` );
        print_and_log("Linux, yay! That's my favorite. I see you're running $$os{name} "
          . "version $$os{version} on $$os{arch} hardware. This will be easy.\n");
    } elsif ( $^O eq "MSWin32" ) {
        print_and_log("Installing WeBWorK on Windows is, afaik, currently impossible.");
        print_and_log("If you get it working, please let us know. Good luck!");
    } else {
        $os->{type}    = $^O;
        $os->{name}    = distribution_name();
        $os->{version} = distribution_version();
        chomp( $os->{arch} = `uname -p` );
        print_and_log("I see you're running $$os{name} version $$os{version} on $$os{arch} hardware. "
          . "This script mostly finds the information it needs at run time. But, there are a few "
          . "places where we have hard coded OS specific details into data structures built into the "
          . "script. We don't have anything for your OS. The script will very likely still work. Either "
          . "way, it would be very helpful if you could send a report to webwork\@maa.org. We can help you "
          . "get it working if it doesn't work, and if it does we would like to add it to the list of supported "
          . "systems.");
    }
    return $os;
}

#Subroutines to find linux distribution and version

sub distribution_name {
    my $release_files_directory = '/etc';
    my $standard_release_file   = 'lsb-release';

    my $distro = get_lsb_info();
    if ($distro) {
        return $distro if ($distro);
    }

    foreach (qw(enterprise-release fedora-release)) {
        if ( -f "$release_files_directory/$_"
            && !-l "$release_files_directory/$_" )
        {
            if ( -f "$release_files_directory/$_"
                && !-l "$release_files_directory/$_" )
            {
                $linux{'DISTRIB_ID'}   = $release_files{$_};
                $linux{'release_file'} = $_;
                return $linux{'DISTRIB_ID'};
            }
        }
    }

    foreach ( keys %release_files ) {
        if ( -f "$release_files_directory/$_"
            && !-l "$release_files_directory/$_" )
        {
            if ( -f "$release_files_directory/$_"
                && !-l "$release_files_directory/$_" )
            {
                if ( $release_files{$_} eq 'redhat' ) {
                    foreach my $rhel_deriv ( 'centos', 'scientific', ) {
                        $linux{'pattern'}      = $version_match{$rhel_deriv};
                        $linux{'release_file'} = 'redhat-release';
                        my $file_info = get_file_info();
                        if ($file_info) {
                            $linux{'DISTRIB_ID'}   = $rhel_deriv;
                            $linux{'release_file'} = $_;
                            return $linux{'DISTRIB_ID'};
                        }
                    }
                    $linux{'pattern'} = '';
                }
                $linux{'release_file'} = $_;
                $linux{'DISTRIB_ID'}   = $release_files{$_};
                return $linux{'DISTRIB_ID'};
            }
        }
    }
    undef;
}

sub distribution_version {
    my $release_files_directory = '/etc';
    my $standard_release_file   = 'lsb-release';
    my $release;
    return $release if ( $release = get_lsb_info('DISTRIB_RELEASE') );
    if ( !$linux{'DISTRIB_ID'} ) {
        distribution_name() or die 'No version because no distro.';
    }
    $linux{'pattern'}         = $version_match{ $linux{'DISTRIB_ID'} };
    $release                  = get_file_info();
    $linux{'DISTRIB_RELEASE'} = $release;
    return $release;
}

sub get_lsb_info {
    my $field                   = shift || 'DISTRIB_ID';
    my $release_files_directory = '/etc';
    my $standard_release_file   = 'lsb-release';
    my $tmp                     = $linux{'release_file'};
    if ( -r "$release_files_directory/" . $standard_release_file ) {
        $linux{'release_file'} = $standard_release_file;
        $linux{'pattern'}      = $field . '=(.+)';
        my $info = get_file_info();
        if ($info) {
            $linux{$field} = $info;
            return $info;
        }
    }
    $linux{'release_file'} = $tmp;
    $linux{'pattern'}      = '';
    undef;
}

sub get_file_info {
    my $release_files_directory = '/etc';
    my $standard_release_file   = 'lsb-release';
    open my $fh, '<', "$release_files_directory/" . $linux{'release_file'}
      or die 'Cannot open file: '
      . $release_files_directory . '/'
      . $linux{'release_file'};
    my $info = '';
    local $_;
    while (<$fh>) {
        chomp $_;
        ($info) = $_ =~ m/$linux{'pattern'}/;
        return "\L$info" if $info;
    }
    undef;
}

#End of linux-finding subroutines.

sub get_existing_users {
    my $envir       = shift;
    my $passwd_file = $envir->{passwd_file};
    my $users;
    open( my $in, '<', $passwd_file );
    while (<$in>) {
        push @$users, ( split( ':', $_ ) )[0];
    }
    close($in);
    return $users;
}

sub get_existing_groups {
    my $envir      = shift;
    my $group_file = $envir->{group_file};
    my $groups;
    open( my $in, '<', $group_file );
    while (<$in>) {
        push @$groups, ( split( ':', $_ ) )[0];
    }
    return $groups;
}

sub user_exists {
    my ( $envir, $user ) = @_;
    my %users = map { $_ => 1 } @{ $envir->{existing_users} };
    return 1 if $users{$user};
}

sub group_exists {
    my ( $envir, $group ) = @_;
    my %groups = map { $_ => 1 } @{ $envir->{existing_groups} };
    return 1 if $groups{$group};
}

############################################################################################
#
# Script Util Subroutines:  The script is based on Term::Readline to interact with user
#
###########################################################################################
sub get_reply {
  my $defaults = {
   print_me => '',
   prompt => '',
   choices => [],
   default => '',
   checkers => [\&confirm_answer],
  }; 
  my $options = shift;
  foreach(keys %$defaults) {
    $options->{$_} = $options->{$_} // $defaults->{$_};
  }

  my $answer = $term->get_reply(
    print_me => $options->{print_me},
    prompt => $options->{prompt},
    choices => $options->{choices},
    default => $options->{default},
  );
  my $checked = { answer => $answer, status => 0};
  foreach my $checker (@{$options -> {checkers}}) {
    $checked = $checker->($checked->{answer});
    last unless $checked->{status};
  }
  $checked->{answer} = get_reply({print_me=> $options->{print_me},
      prompt => $options->{prompt},
      choices => $options->{choices},
      default => $options->{default},
      checkers =>$options->{checkers}}) unless $checked->{status}; 
  return $checked->{answer};
}


#For confirming answers
sub confirm_answer {
    my $answer  = shift;
    print "Ok, you entered: $answer. Please confirm.";

    my $confirm = $term->get_reply(
        print_me => "Ok, you entered: $answer. Please confirm.",
        prompt   => "Well? ",
        choices  => [ "Looks good.", "Change my answer.", "Quit." ],
        default  => "Looks good."
    );
    if ( $confirm eq "Quit." ) {
        die "Exiting...";
    } elsif ( $confirm eq "Change my answer." ) {
        return { answer => $answer, status => 0 };
    } else {
        return { answer => $answer, status => 1 };
    }
}


#####################################################
#
# Check if user is ready to install
#
# ###################################################

sub get_ready {

    my $print_me = <<EOF;
Welcome to the WeBWorK.  This installation script will ask you a few questions and then attempt to install 
WeBWorK on your system. To complete the installation
(a) You must be connected to the internet.
(b) You must have administrative privliges on this machine, and
(c) The mysql server must be running, and you should have already gone through the process of setting up the
root mysql account and securing your mysql server.  If you haven't done this or aren't sure if it has been done
then exit this script and do
'sudo service mysqld start' to start mysql, and then
'mysql_secure_installation' to secure the server and set the root password.
Once you know the root mysql password then you can come back to this script and install webwork.
EOF
    my $ready = $term->ask_yn(
        print_me => $print_me,
        prompt   => 'Ready to install WeBWorK?',
        default  => 'y',
    );
    die "Come back soon!" unless $ready;
}

####################################################################
#
# Check if the user is root
#
# We probably need to be root. The effective user id of the user running the script
# is held in the perl special variable $>.  In particular,
# if $> = 0 user is root, works with sudo too.
####################################################################

sub check_root {
    if ( $> == 0 ) {
        print_and_log("Running as root....");
        return 1;
    } else {

        #my $term = Term::ReadLine->new('');
        my $print_me = <<EOF;
IMPORTANT: I see that you are not running this script as root. Some elevated system
privliges are needed to install WeBWorK.  If you run the script without sufficient privilges then
it will fail in ways that might be hard to track down.    
EOF
        my $prefix = $term->ask_yn(
            print_me => $print_me,
            prompt =>
'Are you sure you\'re running the script with the privilges you\'ll need to complete the installation?',
            default => 'n',
        );
    }
}

sub get_selinux {
    my $enabled;
    my $disable;
    my $full_path = can_run('selinuxenabled');
    if($full_path) {
	my $cmd = [$full_path];
        $enabled = run(
          command => $cmd,
          verbose => IPC_CMD_VERBOSE,
          timeout => IPC_CMD_TIMEOUT
        );
     }
    if($enabled) {
	my $print_me=<<END;
######################################
#
# This machine appears to have SELinux
# enabled.  We strongly recommend disabling
# SELinux. If you choose not to disable
# SELinux then webwork will not work
# properly unless you can devise a 
# SELinux policy that allows it to do
# what it needs to function.
#
# If you choose to disable SELinux I
# will set it to permissive mode for
# this session and replace /etc/selinux/config
# with a config file that will disable
# SELinux permanently after a reboot.
#
#######################################
END
       $disable = $term->ask_yn(
  	    print_me => $print_me,
	    prompt => 'Disable SELinux?',
	    default => 'y',
        ); 
        my $confirmed = confirm_answer($disable);
        get_selinux() unless $confirmed->{status};
    }
    disable_selinux() if $disable;
    print_and_log("Good, SELinux not enabled.\n") unless $enabled;
    print_and_log("You've been warned!\n") if $enabled && !$disable;
}

sub disable_selinux {
    print_and_log("You've chosen to disable SELinux. Good choice."); 
    my $full_path = can_run('setenforce');
    my $cmd = [$full_path,"0"]; #set SELinux in permissive mode
    my $success = run_command($cmd);      
    copy('/etc/selinux/config','/etc/selinux/config.bak')
	or die "Couldn't make a backup of /etc/selinux/config: $!";
    copy('conf/webwork_selinux_config','/etc/selinux/config')
	or die "Couldn't copy conf/webwork_selinux_config to /etc/selinux/config: $!";
    print_and_log(<<END);
######################################################
#
# I have set SELinux to permissive mode for this session
# and replaced /etc/selinux/config with a config file that
# will permanently disable selinux.
#
# After this installation completes, you must reboot the
# machine to permanently disable SELinux
#
# ###################################################### 
END
}

sub get_wwadmin_user {
    my $envir    = shift;
    my $print_me = <<END;
###########################################################################
#
# The first decision is whether or not to create a webwork admin user. 
# The purpose ofdoing this would be to allow the webwork admin user to 
# edit the webwork system code (e.g. for updates) while restricting 
# that user from having write access to other files outside of his 
# home directory.  If the system administrator(s) and webwork
# application maintainer(s) are the same then there is no need to 
# create this user.
#
# If the maintainer of webwork (the webwork administrator) is not the 
# system administrator for the server, then you as a user with root 
# access must decide how to give the webwork admin sufficient privileges 
# to maintain webwork.  One approach, depending on your OS, is to give 
# that user root access by either addiing that user to the wheel group 
# or the sudoers file. This gives the webwork administrator complete
# access to the system, but if that's fine with you then it's fine with me too.
#
# The approach offered here is to create a webwork admin user and group. 
# All of the webwork code will be owned by this user.  The only webwork 
# files that will be writable by other users are those that must be 
# writable by the webserver. For those files and directories we will 
# create a new webwork data group to which we will add the 
# webwork admin user and the webserver.
#
# If you choose not to create this user, the webwork code will be owned 
# by root. We will still give you the opportunity to create the webwork 
# data group. Members of this group will be able to do limited webwork 
# maintenance tasks, such as creating courses from the command line and 
# managing logs, but will not be able edit webwork system files or other
# files that are writable by the webserver.
#
##########################################################################
END
    my $answer    = undef;
    my $confirmed = undef;
    my $exists    = undef;
    my $ww_admin  = undef;

    my $prompt = "Shall I create a webwork admin user?";
    $answer = $term->get_reply(
        print_me => $print_me,
        prompt   => $prompt,
        choices  => [
            "Yes, let's do it",
            "No, the root user will administer webwork",
            "No, a separate webwork admin user already exists"
        ],
        default => "Yes, let's do it",
    );

    #has this been confirmed?
    $confirmed = confirm_answer($answer);
    if ( $answer eq "Yes, let's do it" && $confirmed->{status} ) {
        $ww_admin = create_wwadmin_user($envir);
        return $ww_admin if $ww_admin;
        get_wwadmin_user($envir);    #Try again if not
    } elsif ( $answer eq "No, the root user will administer webwork"
        && $confirmed->{status} )
    {
        print
"Sounds good. We will not create a separate webwork admin user. The root user will administer webwork.\n";
        return "root";
    } elsif ( $answer eq "No, a separate webwork admin user already exists"
        && $confirmed->{status} )
    {
        $ww_admin = $term->get_reply(
            print_me =>
'Please enter the username of the webwork admin user. Note that this user must already exist on the system.',
            prompt  => 'webwork admin username:',
            default => 'wwadmin',
        );
        $confirmed = confirm_answer($ww_admin);
        $exists = user_exists( $envir, $ww_admin );
        if ( $confirmed->{status} && $exists ) {
            return $ww_admin;
        } elsif ( !$exists ) {
            print_and_log("Hey, silly goose, that user doesn't exist!");
            get_wwadmin_user($envir);
        } else {
            print_and_log("You didn't cofirm your last answer so let's try again.");
            get_wwadmin_user($envir);
        }
    } else {
        print_and_log("Let's try again.");
        get_wwadmin_user($envir);
    }
}

sub create_wwadmin_user {
    my $envir   = shift;
    my $wwadmin = $term->get_reply(
        print_me => "You chose to create a webwork admin user.",
        prompt   => "Please enter a username for the webwork admin user.",
        default  => "wwadmin",
    );
    my $exists_already = user_exists( $envir, $wwadmin );
    if ($exists_already) {
        print_and_log("Sorry, that user already exists. Try again.");
        get_wwadmin_user($envir);
    } else {

        my $wwadmin_pw = $term->get_reply(
            prompt =>
              "Please enter an initial password for the webwork admin user.",
            default => "wwadmin",
        );
        my $wwadmin_shell = $term->get_reply(
            prompt =>
              "Please enter a default shell for the webwork admin user.",
            default => $ENV{SHELL},
        );
        my $confirm = $term->ask_yn(
            prompt =>
"Shall I create a webwork admin user with username $wwadmin, initial password"
              . " $wwadmin_pw and default shell $wwadmin_shell?",
            default => 'y',
        );
        if ($confirm) {

   #useradd  -s /usr/bin/bash -c "WeBWorK Administrator" -p $wwadmin_pw $wwadmin
   #TODO: FreeBSD, MacOSX don't have useradd!!!
            my $full_path = can_run("useradd");
            my $cmd       = [ $full_path, '-m', #create user home dir
              '-s', $wwadmin_shell, #set default shell
              '-c', "WeBWorK Administrator",  #comment
              '-p', $wwadmin_pw, #password
              $wwadmin
            ];
            my $success = run_command($cmd);
            if ($success) {
                print_and_log("Created webwork admin user $wwadmin ".
                              "with initial password $wwadmin_pw and ".
                              "default shell $wwadmin_shell.");
                return $wwadmin;
            } else {
                print_and_log("There was an error creating $wwadmin");
                get_wwadmin_user($envir);
            }
        } else {
            print_and_log("Let's try again.");
            get_wwadmin_user($envir);
        }
    }

}

sub get_wwdata_group {
    my ( $envir, $apache, $wwadmin ) = @_;
    my $print_me = <<END;
#############################################################################
# Certain data directories need to be writable by the webserver.  These 
# are the webwork2/DATA, webwork2/htdocs/tmp, webwork2/logs, webwork2/tmp, 
# and the courses/ directories.
#
# It can convenient to give WeBWorK system administrators access to these 
# directories as well, so they can permform administrative tasks such as 
# removing temporary files, creating and editing courses from the command 
# line, managing logs, and so on.
#
# While it can be convenient to allow the WeBWorK administrator(s) to 
# manipulate the webwork files writable by the webserver, we may not want 
# to give him or her rights to manipulate other files writable by the 
# webserver.
#
# We can accomplish this by adding a new webwork data group to the system 
# containing any WeBWorK administrators and also containing the web server. 
# We will then recursively give the directories listed above permissions 
# g+sw and files in those directories g+w.
# 
# If you choose not to create the webwork data group, the webwork 
# directories listed above will be put into the same group as the 
# webserver. We will then recursively give those directories permissions 
# g+sw and the files in those directories permissions g+w.
#
###########################################################################
END
    my $answer    = undef;
    my $confirmed = undef;
    my $exists    = undef;
    my $group     = undef;

    my $prompt = "Shall I create a webwork data group? ";
    $answer = $term->get_reply(
        print_me => $print_me,
        prompt   => $prompt,
        choices  => [
            "Yes, let's do it",
            "No, we'll just use the webserver's group",
            "No, a separate webwork data group already exists"
        ],
        default => "Yes, let's do it",
    );

    #has this been confirmed?
    $confirmed = confirm_answer($answer);
    if ( $answer eq "Yes, let's do it" && $confirmed->{status} ) {
        $group = create_wwdata_group( $envir, $apache, $wwadmin );
        return $group if $group;
        get_wwdata_group( $envir, $apache, $wwadmin );    #Try again if not
    } elsif ( $answer eq "No, we'll just use the webserver's group"
        && $confirmed->{status} )
    {
        print
"Sounds good. We will not create a separate webwork data group. Instead we'lljust use the webserver's group.\n";
        return $apache->{Group};
    } elsif ( $answer eq "No, a separate webwork data group already exists"
        && $confirmed->{status} )
    {
        $group = $term->get_reply(
            print_me =>
'Please enter the group name of the webwork data group. Note that this group must already exist on the system.',
            prompt  => 'webwork data group name: ',
            default => 'wwdata',
        );
        $confirmed = confirm_answer($group);
        $exists = group_exists( $envir, $group );
        if ( $confirmed->{status} && $exists ) {
            return $group;
        } elsif ( !$exists ) {
            print "Hey, silly goose, that user doesn't exist!\n";
            get_wwdata_group( $envir, $apache, $wwadmin );    #Try again if not;
        } else {
            print "You didn't cofirm your last answer so let's try again.\n";
            get_wwdata_group( $envir, $apache, $wwadmin );    #Try again if not
        }
    } else {
        print "Let's try again.\n";
        get_wwdata_group( $envir, $apache, $wwadmin );        #Try again if not
    }
}

#Create webwork data group and add webserver and wwadmin (if user is not root)
sub create_wwdata_group {
    my ( $envir, $apache, $wwadmin ) = @_;
    my $group = $term->get_reply(
        print_me => "You chose to create a webwork data group.",
        prompt   => "What would you like to call the group?",
        default  => "wwdata",
    );

    #does this group exist?
    my $already_exists = group_exists( $envir, $group );
    if ($already_exists) {
        print "Oops - that group already exists. Let's try this again.\n";
        get_wwdata_group( $envir, $apache, $wwadmin );    #Try again if not
    } else {

        #group doesn't exist so now confirm answer
        my $confirmed = confirm_answer($group);
        copy( "/etc/group", "/etc/group.bak" );
        open( my $in, "<", "/etc/group.bak" )
          or die "Can't open /etc/group.bak for reading: $!";
        open( my $out, ">", "/etc/group" )
          or die "Can't open /etc/group for writing: $!";
        my @gids;
        while (<$in>) {
            push @gids, ( split( ':', $_ ) )[2];
            print $out $_;
        }
        my $new_gid = max(@gids) + 1;
        if ( $wwadmin eq 'root' ) {
            print $out "$group:*:$new_gid:" . $apache->{User} . "\n";
        } else {
            print $out "$group:*:$new_gid:" . $apache->{User} . ",$wwadmin\n";
        }
        return $group;
    }
}

##############################################################
#
# Adjust file ownership and permissions
#
#############################################################
#change_grp($server_groupid, $webwork_courses_dir, "$webwork_dir/DATA", "$webwork_dir/htdocs/tmp", "$webwork_dir/logs", "$webwork_dir/tmp");
#change_permissions($server_groupid, "$webwork_courses_dir", "$webwork_dir/DATA", "$webwork_dir/htdocs/tmp", "$webwork_dir/logs", "$webwork_dir/tmp");

#chgrp -R wwdata DATA ../courses htdocs/tmp logs tmp
# chmod -R g+w DATA ../courses htdocs/tmp logs tmp
# find DATA/ ../courses/ htdocs/tmp logs/ tmp/ -type d -a ! -name CVS -exec chmod g+s {}

sub change_owner {
    my $owner     = shift;
    my @dirs      = @_;
    my $full_path = can_run('chown');
    
    my $cmd       = [ $full_path, '-R', $owner, @dirs ];
    my $success = run_command($cmd);
    if ($success) {
        print_and_log("Changed ownership of @dirs and below to $owner.");
    } else {
        print_and_log("There was an error changing ownership of @dirs to $owner.");
    }
    
}

# chmod -R g+w DATA ../courses htdocs/tmp logs tmp
# find DATA/ ../courses/ htdocs/tmp logs/ tmp/ -type d -a ! -name CVS -exec chmod g+s {}
sub change_data_dir_permissions {
    my ( $gid, $courses, $data, $htdocs_tmp, $logs, $tmp, $webwork3log ) = @_;
    my $chmod = can_run('chmod');
    my $cmd =
      [ $chmod, '-R', 'g+w', $courses, $data, $htdocs_tmp, $logs, $tmp ];
    my $chmod_success = run_command($cmd);
    if ($chmod_success) {
        print_and_log("Made the directories \n $courses,\n $data,\n $htdocs_tmp,\n".
                      " $logs,\n $tmp\n group writable.\n");
    } else {
        print_and_log("Could not make the directories group writable!");
    }
    my $find = can_run('find');
    $cmd = [
        $find,    $courses, $data,  $htdocs_tmp, $logs,  $tmp,
        '-type',  'd',      '-and', '!',         '(',    '-name',
        '".git"', '-prune', ')',    '-exec',     $chmod, 'g+s',
        '{}',     ';'
    ];
    my $find_success = run_command($cmd);;
    if ($find_success) {
        print_and_log("Added group sticky bit to \n $courses,\n $data,\n $htdocs_tmp,\n $logs,\n".
                      " $tmp\n and subdirectories (except .git's).\n");
    } else {
        print_and_log("Error. Could not add sticky bit.");
    }
}

sub change_webwork3_log_permissions {
    my $owner     = shift;
    my $webwork3log = shift;

    my $full_path = can_run('chown');
    my $cmd       = [ $full_path, '-R', $owner, $webwork3log ];
    my $success = run_command($cmd);
    if ($success) {
        print_and_log("Changed ownership of $webwork3log to $owner.");
    } else {
        print_and_log("There was an error changing ownership $webwork3log to $owner.");
    }

    $full_path = can_run('chmod');
     $cmd =
	 [ $full_path, '-R', 'g+w', $webwork3log ];
    my $chmod_success = run_command($cmd);
    if ($chmod_success) {
        print_and_log("Made the directory $webwork3log group writable.\n");
    } else {
        print_and_log("Could not make $webwork3log group writable!");
    }
}


####################################################################
#
# Environment Data
#
# What use is this information?
# - any reason to get the hostname?
# - maybe warn against perl versions that are too old; version specific perl bugs?
# - maybe process timezone separately?
####################################################################

sub check_environment {
    print_and_log(<<EOF);
###################################################################
#
# Getting basic information about your environment 
#
# #################################################################
EOF

    my $envir;
    $envir->{host} = hostname;
    print_and_log("And your hostname is " . $envir->{host});
    $envir->{perl} = $^V;
    print_and_log("You're running Perl " . $envir->{perl});
    my $timezone = DateTime::TimeZone->new( name => 'local' );
    $envir->{timezone} = $timezone->name;
    print_and_log("Your timezone is " . $envir->{timezone});
    $envir->{os}          = get_os();
    $envir->{passwd_file} = "/etc/passwd" if -e "/etc/passwd";
    $envir->{group_file}  = "/etc/group" if -e "/etc/group";

    #we're going to get a list of users and groups on the system
    #for use later when we create our own users and groups. Also
    #to double check information, such as user and group for apache
    $envir->{existing_users}  = get_existing_users($envir);
    $envir->{existing_groups} = get_existing_groups($envir);

    return $envir;
}

sub check_apache {
    my ( $envir ) = @_;

    print_and_log(<<EOF);
###################################################################
#
# Gathering information about Apache
#
# #################################################################
EOF

    my $apache;
    $apache->{binary} =
      File::Spec->canonpath( can_run('apache2ctl') || can_run('apachectl') )
      or die "Can't find Apache!\n";

    open( HTTPD, $apache->{binary} . " -V |" ) or die "Can't do this: $!";
    print_and_log("Your apache start up script is at " . $apache->{binary});

    #Get some information from apache2 -V
    while (<HTTPD>) {
        if ( $_ =~ /apache.(\d\.\d\.\d+)/i ) {
            $apache->{version} = $1;
            print_and_log("Your apache version is " . $apache->{version});
        } elsif ( $_ =~ /HTTPD_ROOT\=\"((\/\w+)+)\"$/ ) {
            $apache->{root} = File::Spec->canonpath($1);
            print_and_log("Your apache server root is " . $apache->{root});
        } elsif ( $_ =~ /SERVER_CONFIG_FILE\=\"((\/)?(\w+\/)*(\w+\.?)+)\"$/ ) {
            $apache->{conf} = File::Spec->canonpath($1);
            my $is_absolute =
              File::Spec->file_name_is_absolute( $apache->{conf} );
            if ($is_absolute) {
                next;
            } else {
                $apache->{conf} = File::Spec->canonpath(
                    $apache->{root} . "/" . $apache->{conf} );
            }
            print_and_log("Your apache config file is " . $apache->{conf});
        }
    }
    close(HTTPD);

    return $apache; 
}

sub get_apache_user_group {
    my ( $apache, $envir, $apacheLayout ) = @_;

#Determining apache user/group is hard. Sometimes it's in the main conf file.
#Here we check that, but maybe we should check all conf files under /etc/apache2?
    #Make sure we didn't get a bogus user/group from httpd.conf
    my $os_name = $envir->{os}->{name};
    my %users   = map { $_ => 1 } @{ $envir->{existing_users} };
    my %groups  = map { $_ => 1 } @{ $envir->{existing_groups} };
    unless (($apache->{User} && 
	 $apache->{Group}) &&
	($users{$apache->{User}} &&
	$groups{$apache->{Group}})) {

	open( HTTPDCONF, $apache->{conf} ) or die "Can't do this: $!";
	
	while (<HTTPDCONF>) {
	    if (/^User/) {
		( undef, $apache->{User} ) = split;
	    } elsif (/^Group/) {
		( undef, $apache->{Group} ) = split;
	    }
	}
	close(HTTPDCONF);
	
    }

    print_and_log("Apache runs as user " . $apache->{User});
    print_and_log("Apache runs in group " . $apache->{Group});
    return $apache;
}


sub enable_mpm_prefork {
    my ( $apache, $envir ) = @_;

    return if (version->parse($apache->{version}) < version->parse('2.4.00'));

    if (can_run('a2enmod')) {
	my $a2enmod_cmd = ['a2dismod','mpm_event'];
	my $success = run_command($a2enmod_cmd);

	$a2enmod_cmd = ['a2enmod','mpm_prefork'];
	$success = run_command($a2enmod_cmd);

	print_and_log("Enabled MPM Prefork\n");
    }
}

sub check_apache_modules {
    my ( $apache, $envir ) = @_;
    my %module_hash;

    open( HTTPD, $apache->{binary} . " -M |" ) or die "Can't do this: $!";

    # check to see if mpm and fcgid are installed
    while (<HTTPD>) {
	foreach my $module (@apache2SharedModules) {
	    if (/$module/) {
		$module_hash{$module} = 1;
	    }
	}
    }

    close(HTTPD);

    foreach my $module (@apache2SharedModules) {
	if (!$module_hash{$module}) {
	    print_and_log("*Apache module $module not enabled!\n");
            die;
	}
    }
}

####################################################################
#
# Check for perl modules
#
# ##################################################################
# do we really want to eval "use $module;"?

sub check_modules {
    my @modulesList = @_;

    print_and_log("\nChecking your \@INC for modules required by WeBWorK...\n");
    my @inc = @INC;
    print_and_log("\@INC=");
    print join( "\n", map( "     $_", @inc ) ), "\n\n";

    foreach my $module (@modulesList) {
        eval "use $module";
        if ($@) {
            my $file = $module;
            $file =~ s|::|/|g;
            $file .= ".pm";
            if ( $@ =~ /Can't locate $file in \@INC/ ) {
                print_and_log("** $module not found in \@INC\n");
            } else {
                print_and_log("** $module found, but failed to load: $@");
            }
        } else {
            print_and_log("   $module found and loaded\n");
        }
    }
}

######################################################
#
#Check for prerequisites and get paths for binaries
#
######################################################

sub configure_externalPrograms {

    #Expects a list of applications
    my @applicationsList = @_;
    print_and_log("\nChecking your system for executables required by WeBWorK...\n");

    my $apps;
    foreach my $app (@applicationsList) {
        $apps->{$app} = File::Spec->canonpath( can_run($app) );
        if ( $apps->{$app} ) {
            print_and_log("   $app found at ${$apps}{$app}\n");
            if ( $app eq 'lwp-request' ) {
                delete $apps->{$app};
                $apps->{checkurl} = "$app" . ' -d -mHEAD';
            }
        } else {
            print_and_log("** $app not found in \$PATH\n");
            die;
        }
    }
    my ( undef, $netpbm_prefix, undef ) =
      File::Spec->splitpath( ${$apps}{giftopnm} );
    $$apps{gif2eps} =
        "$$apps{giftopnm}" . " | "
      . $$apps{ppmtopgm} . " | "
      . $$apps{pnmtops}
      . " -noturn 2>/dev/null";
    $$apps{png2eps} =
        "$$apps{pngtopnm}" . " | "
      . $$apps{ppmtopgm} . " | "
      . $$apps{pnmtops}
      . " -noturn 2>/dev/null";
    $$apps{gif2png} = "$$apps{giftopnm}" . " | " . "$$apps{pnmtopng}";

    return $apps;
}

sub get_webwork2_repo {
    my $default  = shift;
    my $print_me = <<END;
##########################################################################################
#
# There are two bundles of code to download that comprise webwork: The 'webwork2'
# code constitutes the web application, and the 'pg' code which defines the language in
# which webwork problems are written and is responsible for translating webwork problem
# for display on the web or in print, answer checking, etc.
#
# We're about to download that code and the WeBWorK Open Problem Library.  Most users
# will want to download the code from the standard github repositories.  But some users
# will want to use their own custom repositories.  Here we ask where you would like to
# download webwork2, pg, and the OPL from.  To accept the defaults, and download the code 
# from the standard repositories, just hit enter. Otherwise, enter your custom urls.  
#
###########################################################################################
END

    my $repo = $term->get_reply(
        print_me => $print_me,
        prompt   => 'Where would you like to download webwork2 from?',
        default => $default,    #constant defined at top
    );

    #has this been confirmed?
    my $confirmed = 0;
    $confirmed = confirm_answer($repo);
    if ($confirmed->{status}) {
        print_and_log("Got it, I'll download webwork2 from $repo.\n");
        return $repo;
    } else {
        get_webwork2_repo($default);
    }
}

sub get_pg_repo {
    my $default = shift;
    my $repo    = $term->get_reply(

        #print_me => $print_me,
        prompt => 'Where would you like to download pg from?',
        default => $default,    #constant defined at top
    );

    #has this been confirmed?
    my $confirmed = 0;
    $confirmed = confirm_answer($repo);
    if ($confirmed->{status}) {
        print_and_log("Got it, I'll download pg from $repo.\n");
        return $repo;
    } else {
        get_pg_repo($default);
    }
}

sub get_opl_repo {
    my $default = shift;
    my $repo    = $term->get_reply(
        #print_me => $print_me,
        prompt  => 'Where would you like to download the OPL from?',
        default => $default,
    );

    #has this been confirmed?
    my $confirmed = 0;
    $confirmed = confirm_answer($repo);
    if ($confirmed->{status}) {
        print_and_log("Got it, I'll download the OPL from $repo.\n");
        return $repo;
    } else {
        get_opl_repo($default);
    }

}

sub is_absolute {
  my $dir = shift;
  $dir = File::Spec->canonpath($dir);
  my $is_absolute = File::Spec->file_name_is_absolute($dir);
  if($is_absolute) {
    return { answer => $dir, status => 1 };
  } else {
    my $abs_dir = File::Spec->rel2abs($dir);
    my $fix = $term->get_reply(
       print_me => "I need an absolute path, but you gave me a relative path.",
       prompt => "How do you want me to fix this? ",
       choices => [ "Go back", "I really meant $abs_dir", "Quit" ],
     );
   if( $fix eq "Go back") {
     return { answer => $dir, status => 0 };
   } elsif( $fix eq "I really meant $abs_dir" ) {
     return { answer => $abs_dir, status => 1 }
   } elsif( $fix eq 'Quit' ) {
     die "Exiting...";
   }

  }
}

sub check_path {
 chomp(my $given = shift);
 my $exists = -e $given;
 return { answer => $given, status=> 1} unless $exists;

 my $reply = $term->get_reply( 
      print_me => "Error! You gave me a path which already exists on the filesystem.",       
      choices => ['Enter new location',"Delete existing $given and use that location","Quit"],
      prompt => 'How would you like to proceed?',
      default => 'Enter new location',
    ); 

 if($reply eq 'Enter new location') {
   return { answer=> $given, status => 0 };
 } elsif($reply eq "Delete existing $given and use that location") {
   return { answer=> $given, status => 1 };
 } elsif($reply eq "Quit") {
   die "Quitting..."
 }
}

sub get_WW_PREFIX {
    my $default  = shift;
    my $dir = get_reply({
    print_me => <<END,
#################################################################
# Installation Prefix: Please enter the absolute path of the directory
# under which we should install the webwork software. A typical choice
# is /opt/webwork/. We will create four subdirectories under your PREFIX:
#
# PREFIX/webwork2 - for the core code for the web-applcation
# PREFIX/pg - for the webwork problem generating language PG
# PREFIX/libraries - for the Open Problem Library and other problem libraries
# PREFIX/courses - for the individual webwork courses on your server
#
# Note that we will also set a new system wide environment variable WEBWORK_ROOT 
# to PREFIX/webwork2/
#################################################################
END
    prompt => 'Where should I install webwork?',
    default=>$default,
    checkers => [\&is_absolute,\&check_path, \&confirm_answer],
  });
      print "Got it, I'll create $dir and install webwork there.\n";
      return $dir;
}


sub get_root_url {
    my $default  = shift;
    my $print_me = <<END;
#################################################################
# Server root url: Please enter the url of your webwork server. If you
# are just installing it locally for testing, you probabably want
#
# http://localhost
#
# If you are installing it for production use, then you should use the
# url users will go to for access to the application, something like
#
# http://webwork.math.yourschool.edu
#
# This script does not currently configure SSL.  Obviously, if this
# is for production use you'll want to use SSL. However, for now just
# use http and after you get the application running then come back and
# hook up ssl.
#################################################################
END
    my $answer = $term->get_reply(
        print_me => $print_me,
        prompt   => 'Server root url:',
        default  => $default,
    );

    #has this been confirmed?
    my $confirmed = confirm_answer($answer);
    if ($confirmed->{status}) {
        print_and_log("Thanks, got it, I'll use \"$answer\" \n");
        return $answer;
    } else {
        get_root_url($default);
    }
}

sub get_webwork_url {
    my $default  = shift;
    my $print_me = <<END;
#################################################################
# Location of the webwork handler: Please enter the location of the
# webwork handler relative to the server root url. A typical 
# choice for this is 
#
# "/webwork2"
#
# which means that the application will be found at
#
# http://webwork.math.yourschool.edu/webwork2
#
# given a server root url of http://webwork.math.yourschool.edu
#
# You might be tempted to put webwork on the server root, in which
# case you would enter "/".  However, we don't recommend this.
# Unless you really know what you are doing, just trust us and
# use "/webwork2".
#################################################################
END
    my $prompt = "Relative location of webwork handler:";
    my $answer = $term->get_reply(
        print_me => $print_me,
        prompt   => $prompt,
        default  => $default,
    );

    #has this been confirmed?
    my $confirmed = confirm_answer($answer);
    if ($confirmed->{status}) {
        print_and_log("Thanks, got it, I'll use \"$answer\" \n");
        return $answer;
    } else {
        get_webwork_url($default);
    }
}

############################################################################
#
#Configure the %mail hash
#
############################################################################

sub get_smtp_server {
    my $default  = shift;
    my $print_me = <<END;
#################################################################
# SMTP Server:  Maybe something like 'mail.yourschool.edu'.  If
# you're not sure 'localhost' is a good choice. 
#################################################################
END
    my $prompt = "SMTP server:";
    my $answer = $term->get_reply(
        print_me => $print_me,
        prompt   => $prompt,
        default  => $default,
    );

    #has this been confirmed?
    my $confirmed = confirm_answer($answer);
    if ($confirmed->{status}) {
        print_and_log("Thanks, got it, I'll use \"$answer\" \n");
        return $answer;
    } else {
        get_smtp_server($default);
    }
}

sub get_smtp_sender {
    my $default  = shift;
    my $print_me = <<END;
##############################################################################
# SMTP Sender:  Maybe something like 'webwork\@yourserver.yourschool.edu'. If
# you're not setting this up right now, 'webwork\@localhost' is fine.
##############################################################################
END
    my $prompt = "SMTP sender:";
    my $answer = $term->get_reply(
        print_me => $print_me,
        prompt   => $prompt,
        default  => $default,
    );

    #has this been confirmed?
    my $confirmed = confirm_answer($answer);
    if ($confirmed->{status}) {
        print_and_log("Thanks, got it, I'll use \"$answer\" \n");
        return $answer;
    } else {
        get_smtp_server($default);
    }
}

############################################################################
#
#Configure the database
#
############################################################################

sub database_exists {
  my ($root_password,$database,$server) = @_;
  my $dbh = DBI->connect("dbi:mysql:database=information_schema;host=$server", 'root', $root_password, { 'RaiseError' => 1 } );
  my $databases = $dbh->selectcol_arrayref('show databases');
  $dbh->disconnect();
  foreach(@$databases) {
    return 1 if $database eq $_;
  }
  return 0;
}

sub connect_to_database {
  my ( $server, $ww_db, $ww_user, $ww_pw ) = @_;
  eval {
    my $dbh = DBI->connect("dbi:mysql:database=$ww_db;host=$server", $ww_user, $ww_pw, { 'RaiseError' => 1 } );
  };
  if($@) {
    print_and_log("Something's wrong: $@");
    return 0;
  } else {
    print_and_log("Connected to $ww_db on $server as $ww_user...\n");
    return 1;
  }
}

############################################################################
#
#Configure the database
#
############################################################################

sub get_mysql_root_password {

  my $password = shift;
  return $password if $password;

  print_and_log(<<END);
############################################################################
# Please enter the root mysql password. 
#############################################################################

END
    my $password;
    while(1) {
      my $double_check;
      $password = read_password('MySQL root password: ');
      $double_check = read_password('Please confirm MySQL root password: ') if $password;
      if($password eq $double_check)  {
          print_and_log("MySQL root password confirmed.\n\n");
          last;
       } else {
          print_and_log("Sorry, the passwords you entered did not match.\n\n");
          redo;
        }
    }
    return $password;
}

sub get_storage_engine {
    my $print_me = <<END;
#############################################################
#  
#  The default engine for MySQL is InnoDB as of MySQL 5.5.5 
#  (MyISAM before 5.5.5) but (at least on some hardware) InnoDB 
#  seems to be 50-100 times slower than MyISAM. So we recommend
#  changing the default MySQL storange engine from InnoDB to 
#  MyISAM. Note that this change only applies to new tables, 
#  tables already constructed will continue to use InnoDB. 
#  But we haven't created any WeBWorK tables so we don't have 
#  to change the engine for any existing tables.  
#
##############################################################
END
    my $prompt = "Change default mysql storage engine to MyISAM?";
    my $engine= $term->ask_yn(
        print_me => $print_me,
        prompt => $prompt,
        default => 'y',
      );
      my $confirmed = confirm_answer($engine);
      if($confirmed->{answer} && $confirmed->{status}) {
        change_storage_engine('/etc/mysql/my.cnf'); #this should be searched for
      } else {
        print_and_log("OK. We won't modify MySQL's default storage engine");
      }
}

sub change_storage_engine {
  my $my_cnf = shift; 
  my (undef,$dir,$file) = File::Spec->splitpath($my_cnf);
  my $engine = 'myisam';
  open(my $fh,'<',$my_cnf) or print_and_log("Couldn't find $my_cnf: $!");
  return unless $fh;
  copy($my_cnf,$dir."/".$file.".bak");
  my $string = do { local($/); <$fh> };
  close($fh);
  open(my $new,'>',$my_cnf);
  $string =~ s/\[mysqld\]/\[mysqld\]\n#\n# webwork wants this:\n#\n\ndefault-storage-engine = $engine\n/;
  print $new $string;
  print_and_log("Modified $my_cnf to set MyISAM to be default MySQL storage engine");
}

# Is there an existing webwork db or would you like me to create one?

sub get_webwork_database {
    
    my ($mysql_root_password, $webwork_db_password) = @_;

    my $print_me = <<END;
#############################################################
#  We now need to designate a MySQL database and database user
#  for webwork.  First we need to know which server hosts your
#  MySQL database and the port through which we can access it.
#  The answer will be of the form 'serverName:port'. If your
#  MySQL server is on this machine, your server name is 
#  'localhost'.  You may omit the port number if your MySQL 
#  server is listening on the dfault port of 3306.
#############################################################
END
    my $prompt = "Please enter the MySQL server and port ";
    my $choices = [];
    my $default = 'localhost';
    my $server = get_reply({
        print_me => $print_me,
        prompt => $prompt,
        default => $default,
      });
    $print_me = <<END;
##############################################################
#  If you would like me to create a new database and user for 
#  webwork, you will need ot know the root mysql password.
#
#  If such a database and mysql user has already been created, 
#  you will need to know (a) the name of the database, (b) the 
#  name and password of the mysql user with the appropriate 
#  privileges on that database.
###############################################################
END
    $prompt = "Create a new database or use an existing one? ";
    $choices = ['Create a new database','Use an existing database'];
    $default = 'Create a new database';
    my $new_or_existing = get_reply({
        print_me => $print_me,
        prompt => $prompt,
        choices => $choices,
        default => $default
      });     
    if($new_or_existing eq 'Create a new database') {
      print_and_log(<<END);
###################################################################
# Great, we'll create a new mysql database for webwork. To do so
# we'll need the root mysql password.
# ##################################################################
END
      my $mysql_root_password = get_mysql_root_password($mysql_root_password);
      my $print_me =<<END;
########################################################################
# Thanks. I'll keep it secret. Please choose a name for the webwork 
# database. It can be anything that conforms to mysql's rules for 
# database names.  If you don't know those, just be sensible and things 
# will probably be ok. (Or look up the rules if you are inclined to 
# be unsensible.)  Also, you can't choose something that is the name of
# an existing mysql database.
########################################################################
END
      my $prompt = "Name for the webwork database:";
      my $database = get_reply({
          print_me => $print_me,
          prompt => $prompt,
          default => WW_DB,
        });
      my $exists = database_exists($mysql_root_password,$database,$server);
      if($exists) {
        print_and_log("\n\nSorry, Charlie. That database already exists. Let's try".
          " this again.\n\n");
        sleep(2);
        get_webwork_database($mysql_root_password, $webwork_db_password);
      } else {
        my $username = get_database_username(WWDB_USER);
        my $password = get_database_password($webwork_db_password);
        create_database( $server, $mysql_root_password, $database,
            $username, $password );
        return ($database,$server,$username,$password);
      }
    } elsif($new_or_existing eq 'Use an existing database') {
      my $print_me =<<END;
###################################################################
# Ok, we can use an existing database.
####################################################################
END
      my $prompt = "Name of the existing webwork database:";
      my $database = get_reply({
        print_me => $print_me,
        prompt => $prompt,
        default => WW_DB,
      });
      my $username = get_database_username(WWDB_USER);
      my $password = get_database_password($webwork_db_password);
      my $can_connect = connect_to_database($server,$database,$username,$password);
      return ($database,$server,$username,$password) if $can_connect;
      get_webwork_database($mysql_root_password, $webwork_db_password);
    } else {
      get_webwork_database(W$mysql_root_password, $webwork_db_password);
    }
}

sub get_dsn {
    my ($database,$server) = @_;
    return "dbi:mysql:$database:$server";
}

sub get_database_username {
    my $default  = shift;
    my $print_me = <<END;
#############################################################################
# Now we need new mysql user with the necessary privileges on the 
# webwork database. For maximum security, this user should have no 
# privileges on other tables.  So, 'root' is a bad choice. 
#
# If you created a new webwork database, we suggest creating a new user 
# for that database. In that case, we will give that user the appropriate
# privileges. 
#
# If you are using an existing database, we are expecting you to 
# also use an existing database user here and we are expecting that this 
# database user has appropriate privileges on that database.
###############################################################################
END
    my $prompt = "webwork database username:";
    my $answer = get_reply({
        print_me => $print_me,
        prompt => $prompt,
        default => $default,
      });
}

sub get_database_password {
    
    my $password = shift;
    return $password if $password;

    my $print_me = <<END;
##############################################################################
# Now we need a password to identify the webwork database user.  Note that
# this password will be written into one of the (plain text) config files
# in webwork2/conf/.  So, it's important for security that this password not be
# the same as the mysql root password.
#
# If you created a new database and a new database user, then you can enter
# any password you like here.
#
# If you are using an existing database and db user, then we are expecting you
# to use the existing password for that user.
##############################################################################
END
    my $prompt = "Please enter webwork database password:";
    my $answer = get_reply({
      print_me => $print_me,
      prompt => $prompt,
    });
}


#############################################################
#
# Put software in correct location, write configuration files
#
#############################################################

###########################################################################
#
# Create prefix path
#
# ########################################################################

sub create_prefix_path {
    my $dir = shift;
    remove_tree($dir,{ verbose => 1 }) if -e $dir;
    make_path($dir, {error => \my $err} );
         if (@$err) {
             for my $diag (@$err) {
                 my ($file, $message) = %$diag;
                 if ($file eq '') {
                     print_and_log("General error: $message");
                 }
                 else {
                     print_and_log("Problem creating $file: $message");
                 }
             }
         }
         else {
             print_and_log("Created $dir. No error encountered.");
         }
}

############################################################################
#
# Get the software, put it in the correct location
#
############################################################################

sub get_webwork {
    my ( $prefix, $apps, $wwadmin ) = @_;
    create_prefix_path($prefix);
    chdir $prefix or die "Can't chdir to $prefix";
    my $ww2_repo =
      get_webwork2_repo(WEBWORK2_REPO);   #WEBWORK2_REPO constant defined at top
    my $ww2_cmd = [$apps->{git},'clone',$ww2_repo];

    my $pg_repo = get_pg_repo(PG_REPO);    #PG_REPO constant defined at top
    my $pg_cmd = [$apps->{git},'clone',$pg_repo];

    my $opl_repo = get_opl_repo(OPL_REPO);    #OPL_REPO constant defined at top
    my $opl_cmd = [$apps->{git},'clone',$opl_repo];

    my $buffer;
    my $ww2_success = run_command($ww2_cmd);

    if ($ww2_success) {
        print_and_log("Fetched webwork2 successfully.\n");
        chdir "$prefix/webwork2";
        run_command(['git','checkout','-b','ww3','origin/ww3']);
        chdir $prefix;
    } else {
        print_and_log("Couldn't get webwork2!");
    }
    my $pg_success = run_command($pg_cmd);
    if ($pg_success) {
        print_and_log("Fetched pg successfully!");
    } else {
        print_and_log("Couldn't get pg!");
    }

    make_path( 'libraries', { owner => $wwadmin, group => $wwadmin } );
    make_path( 'courses',   { owner => $wwadmin, group => $wwadmin } );
    chdir "$prefix/libraries";

    my $opl_success = run_command($opl_cmd);;
    if ($opl_success) {
        print_and_log("Fetched OPL successfully");
    } else {
        print_and_log("Couldn't get OPL!");
    }
}

#############################################################
#
# Unpack jsMath fonts
#
#############################################################

sub unpack_jsMath_fonts {
    my $webwork_dir = shift;
    
    # check if jsMath even exists, since it doesn't anymore
    return if (!(-e "$webwork_dir/htdocs/jsMath/jsMath-fonts.tar.gz"));

    # cd /opt/webwork/webwork2/htdocs/jsMath
    chdir("$webwork_dir/htdocs/jsMath");
    system("tar vfxz jsMath-fonts.tar.gz");
    my $cmd = ["tar","vfxz","jsMath-fonts.tar.gz"];
    my $success = run_command($cmd);
    if ($success) {
        print_and_log("Unpacked jsMath fonts successfully!");
    } else {
        print_and_log("Could not unpack jsMath fonts! Maybe it doesn't matter.");
    }
    
}

sub get_MathJax {
    my $WW_PREFIX = shift;
    chdir($WW_PREFIX);

    my $full_path = can_run('git');
    #As of ww2.8, MathJax is no longer a git submodule.
    #pre-2.8 code: 
    #command: system("git submodule update --init");
    #my $cmd = [ $full_path, 'submodule', "update", "--init" ];

    my $cmd = [ $full_path, 'clone', MATHJAX_REPO];
    my $success = run_command($cmd);
    if ($success) {
        print_and_log("Downloaded MathJax to $WW_PREFIX/MathJax\n");
    } else {
        print_and_log("Could not download MathJax. You'll have to do this manually.");
    }
}

#copy("adminClasslist.lst","$prefix/courses/adminClasslist.lst");
#copy("defaultClasslist.lst","$prefix/courses/defaultClasslist.lst");
sub copy_classlist_files {
    my ( $webwork_dir, $courses_dir ) = @_;
    copy( "$webwork_dir/courses.dist/adminClasslist.lst",
        "$courses_dir/adminClasslist.lst" )
      or warn
"Couldn't copy $webwork_dir/courses.dist/adminClasslist.lst to $courses_dir."
      . " You'll have to copy this over manually: $!";
    print_and_log("Copied adminClasslist.lst to $courses_dir");
    copy( "$webwork_dir/courses.dist/defaultClasslist.lst", "$courses_dir" )
      or warn
"Couldn't copy $webwork_dir/courses.dist/defaultClasslist.lst to $courses_dir."
      . " You'll have to copy this over manually: $!";
    print_and_log("Copied defaultClasslist.lst file to $courses_dir\n");
}

sub symlink_model_course {
    my ( $webwork_dir, $courses_dir ) = @_;
    my $full_path = can_run('ln');
    my $dist_path =
      File::Spec->canonpath( $webwork_dir . '/courses.dist/modelCourse' );
    my $link_path = File::Spec->canonpath( $courses_dir . '/modelCourse' );
    my $cmd = [ $full_path, '-s', $dist_path, $link_path ];
    my $success = run_command($cmd);
    if ($success) {
        print_and_log("Symlinked $webwork_dir/courses.dist/modelCourse to $courses_dir/modelCourse");
    } else {
        print_and_log("Could not symlink $webwork_dir/courses.dist/modelCourse to $courses_dir/modelCourse. ".
                      "You'll have to do this manually: $!");
    }
}

#############################################################
#
# Create webwork database...
#
############################################################

sub create_database {
    my ( $dsn, $root_pw, $ww_db, $ww_user, $ww_pw ) = @_;
    my $dbh = DBI->connect( 'DBI:mysql:database=mysql', 'root', $root_pw );
    print_and_log("Connected to mysql as root...");
    $dbh->do("CREATE DATABASE IF NOT EXISTS $ww_db")
      or die "Could not create $ww_db database: $!\n";
    print_and_log("Created $ww_db database...");
    $dbh->do(
"GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, DROP, LOCK TABLES ON $ww_db.* TO $ww_user\@localhost IDENTIFIED BY '$ww_pw'"
      )
      or (print_and_log("Could not grant privileges to $ww_user on $ww_db database: $!") && die);
      
    print_and_log("Granted privileges...");
    $dbh->disconnect();
}

#############################################################
#
#  Write config files
#
############################################################

sub write_database_conf {
    my $conf_dir = shift;
    copy( "$conf_dir/database.conf.dist", "$conf_dir/database.conf" )
      or die "Can't copy database.conf.dist to database.conf: $!";
}

sub write_site_conf {
    my (
        $WW_PREFIX,         $conf_dir,          $webwork_url,
        $server_root_url,   $apache,            $database_dsn,
        $database_username, $database_password, $apps
    ) = @_;
    open( my $in, "<", "$conf_dir/site.conf.dist" )
      or die "Can't open $conf_dir/site.conf.dist for reading: $!";
    open( my $out, ">", "$conf_dir/site.conf" )
      or die "Can't open $conf_dir/site.conf for writing: $!";
    while (<$in>) {
        if (/^\$webwork_url/) {
            print $out "\$webwork_url = \"$webwork_url\";\n";
        } elsif (/^\$server_root_url/) {
            print $out "\$server_root_url = \"$server_root_url\";\n";
        } elsif (/^\$server_userID/) {
            print $out "\$server_userID = \"" . $apache->{User} . "\";\n";
        } elsif (/^\$server_groupID/) {
            print $out "\$server_groupID = \"" . $apache->{Group} . "\";\n";
        } elsif (/^\$database_dsn/) {
            print $out "\$database_dsn = \"$database_dsn\";\n";
        } elsif (/^\$database_username/) {
            print $out "\$database_username = \"$database_username\";\n";
        } elsif (/^\$database_password/) {
            print $out "\$database_password = \"$database_password\";\n";
        } elsif (/^\$externalPrograms{(\w+)}/) {
            next if ( $1 =~ /tth/ );
            print $out "\$externalPrograms{$1} = \"$$apps{$1}\";\n";
        } elsif (/^\$pg_dir/) {
            print $out "\$pg_dir = \"$WW_PREFIX/pg\";\n";
        } elsif (/^\$webwork_courses_dir/) {
            print $out "\$webwork_courses_dir = \"$WW_PREFIX/courses\";\n";
        } else {
            print $out $_;
        }
    }
}

sub write_localOverrides_conf {
    my ( $WW_PREFIX, $conf_dir ) = @_;
    open( my $in, "<", "$conf_dir/localOverrides.conf.dist" )
      or die "Can't open $conf_dir/localOverrides.conf.dist for reading: $!";
    open( my $out, ">", "$conf_dir/localOverrides.conf" )
      or die "Can't open $conf_dir/localOverrides.conf for writing: $!";
    while (<$in>) {
        if (/^\$problemLibrary{root}/) {
            print $out "\$problemLibrary{version} = \"2.5\";\n";
            print $out
"\$problemLibrary{root} = \"$WW_PREFIX/libraries/webwork-open-problem-library/OpenProblemLibrary\";\n";
        } elsif (/^\$pg{options}{displayMode}/) {
            print $out "\$pg{options}{displayMode} = \"MathJax\";\n";
        } else {
            print $out $_;
        }
    }
}

sub write_webwork3_conf {
    my ( $WW_PREFIX, $DB_PWD, $conf_dir ) = @_;
    open( my $in, "<", "$conf_dir/webwork3.conf.dist" )
      or die "Can't open $conf_dir/localOverrides.conf.dist for reading: $!";
    open( my $out, ">", "$conf_dir/webwork3.conf" )
      or die "Can't open $conf_dir/webwork3.conf for writing: $!";
    while (<$in>) {
        if (/^webwork_dir/) {
            print $out "webwork_dir: \"${WW_PREFIX}/webwork2\"\n";
        } elsif (/^pg_dir/) {
            print $out "pg_dir: \"${WW_PREFIX}/pg\"\n";
	} elsif (/^\s+password/) {
            print $out "        password: '$DB_PWD'\n";
        } else {
            print $out $_;
        }
    }
}

sub write_webwork_apache2_config {
    my $webwork_dir = shift;
    my $config_file = shift;
    my $conf_dir    = "$webwork_dir/conf";
    open( my $in, "<", "$conf_dir/${config_file}.dist" )
      or die "Can't open $conf_dir/${config_file}.dist for reading: $!";
    open( my $out, ">", "$conf_dir/${config_file}" )
      or die "Can't open $conf_dir/${config_file} for writing: $!";
    while (<$in>) {
        next if /^\#/;
        if (/^my\s\$webwork_dir/) {
            print $out "my \$webwork_dir = \"$webwork_dir\";\n";
        } else {
            print $out $_;
        }
    }
}

sub edit_httpd_conf {
  my $apache = shift;
  my $httpd_conf = $apache->{conf};

  my (undef,$dir,$file) = File::Spec->splitpath($httpd_conf);

  my $print_me = <<END;
#######################################################################
#
# Next, I would like to increase apache's page timout value from 300
# to 1200. 
#
#######################################################################
END
  my $prompt = "Please enter a value for Timeout:";
  my $default = 1200;
  my $timeout = get_reply({
      print_me => $print_me,
      prompt => $prompt,
      default => $default,
    });

   
  #Make a backup copy of the apache config file
  copy($httpd_conf,$dir."/".$file.".bak")
    or die "Couldn't copy $httpd_conf to ".$dir.$file.".bak: $!\n";
  print_and_log("Backed up $httpd_conf to ".$dir.$file.".bak");

  #Open apache config file for reading 
  open(my $fh, '<',$httpd_conf)
    or die "Couldn't open $httpd_conf for reading: $!\n";
  #read it into a string
  my $string = do { local($/); <$fh> };
  close($fh);

  #Make replacements
  if($string =~ /(Timeout\s+\d+)/s) {
   $string =~ s/$1/Timeout $timeout/;
  }

  #Open apache config file for writing and write!
  open($fh, '>',$httpd_conf)
    or die "Couldn't open $httpd_conf for writing: $!\n";
  print $fh $string;
  print_and_log("Set Timeout $timeout in $httpd_conf");
  close($fh);
}


sub edit_mpm_conf {
  my $apache = shift;
  my $httpd_conf = $apache->{MPMConfFile} || $apache->{conf};

  my (undef,$dir,$file) = File::Spec->splitpath($httpd_conf);

  my $print_me = <<END;

###################################################################
#
# Now I would like to modify the prefork MPM
# settings MaxClients and MaxRequestsPerChild. By default I'll change 
# MaxClients from 150 to 20 and MaxRequestsPerChild from 0 to 100.
#
# For WeBWorK a rough rule of thumb is 20 MaxClients per 1 GB of 
# memory.  So, e.g., if you have 4GB of RAM you may want to use
# MaxClients 80.
# 
######################################################################
END
  my $prompt = "Please enter a value for prefork MaxClients/MaxRequestWorkers:";
  my $default = 20;
  my $max_clients = get_reply({
      print_me => $print_me,
      prompt => $prompt,
      default => $default,
    });

  $prompt = "Please enter a value for prefork MaxRequestsPerChild/MaxConnectionsPerChild:";
  $default = 100;
  my $max_requests_per_child = get_reply({
      prompt => $prompt,
      default => $default,
    });

  #Make a backup copy of the apache config file
  copy($httpd_conf,$dir."/".$file.".bak")
    or die "Couldn't copy $httpd_conf to ".$dir.$file.".bak: $!\n";
  print_and_log("Backed up $httpd_conf to ".$dir.$file.".bak");

  #Open apache config file for reading 
  open(my $fh, '<',$httpd_conf)
    or die "Couldn't open $httpd_conf for reading: $!\n";
  #read it into a string
  my $string = do { local($/); <$fh> };
  close($fh);

  my $clients_directive = 'MaxClients';
  my $request_directive = 'MaxRequestsPerChild';

  if (version->parse($apache->{version}) >= version->parse('2.4.00')) {
      $clients_directive = 'MaxRequestWorkers';
      $request_directive = 'MaxConnectionsPerChild';
  }

  if($string =~ /\<IfModule (mpm\_prefork\_module|prefork\.c)\>.*?($clients_directive\s+\d+).*?\<\/IfModule\>/s) {
    $string =~ s/$2/$clients_directive           $max_clients/;
  } else {
      $string .= "\n $clients_directive           $max_clients\n";
  }
  if($string =~ /\<IfModule (mpm\_prefork\_module|prefork\.c)\>.*?($request_directive\s*\d+).*?\<\/IfModule\>/s) {
    $string =~ s/$2/$request_directive $max_requests_per_child/;
  } else {
      $string .= "\n $request_directive           $max_requests_per_child\n";
  }

  #Open apache config file for writing and write!
  open($fh, '>',$httpd_conf)
    or die "Couldn't open $httpd_conf for writing: $!\n";
  print $fh $string;
  print_and_log("Set prefork $clients_directive $max_clients in $httpd_conf");
  print_and_log("Set prefork $request_directive $max_requests_per_child in $httpd_conf");
  close($fh);
}

##########################################################
#
#  Configure environment (symlink webwork-apache2.config,
#  set path, WEBWORK_ROOT
#
##########################################################

sub configure_shell {
    my ($WW_PREFIX, $wwadmin) = @_;

    #We want to configure the shell of the wwadmin user, root, and the user that logged in.
    #export PATH=$PATH:/opt/webwork/webwork2/bin
    #export WEBWORK_ROOT=/opt/webwork/webwork2
    
    my $user = $ENV{SUDO_USER};
    my @users = ('root',$wwadmin,$user);
    my @unique = do { my %seen; grep { !$seen{$_}++ } @users };
    foreach(@unique) {
        #Remember that we used User::pwent which overrides the builtin pw* functions.
        my $pw  = getpwnam($_);
        my $dir = $pw->dir;
        if (-f "$dir/.bashrc") {
            copy("$dir/.bashrc","$dir/.bashrc.bak");
            open(my $bashrc,'>>',"$dir/.bashrc" ) or warn "Couldn't open $dir/.bashrc: $!";
            print $bashrc "export PATH=\$PATH:$WW_PREFIX/webwork2/bin\n";
            print_and_log("Added 'export PATH=\$PATH:$WW_PREFIX/webwork2/bin' to $dir/.bashrc");
            print $bashrc "export WEBWORK_ROOT=$WW_PREFIX/webwork2\n";
            print_and_log("Added 'export WEBWORK_ROOT=$WW_PREFIX/webwork2' to $dir/.bashrc");
            close($bashrc);
        }
        $ENV{'WEBWORK_ROOT'}="$WW_PREFIX/webwork2";
    }
}

sub setup_opl {
    my $WW_PREFIX = shift;
    symlink(
        "$WW_PREFIX/libraries/webwork-open-problem-library/OpenProblemLibrary",
        "$WW_PREFIX/courses/modelCourse/templates/Library"
    );
    system("$WW_PREFIX/webwork2/bin/OPL-update");

    #$ cd /opt/webwork/courses/modelCourse/templates/
    #$ sudo ln -s /opt/webwork/libraries/NationalProblemLibrary Library
    #cd /opt/webwork/libraries/NationalProblemLibrary
    #$ NPL-update ## after write config files since must have $db_pass
}

#############################################################
#
# Create admin course
#
############################################################

sub create_admin_course {
    my $WW_PREFIX = shift;

    # cd /opt/webwork/courses
    chdir("$WW_PREFIX/courses");
    system(
"$WW_PREFIX/webwork2/bin/addcourse admin --db-layout=sql_single --users=$WW_PREFIX/courses/adminClasslist.lst --professors=admin"
    );
}


sub install_chromatic {
  my $pg_dir = shift;

  chdir("$pg_dir/lib/chromatic");

  my $color_dot_c = File::Spec->canonpath("$pg_dir/lib/chromatic/color.c");
  #should now check that this really exists 

  my $gcc = can_run('gcc')
    or die "Can't find gcc - please install it and try again.";

  #gcc -O3 color.c -o color
  chdir("$pg_dir/lib/chromatic/");

  my $cmd = ['gcc','-O3',$color_dot_c,'-o','color']; #should be an array reference

  my $success = run_command($cmd);
  if ($success) {
    print_and_log("Compiled $color_dot_c."); 
  } else {
      print_and_log("Couldn't compile $color_dot_c.");
  }
}

#############################################################
#
# Restart apache and launch web-browser!
#
#############################################################

sub restart_apache {
    my $apache = shift;
    my $cmd = [ $apache->{binary}, 'restart' ];
    my $success = run_command($cmd);;
    if ($success) {
        print_and_log("Apache successfully restarted.");
    } else {
        print_and_log("Could not restart apache.");
    }
}

sub write_launch_browser_script {
    my ( $dir, $url ) = @_;

    #We want to open the browser as the user that logged in, not root if
    #using sudo. 
    my $username = $ENV{SUDO_USER} || $ENV{LOGNAME} || $ENV{USER} || getpwuid($<);

   #Remember that we used User::pwent which overrides the builtin pw* functions.
    my $pw  = getpwnam($username);
    my $uid = $pw->uid;
    my $gid = $pw->gid;

    #Now we need to get back to starting dir
    chdir $dir;

    #Get preferred web browser
    my $browser =
         can_run('xdg-open')
	 || can_run('x-www-browser')
      || can_run('www-browser')
      || can_run('gnome-open')
      || can_run('firefox');
    return unless $browser;
    open( my $out, ">", "launch_browser.sh" )
      or die "Can't open launch_browser.sh: $!";
    print $out "#!/usr/bin/env bash\n\n";
    print $out "su -c \"$browser $url\" $username\n";
    close($out);
    chown $uid, $gid, "launch_browser.sh";
}

###############################################################
#
# Now we finally come to the actual installation procedure
#
###############################################################

#We'll use this later
my $installer_dir = getcwd();

#Check if user is ready to install webwork
get_ready();

#Check if user is running script as root
check_root();

#Deal with SELinux
get_selinux();

#Get os, host, perl version, timezone
my $envir = check_environment();
my %siteDefaults;
$siteDefaults{timezone} = $envir->{timezone};

#Get apache version, path to config file, server user and group;
my $apache = check_apache( $envir );

#Put the information from the layout in the apache object;
my $layout;
if (version->parse($apache->{version}) >= version->parse('2.4.00')) {
    $layout = $apache24Layouts->{$envir->{os}->{name}}; 
} else {
    $layout = $apache22Layouts->{$envir->{os}->{name}};
}

foreach my $key (keys %$layout) {
    $apache->{$key} = $layout->{$key};
}

#enable mpm prefork
enable_mpm_prefork($apache);

#check and see if our modules are enabled
check_apache_modules($apache,$envir);

#get the apache user and group, eithe from the layout or from the system
$apache = get_apache_user_group($apache,$envir);

my $server_userID  = $apache->{User};
my $server_groupID = $apache->{Group};

#Check perl prerequisites
print_and_log(<<EOF);
###################################################################
#
# Checking for required perl modules and external programs...
#
# #################################################################
EOF
check_modules(@modulesList);
check_modules(@apache2ModulesList);

#Check binary prerequisites
my $apps = configure_externalPrograms(@applicationsList);

#Get directory root PREFIX, download software, and configure filesystem locations for webwork software
my $WW_PREFIX = get_WW_PREFIX(WW_PREFIX);    #constant defined at top

#== Top level determined from PREFIX ==
my $webwork_dir         = "$WW_PREFIX/webwork2";
my $pg_dir              = "$WW_PREFIX/pg";
my $webwork_courses_dir = "$WW_PREFIX/courses";
my $webwork_htdocs_dir  = "$webwork_dir/htdocs";
$ENV{WEBWORK_ROOT} = $webwork_dir;

print_and_log(<<EOF);
#########################################################################
#  At this point we need to make some access control decisions. 
#  These decisions are important because they directly impact 
#  application and system security.  But, the right answers often 
#  depend on a mix of factors, such as
#  - institutional and/or departmental policies,
#  - the level of involvement and expertise of the application 
#    owner(s) and the system administrator(s)
#  - personal preferences and intended workflows 
#
#  Here we offer the option of creating a webwork admin user and 
#  a webwork data group, for four different access control options.  
#  If none of these four options fit your situation, then you should 
#  select one now with the intention of tweaking it manually after 
#  this script exits.
#
#  Let's first deal with the webwork admin user, and then the webwork 
#  data group.  
############################################################################
EOF

my $wwadmin = get_wwadmin_user($envir);
my $wwdata = get_wwdata_group( $envir, $apache, $wwadmin );

#(3) $server_root_url   = "";  # e.g.  http://webwork.yourschool.edu
#$webwork_url         = "/webwork2";
#$server_root_url   = "";   # e.g.  http://webwork.yourschool.edu or localhost

my $server_root_url    = get_root_url(ROOT_URL);     #constant defined at top
my $webwork_url        = get_webwork_url(WW_URL);    #constant defined at top
my $webwork_htdocs_url = "/webwork2_files";

#Configure mail settings
#(4) $mail{smtpServer}            = 'mail.yourschool.edu';
#(5) $mail{smtpSender}            = 'webwork@yourserver.yourschool.edu';
my %mail;
$mail{smtpServer} = get_smtp_server(SMTP_SERVER);    #constant defined at top
$mail{smtpSender} = get_smtp_sender(SMTP_SENDER);    #constant defined at top

#(6) database root password
#(7) $database_dsn = "dbi:mysql:webwork";
#(8) $database_username = "webworkWrite";
#(9) $database_password = "";
my ($ww_db,$database_server,$database_username,$database_password) = get_webwork_database($mysql_root_password, $webwork_db_password);  #constant defined at top

my $database_dsn        = get_dsn($ww_db,$database_server);

get_storage_engine();

print_and_log(<<EOF);
#######################################################################
#
#  Now I'm going to download the webwork code.  This will take a couple
#  of minutes.
# 
######################################################################
EOF
get_webwork( $WW_PREFIX, $apps );

print_and_log(<<EOF);
#######################################################################
#
#
# Now we will unpack the jsMath font files.
#
# This may take awhile
#
# 
######################################################################
EOF
unpack_jsMath_fonts($webwork_dir);

print_and_log(<<EOF);
#######################################################################
#
#
# Now we will download MathJax.
#
# This too may take awhile
#
# 
######################################################################
EOF
get_MathJax($WW_PREFIX);

print_and_log(<<EOF);
#######################################################################
#
#  Now I'm going to copy some classlist files and the modelCourse/ dir from
#  webwork2/courses.dist to $webwork_courses_dir.  
#  modelCourse/ will serve as a default template for WeBWorK courses you create.
#   
######################################################################
EOF
copy_classlist_files( $webwork_dir, $webwork_courses_dir );

#Symlinking webwork2/courses.dist/modelCourse to courses/modelCourse is
#better than copying it over for updates.
#copy_model_course( $webwork_dir, $webwork_courses_dir );
symlink_model_course( $webwork_dir, $webwork_courses_dir );

print_and_log(<<EOF);
#######################################################################
#
#
# Alrighty, so far so good.  Let's see, where are we?  Oh, right: we've
# created the webwork database, downloaded all of the code, moved things
# around, and obtained all of the config information we need.  
#
# Not too much left to do.
#
# Next up: We'll write the config files
#
# 
######################################################################
EOF

# No longer necessary to copy database.conf.dist to database.conf
#write_database_conf("$webwork_dir/conf");

write_site_conf(
    $WW_PREFIX,         "$webwork_dir/conf", $webwork_url,
    $server_root_url,   $apache,             $database_dsn,
    $database_username, $database_password,  $apps
);

write_localOverrides_conf( $WW_PREFIX, "$webwork_dir/conf" );

my $apache_config_file;

if (version->parse($apache->{version}) >= version->parse('2.4.00')) {
    $apache_config_file = 'webwork.apache2.4-config';
} else {
    $apache_config_file = 'webwork.apache2-config';
}

write_webwork_apache2_config("$webwork_dir", $apache_config_file);

write_webwork3_conf($WW_PREFIX,$database_password, "$webwork_dir/conf") 
    if -e "$WW_PREFIX/webwork2/conf/webwork3.conf.dist";

print_and_log(<<EOF);
#######################################################################
#
# Well, that was easy.  Now I need to slightly modify the 
# configuration of your apache webserver.  Note that we will
# back up the apache config file before any modifications are
# made. 
#
# First, I'm going symlink webwork.apache2-config to your apache 
# conf.d dir as webwork.conf. This will have the effect of starting 
# webwork whenever the webserver is started.  This *must* be done
# to enable webwork, so sorry - no choice in this matter.
#
#######################################################################
EOF

my $ln = can_run('ln');
my $cmd = [$ln, '-s', "$webwork_dir/conf/$apache_config_file", "$apache->{OtherConfig}/webwork.conf"];
my $success = run_command($cmd);;

if ($success) {

    print_and_log("Added webwork's apache config file to apache.");

} else {
    print_and_log("Couldn't add webwork's apache config file to apache.");
}

edit_httpd_conf($apache);

edit_mpm_conf($apache);

print_and_log(<<EOF);
#######################################################################
#
# Sanity check: Let's make sure we can restart apache. 
# 
######################################################################
EOF

restart_apache($apache);

print_and_log(<<EOF);
#######################################################################
#
# Kay. Now I'm going to set up the OPL.  This could take a few...
# 
######################################################################
EOF
setup_opl($WW_PREFIX);


print_and_log(<<EOF);
######################################################################
#
# Now I'm going to compile pg/lib/chromatic/color.c. When you get a
# chance you should check out Nandor Sieben's excellent graph theory
# problems that use this.
#
#####################################################################
EOF
install_chromatic($pg_dir);

print_and_log(<<EOF);
#######################################################################
#
# Creating admin course...
# 
######################################################################
EOF
create_admin_course($WW_PREFIX);

if ( $wwadmin ne 'root' ) {
    print_and_log(<<EOF);
#######################################################################
#
#  Now I'm going to change the ownship of $WW_PREFIX and everything 
#  under it to $wwadmin:$wwadmin with permissions u+rwX,go+rwX
#  
######################################################################
EOF

#chown -R $wwadmin:$wwadmin $WW_PREFIX
#chmod -R u+rwX,go+rX $WW_PREFIX
#doing this with sub rather than perl built in to make sure it's done recursively
    change_owner( "$wwadmin:$wwadmin", $WW_PREFIX );
    my $chmod = can_run('chmod');
    my $cmd = [ $chmod, '-R', 'u+rwX,go+rX', $WW_PREFIX ];
    my $success = run_command($cmd);;
    if ($success) {
        print_and_log("Changed the ownship of $WW_PREFIX and ".
                      "everything under it to $wwadmin:$wwadmin ".
                      "with permissions u+rwX,go+rwX\n");
    } else {
        print_and_log("Couldn't change ownership of $WW_PREFIX.");
    }
}

print_and_log(<<EOF);
#######################################################################
#
#  Now I'm going to change the ownship and permissions of some directories
#  under $webwork_dir and $webwork_courses_dir that should be web accessible.  
#  Faulty permissions is one of the most common cause of problems, especially
#  after upgrades. 
# 
######################################################################
EOF
change_owner(
    "$wwadmin:$wwdata",  $webwork_courses_dir,
    "$webwork_dir/DATA", "$webwork_dir/htdocs/tmp",
    "$webwork_dir/logs", "$webwork_dir/tmp"
);
change_data_dir_permissions(
    $wwdata,             "$webwork_courses_dir",
    "$webwork_dir/DATA", "$webwork_dir/htdocs/tmp",
    "$webwork_dir/logs", "$webwork_dir/tmp"
);

my $webwork3log = "$webwork_dir/webwork3/logs";

if (-e $webwork3log) {
    change_webwork3_log_permissions("$wwadmin:$wwdata",$webwork3log);
    #temporary hack until logs is in the git repo
} else {
    my $full_path = can_run('mkdir');
    my $cmd = [$full_path,$webwork3log]; #set SELinux in permissive mode
    my $success = run_command($cmd);  
    change_webwork3_log_permissions("$wwadmin:$wwdata",$webwork3log);
}
    

print_and_log(<<EOF);
######################################################
#
# Hey! I'm done!  
#
#######################################################

Restarting apache...
EOF

restart_apache($apache);

print_and_log(<<EOF);
Check it out at $server_root_url/webwork2! You can login to the 
admin course with initial username and password 'admin'.  

Have fun! :-)
EOF

write_launch_browser_script( $installer_dir,
    'http://localhost' . $webwork_url );

configure_shell($WW_PREFIX,$wwadmin);
copy("webwork_install.log","$WW_PREFIX/webwork_install.log") if -f 'webwork_install.log';

__END__
==encoding utf8

=head1 NAME

ww_install.pl 

=head1 DESCRIPTION

ww_install.pl, a WeBWorK Installation Script

=head2 Goals

=over

=item *

Interactively install webwork on any machine on which the prerequisites are installed

=item

Do as much as possible for the user, finding paths, writing config files, etc.

=item

Try not use anything other than core perl modules, webwork modules, webwork prerequisite modules

=item

Eventually add option for --nointeractive  and options to specify command line options

=back

=head2 How it works

=over

=item 1

Check if running as root

=item 2

Have you downloaded webwork already?

--if so, where is webwork2/, pg/, courses/, libraries/?

--if not, do you want me to get the software for you via svn?

=item 3

Check prerequisites, using this opportunity to populate %externalPrograms hash, and gather
environment information: $server_userID, $server_groupID, hostname?, timezone?

=item 4

Initially ask user minimum set of config questions:

=over

=item *

Directory root PREFIX

=item *

Accept standard webwork layout below PREFIX? (later)

=item *

  $server_root_url = "";  # e.g.  http://webwork.yourschool.edu (default from hostname lookup in (2))

=item *

  $server_userID = "";  # e.g.  www-data (default from httpd.conf lookup in (2))

=item *

  $server_groupID = "";  # e.g.  wwdata (gets the default from httpd.conf lookup in (2))

=item *

  $mail{smtpServer} = 'mail.yourschool.edu';

=item *

  $mail{smtpSender} = 'webwork@yourserver.yourschool.edu';

=item *

  $mail{smtpTimeout} = 30;

=item *

database root password

=item *

$database_dsn = "dbi:mysql:webwork";

=item *

$database_username = "webworkWrite";

=item *

$database_password = "";

=item *

$siteDefaults{timezone} = "America/New_York";

=back

=item 5

Put software in correct locations

=item 6

Use gathered information to write site.conf file, localOverrides.conf, webwork.apache2-config, wwapache2ctl,

=item 7

Check and fix filesystem permissions in webwork2/ tree

=item 8

Create initial database user, initial mysql tables

=item 9

Create admin course

=item 10

Append include statement to httpd.conf to pick up webwork.apache2-config

=item 11

Restart apache, check for errors

=item 12

Do some testing!

=back

=head1 AUTHOR

Jason Aubrey <aubreyja@gmail.com>

=head1 COPYRIGHT AND DISCLAIMER

This program is Copyright 2013 by Jason Aubrey.  This program is
free software; you can redistribute it and/or modify it under the terms
of the Perl Artistic License or the GNU General Public License as
published by the Free Software Foundation; either version 2 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
General Public License for more details.

If you do not have a copy of the GNU General Public License write to
the Free Software Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139,
USA.

=cut
