package centos::7;

use strict;
use warnings;

use WeBWorK::Install::Utils;

my $ww_versions = [];

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

    mysql => 'mariadb',
    mysql_server => 'mariadb-server',
    ssh_server => 'openssh-server',

    apache2 => 'httpd',
    mod_mpm => 'httpd',
    mod_fcgid => 'mod_fcgid',
    mod_perl => 'mod_perl',
    mod_apreq => 'libapreq2',
    
    preview_latex => 'tex-preview',
    texlive => 'texlive-latex',
    texlive_epsf => 'texlive-epsf',
};

sub get_binary_prerequisites {
    return $binary_prerequisites;
}

# A list of perl modules that we need
my $perl_prerequisites = {
    'Apache2::Request' => 'lipapreq2',
    'Apache2::Cookie' => 'libapreq2',
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
    'Data::UUID' => 'perl-Data-UUID',
    'Date::Format' => 'perl-TimeDate',
    'Date::Parse' => 'perl-TimeDate',
    'DateTime' => 'perl-TimeDate',
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
    'Locale::Maketext::Lexicon' => 'CPAN', #is availble for fedora
    'Locale::Maketext::Simple' => 'perl-Locale-Maketext-Simple',
    'LWP::Protocol::https' => 'perl-LWP-Protocol-https',
    'Mail::Sender' => 'perl-Mail-Sender',
    'MIME::Base64' => '',
    'Net::IP' => '',
    'Net::LDAPS' => '',
    'Net::OAuth' => '',
    'Net::SMTP' => '',
    'Opcode' => '',
    'PadWalker' => '',
    'Path::Class' => '',
    'PHP::Serialization' => '',
    'Pod::Usage' => '',
    'Pod::WSDL' => '',
    'Safe' => '',
    'Scalar::Util' => '',
    'SOAP::Lite' => '',
    'Socket' => '',
    'SQL::Abstract' => '',
    'String::ShellQuote' => '',
    'Template' => '',
    'Text::CSV' => '',
    'Text::Wrap' => '',
    'Tie::IxHash' => '',
    'Time::HiRes' => '',
    'Time::Zone' => '',
    'URI::Escape' => '',
    'UUID::Tiny' => '',
    'XML::Parser' => '',
    'XML::Parser::EasyTree' => '',
    'XML::Writer' => '',
    'XMLRPC::Lite' => '',
    'YAML' => '',
};

sub get_perl_prerequisites {
    return $perl_prerequisites;
}

# A hash containing information about the apache webserver
my $apacheLayout = {
    MPMDir       => '',
    MPMConfFile  => '',
    ServerRoot   => '',
    DocumentRoot => '',
    ConfigFile   => '',
    OtherConfig  => '',
    SSLConfig    => '',
    Modules      => '',
    ErrorLog     => '',
    AccessLog    => '',
    Binary       => '',
    User         => '',
    Group        => '',
};

sub get_apacheLayout {
    return $apacheLayout;
}

# A command for any distro specific stuff that needs to be done
# before installing prerequisites
sub prepreq_hook {

};

# A command for updating the package sources
sub update_sources {
    run_command(['yum', '-y', 'install', 'epel-release']);
};

# A command for updating the system
sub update_packages {

};

# A command for installing a package given a name
sub package_install {

};

# A command for installing a cpan package given a name
sub CPAN_install {

};

# A command for any distro specific stuff that needs to be done
# after installing prerequieists
sub postpreq_hook {

}

# A command for checking if the required services are running and
# configuring them
sub configure_services {

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
sub add_epel {
  my $arch = `rpm -q --queryformat "%{ARCH}" \$(rpm -q --whatprovides /etc/redhat-release)`;
  #or: ARCH=$(uname -m)

  my $ver = `rpm -q --queryformat "%{VERSION}" \$(rpm -q --whatprovides /etc/redhat-release)`;
  my $majorver = substr($ver,0,1);
  #or: MAJORVER=$(cat /etc/redhat-release | awk -Frelease {'print $2'}  | awk {'print $1'} | awk -F. {'print $1'})
  open(my $fh,'>','/etc/yum.repos.d/epel-bootstrap.repo') 
    or die "Couldn't open /etc/yum.repos.d/epel-bootstrap.repo for writing: $!";
  print $fh <<EOM;
[epel]
name=Bootstrap EPEL
mirrorlist=http://mirrors.fedoraproject.org/mirrorlist?repo=epel-$majorver&arch=$arch
failovermethod=priority
enabled=0
gpgcheck=0
EOM
  close($fh);

  #unlink('/etc/yum.repos.d/epel-bootstrap.repo');
}
sub yum_install {
  my @packages = @_;
  run_command(['yum','-y','update']);
  run_command(['yum','-y','install',@packages]);
}

