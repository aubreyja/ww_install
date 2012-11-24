#!/usr/bin/env perl
##########################################################################################################
#WeBWorK Installation Script
#
#Goals:
#(1) interactively install webwork on any machine on which the prerequisites are installed
#(2) do as much as possible for the user, finding paths, writing config files, etc.
#(3) never use anything other than core perl modules, webwork modules, webwork prerequisite modules
#(4) eventually add options for --nointeractive, --with-svn, other?
#
#How it works
#(1) check if running as root
#(2) Have you downloaded webwork already?
#--if so, where is webwork2/, pg/, NationalProblemLibrary/?
#--if not, do you want me to get the software for you via svn?
#(3) check prerequisites, using this opportunity to populate %externalPrograms hash, and gather 
#environment information: $server_userID, $server_groupID, hostname?, timezone?
#(4) Initially ask user minimum set of config questions:
#-Directory root PREFIX
#--accept standard webwork layout below PREFIX? (later)
#-$server_root_url   = "";  # e.g.  http://webwork.yourschool.edu (default from hostname lookup in (2))
#-$server_userID     = "";  # e.g.  www-data    (default from httpd.conf lookup in (2))
#-$server_groupID    = "";  # e.g.  wwdata      (default from httpd.conf lookup in (2))
#-$mail{smtpServer}            = 'mail.yourschool.edu';
#-$mail{smtpSender}            = 'webwork@yourserver.yourschool.edu';
#-$mail{smtpTimeout}           = 30;
#-database root password
#-$database_dsn = "dbi:mysql:webwork";
#-$database_username = "webworkWrite";
#-$database_password = "";
#-$siteDefaults{timezone} = "America/New_York";
#(5) Put software in correct locations
#(6) use gathered information to write initial global.conf file, webwork.apache2-config,database.conf, 
#wwapache2ctl, 
#(7) check and fix filesystem permissions in webwork2/ tree
#(8) Create initial database user, initial mysql tables
#(9) Create admin course
#(10) append include statement to httpd.conf to pick up webwork.apache2-config
#(11) restart apache, check for errors 
#(12) Do some testing!
#######################################################################################################


use strict;
use warnings;

use Config;

use File::Path qw(make_path);
use File::Spec;
use File::Copy;
use File::CheckTree;
#use File::Glob ':bsd_glob';

use IPC::Cmd qw(can_run run run_forked);
use Params::Check qw(check);

use Sys::Hostname;
use User::pwent;
use Data::Dumper;

use DBI;

use DB_File;
use Fcntl;

use POSIX;
use List::Util qw(max);

use DateTime::TimeZone; #non-core!

use Term::UI;
use Term::ReadLine;
#use Term::ReadKey;
###############################################################################################
# Create a new Term::Readline object for interactivity
#Don't worry people with spurious warnings.
###############################################################################################
$Term::UI::VERBOSE = 0;
my $term = Term::ReadLine->new('');

#########################################################################################
#
# Defaults - each of these values is passed as a default to some config question
#
########################################################################################

use constant WEBWORK2_REPO => 'https://github.com/openwebwork/webwork2.git';
use constant PG_REPO => 'https://github.com/openwebwork/pg.git';
use constant OPL_REPO => 'https://github.com/openwebwork/webwork-open-problem-library.git';

use constant WW_PREFIX => '/opt/webwork/';
use constant ROOT_URL => 'http://localhost';
use constant WW_URL => '/webwork2';

use constant SMTP_SERVER => 'localhost';
use constant SMTP_SENDER => 'webwork@localhost';

use constant WW_DB => 'webwork';
use constant WWDB_USER => 'webworkWrite';

#######################################################################################
#
# Constants that control behavior of the script
#
# ####################################################################################

use constant IPC_CMD_TIMEOUT => 6000; #Sets maximum time system commands will be allowed to run
use constant IPC_CMD_VERBOSE => 1; #Controls whether all output of a command 
				   #should be printed to STDOUT/STDERR

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
	HTML::Tagset
	IO::File
	Iterator
	Iterator::Util
	Mail::Sender
	MIME::Base64
	Net::IP
	Net::LDAPS
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

####################################################################################################
#
# Platform specific data - these data structures are to help with identifying our platform and
# eventually will be used for specifying prerequiste packages, likely locations of binaries we can't find
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
    'gentoo'                => 'Gentoo Base System release (.*)',
    'debian'                => '(.+)',
    'suse'                  => 'VERSION = (.*)',
    'fedora'                => 'Fedora(?: Core)? release (\d+) \(',
    'redflag'               => 'Red Flag (?:Desktop|Linux) (?:release |\()(.*?)(?: \(.+)?\)',
    'redhat'                => 'Red Hat(?: Enterprise)? Linux(?: Server)? release (.*) \(',
    'oracle enterprise linux' => 'Enterprise Linux Server release (.+) \(',
    'slackware'             => '^Slackware (.+)$',
    'pardus'                => '^Pardus (.+)$',
    'centos'                => '^CentOS(?: Linux)? release (.+)(?:\s\(Final\))',
    'scientific'            => '^Scientific Linux release (.+) \(',
);

#Apache 2.2 locations for various operating systems
#From http://wiki.apache.org/httpd/DistrosDefaultLayout
#Note that the above url may not contain current information
#double checking it with the docs for your favorite distro would
#be helpful

my $apache22Layouts = {
  httpd22 => { #Apache 2.2 default layout
    MPMDir => 'server/mpm/prefork',
    ServerRoot => '/usr/local/apache2',
    DocumentRoot => '/usr/local/apache2/htdocs',
    ConfigFile => '/usr/local/apache2/conf/httpd.conf',
    OtherConfig => '/usr/local/apache2/conf/extra',
    SSLConfig => '/usr/local/apache2/conf/extra/httpd-ssl.conf',
    ErrorLog => '/usr/local/apache2/logs/error_log',
    AccessLog => '/usr/local/apache2/logs/access_log',
    ctl => '/usr/local/apache2/bin/apachectl',
    User => '',
    Group => '',
  },
    ubuntu => {  #Checked 12.04
      MPMDir => 'server/mpm/prefork',
      ServerRoot => '/etc/apache2',
      DocumentRoot => '/var/www',
      ConfigFile => '/etc/apache2/apache2.conf',
      OtherConfig => '/etc/apache2/conf.d',
      SSLConfig => '',
      Modules => '/etc/apache2/mods_enabled',
      ErrorLog => '/var/log/apache2/error.log',
      AccessLog => '/var/log/access.log',
      Binary => '/usr/sbin/apache2ctl',
      User => 'www-data',
      Group => 'www-data',
    },
    rhel => { #And Fedora Core, CentOS...checked Fedora 17, CentOS 6
      MPMDir => 'server/mpm/prefork',
      ServerRoot => '/etc/httpd',
      DocumentRoot => '/var/www/html',
      ConfigFile => '/etc/httpd/conf/httpd.conf',
      OtherConfig => '/etc/httpd/conf.d',
      SSLConfig => '',
      Modules => '/etc/httpd/modules', #symlink
      ErrorLog => '/var/log/httpd/error_log',
      AccessLog => '/var/log/httpd/access_log',
      Binary => '/usr/sbin/apachectl',
      User => 'apache',
      Group => 'apache',
    },
    freebsd => { #Checked on freebsd 8.2
      MPMDir => '',
      ServerRoot => '/usr/local',
      DocumentRoot => '/usr/local/www/apache22/data',
      ConfigFile => '/usr/local/etc/apache22/httpd.conf',
      OtherConfig => '/usr/local/etc/apache22/extra',
      SSLConfig => '/usr/local/etc/apache22/extra/httpd-ssl.conf',
      Modules => '',
      ErrorLog => '/var/log/httpd-error.log',
      AccessLog => '/var/log/httpd-access.log',
      Binary => '/usr/sbin/apachectl',
      User => 'www',
      Group => 'www',
    },
    osx => { #Checked on OSX 10.7
      MPMDir => 'server/mpm/prefork',
      ServerRoot => '/usr',
      DocumentRoot => '/Library/WebServer/Documents',
      ConfigFile => '/etc/apache2/httpd.conf',
      OtherConfig => '/etc/apache2/extra',
      SSLConfig => '/etc/apache2/extra/httpd-ssl.conf',
      Modules => '/usr/libexec/apache2',
      ErrorLog => '/var/log/apache2/error_log',
      AccessLog => '/var/log/apache2/access_log',
      Binary => '/usr/sbin/apachectl',
      User => '_www',
      Group => '_www',
      },
    suse => {
      MPMDir => '',
      ServerRoot => '/srv/www',
      DocumentRoot => '/srv/www/htdocs',
      ConfigFile => '/etc/apache2/httpd.conf',
      OtherConfig => '/etc/sysconfig/apache2',
      SSLConfig => '/etc/apache2/ssl-global.conf',
      ErrorLog => '/var/log/apache2/httpd-error.log',
      AccessLog => '/var/log/apache2/httpd-access.log',
      Binary => '/usr/sbin/apachectl',
      User => 'wwwrun',
      Group => 'www',
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
  if($^O eq "darwin") {
    $os->{type} = "unix";
    $os->{name} = "darwin";
    chomp($os->{version} =`sw_vers -productVersion`);
    chomp($os->{arch} = `uname -p`);
    print "Great, you're on Mac running OS X $$os{version} on $$os{arch} hardware.\n";
  } elsif($^O eq "freebsd") {
    $os->{type} = "unix";
    $os->{name} = "freebsd";
    chomp($os->{version} = `uname -r`);
    chomp($os->{arch} = `uname -p`);
    print "I see - rocking it on FreeBSD $$os{version} on $$os{arch} hardware.\n";
  } elsif($^O eq "linux") { #Now we're going to have to look more closely to get specific distro 
    $os->{type} = "linux";
    $os->{name} = distribution_name();
    $os->{version} = distribution_version();
    chomp($os->{arch} = `uname -p`);
    print "Linux, yay! That's my favorite. I see you're running $$os{name} ". 
	"version $$os{version} on $$os{arch} hardware. This will be easy.\n";
  } elsif($^O eq "MSWin32") {
    print "Installing WeBWorK on Windows is, afaik, currently impossible.\n"; 
    die "If you get it working, please let us know. Good luck!";
  } else {
    $os->{type} = $^O;
    $os->{name} = distribution_name();
    $os->{version} = distribution_version();
    chomp($os->{arch} = `uname -p`);
    print "I see you're running $$os{name} version $$os{version} on $$os{arch} hardware. "
    ."This script mostly finds the information it needs at run time. But, there are a few "
    ."places where we have hard coded OS specific details into data structures built into the "
    ."script. We don't have anything for your OS. The script will very likely still work. Either "
    ."way, it would be very helpful if you could send a report to webwork\@maa.org. We can help you "
    ."get it working if it doesn't work, and if it does we would like to add it to the list of supported "
    ."systems.\n";
  }
  return $os;
}

#Subroutines to find linux distribution and version

sub distribution_name {
    my $release_files_directory='/etc';
    my $standard_release_file = 'lsb-release';

    my $distro = get_lsb_info();
    if ($distro){
        return $distro if ($distro);
    }

    foreach (qw(enterprise-release fedora-release)) {
        if (-f "$release_files_directory/$_" && !-l "$release_files_directory/$_"){
            if (-f "$release_files_directory/$_" && !-l "$release_files_directory/$_"){
                $linux{'DISTRIB_ID'} = $release_files{$_};
                $linux{'release_file'} = $_;
                return $linux{'DISTRIB_ID'};
            }
        }
    }

    foreach (keys %release_files) {
        if (-f "$release_files_directory/$_" && !-l "$release_files_directory/$_"){
            if (-f "$release_files_directory/$_" && !-l "$release_files_directory/$_"){
                if ( $release_files{$_} eq 'redhat' ) {
                    foreach my $rhel_deriv ('centos','scientific',) {
                        $linux{'pattern'} = $version_match{$rhel_deriv};
                        $linux{'release_file'}='redhat-release';
                        my $file_info = get_file_info();
                        if ($file_info) {
                            $linux{'DISTRIB_ID'} = $rhel_deriv;
                            $linux{'release_file'} = $_;
                            return $linux{'DISTRIB_ID'};
                        }
                    }
                    $linux{'pattern'}='';
                }
                $linux{'release_file'} = $_;
                $linux{'DISTRIB_ID'} = $release_files{$_};
                return $linux{'DISTRIB_ID'};
            }
        }
    }
    undef 
}

sub distribution_version {
    my $release_files_directory='/etc';
    my $standard_release_file = 'lsb-release';
    my $release;
    return $release if ($release = get_lsb_info('DISTRIB_RELEASE'));
    if (! $linux{'DISTRIB_ID'}){
         distribution_name() or die 'No version because no distro.';
    }
    $linux{'pattern'} = $version_match{$linux{'DISTRIB_ID'}};
    $release = get_file_info();
    $linux{'DISTRIB_RELEASE'} = $release;
    return $release;
}

sub get_lsb_info {
    my $field = shift || 'DISTRIB_ID';
    my $release_files_directory='/etc';
    my $standard_release_file = 'lsb-release';
    my $tmp = $linux{'release_file'};
    if ( -r "$release_files_directory/" . $standard_release_file ) {
        $linux{'release_file'} = $standard_release_file;
        $linux{'pattern'} = $field . '=(.+)';
        my $info = get_file_info();
        if ($info){
            $linux{$field} = $info;
            return $info
        }
    } 
    $linux{'release_file'} = $tmp;
    $linux{'pattern'} = '';
    undef;
}

sub get_file_info {
    my $release_files_directory='/etc';
    my $standard_release_file = 'lsb-release';
    open my $fh, '<', "$release_files_directory/" . $linux{'release_file'} or die 'Cannot open file: '.$release_files_directory.'/' . $linux{'release_file'};
    my $info = '';
    local $_;
    while (<$fh>){
        chomp $_;
        ($info) = $_ =~ m/$linux{'pattern'}/;
        return "\L$info" if $info;
    }
    undef;
}

#End of linux-finding subroutines.

sub get_existing_users {
  my $envir = shift;
  my $passwd_file = $envir -> {passwd_file};
  my $users;
  open(my $in,'<',$passwd_file);
  while(<$in>) {
   push @$users,(split(':',$_))[0];
  }
  close($in);
  return $users;
}

sub get_existing_groups {
  my $envir = shift;
  my $group_file = $envir -> {group_file}; 
  my $groups;
  open(my $in,'<',$group_file);
  while(<$in>) {
   push @$groups,(split(':',$_))[0];
  }
  return $groups;
}

############################################################################################
#
# Script Util Subroutines:  The script is based on Term::Readline to interact with user
#
###########################################################################################


#For confirming answers
sub confirm_answer {
  my $answer = shift;   
  my $confirm = $term -> get_reply(
    print_me => "Ok, you entered $answer. Please confirm.",
    prompt => "Well? ",
    choices => ["Looks good.","Change my answer.","Quit."],
    default => "Looks good."
    );
  if($confirm eq "Quit."){
    die "Exiting...";
  } elsif($confirm eq "Change my answer.") {
    return 0;
  } else {
    return 1;
  }
}


#####################################################
#
# Check if user is ready to install
#
# ###################################################

sub get_ready {

my $print_me=<<EOF;
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
 my $ready = $term -> ask_yn(
                    print_me => $print_me,
                    prompt => 'Ready to install WeBWorK?',
                    default => 1,
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
  if($> == 0) {
    print "Running as root....\n";
    return 1;
  } else {
    #my $term = Term::ReadLine->new('');
my $print_me =<<EOF;
IMPORTANT: This script is not running as root. Typically root privliges are
needed to install WeBWorK. You should probably quit now and run the script
as root or with sudo.
EOF
    my $prefix = $term -> ask_yn(
                  print_me => $print_me,
                  prompt => 'Continue without root privliges?',
                  default => 0,
                );
  }
}

sub get_wwadmin_user {
  my $print_me =<<END; 
####################################################################################
#
# The first decision is whether or not to create a webwork admin user. The purpose of
# doing this would be to allow the webwork admin user to edit the webwork system code
# (e.g. for updates) while restricting that user from having write access to other
# files outside of his home directory.  If the system administrator(s) and webwork
# application maintainer(s) are the same then there is no need to create this user.
#
# If the maintainer of webwork (the webwork administrator) is not the system 
# administrator for the server, then you as a user with root access must decide how
# to give the webwork admin sufficient privileges to maintain webwork.  One approach,
# depending on your OS, is to give that user root access by either addiing that user 
# to the wheel group or the sudoers file. This gives the webwork administrator complete
# access to the system, but if that's fine with you then it's fine with me too.
#
# The approach offered here is to create a webwork admin user and group. All of the
# webwork code will be owned by this user.  The only webwork files that will be 
# writable by other users are those that must be writable by the webserver. For those
# files and directories we will create a new webwork data group to which we will add the 
# webwork admin user and the webserver.
#
# If you choose not to create this user, the webwork code will be owned by root. We
# will still give you the opportunity to create the webwork data group. Members of this
# group will be able to do limited webwork maintenance tasks, such as creating courses from 
# the command line and managing logs, but will not be able edit webwork system files or other
# files that are writable by the webserver.
#
######################################################################################
END
  my $prompt = "Shall I create a webwork admin user?";
  my $answer = $term -> ask_yn(
              print_me => $print_me,
              prompt => $prompt,
              default => 1,
            );

  #has this been confirmed?
  my $confirmed = confirm_answer($answer);
  if($confirmed && $answer) {
    my $ww_admin = create_wwadmin_user();
    return $ww_admin if $ww_admin;
    get_wwadmin_user(); #Try again if not
  } elsif($confirmed && !$answer) {
    print "Sounds good. We will not create a webwork admin user\n";
    return "root";
  } else {
    print "Let's try again.\n";
    get_wwadmin_user();
  }
}


sub create_wwadmin_user {
    my $wwadmin = $term -> get_reply(
		print_me => "You chose to create a webwork admin user.",
		prompt => "Please enter a userid for the webwork admin user.",
		default => "wwadmin",
	);
    my $wwadmin_pw = $term -> get_reply(
		prompt => "Please enter an initial password for the webwork admin user.",
		default => "wwadmin",
	);
    my $wwadmin_shell = $term -> get_reply(
		prompt => "Please enter a default shell for the webwork admin user.",
		default => $ENV{SHELL},
	);
    my $confirm = $term -> ask_yn(
		prompt => "Shall I create a webwork admin user with userid $wwadmin, initial password"
			  ." $wwadmin_pw and default shell $wwadmin_shell?",
		default => 1,
	);
    if($confirm) {
     #useradd  -s /usr/bin/bash -c "WeBWorK Administrator" -p $wwadmin_pw $wwadmin
	#TODO: FreeBSD, MacOSX don't have useradd!!!
	my $full_path = can_run("useradd");
        my $cmd = [$full_path, '-s',$wwadmin_shell,'-c',"WeBWorK Administrator",'-p',$wwadmin_pw,$wwadmin];
        if( scalar run( command => $cmd,
                    verbose => IPC_CMD_VERBOSE,
                    timeout => IPC_CMD_TIMEOUT))
	{
	  print "Created webwork admin user $wwadmin with initial password $wwadmin_pw and default shell $wwadmin_shell.\n";
	  return $wwadmin;
	} else {
   	  print "Let's try again.\n";
   	  get_wwadmin_user();
	}
    } else {
   	print "Let's try again.\n";
   	get_wwadmin_user();
    }

}



sub get_wwdata_group {
  my ($apache,$WW_PREFIX,$wwadmin) = @_;
  my $print_me =<<END; 
####################################################################################
# Certain data directories need to be writable by the webserver.  These are the 
# webwork2/DATA, webwork2/htdocs/tmp, webwork2/logs, webwork2/tmp, and 
# $WW_PREFIX/courses directories.
#
# It can convenient to give WeBWorK system administrators access to these directories
# as well, so they can permform admiistrative tasks such as removing temporary files,
# creating and editing courses from the command line, managing logs, and so on.
#
# While it can be convenient to allow the WeBWorK administrator(s) to manipulate the 
# webwork files writable by the webserver, we may not want to give him or her rights 
# to manipulate other files writable by the webserver.
#
# We can accomplish this by adding a new webwork data group to the system containing any
# WeBWorK administrators and also containing the web server. We will then recursively 
# give the directories listed above permissions g+sw and files in those directories g+w.
# 
# If you choose not to create the webwork data group, the webwork directories listed above
# will be put into the same group as the webserver. We will then recursively give those 
# directories permissions g+sw and the files in those directories permissions g+w.
#
######################################################################################
END
  my $prompt = "Shall I create a webwork data group?";
  my $answer = $term -> ask_yn(
              print_me => $print_me,
              prompt => $prompt,
              default => 1,
            );

  #has this been confirmed?
  my $confirmed = confirm_answer($answer);
  if($confirmed && $answer) {
    my $group = $term -> get_reply(
		print_me => "You chose to create a webwork data group.",
		prompt => "What would you like to call the group?",
		default => "wwdata",
	);
    if($group eq $apache->{group}) {
	print $apache->{group}." already exists. Let's try again.\n",
	get_wwdata_group($apache,$WW_PREFIX,$wwadmin);
    } 
    my $confirm_name = confirm_answer($group);
    if($confirm_name) {
	print "Great, I'll create a webwork data group called $group.\n";
	create_wwdata_group($apache,$group,$wwadmin);
	return $group;
    } else {
	print "Looks like you changed your mind. Let's start over.\n";
	get_wwdata_group($apache,$WW_PREFIX,$wwadmin);
    }
  } elsif($confirmed && !$answer) {
	print "Sounds good. We will not create a webwork data group";
	return $apache->{group};
  } else {
   	 get_wwdata_group($apache,$WW_PREFIX,$wwadmin);
  }
}

#Create webwork data group and add webserver and wwadmin (if user is not root)
sub create_wwdata_group {
  my ($apache,$group,$wwadmin) = @_;
  copy("/etc/group","/etc/group.bak");
  open(my $in, "<","/etc/group.bak")
    or die "Can't open /etc/group.bak for reading: $!";
  open(my $out, ">", "/etc/group")
    or die "Can't open /etc/group for writing: $!";
  my @gids;
  while(<$in>) {
    push @gids,(split(':',$_))[2];
    print $out $_;
  }
  my $new_gid = max(@gids)+1;
  if($wwadmin eq 'root') {
   print $out "$group:*:$new_gid:".$apache->{user}."\n";
  } else {
   print $out "$group:*:$new_gid:".$apache->{user}.",$wwadmin\n";
  }
}

##############################################################
#
# Adjust file owernship and permissions
#
#############################################################
#change_grp($server_groupid, $webwork_courses_dir, "$webwork_dir/DATA", "$webwork_dir/htdocs/tmp", "$webwork_dir/logs", "$webwork_dir/tmp");
#change_permissions($server_groupid, "$webwork_courses_dir", "$webwork_dir/DATA", "$webwork_dir/htdocs/tmp", "$webwork_dir/logs", "$webwork_dir/tmp");

#chgrp -R wwdata DATA ../courses htdocs/tmp logs tmp
# chmod -R g+w DATA ../courses htdocs/tmp logs tmp
# find DATA/ ../courses/ htdocs/tmp logs/ tmp/ -type d -a ! -name CVS -exec chmod g+s {}

sub change_owner {
 my $owner = shift;
 my @dirs = @_;
  my $full_path = can_run('chown'); 
  my $cmd = [$full_path, '-R',$owner,@dirs];
    if( scalar run( command => $cmd,
                    verbose => IPC_CMD_VERBOSE,
                    timeout => IPC_CMD_TIMEOUT )
    ) {
        print "Changed ownership of @dirs and below to $owner.\n";
    }
}

# chmod -R g+w DATA ../courses htdocs/tmp logs tmp
# find DATA/ ../courses/ htdocs/tmp logs/ tmp/ -type d -a ! -name CVS -exec chmod g+s {}
sub change_data_dir_permissions {
 my ($gid, $courses, $data, $htdocs_tmp, $logs, $tmp) = @_;
  my $chmod = can_run('chmod'); 
  my $cmd = [$chmod, '-R','g+w', $courses, $data, $htdocs_tmp, $logs, $tmp];
    if( scalar run( command => $cmd,
                    verbose => IPC_CMD_VERBOSE,
                    timeout => IPC_CMD_TIMEOUT )
    ) {
        print "Made the directories \n $courses,\n $data,\n $htdocs_tmp,\n $logs,\n $tmp\n group writable.\n";
    }
  my $find = can_run('find'); 
  $cmd = [$find, $courses, $data, $htdocs_tmp, $logs, $tmp, '-type', 'd','-and', '!', '(', '-name', '".git"','-prune', ')','-exec',$chmod,'g+s', '{}', ';'];
    if( scalar run( command => $cmd,
                    verbose => IPC_CMD_VERBOSE,
                    timeout => IPC_CMD_TIMEOUT )
    ) {
        print "Added group sticky bit to \n $courses,\n $data,\n $htdocs_tmp,\n $logs,\n $tmp\n and subdirectories (except .git's).\n";
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
print<<EOF;
###################################################################
#
# Getting basic information about your environment 
#
# #################################################################
EOF

  my $envir;
 $envir->{host} = hostname;
 print "And your hostname is ".$envir->{host}."\n";
 $envir->{perl} = $^V;
 print "You're running Perl ".$envir->{perl}."\n";
 my $timezone = DateTime::TimeZone -> new(name=>'local');
 $envir->{timezone} = $timezone->name;
  print "Your timezone is ".$envir->{timezone}."\n";
 $envir->{os} = get_os();
 $envir->{passwd_file} = "/etc/passwd" if -e "/etc/passwd";
 $envir->{group_file} = "/etc/group" if -e "/etc/group";


 #we're going to get a list of users and groups on the system
 #for use later when we create our own users and groups. Also
 #to double check information, such as user and group for apache 
 $envir->{existing_users} = get_existing_users($envir);
 $envir->{existing_groups} = get_existing_groups($envir);

  return $envir;
}


sub check_apache {
  my ($envir,$apache22Layouts) = @_;

print<<EOF;
###################################################################
#
# Gathering information about Apache
#
# #################################################################
EOF


  my $apache;
  $apache->{binary} = File::Spec->canonpath(can_run('apache2ctl') || can_run('apachectl')) or die "Can't find Apache!\n";

  open(HTTPD,$apache->{binary}." -V |") or die "Can't do this: $!";
  print "Your apache start up script is at ".$apache->{binary}."\n";

  #Get some information from apache2 -V
  while(<HTTPD>) {
    if ($_ =~ /apache.(\d\.\d\.\d+)/i){
      $apache->{version} = $1;
      print "Your apache version is ".$apache->{version}."\n";
    } elsif ($_ =~ /HTTPD_ROOT\=\"((\/\w+)+)\"$/) {
      $apache->{root} = File::Spec->canonpath($1);
      print "Your apache server root is ".$apache->{root}."\n";
    } elsif ($_=~ /SERVER_CONFIG_FILE\=\"((\/)?(\w+\/)*(\w+\.?)+)\"$/) {
      $apache->{conf} = File::Spec->canonpath($1);
        my $is_absolute = File::Spec->file_name_is_absolute( $apache->{conf} );
        if($is_absolute) {
          next;
        } else {
          $apache->{conf} = File::Spec->canonpath( $apache->{root}."/".$apache->{conf} );
        }
      print "Your apache config file is ".$apache->{conf}."\n";
    }
  }
  close(HTTPD);

  #Determining apache user/group is hard. Sometimes it's in the main conf file.
  #Here we check that, but maybe we should check all conf files under /etc/apache2?  
  open(HTTPDCONF,$apache->{conf}) or die "Can't do this: $!";
  while(<HTTPDCONF>){
    if (/^User/) {
      (undef,$apache->{user}) = split;
    } elsif (/^Group/){
      (undef,$apache->{group}) = split;
    }
  }
    close(HTTPDCONF);

    #Make sure we didn't get a bogus user/group from httpd.conf
    my $os_name = $envir->{os}->{name};
    my %users = map{ $_ => 1 } @{$envir->{existing_users}};
    my %groups = map{ $_ => 1 } @{$envir->{existing_groups}};

    #if the apache user/group from httpd.conf doesn't make sense, then
    #get a hard-coded value from %apache22Layouts.
    unless($users{$apache->{user}} && $groups{$apache->{group}}) {
	$apache->{user} = $apache22Layouts->{$os_name}->{User};
	$apache->{group} = $apache22Layouts->{$os_name}->{Group};
  }
        print "Apache runs as user ".$apache->{user}."\n";
        print "Apache runs in group ".$apache->{group}."\n";
  return $apache;
}



####################################################################
#
# Check for perl modules
#
# ##################################################################
# do we really want to eval "use $module;"?

sub check_modules {
	my @modulesList = @_;
	
	print "\nChecking your \@INC for modules required by WeBWorK...\n";
	my @inc = @INC;
	print "\@INC=";
	print join ("\n", map("     $_", @inc)), "\n\n";
	
	foreach my $module (@modulesList)  {
		eval "use $module";
		if ($@) {
			my $file = $module;
			$file =~ s|::|/|g;
			$file .= ".pm";
			if ($@ =~ /Can't locate $file in \@INC/) {
				print "** $module not found in \@INC\n";
			} else {
				print "** $module found, but failed to load: $@";
			}
		} else {
			print "   $module found and loaded\n";
		}
	}
}

#####################################################################
#
#Check for prerequisites and get paths for binaries
#
#####################################################################

sub configure_externalPrograms {
  #Expects a list of applications 	
  my @applicationsList = @_;
	print "\nChecking your system for executables required by WeBWorK...\n";
	
  my $apps;
	foreach my $app (@applicationsList)  {
		$apps->{$app} = File::Spec->canonpath(can_run($app));
		if ($apps->{$app}) {
			print "   $app found at ${$apps}{$app}\n";
      if($app eq 'lwp-request') {
        delete $apps -> {$app};
        $apps -> {checkurl} = "$app".' -d -mHEAD';
      }
		} else {
			warn "** $app not found in \$PATH\n";
		}
	}
  my (undef,$netpbm_prefix,undef) = File::Spec->splitpath(${$apps}{giftopnm});
  $$apps{gif2eps} = "$$apps{giftopnm}"." | ".$$apps{ppmtopgm}." | " .$$apps{pnmtops} ." -noturn 2>/dev/null";
  $$apps{png2eps} = "$$apps{pngtopnm}"." | ".$$apps{ppmtopgm}." | " .$$apps{pnmtops} ." -noturn 2>/dev/null";
  $$apps{gif2png} = "$$apps{giftopnm}"." | "."$$apps{pnmtopng}";

  return $apps;
}


sub get_webwork2_repo {
	my $default = shift;
my $print_me=<<END;
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

  my $repo = $term -> get_reply(
              print_me => $print_me,
              prompt => 'Where would you like to download webwork2 from?',
              default => $default, #constant defined at top
            );
  #has this been confirmed?
  my $confirmed = 0;
  $confirmed = confirm_answer($repo);
  if($confirmed) {
    print "Got it, I'll download webwork2 from $repo.\n";
    return $repo;
  } else {
    get_webwork2_repo($default);
  }
}


sub get_pg_repo {
  my $default = shift;
  my $repo = $term -> get_reply(
              #print_me => $print_me,
              prompt => 'Where would you like to download pg from?',
              default => $default, #constant defined at top
            );
  #has this been confirmed?
  my $confirmed = 0;
  $confirmed = confirm_answer($repo);
  if($confirmed) {
    print "Got it, I'll download pg from $repo.\n";
    return $repo;
  } else {
    get_pg_repo($default);
  }
}

sub get_opl_repo {
  my $default = shift;
  my $repo = $term -> get_reply(
              #print_me => $print_me,
              prompt => 'Where would you like to download the OPL from?',
              default => $default, 
            );
  #has this been confirmed?
  my $confirmed = 0;
  $confirmed = confirm_answer($repo);
  if($confirmed) {
    print "Got it, I'll download the OPL from $repo.\n";
    return $repo;
  } else {
    get_opl_repo($default);
  }

}

sub get_WW_PREFIX {
  my $default = shift;
  my $print_me =<<END; 
#################################################################
# Installation Prefix: Please enter the absolute path of the directory
# under which we should install the webwork software. A typical choice
# is /opt/webwork/. We will create # four subdirectories under your PREFIX:
#
# PREFIX/webwork2 - for the core code for the web-applcation
# PREFIX/pg - for the webwork problem generating language PG
# PREFIX/libraries - for the National Problem Library and other problem libraries
# PREFIX/courses - for the individual webwork courses on your server
#
# Note that we will also set a new system wide environment variable WEBWORK_ROOT 
# to PREFIX/webwork2/
#################################################################
END
  my $dir= $term -> get_reply(
              print_me => $print_me,
              prompt => 'Where should I install webwork?',
              default => $default,
            );
  #has this been confirmed?
  my $confirmed = 0;

  #remove trailing "/"'s
  $dir = File::Spec->canonpath($dir);


  # Now we'll check for errors, if we don't need any fixes, we'll move on
  my $fix = 0;

  #check if reply is an absolute path
  my $is_absolute = File::Spec->file_name_is_absolute($dir);
  if($is_absolute) { #everything is fine by us, let's confirm with user
   $confirmed = confirm_answer($dir);
  } else {
    $dir = File::Spec->rel2abs($dir);
    $fix = $term -> get_reply(
      print_me => "I need an absolute path, but you gave me a relative path.",
      prompt => "How do you want to fix this? ",
      choices =>["Go back","I really meant $dir","Quit"]
    );
  }

  if($fix eq "Go back") {
    $fix = 0;
    get_WW_PREFIX(WW_PREFIX); #constant defined at top
  } elsif($fix eq "I really meant $dir") {
    $fix = 0;
    $confirmed = confirm_answer($dir);
  } elsif($fix eq "Quit") {
    die "Exiting...";
  }
  if($confirmed && !$fix) {
    print "Got it, I'll create $dir and install webwork there.\n";
    #print "\$confirmed = $confirmed and \$fix = $fix\n";
    return $dir;
  } else {
    #print "Here!\n";
    get_WW_PREFIX(WW_PREFIX); #constant defined at top
  }
}

sub get_root_url {
  my $default = shift;
  my $print_me =<<END; 
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
  my $answer = $term -> get_reply(
              print_me => $print_me,
              prompt => 'Server root url:',
              default => $default,
            );

  #has this been confirmed?
  my $confirmed = confirm_answer($answer);
  if($confirmed) {
    print "Thanks, got it, I'll use \"$answer\" \n";
    return $answer;
  } else {
    get_root_url($default);
  }
}

sub get_webwork_url {
  my $default = shift;
  my $print_me =<<END; 
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
  my $answer = $term -> get_reply(
              print_me => $print_me,
              prompt => $prompt,
              default => $default,
            );

  #has this been confirmed?
  my $confirmed = confirm_answer($answer);
  if($confirmed) {
    print "Thanks, got it, I'll use \"$answer\" \n";
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
  my $default = shift;
  my $print_me =<<END; 
#################################################################
# SMTP Server:  Maybe something like 'mail.yourschool.edu'.  If
# you're not sure 'localhost' is a good choice. 
#################################################################
END
  my $prompt = "SMTP server:";
  my $answer = $term -> get_reply(
              print_me => $print_me,
              prompt => $prompt,
              default => $default,
            );

  #has this been confirmed?
  my $confirmed = confirm_answer($answer);
  if($confirmed) {
    print "Thanks, got it, I'll use \"$answer\" \n";
    return $answer;
  } else {
    get_smtp_server($default);
  }
}

sub get_smtp_sender {
  my $default = shift;
  my $print_me =<<END; 
##############################################################################
# SMTP Sender:  Maybe something like 'webwork\@yourserver.yourschool.edu'. If
# you're not setting this up right now, 'webwork\@localhost' is fine.
##############################################################################
END
  my $prompt = "SMTP sender:";
  my $answer = $term -> get_reply(
              print_me => $print_me,
              prompt => $prompt,
              default => $default,
            );

  #has this been confirmed?
  my $confirmed = confirm_answer($answer);
  if($confirmed) {
    print "Thanks, got it, I'll use \"$answer\" \n";
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

sub get_mysql_root_password {
  
  my $print_me =<<END; 
####################################################################################
# Please enter the root mysql password. Please escape any special characters with \
# Caution: The password will be echoed back as you type.
#####################################################################################
END
  my $prompt = "Root mysql password:";
  my $answer = $term -> get_reply(
              print_me => $print_me,
              prompt => $prompt,
            );
  #has this been confirmed?
  if($answer) {
    print "Thanks; I'll keep it secret.\n";
    return $answer;
  } else {
    get_mysql_root_password();
  }
}

#TODO: Make this a question
sub get_webwork_database {
  my $default = shift;
  my $print_me =<<END; 
##############################################################################
# Now we want to create a new mysql database for webwork database. As a first 
# step, please choose a name for the database.  It can be anything that conforms
# to mysql's rules for database names.  If you don't know those, just be sensible
# and things will probably be ok. (Or look up the rules if you are inclined to 
# be unsensible.)
###############################################################################
END
  my $prompt = "Name for the webwork database:";
  my $answer = $term -> get_reply(
              print_me => $print_me,
              prompt => $prompt,
              default => $default,
            );

  #has this been confirmed?
  my $confirmed = confirm_answer($answer);
  if($confirmed) {
    print "Thanks, got it, I'll use \"$answer\" \n";
    return $answer;
  } else {
    get_webwork_database($default);
  }
  return $answer
}

sub get_dsn {
  my $database = shift;
  return "dbi:mysql:$database";
}


sub get_database_username {
  my $default = shift;
  my $print_me =<<END; 
##############################################################################
# Now we want to create a new mysql user with the necessary privileges on the 
# webwork database, but no privileges on other tables.  An example is 
# 'webworkWrite'.  But, you can use anything except 'root'.
##############################################################################
END
  my $prompt = "webwork database username:";
  my $answer = $term -> get_reply(
              print_me => $print_me,
              prompt => $prompt,
              default => $default,
            );

  #has this been confirmed?
  my $confirmed = confirm_answer($answer);
  if($confirmed) {
    print "Thanks, got it, I'll use \"$answer\" \n";
    return $answer;
  } else {
    get_database_username($default);
  }

}

sub get_database_password {
  my $print_me =<<END; 
##############################################################################
# Now create a password to identify the webwork database user.  Note that
# this password will be written into one of the (plain text) config files
# in webwork2/conf/.  It's important for security that this password not be
# the same as the mysql root password.
# Caution: The password will be echoed back as you type.
##############################################################################
END
  my $prompt = "webwork database password:";
  my $answer = $term -> get_reply(
              print_me => $print_me,
              prompt => $prompt,
            );

  #has this been confirmed?
  if($answer) {
    return $answer;
  } else {
    get_database_password();
  }


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
  make_path($dir);
}

############################################################################
#
# Get the software, put it in the correct location 
#
############################################################################

#TODO: Switch from NPL to OPL
sub get_webwork {
  my ($prefix,$apps,$wwadmin) = @_;
  create_prefix_path($prefix);
  chdir $prefix or die "Can't chdir to $prefix";
  my $ww2_repo = get_webwork2_repo(WEBWORK2_REPO); #WEBWORK2_REPO constant defined at top
  my $ww2_cmd = $apps->{git}." clone ".$ww2_repo;

  my $pg_repo = get_pg_repo(PG_REPO); #PG_REPO constant defined at top
  my $pg_cmd = $apps->{git}." clone ".$pg_repo;

  my $opl_repo = get_opl_repo(OPL_REPO); #OPL_REPO constant defined at top
  my $opl_cmd = $apps->{git}." clone ".$opl_repo;

  my $buffer;
  if( scalar run( command => $ww2_cmd,
	  verbose => IPC_CMD_VERBOSE,
	  buffer => \$buffer,
	  timeout => IPC_CMD_TIMEOUT )
  ) {
      print "fetched webwork2 successfully: $buffer\n";
    }
  

  if( scalar run( command => $pg_cmd,
	  verbose => IPC_CMD_VERBOSE,
	  buffer => \$buffer,
	  timeout => IPC_CMD_TIMEOUT)
  ) {
      print "fetched pg successfully: $buffer\n";
    }
#TODO: change owner and group after deciding if wwadmin exists
  make_path('libraries',{owner=>$wwadmin,group=>$wwadmin});
  make_path('courses',{owner=>$wwadmin,group=>$wwadmin});
  chdir "$prefix/libraries";
#TODO: Switch from NPL to OPL
  if( scalar run( command => $opl_cmd,
	  verbose => IPC_CMD_VERBOSE,
	  buffer => \$buffer,
	  timeout => IPC_CMD_TIMEOUT)
  ) {
      print "fetched OPL successfully: $buffer\n";
    }
  }

#############################################################
#
# Unpack jsMath fonts
#
#############################################################

sub unpack_jsMath_fonts {
  my $webwork_dir = shift;
  # cd /opt/webwork/webwork2/htdocs/jsMath
  chdir("$webwork_dir/htdocs/jsMath");
  system("tar vfxz jsMath-fonts.tar.gz");
}

sub get_MathJax {
  my $webwork_dir = shift;
  chdir("$webwork_dir");
  #system("git submodule update --init");
  my $full_path = can_run('git'); 
  my $cmd = [$full_path, 'submodule', "update", "--init"];
  if( scalar run( command => $cmd,
  	    verbose => IPC_CMD_VERBOSE,
  	    timeout => IPC_CMD_TIMEOUT )
  ) {
    print "Downloaded MathJax to $webwork_dir/htdocs/mathjax\n";
  } else {
    warn "Could not download MathJax. You'll have to do this manually: $!";
  }
}

#copy("adminClasslist.lst","$prefix/courses/adminClasslist.lst");
#copy("defaultClasslist.lst","$prefix/courses/defaultClasslist.lst");
sub copy_classlist_files {
  my ($webwork_dir, $courses_dir) = @_;
  copy("$webwork_dir/courses.dist/adminClasslist.lst", "$courses_dir/adminClasslist.lst") or
	warn "Couldn't copy $webwork_dir/courses.dist/adminClasslist.lst to $courses_dir."
	." You'll have to copy this over manually: $!";
  print "copied adminClasslist.lst to $courses_dir\n";
  copy("$webwork_dir/courses.dist/defaultClasslist.lst", "$courses_dir") or
	warn "Couldn't copy $webwork_dir/courses.dist/defaultClasslist.lst to $courses_dir."
	." You'll have to copy this over manually: $!";
  print "copied defaultClasslist.lst file to $courses_dir\n";
}


sub copy_model_course {
  my ($webwork_dir, $courses_dir) = @_;
  my $full_path = can_run('cp'); 
  my $cmd = [$full_path, '-r', "$webwork_dir/courses.dist/modelCourse", "$courses_dir"];
  if( scalar run( command => $cmd,
  	    verbose => IPC_CMD_VERBOSE,
  	    timeout => IPC_CMD_TIMEOUT)
  ) {
    print "copied modelCourse/ to $courses_dir/\n";
  } else {
    warn "Could not copy modelCourse/ to $courses_dir/. You'll have to copy this over manually: $!";
  }
}

#############################################################
#
# Create webwork database...
#
############################################################

sub create_database {
  my ($dsn, $root_pw, $ww_db, $ww_user, $ww_pw) = @_;
  my $dbh = DBI->connect('DBI:mysql:database=mysql', 'root', $root_pw);
  print "Connected to mysql as root...\n";
  $dbh -> do("CREATE DATABASE $ww_db") or die "Could not create $ww_db database: $!\n";
  print "Created $ww_db database...\n";
  $dbh -> do("GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, DROP, LOCK TABLES ON $ww_db.* TO $ww_user\@localhost IDENTIFIED BY '$ww_pw'")
    or die "Could not grant privileges to $ww_user on $ww_db database: $!\n";
  print "Granted privileges...\n";
  $dbh -> disconnect();
}

#############################################################
#
#  Write config files
#
############################################################

sub write_database_conf {
  my $conf_dir = shift;
  copy("$conf_dir/database.conf.dist","$conf_dir/database.conf") or die "Can't copy database.conf.dist to database.conf: $!";
}

sub write_site_conf {
  my ($WW_PREFIX,$conf_dir,$webwork_url,$server_root_url,$apache,$database_dsn,$database_username,$database_password,$apps)
	 = @_;
  open(my $in, "<","$conf_dir/site.conf.dist")
    or die "Can't open $conf_dir/site.conf.dist for reading: $!";
  open(my $out, ">", "$conf_dir/site.conf")
    or die "Can't open $conf_dir/site.conf for writing: $!";
  while( <$in> ) {
    if(/^\$webwork_url/) {
      print $out "\$webwork_url = \"$webwork_url\";\n";
    } elsif(/^\$server_root_url/) {
      print $out "\$server_root_url = \"$server_root_url\";\n";
    } elsif(/^\$server_userID/) {
      print $out "\$server_userID = \"".$apache->{user}."\";\n";
    } elsif(/^\$server_groupID/) {
      print $out "\$server_groupID = \"".$apache->{group}."\";\n";
    } elsif (/^\$database_dsn/) {
      print $out "\$database_dsn = \"$database_dsn\";\n";
    } elsif (/^\$database_username/) {
      print $out "\$database_username = \"$database_username\";\n";
    } elsif (/^\$database_password/) {
      print $out "\$database_password = \"$database_password\";\n";
    } elsif (/^\$externalPrograms{(\w+)}/) {
      next if ($1 =~ /tth/);
        print $out "\$externalPrograms{$1} = \"$$apps{$1}\";\n";
    } elsif (/^\$pg_dir/) {
      print $out "\$pg_dir = \"$WW_PREFIX/pg\";\n";
    } elsif(/^\$webwork_courses_dir/) {
      print $out "\$webwork_courses_dir = \"$WW_PREFIX/courses\";\n";
    } else {
      print $out $_;
    }
  }
}

sub write_localOverrides_conf {
  my ($WW_PREFIX,$conf_dir) = @_;
  open(my $in,"<","$conf_dir/localOverrides.conf.dist")
    or die "Can't open $conf_dir/localOverrides.conf.dist for reading: $!";
  open(my $out,">","$conf_dir/localOverrides.conf")
    or die "Can't open $conf_dir/localOverrides.conf for writing: $!";
    while( <$in> ) {
    if(/^\$problemLibrary{root}/) {
      print $out "\$problemLibrary{version} = \"2.5\";\n";
      print $out "\$problemLibrary{root} = \"$WW_PREFIX/libraries/webwork-open-problem-library/OpenProblemLibrary\";\n";
    } elsif(/^\$pg{options}{displayMode}/) {
      print $out "\$pg{options}{displayMode} = \"MathJax\";\n";
    } else {
      print $out $_;
    }
  }
}


sub write_webwork_apache2_config {
  my $webwork_dir= shift;
  my $conf_dir = "$webwork_dir/conf";
  open(my $in,"<","$conf_dir/webwork.apache2-config.dist")
    or die "Can't open $conf_dir/webwork.apache2-config.dist for reading: $!";
  open(my $out,">","$conf_dir/webwork.apache2-config")
    or die "Can't open $conf_dir/webwork.apache2-config for writing: $!";
    while( <$in> ) {
      next if /^\#/;
      if(/^my\s\$webwork_dir/) {
        print $out "my \$webwork_dir = \"$webwork_dir\";\n";
      } else {
        print $out $_;
      }
  }
}

##########################################################
#
#  Configure environment (symlink webwork-apache2.config,
#  set path, WEBWORK_ROOT
#
##########################################################

sub configure_shell {
#export PATH=$PATH:/opt/webwork/webwork2/bin
#export WEBWORK_ROOT=/opt/webwork/webwork2
}


sub setup_opl {
  my $WW_PREFIX = shift;
  symlink("$WW_PREFIX/libraries/webwork-open-problem-library/OpenProblemLibrary",
          "$WW_PREFIX/courses/modelCourse/templates/Library");
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
  system("$WW_PREFIX/webwork2/bin/addcourse admin --db-layout=sql_single --users=$WW_PREFIX/courses/adminClasslist.lst --professors=admin");
}

#############################################################
#
# Restart apache and launch web-browser!
#
#############################################################

sub restart_apache {

}


sub launch_browser {

}

###############################################################################################
#
# Now we finally come to the actuall installation procedure
#
###############################################################################################


#Check if user is ready to install webwork
get_ready();

#Check if user is running script as root
check_root();

#Get os, host, perl version, timezone
my $envir = check_environment();
my %siteDefaults;
$siteDefaults{timezone} = $envir->{timezone}; 

#Get apache version, path to config file, server user and group;
my $apache = check_apache($envir,$apache22Layouts);
my $server_userID = $apache->{user};
my $server_groupID = $apache->{group};

#Check perl prerequisites
print<<EOF;
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
my $WW_PREFIX = get_WW_PREFIX(WW_PREFIX); #constant defined at top

#== Top level determined from PREFIX ==
my $webwork_dir = "$WW_PREFIX/webwork2";
my $pg_dir              = "$WW_PREFIX/pg";
my $webwork_courses_dir = "$WW_PREFIX/courses"; 
my $webwork_htdocs_dir  = "$webwork_dir/htdocs";
$ENV{WEBWORK_ROOT} = $webwork_dir;

print<<EOF; 
####################################################################################
#  At this point we need to make some access control decisions. These decisions
#  are important because they directly impact application and system security.
#  But, the right answers often depend on a mix of factors, such as
#  - institutional and/or departmental policies,
#  - the level of involvement and expertise of the application owner(s) and the
#  system administrator(s)
#  - personal preferences and intended workflows 
#
#  Here we offer the option of creating a webwork admin user and a webwork data
#  group, for four different access control options.  If none of these four options fit 
#  your situation, then you should select one now with the intention of tweaking it 
#  manually after this script exits.
#
#  Let's first deal with the webwork admin user, and then the webwork data group.
#
########################################################################################
EOF

my $wwadmin = get_wwadmin_user();
my $wwdata = get_wwdata_group($apache,$WW_PREFIX,$wwadmin);




#(3) $server_root_url   = "";  # e.g.  http://webwork.yourschool.edu
#$webwork_url         = "/webwork2";
#$server_root_url   = "";   # e.g.  http://webwork.yourschool.edu or localhost

my $server_root_url = get_root_url(ROOT_URL); #constant defined at top
my $webwork_url = get_webwork_url(WW_URL); #constant defined at top
my $webwork_htdocs_url  = "/webwork2_files";

#Configure mail settings
#(4) $mail{smtpServer}            = 'mail.yourschool.edu';
#(5) $mail{smtpSender}            = 'webwork@yourserver.yourschool.edu';
my %mail;
$mail{smtpServer} = get_smtp_server(SMTP_SERVER); #constant defined at top
$mail{smtpSender} = get_smtp_sender(SMTP_SENDER); #constant defined at top


#(6) database root password
#(7) $database_dsn = "dbi:mysql:webwork";
#(8) $database_username = "webworkWrite";
#(9) $database_password = "";
my $mysql_root_password = get_mysql_root_password();
my $ww_db = get_webwork_database(WW_DB); #constant defined at top
my $database_dsn = get_dsn($ww_db); 
my $database_username = get_database_username(WWDB_USER); #constant defined at top
my $database_password = get_database_password();

print<<EOF;
#######################################################################
#
#  OK, now I'm going to create the webwork mysql database $ww_db. The webwork db
#  user $database_username will have rights to modifiy tables of that database but
#  no others.
# 
######################################################################
EOF
create_database($database_dsn,$mysql_root_password, $ww_db, $database_username, $database_password);

print<<EOF;
#######################################################################
#
#  Now I'm going to download the webwork code.  This will take a couple
#  of minutes.
# 
######################################################################
EOF
get_webwork($WW_PREFIX,$apps);

print<<EOF;
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

print<<EOF;
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
get_MathJax($webwork_dir);

print<<EOF;
#######################################################################
#
#  Now I'm going to copy some classlist files and the modelCourse/ dir from
#  webwork2/courses.dist to $webwork_courses_dir.  
#  modelCourse/ will serve as a default template for WeBWorK courses you create.
#   
######################################################################
EOF
copy_classlist_files($webwork_dir,$webwork_courses_dir);
copy_model_course($webwork_dir, $webwork_courses_dir);


print<<EOF;
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

write_database_conf("$webwork_dir/conf");

write_site_conf($WW_PREFIX,
	"$webwork_dir/conf",
	$webwork_url,
	$server_root_url,
	$apache,
	$database_dsn,
	$database_username,
	$database_password,
	$apps);

write_localOverrides_conf($WW_PREFIX,"$webwork_dir/conf");

write_webwork_apache2_config("$webwork_dir");

print<<EOF;
#######################################################################
#
# Well, that was easy.  Now i'm going to symlink webwork.apache2-config
# to your apache conf.d dir as webwork.conf. 
#
# 
######################################################################
EOF
symlink("$webwork_dir/conf/webwork.apache2-config",$apache->{root}."/conf.d/webwork.conf");


print<<EOF;
#######################################################################
#
# Kay. Now I'm going to set up the OPL.  This could take a few...
# 
######################################################################
EOF
setup_opl($WW_PREFIX);

print<<EOF;
#######################################################################
#
# Creating admin course...
# 
######################################################################
EOF
create_admin_course($WW_PREFIX);

if($wwadmin ne 'root') {
print<<EOF;
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
change_owner("$wwadmin:$wwadmin",$WW_PREFIX);
my $chmod = can_run('chmod'); 
my $cmd = [$chmod, '-R','u+rwX,go+rX',$WW_PREFIX];
  if( scalar run( command => $cmd,
                  verbose => IPC_CMD_VERBOSE,
                  timeout => IPC_CMD_TIMEOUT )
  ) {
      print "Changed the ownship of $WW_PREFIX and everything under it to $wwadmin:$wwadmin"
            ." with permissions u+rwX,go+rwX\n";
  } else {
    print "Couldn't change ownership of $WW_PREFIX: $!";
  }
}



print<<EOF;
#######################################################################
#
#  Now I'm going to change the ownship and permissions of some directories
#  under $webwork_dir and $webwork_courses_dir that should be web accessible.  
#  Faulty permissions is one of the most common cause of problems, especially
#  after upgrades. 
# 
######################################################################
EOF
change_owner("$wwadmin:$wwdata", $webwork_courses_dir, "$webwork_dir/DATA", "$webwork_dir/htdocs/tmp", "$webwork_dir/logs", "$webwork_dir/tmp");
change_data_dir_permissions($wwdata, "$webwork_courses_dir", "$webwork_dir/DATA", "$webwork_dir/htdocs/tmp", "$webwork_dir/logs", "$webwork_dir/tmp");


print<<EOF;
#######################################################################
#
# Hey! I'm done!  
#
#######################################################################

Restarting apache...
EOF
my $cmd = [$apache->{binary},'restart'];
if(scalar run( command => $cmd,
                  verbose => IPC_CMD_VERBOSE,
                  timeout => IPC_CMD_TIMEOUT )
  ) {
print<<EOF
Check it out at $server_root_url/webwork2! You can login to the admin course with initial
username and password 'admin'.  Have fun! :-)
EOF
}
