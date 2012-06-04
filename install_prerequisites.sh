#!/bin/bash

if [ -e "/etc/redhat-release" ]
then
	sudo yum install dvipng gcc libapreq2 mod_perl mysql-server perl-DateTime perl-Email-Address perl-GD perl-GDGraph perl-LDAP perl-libapreq2 perl-Locale-Maketext-Lexicon perl-Mail-Sender perl-PHP-Serialization perl-PadWalker perl-SOAP-Lite perl-SQL-Abstract perl-String-ShellQuote perl-Tie-IxHash system-config-services tex-preview uuid-perl perl-IPC-Cmd perl-Term-UI git
else
    echo "I don't know what packages you need.  Fork me to fix this!"
fi
