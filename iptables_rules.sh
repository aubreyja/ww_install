#!/bin/bash

#Delete all existing rules
iptables -F
 
# Set default chain policies
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP
 
# Allow full loopback access
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
 
# Allow connections that are related to allowed connections...
iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
 
# Allow incoming SSH
iptables -A INPUT -i eth0 -p tcp --dport 22 -m state --state NEW,ESTABLISHED -j ACCEPT
iptables -A OUTPUT -o eth0 -p tcp --sport 22 -m state --state ESTABLISHED -j ACCEPT
 
# Allow outgoing ssh - mainly for git - outgoing is mainly for git over ssh
iptables -A OUTPUT -o eth0 -p tcp --dport 22 -m state --state NEW,ESTABLISHED -j ACCEPT
iptables -A INPUT -i eth0 -p tcp --sport 22 -m state --state ESTABLISHED -j ACCEPT
 
# Allow incoming HTTP(S)
iptables -A INPUT -i eth0 -p tcp --dport 80 -m state --state NEW,ESTABLISHED -j ACCEPT
iptables -A OUTPUT -o eth0 -p tcp --sport 80 -m state --state ESTABLISHED -j ACCEPT
iptables -A INPUT -i eth0 -p tcp --dport 443 -m state --state NEW,ESTABLISHED -j ACCEPT
iptables -A OUTPUT -o eth0 -p tcp --sport 443 -m state --state ESTABLISHED -j ACCEPT
 
# Allow outgoing HTTP(S) - outgoing is mainly for git/svn over http(s)
iptables -A OUTPUT -o eth0 -p tcp --dport 80 -m state --state NEW,ESTABLISHED -j ACCEPT
iptables -A INPUT -i eth0 -p tcp --sport 80 -m state --state ESTABLISHED -j ACCEPT
iptables -A OUTPUT -o eth0 -p tcp --dport 443 -m state --state NEW,ESTABLISHED -j ACCEPT
iptables -A INPUT -i eth0 -p tcp --sport 443 -m state --state ESTABLISHED -j ACCEPT
 
# Allow dns
iptables -A OUTPUT -p udp -o eth0 --dport 53 -j ACCEPT
iptables -A INPUT -p udp -i eth0 --sport 53 -j ACCEPT
 
# Allow outgoing mail
iptables -A OUTPUT -o eth0 -p tcp --sport 25 -m state --state NEW,ESTABLISHED -j ACCEPT
iptables -A OUTPUT -o eth0 -p tcp --dport 25 -m state --state NEW,ESTABLISHED -j ACCEPT
iptables -A INPUT -i eth0 -p tcp --sport 25 -m state --state ESTABLISHED -j ACCEPT
 
# Allow ldap!!
iptables -A INPUT -i eth0 -p udp -m udp --dport 3268 -j ACCEPT
iptables -A OUTPUT -o eth0 -p udp -m udp --sport 3268 -j ACCEPT
iptables -A OUTPUT -o eth0 -p udp -m udp --dport 3268 -j ACCEPT
 
iptables -A INPUT -i eth0 -p tcp -m tcp --dport 3268 -j ACCEPT
iptables -A OUTPUT -o eth0 -p tcp -m tcp --sport 3268 -j ACCEPT
iptables -A OUTPUT -o eth0 -p tcp -m tcp --dport 3268 -j ACCEPT
 
#Log dropped packets - this all should go below the actual rules
iptables -N LOGGING #create logging chain
iptables -A INPUT -j LOGGING #incoming connections not handled above go to logging chain
iptables -A LOGGING -m limit --limit 2/min -j LOG --log-prefix "IPTables Packet Dropped: " --log-level 4 #do logging
iptables -A LOGGING -j DROP #then drop the packets
 
#Save the iptables rules on redhat with
#/sbin/service iptables save

