package WeBWorK::Install::Utils;

use strict;
use warnings;
use Exporter 'import';

use FindBin;
use lib "$FindBin::Bin/../lib";
use Linux::Distribution qw(distribution_name distribution_version);
use cpan_config;

use Term::UI;
use Term::ReadLine;
use File::Copy;

use User::pwent;

use IO::Handle qw();

use IPC::Cmd qw(can_run run);
$IPC::Cmd::USE_IPC_RUN = 1;

use Config;
use CPAN;

our @EXPORT = qw(
print_and_log
writelog
run_command
get_existing_users
get_existing_groups
user_exists
group_exists
backup_file
slurp_file
get_reply
confirm_answer
);

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

$ENV{PERL_MM_USE_DEFAULT}=1;
$ENV{PERL_MM_NONINTERACTIVE}=1;
$ENV{AUTOMATED_TESTING}=1;

#######################################################################################
#
# Constants that control behavior IPC::Cmd::run
#
# ####################################################################################

use constant IPC_CMD_TIMEOUT =>
  6000;    #Sets maximum time system commands will be allowed to run
use constant IPC_CMD_VERBOSE => 1;    #Controls whether all output of a command
                                      #should be printed to STDOUT/STDERR

###########################################################
#
# Logging
#
###########################################################


# Globals: filehandle LOG is global.
my $LOG;
if (!open($LOG,"> ../webwork_install.log")) {
    die "Unable to open log file.\n";
} else {
    print $LOG 'This is ww_install.pl '.localtime."\n\n";
}

sub print_and_log {
  my $msg = shift;
  print $LOG "$msg";
  print "$msg";
}

sub writelog {
  my $msg = shift;
  print $LOG "$msg";
}

sub run_command {
    my $cmd = shift; #should be an array reference

    my $output;
    my (
        $success, $error_message, $full_buf,
        $stdout_buf, $stderr_buf
      )
      = run(
        command => $cmd,
        buffer => \$output,
        verbose => IPC_CMD_VERBOSE,
        timeout => IPC_CMD_TIMEOUT
      );
      my $cmd_string = join(' ',@$cmd);
      writelog("Running [".$cmd_string."]\n");
      writelog("OUTPUT: ".$output."\n") if defined($output);
  
      if (!$success) {
        writelog($error_message) if $error_message;
        my $print_me = "Warning! The last command exited with an error: $error_message\n\n".
            "We have logged the error message, if any. We suggest that you exit now and ".
            "report the error at https://github.com/openwebwork/ww_install ".
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

sub backup_file {
  my $fullpath = $_;
  my (undef,$dir,$file) = File::Spec->splitpath($fullpath);
  copy($fullpath,$dir."/".$file.".bak");
  #add error handling...
  #add success reporting
}

sub slurp_file {
  my $fullpath = shift;
  open(my $fh,'<',$fullpath) or print_and_log("Couldn't find $fullpath: $!");
  return unless $fh;
  my $string = do { local($/); <$fh> };
  close($fh);
  return $string;
}
#####################################################################
#
# Script Util Subroutines:  The script is based on Term::Readline 
# to interact with user
#
######################################################################
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
  writelog($term->history_as_string()."\n");
  Term::UI::History->flush();

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


1;

