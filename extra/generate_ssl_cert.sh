#!/bin/sh

echo "First we'll create an RSA private key."
echo "When asked to enter a passphrase, enter a very good one and remember it!"
openssl genrsa -des3 -out server.key 1024 
echo "Next we generate a certificate signing request."
echo "IMPORTANT: When you are prompted for a common name
enter your server's fully qualified domain name."
openssl req -new -key server.key -out server.csr
echo "Next we'll modify the key so that Apache doesn't ask for the
passphrase each time the webserver is started."
cp server.key server.key.bak1
openssl rsa -in server.key.bak1 -out server.key
echo "Next we'll generate a self signed certificate which is good for 365 days"
openssl x509 -req -days 365 -in server.csr -signkey server.key -out server.crt

#TODO: The remaining steps probably require some OS specific information.
#E.g. locations and group ownership is probably ubuntu/debian specific

#(1) Move files and adjust ownership and permissions
#echo "Now we'll move server.crt and server.key to /etc/ssl/private"
#mv server.crt /etc/ssl/private
#mv server.key /etc/ssl/private
#cd /etc/ssl/private
#echo "Changing group ownership and permissions on server.key and server.cert" 
#chgrp ssl-cert server.*
#chmod 640 server.*

#(2) Enable ssl apache module
#a2enmod ssl #ubuntu/debian only

#(3) Edit virtual hosts site definitions
# to enable ssl at *:443 and redirect *:80
# see conf/ dir for example file for ubuntu

#(4) Restart apache

