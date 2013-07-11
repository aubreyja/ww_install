#!/bin/sh

add_epel () {
    ARCH=$(uname -m)
    MAJORVER=$(cat /etc/redhat-release | awk -Frelease {'print $2'}  | awk {'print $1'} | awk -F. {'print $1'})
    sudo cat <<EOM >/etc/yum.repos.d/epel-bootstrap.repo
[epel]
name=Bootstrap EPEL
mirrorlist=http://mirrors.fedoraproject.org/mirrorlist?repo=epel-$MAJORVER&arch=$ARCH
failovermethod=priority
enabled=0
gpgcheck=0
EOM
    sudo yum --enablerepo=epel -y install epel-release
    sudo rm -f /etc/yum.repos.d/epel-bootstrap.repo
}

yum_install () {
    sudo yum -y install make patch gcc libapreq2 mod_perl mysql-server 
    sudo yum -y install dvipng netpbm netpbm-progs tex-preview git subversion system-config-services
    sudo yum -y install perl-CPAN perl-DateTime perl-Email-Address 
    sudo yum -y install perl-GD perl-GDGraph perl-LDAP perl-libapreq2 
    sudo yum -y install perl-Locale-Maketext-Lexicon perl-Mail-Sender 
    sudo yum -y install perl-PHP-Serialization perl-PadWalker 
    sudo yum -y install perl-SOAP-Lite perl-SQL-Abstract perl-String-ShellQuote 
    sudo yum -y install perl-Tie-IxHash uuid-perl perl-IPC-Cmd perl-Term-UI 
    sudo yum -y install perl-Exception-Class perl-Net-IP perl-XML-Parser
    sudo yum -y install perl-JSON perl-HTML-Scrubber perl-Net-OAuth perl-Text-CSV
}

apt_get_install () {
    APTOPTS='-y --allow-unauthenticated'
    sudo apt-get $APTOPTS install gcc make
    sudo apt-get $APTOPTS install git subversion
    sudo apt-get $APTOPTS install perl perl-modules 
    sudo apt-get $APTOPTS install dvipng netpbm unzip
    sudo apt-get $APTOPTS install preview-latex-style texlive-latex-base 
    sudo apt-get $APTOPTS install mysql-server openssh-server
    sudo apt-get $APTOPTS install apache2 apache2-mpm-prefork apache2.2-common libapreq2 libapache2-request-perl 
    sudo apt-get $APTOPTS install libdatetime-perl libdbi-perl libdbd-mysql-perl libemail-address-perl 
    sudo apt-get $APTOPTS install libexception-class-perl libextutils-xsbuilder-perl libgd-gd2-perl 
    sudo apt-get $APTOPTS install liblocale-maketext-lexicon-perl libmime-tools-perl libnet-ip-perl 
    sudo apt-get $APTOPTS install libnet-ldap-perl libnet-oauth-perl libossp-uuid-perl libpadwalker-perl 
    sudo apt-get $APTOPTS install libphp-serialization-perl libsoap-lite-perl libsql-abstract-perl 
    sudo apt-get $APTOPTS install libstring-shellquote-perl libtimedate-perl libuuid-tiny-perl libxml-parser-perl 
    sudo apt-get $APTOPTS install libxml-writer-perl libpod-wsdl-perl libjson-perl libtext-csv-perl 
    sudo apt-get $APTOPTS install libhtml-scrubber-perl 
}

if [ -e "/etc/redhat-release" ]
then
  if [ -e "/etc/fedora-release" ]
  then
    printf "%b\n" "# We've got Fedora"
    MYSQLSTART='sudo systemctl start mysqld.service'
    MYSQLENABLE='sudo systemctl enable mysqld.service'
    APACHESTART='sudo systemctl start httpd.service'
    APACHEENABLE='sudo systemctl enable httpd.service'
    CPANOPT='-j lib/cpan_config.pm'
  else 
    printf "%b\n" "# We've got a relative of RedHat which is not Fedora"
    MYSQLSTART='sudo service mysqld start'
    MYSQLENABLE='sudo chkconfig mysqld on'
    APACHESTART='sudo service httpd start'
    APACHEENABLE='sudo chkconfig httpd on'
    #CPANOPT=''
    printf "%b\n" "# Adding EPEL repository...."
    add_epel
  fi
  sudo yum -y update
  yum_install
  sudo cpan $CPANOPT XML::Parser::EasyTree Iterator Iterator::Util Pod::WSDL UUID::Tiny HTML::Template PHP::Serialization
  $MYSQLSTART
  $MYSQLENABLE
  $APACHESTART
  $APACHEENABLE
  sudo /usr/bin/mysql_secure_installation
elif [ -e "/etc/debian_version" ]
then
    sudo apt-get -y update
    sudo apt-get -y upgrade
    apt_get_install
    sudo cpan -j lib/cpan_config.pm XML::Parser::EasyTree HTML::Template Iterator Iterator::Util Mail::Sender
    sudo a2enmod apreq
    sudo apache2ctl restart
elif [ -e "/etc/SuSE-release" ]
then
    sudo zypper install gcc make subversion git wget texlive texlive-latex netpbm gd mysql-community-server mysql-community-server-client apache2 apache2-devel apache2-prefork perl perl-base perl-ExtUtils-XSBuilder perl-libwww-perl perl-GD perl-Tie-IxHash perl-TimeDate perl-DateTime perl-DBI perl-SQL-Abstract perl-DBD-mysql perl-OSSP-uuid perl-Email-Address perl-Exception-Class perl-URI perl-HTML-Parser perl-HTML-Tagset perl-HTML-Template perl-Iterator perl-XML-Parser perl-XML-Writer perl-Iterator-Util perl-JSON perl-Mail-Sender perl-MIME-tools perl-Net-IP perl-Net-SSLeay perl-IO-Socket-SSL perl-ldap-ssl perl-PadWalker perl-PHP-Serialization perl-SOAP-Lite perl-Locale-Maketext-Lexicon apache2-mod_perl apache2-mod_perl-devel
    sudo cpan -j lib/cpan_config.pm Apache::Test Pod::WSDL String::ShellQuote UUID::Tiny XML::Parser::EasyTree
##openSUSE doesn't seem to provide a package for libapreq2, meaning no way to get Apache2::Request or Apache2::Cookie without compiling from source
##Once they get this working, wil be able to do add Apache2::Modules repository to get libapreq2 via
#zypper ar -f http://download.opensuse.org/repositories/Apache:/Modules/Apache_openSUSE_12.2/Apache:Modules.repo #obviously this will have to be generalized
#then add libapreq2 perl-Apache2-Request perl-Apache2-Cookie to install list above. 
##In the meantime, here we go:
    wget http://search.cpan.org/CPAN/authors/id/I/IS/ISAAC/libapreq2-2.13.tar.gz
    tar -xzf libapreq2-2.13.tar.gz
    cd libapreq2-2.13
    perl Makefile.PL --with-apache2-apxs=/usr/sbin/apxs2
    make
    make install
    cd ..
    rm -rf libapreq2-2.13/
    rm libapreq2-2.13.tar.gz
else
    echo "I don't know what packages you need.  Fork me to fix this!"
fi


