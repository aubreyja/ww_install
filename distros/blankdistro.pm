package blankdistro;

use strict;
use warnings;

use install_utils;

# This is a list of WeBWorK versions for which the installer has
# been verified to work for this distro. 
my $ww_versions = [];

sub get_ww_versions {
    return $ww_versions;
}

# A list of packages for various binaries that we need. 
my $binary_prerequisites = {};    

sub get_binary_prerequisites {
    return $binary_prerequisites;
}

# A list of perl modules that we need
my $perl_prerequisites = {};

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
