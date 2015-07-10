package blankdistro;

use strict;
use warnings;

use WeBWorK::Install::Utils;

my $ww_versions = [];

sub get_ww_versions {
    return $ww_versions;
}

# Keep these hashes fleshed out because their keys are used to validate
# other distros.  That is, if we add a package here there will be a
# message that that package should be added to other distros with an actual
# value. 

# A list of packages for various binaries that we need. 
my $binary_prerequisites = {
    mkdir => '',
    mv => '',
    gcc => '',
    make => '',
    tar => '',
    gzip => '',
    unzip => '',
    dvipng => '',
    curl => '',
    perl => '',
    netpbm => '',  #provides giftopnm, ppmtopgm, pnmtops, pnmtopng, 
                        #and pgntopnm
    git => '',
    svn => '',

    mysql => '',
    mysql_server => '',
    ssh_server => '',

    apache2 => '',
    mod_mpm => '',
    mod_fcgid => '',
    mod_perl => '',
    mod_apreq => '',
    
    preview_latex => '',
    texlive => '',
};

sub get_binary_prerequisites {
    return $binary_prerequisites;
}

# A list of perl modules that we need
my $perl_prerequisites = {
    'Apache2::Request' => '',
    'Apache2::Cookie' => '',
    'Apache2::ServerRec' => '',
    'Apache2::ServerUtil' => '',
    'Array::Utils' => '',
    'Benchmark' => '',
    'Carp' => '',
    'CGI' => '',
    'Dancer' => '',
    'Dancer::Plugin::Database' => '',
    'Data::Dumper' => '',
    'Data::UUID' => '',
    'Date::Format' => '',
    'Date::Parse' => '',
    'DateTime' => '',
    'DBD::mysql' => '',
    'DBI' => '',
    'Digest::MD5' => '',
    'Email::Address' => '',
    'Errno' => '',
    'Exception::Class' => '',
    'ExtUtils::XSBuilder' => '',
    'File::Copy' => '',
    'File::Find' => '',
    'File::Find::Rule' => '',
    'File::Path' => '',
    'File::Spec' => '',
    'File::stat' => '',
    'File::Temp' => '',
    'GD' => '',
    'Getopt::Long' => '',
    'Getopt::Std' => '',
    'HTML::Entities' => '',
    'HTML::Scrubber' => '',
    'HTML::Tagset' => '',
    'HTML::Template' => '',
    'IO::File' => '',
    'Iterator' => '',
    'Iterator::Util' => '',
    'JSON' => '',
    'Locale::Maketext::Lexicon' => '',
    'Locale::Maketext::Simple' => '',
    'LWP::Protocol::https' => '',
    'Mail::Sender' => '',
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

sub midpreq_hook {
 
};

# A command for updating the package sources
sub update_sources {

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
