package WeBWorK::Install::Utils;


use Exporter 'import'; # gives you Exporter's import() method directly
@EXPORT_OK = qw(writelog print_and_log); # symbols to export on request

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


