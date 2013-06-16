#!/bin/bash

if [ -e "/etc/redhat-release" ]
then
	sudo yum install dvipng gcc libapreq2 mod_perl mysql-server perl-DateTime perl-Email-Address perl-GD perl-GDGraph perl-LDAP perl-libapreq2 perl-Locale-Maketext-Lexicon perl-Mail-Sender perl-PHP-Serialization perl-PadWalker perl-SOAP-Lite perl-SQL-Abstract perl-String-ShellQuote perl-Tie-IxHash system-config-services tex-preview uuid-perl perl-IPC-Cmd perl-Term-UI git subversion perl-Exception-Class perl-Net-IP perl-XML-Parser
    sudo cpan -j lib/cpan_config.pm XML::Parser::EasyTree Iterator Iterator::Util Pod::WSDL UUID::Tiny HTML::Template
    sudo service start mysqld.service
    sudo /usr/bin/mysql_secure_installation
elif [ -e "/etc/debian_version" ]
then
    sudo apt-get -y update
    sudo apt-get -y upgrade
    sudo apt-get -y install apache2 apache2-mpm-prefork apache2.2-common libapreq2 dvipng gcc perl perl-modules libapache2-request-perl git libdatetime-perl libdbi-perl libdbd-mysql-perl libemail-address-perl libexception-class-perl libextutils-xsbuilder-perl libgd-gd2-perl liblocale-maketext-lexicon-perl libmime-tools-perl libnet-ip-perl libnet-ldap-perl libnet-oauth-perl libossp-uuid-perl libpadwalker-perl libphp-serialization-perl libsoap-lite-perl libsql-abstract-perl libstring-shellquote-perl libtimedate-perl libuuid-tiny-perl libxml-parser-perl libxml-writer-perl libpod-wsdl-perl libjson-perl libtext-csv-perl libhtml-scrubber-perl make mysql-server netpbm openssh-server preview-latex-style subversion texlive unzip
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

