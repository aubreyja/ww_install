#!/bin/bash

if [ -e "/etc/redhat-release" ]
then
	sudo yum install dvipng gcc libapreq2 mod_perl mysql-server perl-DateTime perl-Email-Address perl-GD perl-GDGraph perl-LDAP perl-libapreq2 perl-Locale-Maketext-Lexicon perl-Mail-Sender perl-PHP-Serialization perl-PadWalker perl-SOAP-Lite perl-SQL-Abstract perl-String-ShellQuote perl-Tie-IxHash system-config-services tex-preview uuid-perl perl-IPC-Cmd perl-Term-UI git subversion
elif [ -e "/etc/debian_version" ]
then
    sudo apt-get install apache2 apache2-mpm-prefork dvipng gcc libapache2-request-perl libdatetime-perl libdbd-mysql-perl libemail-address-perl libexception-class-perl libextutils-xsbuilder-perl libgd-gd2-perl liblocale-maketext-lexicon-perl libmail-sender-perl libmime-perl libnet-ip-perl libnet-ldap-perl libossp-uuid-perl libpadwalker-perl libphp-serialization-perl libsoap-lite-perl libsql-abstract-perl libstring-shellquote-perl libtimedate-perl libuuid-tiny-perl libxml-parser-perl libxml-writer-perl make mysql-server netpbm openssh-server preview-latex-style subversion texlive unzip
else
    echo "I don't know what packages you need.  Fork me to fix this!"
fi
