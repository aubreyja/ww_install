package centos::6;

use strict;
use warnings;

use WeBWorK::Install::Utils;

my $ww_versions = ['2.11'];

sub get_ww_versions {
    return $ww_versions;
}

# A list of packages for various binaries that we need. 
my $binary_prerequisites = {
    mkdir => 'coreutils',
    mv => 'coreutils',
    gcc => 'gcc',
    make => 'make',
    patch => 'patch',
    tar => 'tar',
    system_config => 'system-config-services',
    gzip => 'gzip',
    unzip => 'coreutils',
    dvipng => 'dvipng',
    curl => 'curl',
    perl => 'perl',
    netpbm => 'netpbm',  #provides giftopnm, ppmtopgm, pnmtops, pnmtopng, 
    netpbm_progs => 'netpbm-progs',               #and pgntopnm
    git => 'git',
    svn => 'subversion',

    mysql => 'mysql',
    mysql_server => 'mysql-server',
    ssh_server => 'openssh-server',

    apache2 => 'httpd',
    mod_mpm => 'httpd',
    mod_fcgid => 'mod_fcgid',
    mod_perl => 'mod_perl',
    mod_apreq => 'libapreq2',
    
    preview_latex => 'tex-preview',
    texlive => 'texlive-latex',
    texlive_epsf => 'texlive-epsf',
    txlive_texmf => 'texlive-texmf-latex',
};

sub get_binary_prerequisites {
    return $binary_prerequisites;
}

# A list of perl modules that we need
my $perl_prerequisites = {
    'Test::XML' => 'perl-Test-XML', # needed in centos 7 for cpan installs
    'Test::Simple' => 'perl-Test-Simple',
    'Test::Requires' => 'perl-Test-Requires',
    'Test::TCP' => 'perl-Test-TCP',
    'HTTP::Tiny' => 'perl-HTTP-Tiny', 
    'Plack'      => 'CPAN',
    'Plack::Builder' => 'CPAN',
    'Apache2::Request' => 'perl-libapreq2',
    'Apache2::Cookie' => 'perl-libapreq2',
    'Apache2::ServerRec' => 'mod_perl',
    'Apache2::ServerUtil' => 'mod_perl',
    'Array::Utils' => 'CPAN',
    'Benchmark' => 'perl',
    'Carp' => 'perl',
    'CGI' => 'perl-CGI',
    'CPAN' => 'perl-CPAN',
    'Dancer' => 'CPAN',
    'Dancer::Plugin::Database' => 'CPAN',
    'Data::Dumper' => 'perl-Data-Dumper',
    'Data::UUID' => 'CPAN',
    'Date::Format' => 'perl-TimeDate',
    'Date::Parse' => 'perl-TimeDate',
    'DateTime' => 'perl-DateTime',
    'DBD::mysql' => 'perl-DBD-MySQL',
    'DBI' => 'perl-DBI',
    'Digest::MD5' => 'perl',
    'Email::Address' => 'perl-Email-Address',
    'Errno' => 'perl',
    'Exception::Class' => 'perl-Exception-Class',
    'ExtUtils::XSBuilder' => 'perl-ExtUtils-XSBuilder',
    'File::Copy' => 'perl',
    'File::Find' => 'perl',
    'File::Find::Rule' => 'perl-File-Find-Rule',
    'File::Path' => 'perl',
    'File::Spec' => 'perl',
    'File::stat' => 'perl',
    'File::Temp' => 'perl',
    'GD' => 'perl-GD',
    'GDGraph' => 'perl-GDGraph',
    'Getopt::Long' => 'perl',
    'Getopt::Std' => 'perl',
    'HTML::Entities' => 'perl-HTML-Parser',
    'HTML::Scrubber' => 'perl-HTML-Scrubber',
    'HTML::Tagset' => 'perl-HTML-Tagset',
    'HTML::Template' => 'perl-HTML-Template',
    'IO::File' => 'perl',
    'Iterator' => 'CPAN',
    'Iterator::Util' => 'CPAN',
    'JSON' => 'perl-JSON',
    'Locale::Maketext::Lexicon' => 'perl-Locale-Maketext-Lexicon',
    'Locale::Maketext::Simple' => 'perl-Locale-Maketext-Simple',
    'LWP::Protocol::https' => '',
    'Mail::Sender' => 'perl-Mail-Sender',
    'MIME::Base64' => 'perl', 
    'Net::IP' => 'perl-Net-IP',
    'Net::LDAPS' => 'perl-LDAP',
    'Net::OAuth' => 'perl-Net-OAuth',
    'Net::SMTP' => 'perl-Net-SMTP-SSL',
    'Opcode' => 'perl',
    'PadWalker' => 'perl-PadWalker',
    'Path::Class' => 'perl-Path-Class',
    'PHP::Serialization' => 'CPAN',
    'Pod::Usage' => 'perl',
    'Pod::WSDL' => 'CPAN',
    'Safe' => 'perl',
    'Scalar::Util' => 'perl',
    'SOAP::Lite' => 'perl-SOAP-Lite',
    'Socket' => 'perl',
    'SQL::Abstract' => 'perl-SQL-Abstract',
    'String::ShellQuote' => 'perl-String-ShellQuote',
    'Template' => 'CPAN',
    'Text::CSV' => 'perl-Text-CSV',
    'Text::Wrap' => 'perl',
    'Tie::IxHash' => 'perl-Tie-IxHash',
    'Time::HiRes' => 'perl-Time-HiRes',
    'Time::Zone' => 'perl-TimeDate',
    'URI::Escape' => 'perl',
    'UUID::Tiny' => 'CPAN',
    'XML::Parser' => 'perl-XML-Parser',
    'XML::Parser::EasyTree' => 'CPAN',
    'XML::Writer' => 'perl-XML-Writer',
    'XMLRPC::Lite' => 'CPAN',
    'YAML' => 'perl-YAML',
};

sub get_perl_prerequisites {
    return $perl_prerequisites;
}

# A hash containing information about the apache webserver
my $apacheLayout = {
    MPMDir       => '',
    MPMConfFile  => '/etc/httpd/conf/httpd.conf',
    ServerRoot   => '/etc/httpd',
    DocumentRoot => '/var/www/html',
    ConfigFile   => '/etc/httpd/conf/httpd.conf',
    OtherConfig  => '/etc/httpd/conf.d',
    SSLConfig    => '',
    Modules      => '/etc/httpd/modules',
    ErrorLog     => '/var/log/httpd/error_log',
    AccessLog    => '/var/log/httpd/access_log',
    Binary       => '/usr/sbin/apachectl',
    User         => 'apache',
    Group        => 'apache',
};

sub get_apacheLayout {
    return $apacheLayout;
}

# A command for any distro specific stuff that needs to be done
# before installing prerequisites
sub prepreq_hook {

};

sub midpreq_hook {
    # we need a newer version of LWP::Protocol::https than is installed
    # which we can get by focing the cpan install (it fails because but 67001
    run_command(['cpan', '-f', 'LWP::Protocol::https']);
    run_command(['cpan', '-f', 'SOAP::Lite']);
    # Unfortunately we need an older version of something installed by CPAN
};

# A command for updating the package sources
sub update_sources {
    run_command(['yum', '-y', 'install', 'epel-release']);
};

# A command for updating the system
sub update_packages {
    run_command(['yum', '-y', 'update']);
};

# A command for installing a package given a name
sub package_install {
    my $self = shift;
    my @packages = @_;
    run_command(['yum','-y','install',@packages]);
};

# A command for installing a cpan package given a name
sub CPAN_install {
    my $self = shift;
    my @modules = @_;
    run_command(['cpan',@modules]);
};

# A command for any distro specific stuff that needs to be done
# after installing prerequieists
sub postpreq_hook {

}

# A command for checking if the required services are running and
# configuring them
sub configure_services {
    run_command(['service','mysqld','start']);
    run_command(['chkconfig','mysqld','on']);
    run_command(['service','httpd','start']);
    run_command(['chkconfig','httpd','on']);
    run_command(['mysql_secure_installation']);
}

# A command for any distro specific stuff that needs to be done
# before the webwork config process begins
sub preconfig_hook {

}

# A command for any distro specific stuff that needs to be done
# after webwork has been configured
sub postconfig_hook {

}

# A comand for any distro specific stuff that needs to be done
# after webwork has been fully installed
sub postinstall_hook {

}


1;
