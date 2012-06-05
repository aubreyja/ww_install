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


use strict;
use warnings;

use Config;

use File::Path qw(make_path);
use File::Spec;
use File::Copy;
use File::CheckTree;
#use File::Glob ':bsd_glob';

use IPC::Cmd qw(can_run run run_forked);
use Term::UI;
use Term::ReadLine;
#use Term::ReadKey;
use Params::Check qw(check);

use Sys::Hostname;
use User::pwent;
use Data::Dumper;

use DBI;

use DB_File;
use Fcntl;

use POSIX;

#Non-core
use DateTime::TimeZone;

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
	tth
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

# OK, Let's get started....
##############################################################
# Create a new Term::Readline object for interactivity
#Don't worry people with spurious warnings.
###############################################################
$Term::UI::VERBOSE = 0;
my $term = Term::ReadLine->new('');

#Check if user is ready to install webwork
get_ready();

#Check if user is running script as root
check_root();

#Get os, host, perl version, timezone
my %envir = get_environment();
my %siteDefaults;
$siteDefaults{timezone} = $envir{timezone}; 

#Get apache version, path to config file, server user and group;
my %apache = check_apache();
my $server_userid = $apache{user};
my $server_groupid = $apache{group};

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
my $WW_PREFIX = get_WW_PREFIX('/opt/webwork');

#== Top level determined from PREFIX ==
my $webwork_dir = "$WW_PREFIX/webwork2";
my $pg_dir              = "$WW_PREFIX/pg";
my $webwork_courses_dir = "$WW_PREFIX/courses"; 
my $webwork_htdocs_dir  = "$webwork_dir/htdocs";



#(3) $server_root_url   = "";  # e.g.  http://webwork.yourschool.edu
#$webwork_url         = "/webwork2";
#$server_root_url   = "";   # e.g.  http://webwork.yourschool.edu or localhost

my $server_root_url = get_root_url('http://localhost');
my $webwork_url = get_webwork_url('/webwork2');
my $webwork_htdocs_url  = "/webwork2_files";

#Configure mail settings
#(4) $mail{smtpServer}            = 'mail.yourschool.edu';
#(5) $mail{smtpSender}            = 'webwork@yourserver.yourschool.edu';
my %mail;
$mail{smtpServer} = get_smtp_server('localhost');
$mail{smtpSender} = get_smtp_sender('webwork@localhost');


#(6) database root password
#(7) $database_dsn = "dbi:mysql:webwork";
#(8) $database_username = "webworkWrite";
#(9) $database_password = "";
my $mysql_root_password = get_mysql_root_password();
my $database_username = get_database_username('webworkWrite');
my $database_password = get_database_password();
my $ww_db = "webwork";
my $database_dsn = "dbi:mysql:webwork";

#Configuration done, now start doing things...
# Now get all of the webwork software
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
#  Now I'm going to change the ownship and permissions of some directories
#  under $webwork_dir and $webwork_courses_dir that should be web accessible.  
#  Faulty permissions is one of the most common cause of problems, especially
#  after upgrades. 
# 
######################################################################
EOF
change_grp($server_groupid, $webwork_courses_dir, "$webwork_dir/DATA", "$webwork_dir/htdocs/tmp", "$webwork_dir/logs", "$webwork_dir/tmp");
change_permissions($server_groupid, "$webwork_courses_dir", "$webwork_dir/DATA", "$webwork_dir/htdocs/tmp", "$webwork_dir/logs", "$webwork_dir/tmp");

#chgrp -R wwdata DATA ../courses htdocs/tmp logs tmp
# chmod -R g+w DATA ../courses htdocs/tmp logs tmp
# find DATA/ ../courses/ htdocs/tmp logs/ tmp/ -type d -a ! -name CVS -exec chmod g+s {}
print<<EOF;
#######################################################################
#
#  Now I'm going to create the webwork mysql database $ww_db. The webwork db
#  user $database_username will have rights to modifiy tables of that database but
#  no others.
# 
######################################################################
EOF
create_database($database_dsn,$mysql_root_password, $ww_db, $database_username, $database_password);




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
####################################################################
# We probably need to be root. The effective user id of the user running the script
# is held in the perl special variable $>.  In particular,
# if $> = 0 user is root, works with sudo too.
# run it like this at the top of the script:

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


####################################################################
#
# Environment Data
#
####################################################################
# What use is this information? 
# - any reason to get the hostname?
# - maybe use OS to do OS specific processing?
# - maybe warn against perl versions that are too old; version specific perl bugs?
# - maybe process timezone separately?

sub get_environment {
print<<EOF;
###################################################################
#
# Getting basic information about your environment
#
# #################################################################
EOF
 my %envir;
 $envir{OS} = $^O;
 $envir{host} = hostname;
 $envir{perl} = $^V;
 my $timezone = DateTime::TimeZone -> new(name=>'local');
 $envir{timezone} = $timezone->name;
  print "Looks like you're on ". ucfirst($_->{OS})."\n";
  print "And your hostname is ". $_->{host} ."\n";
  print "You're running Perl $_->{perl}\n";
  print "Your timezone is $_->{timezone}\n";
  return %envir;
}


sub check_apache {
print<<EOF;
###################################################################
#
# Gathering information about Apache
#
# #################################################################
EOF

  my %apache;
  $apache{binary} = File::Spec->canonpath(can_run('apache2ctl') || can_run('apachectl')) or die "Can't find Apache!\n";

  open(HTTPD,"$apache{binary} -V |") or die "Can't do this: $!";
  print "Your apache start up script is at $apache{binary}\n";

  while(<HTTPD>) {
    if ($_ =~ /apache.(\d\.\d\.\d+)/i){
      $apache{version} = $1;
      print "Your apache version is $apache{version}\n";
    } elsif ($_ =~ /HTTPD_ROOT\=\"((\/\w+)+)\"$/) {
      $apache{root} = File::Spec->canonpath($1);
      print "Your apache server root is $apache{root}\n";
    } elsif ($_=~ /SERVER_CONFIG_FILE\=\"((\/)?(\w+\/)+(\w+\.?)+)\"$/) {
      $apache{conf} = File::Spec->canonpath($1);
        my $is_absolute = File::Spec->file_name_is_absolute( $apache{conf} );
        if($is_absolute) {
          next;
        } else {
          $apache{conf} = File::Spec->canonpath( "$apache{root}/$apache{conf}" );
        }
      print "Your apache config file is $apache{conf}\n";
    }
  }
  close(HTTPD);

  open(HTTPDCONF,$apache{conf}) or die "Can't do this: $!";
  while(<HTTPDCONF>){
    if (/^User/) {
      (undef,$apache{user}) = split;
      print "Apache runs as user $apache{user}\n";
    } elsif (/^Group/){
      (undef,$apache{group}) = split;
      print "Apache runs in group $apache{group}\n";
    }
  }
  close(HTTPDCONF);
  return %apache;
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
        $apps -> {check_url} = "$app".' -d -mHEAD';
      }
		} else {
			warn "** $app not found in \$PATH\n";
		}
	}
  my (undef,$netpbm_prefix,undef) = File::Spec->splitpath(${$apps}{giftopnm});
  $$apps{gif2eps} = "$$apps{giftopnm}"." | ".$$apps{ppmtopgm}." | " .$$apps{pnmtops} ." -noturn 2>/dev/null";
  $$apps{png2eps} = "$$apps{pngtopnm}"." | ".$$apps{ppmtopgm}." | " .$$apps{pnmtops} ." -noturn 2>/dev/null";
  $$apps{gif2png} = "$$apps{giftopnm}"." | "."$$apps{pnmtopng}";

  #return Data::Dumper->Dump([$netpbm_prefix,$apps],[qw(*netpbm_prefix *externalPrograms)]);
  return $apps;
}

sub confirm_answer {
  my $answer = shift;   
  my $confirm = $term -> get_reply(
    print_me => "Ok, you entered $answer. Please confirm.",
    prompt => "Well? ",
    choices => ["Looks good.","Change my answer.","Quit."],
    defalut => "Looks good."
    );
  if($confirm eq "Quit."){
    die "Exiting...";
  } elsif($confirm eq "Change my answer.") {
    return 0;
  } else {
    return 1;
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
    get_WW_PREFIX('/opt/webwork');
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
    get_WW_PREFIX('/opt/webwork');
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
# "/webwork"
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
# just merge into get_webwork?

sub create_prefix_path {
  my $dir = shift;
  #Check that path given is an absolute path
  #Confirm that user wants this
  #Create path - can we create a new wwadmin group?
  make_path($dir);
}

############################################################################
#
# Get the software, put it in the correct location 
#
############################################################################

sub get_webwork {
  my ($prefix,$apps) = @_;
  create_prefix_path($prefix);
  chdir $prefix or die "Can't chdir to $prefix";
  my $ww2_cmd = $apps->{git}." clone https://github.com/openwebwork/webwork2.git";
  my $buffer;
  if( scalar run( command => $ww2_cmd,
  verbose => 1,
  buffer => \$buffer,
  timeout => 200 )
  ) {
      print "fetched webwork2 successfully: $buffer\n";
    }
  my $pg_cmd = $apps->{git}." clone https://github.com/openwebwork/pg.git";

  if( scalar run( command => $pg_cmd,
  verbose => 1,
  buffer => \$buffer,
  timeout => 200 )
  ) {
      print "fetched pg successfully: $buffer\n";
    }
  make_path('libraries',{owner=>'root',group=>'root'});
  make_path('courses',{owner=>'root',group=>'root'});
  chdir "$prefix/libraries";
  my $npl_cmd = $apps->{svn}." checkout http://svn.webwork.maa.org/npl/trunk/NationalProblemLibrary";
  if( scalar run( command => $npl_cmd,
  verbose => 1,
  buffer => \$buffer,
  timeout => 6000 )
  ) {
      print "fetched npl successfully: $buffer\n";
    }
  }

sub copy_classlist_files {
  my ($webwork_dir, $courses_dir) = @_;
  my $full_path = can_run('cp'); 
  my $cmd = [$full_path, "$webwork_dir/courses.dist/*.lst", "$courses_dir"];
    if( scalar run( command => $cmd,
                    verbose => 1,
                    timeout => 20 )
    ) {
        print "copied classlist files to $courses_dir\n";
    }
}

  #copy("adminClasslist.lst","$prefix/courses/adminClasslist.lst");
  #copy("defaultClasslist.lst","$prefix/courses/defaultClasslist.lst");

sub copy_model_course {
  my ($webwork_dir, $courses_dir) = @_;
  my $full_path = can_run('cp'); 
  my $cmd = [$full_path, '-r', "$webwork_dir/courses.dist/modelCourse", "$courses_dir"];
    if( scalar run( command => $cmd,
                    verbose => 1,
                    timeout => 20 )
    ) {
        print "copied modelCourse/ to $courses_dir/\n";
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

sub change_grp {
 my ($gid, $courses, $data, $htdocs_tmp, $logs, $tmp) = @_;
  my $full_path = can_run('chgrp'); 
  my $cmd = [$full_path, '-R',$gid, $courses, $data, $htdocs_tmp, $logs, $tmp];
    if( scalar run( command => $cmd,
                    verbose => 1,
                    timeout => 20 )
    ) {
        print "Changed ownership of\n $courses,\n $data,\n $htdocs_tmp,\n $logs,\n $tmp\n to $gid.\n";
    }
}

sub change_permissions {
 my ($gid, $courses, $data, $htdocs_tmp, $logs, $tmp) = @_;
  my $chmod = can_run('chmod'); 
  my $cmd = [$chmod, '-R','g+w', $courses, $data, $htdocs_tmp, $logs, $tmp];
    if( scalar run( command => $cmd,
                    verbose => 1,
                    timeout => 20 )
    ) {
        print "Made the directories \n $courses,\n $data,\n $htdocs_tmp,\n $logs,\n $tmp\n group writable.\n";
    }
  my $find = can_run('find'); 
  $cmd = [$find, $courses, $data, $htdocs_tmp, $logs, $tmp, '-type', 'd','-and', '!', '(', '-name', '".git"','-prune', ')','-exec',$chmod,'g+s', '{}', ';'];
    if( scalar run( command => $cmd,
                    verbose => 1,
                    timeout => 20 )
    ) {
        print "Added group sticky bit to \n $courses,\n $data,\n $htdocs_tmp,\n $logs,\n $tmp\n and subdirectories (except .git's).\n";
    }
}
#############################################################
#
# Create webwork database...
#
############################################################

sub create_database {
  my ($dsn, $root_pw, $ww_db, $ww_user, $ww_pw) = @_;
  my $dbh = DBI->connect($dsn, 'root', $root_pw);
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

}

sub write_prelocal_conf {

}

sub write_global_conf {

}

sub write_postlocal_conf {

}

sub write_webwork_apache2_config {

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

sub symlink_webwork_apache2_config {
# cd /etc/httpd/conf.d
# ln -s /opt/webwork/webwork2/conf/webwork.apache2-config webwork.conf
}

sub setup_npl {
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

# cd /opt/webwork/courses
# /opt/webwork/webwork2/bin/addcourse admin --db-layout=sql_single --users=adminClasslist.lst --professors=admin

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


