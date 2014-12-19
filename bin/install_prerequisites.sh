#!/bin/sh

add_epel () {
    ARCH=$(uname -m)
    MAJORVER=$(cat /etc/redhat-release | awk -Frelease {'print $2'}  | awk {'print $1'} | awk -F. {'print $1'})
     cat <<EOM >/etc/yum.repos.d/epel-bootstrap.repo
[epel]
name=Bootstrap EPEL
mirrorlist=http://mirrors.fedoraproject.org/mirrorlist?repo=epel-$MAJORVER&arch=$ARCH
failovermethod=priority
enabled=0
gpgcheck=0
EOM
     yum --enablerepo=epel -y install epel-release
     rm -f /etc/yum.repos.d/epel-bootstrap.repo
}

yum_install () {
     yum -y install make patch gcc libapreq2 mod_perl mariadb-server 
     yum -y install dvipng netpbm netpbm-progs tex-preview git subversion system-config-services
     yum -y install perl-CPAN perl-YAML perl-DateTime perl-Email-Address
     yum -y install perl-GD perl-GDGraph perl-LDAP perl-libapreq2 
     yum -y install perl-Locale-Maketext-Lexicon perl-Mail-Sender perl-Time-HiRes
     yum -y install perl-PHP-Serialization perl-PadWalker
     yum -y install perl-SOAP-Lite perl-SQL-Abstract perl-String-ShellQuote 
     yum -y install perl-Tie-IxHash uuid-perl perl-IPC-Cmd perl-Term-UI 
     yum -y install perl-Exception-Class perl-Net-IP perl-XML-Parser perl-XML-Writer
     yum -y install perl-JSON perl-HTML-Scrubber perl-Net-OAuth perl-Text-CSV
     yum -y install perl-File-Find-Rule #ww2.8
     yum -y install mod_fcgid
     #note texlive-path is for fedora, but not availabe or necc on centos
     yum -y install texlive-epsf texlive-path
}

apt_get_install () {
    APTOPTS='-y --allow-unauthenticated'

    #make sure we don't try to get anything off of 
    #a cdrom. (Allowing it causes script to hang 
    # on Debian 7)
    sed -i -e 's/deb cdrom/#deb cdrom/g' /etc/apt/sources.list

    #Install some prerequisites
     apt-get $APTOPTS install gcc make
     apt-get $APTOPTS install git subversion
     apt-get $APTOPTS install perl perl-modules 
     apt-get $APTOPTS install dvipng netpbm unzip
     apt-get $APTOPTS install preview-latex-style texlive-latex-base texlive-latex-recommended
     apt-get $APTOPTS install mysql-server openssh-server
     apt-get $APTOPTS install apache2-mpm-prefork libapache2-request-perl 
     apt-get $APTOPTS install libdatetime-perl libdbi-perl libdbd-mysql-perl libemail-address-perl 
     apt-get $APTOPTS install libexception-class-perl libextutils-xsbuilder-perl libgd-gd2-perl 
     apt-get $APTOPTS install liblocale-maketext-lexicon-perl libmime-tools-perl libnet-ip-perl 
     apt-get $APTOPTS install libnet-ldap-perl libnet-oauth-perl libossp-uuid-perl libpadwalker-perl libyaml-perl libtemplate-perl 
     apt-get $APTOPTS install libphp-serialization-perl libsoap-lite-perl libsql-abstract-perl 
     apt-get $APTOPTS install libstring-shellquote-perl libtimedate-perl libuuid-tiny-perl libxml-parser-perl 
     apt-get $APTOPTS install libxml-writer-perl libpod-wsdl-perl libjson-perl libtext-csv-perl 
     apt-get $APTOPTS install libhtml-scrubber-perl texlive-generic-recommended texlive-fonts-recommended
     apt-get $APTOPTS install libfile-find-rule-perl #ww2.8
     apt-get $APTOPTS install libapache2-mod-fcgid #ww3
}

if [ -e "/etc/redhat-release" ]
then
  if [ -e "/etc/fedora-release" ]
  then
    printf "%b\n" "# We've got Fedora"
    MYSQLSTART='systemctl start mariadb.service'
    MYSQLENABLE='systemctl enable mariadb.service'
    APACHESTART='systemctl start httpd.service'
    APACHEENABLE='systemctl enable httpd.service'
    CPANOPT='-j lib/cpan_config.pm'
  else 
    printf "%b\n" "# We've got a relative of RedHat which is not Fedora"
    MYSQLSTART='service mariadb start'
    MYSQLENABLE='chkconfig mariadb on'
    APACHESTART='service httpd start'
    APACHEENABLE='chkconfig httpd on'
    #CPAN on centos isn't new enough to have the -j so we do it manually
    CPANOPT='-j lib/cpan_config.pm'
    printf "%b\n" "# Adding EPEL repository...."
    add_epel
  fi
   yum -y update
  yum_install

  # Right now there isn't a package which provides the latex path.sty file
  # in CentOS 7.  Since its a noarch kind of package we can just steal it from
  # Fedora.  This is an ugly hack
if [ -e "/etc/redhat-release" ]
then
    if grep -q "CentOS Linux Release 7" "/etc/redhat-release"
    then
	curl -ksSO ftp://211.68.71.80/pub/mirror/fedora/updates/testing/18/i386/texlive-path-svn22045.3.05-0.1.fc18.noarch.rpm
	yum install texlive-path-svn22045.3.05-0.1.fc18.noarch.rpm
    fi
fi

  # currently needed bcause cpan doesnt find these prerequsities for Pod::WSDL and Test::XML is broken
   cpan $CPANOPT Module::Build Fatal XML::SAX 
   cpan $CPANOPT -f Test::XML    
   cpan $CPANOPT XML::Parser::EasyTree Iterator Iterator::Util UUID::Tiny PHP::Serialization Env Pod::WSDL
   cpan $CPANOPT Locale::Maketext::Lexicon SQL::Abstract XMLRPC::Lite
   #ww3
   cpan $CPANOPT Dancer Dancer::Plugin::Database Plack::Runner Plack::Handler::FCGI Path::Class Array::Utils Template
   cpan $CPANOPT File::Find::Rule Path::Class FCGI File::Slurp
    #This needs to be last because of some sort of prereq issue. 
   cpan $CPANOPT HTML::Template
  $MYSQLSTART
  $MYSQLENABLE
  $APACHESTART
  $APACHEENABLE
   /usr/bin/mysql_secure_installation
elif [ -e "/etc/debian_version" ]
then
     apt-get -y update
     apt-get -y upgrade
     apt_get_install
     CPANOPT='-j lib/cpan_config.pm'
     cpan $CPANOPT XML::Parser::EasyTree HTML::Template Iterator Iterator::Util Mail::Sender
   #ww3
     cpan $CPANOPT Dancer Dancer::Plugin::Database Plack::Runner Plack::Handler::FCGI Path::Class Array::Utils
     cpan $CPANOPT File::Find::Rule Path::Class FCGI File::Slurp
     a2enmod apreq
     a2enmod fcgid
     apache2ctl restart
elif [ -e "/etc/SuSE-release" ]
then
     zypper install gcc make subversion git wget texlive texlive-latex netpbm gd mysql-community-server mysql-community-server-client apache2 apache2-devel apache2-prefork perl perl-base perl-ExtUtils-XSBuilder perl-libwww-perl perl-GD perl-Tie-IxHash perl-TimeDate perl-DateTime perl-DBI perl-SQL-Abstract perl-DBD-mysql perl-OSSP-uuid perl-Email-Address perl-Exception-Class perl-URI perl-HTML-Parser perl-HTML-Tagset perl-HTML-Template perl-Iterator perl-XML-Parser perl-XML-Writer perl-Iterator-Util perl-JSON perl-Mail-Sender perl-MIME-tools perl-Net-IP perl-Net-SSLeay perl-IO-Socket-SSL perl-ldap-ssl perl-PadWalker perl-PHP-Serialization perl-SOAP-Lite perl-Locale-Maketext-Lexicon apache2-mod_perl apache2-mod_perl-devel
     cpan -j lib/cpan_config.pm Apache::Test Pod::WSDL String::ShellQuote UUID::Tiny XML::Parser::EasyTree
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


