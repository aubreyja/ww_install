[WeBWorK](https://github.com/openwebwork) Installation Script(s)
===============================================================

This repository consists of a perl script `ww_install.pl`, along with some supporting bash scripts, 
config files, and perl modules designed to work together install the open source online homework system 
[WeBWorK](https://github.com/openwebwork).

The script has been updated to install WeBWorK 2.13 as of 12/1/2017 by Arnold Pizer.

Temporary General Instructions for installing WeBWorK 2.13 using the ww_install script. 
*  You should use the perl script ww_install.pl as the bash shell script install_webwork.sh has not yet been updated.
*  First look at the notes below to see if you need to do anything before running the ww_install.pl script.
*  After any preliminaries in a working directory run
   - git clone git://github.com/openwebwork/ww_install.git
     * Note you will have to install git (e.g. as root, apt-get install git) if it is not on your system
   - cd to the directory ww_install
   - Run perl bin/ww_install as root. Note either use sudo or su to root depending on the system.
   - Accept all defaults



It has been tested and works on 
*  Debian 9
   - Notes for Debian
     - Before running the script ww_install.pl do the following:
       1. For some reason WeBWorK fails to work with MariaDB as installed from the Debian package so we use the package from mariadb.org.
       2. Open firefox and goto https://downloads.mariadb.org
       3. Click on: Use CentOS, Fedora, Red Hat, Debian, Ubuntu, openSUSE, or Mageia? See our repository configuration tool.
       4. Select: Debian, Debian 9 Stretch, 10.2. and a mirror
       5. Follow the instrucions for running commands but run them as root as sudo does not work.  Note that using copy and paste works well.
     - Now run the script ww_install as root
     - The script ww_install will stop at installing Email::Sender::Simple with an error.  Just rerun the 
       script and it will get past that point. I think Email::Sender::Simple does get installed correctly.

*  Fedora 24 (Workstation)
   - Notes for Fedora 
     - Before running the script ww_install.pl do the following:
       1. Run the command: sudo dnf install perl-core
       2. Run the command: sudo dnf update perl-Errno
       3. Edit the file /etc/selinus/config setting: SELINUX=disabled and reboot.
     - Now run the script ww_install as root

*  Ubuntu 16.04 LTS (Desktop) 
   - Notes for Ubuntu
     - None 

*  CentOS 7 (Server with GUI)
   - Notes for CentOS. 
     - Before running the script ww_install.pl do the following:
       1. Run the command: sudo yum install perl-core
       2. Edit the file /etc/selinus/config setting: SELINUX=disabled and reboot.
     - Now run the script ww_install as root

On these systems it did install WeBWorK. 

Gotchas
-------

-  See the notes above. 

Usage
-------

To install [WeBWorK](https://github.com/openwebwork):

1. Get the `install_webwork.sh` script:

  `wget --no-check-certificate https://raw.githubusercontent.com/openwebwork/ww_install/master/install_webwork.sh`
  
  or if you prefer
  
  `curl -ksSO https://raw.githubusercontent.com/openwebwork/ww_install/master/install_webwork.sh`

2. As root (or with sudo) do

  `bash install_webwork.sh`

Note that if you use sudo, then you must be a sudoer with sufficient administrative rights 
(probably `ALL=(ALL) ALL`) for `install_webwork.sh` to work properly. If not, run this command as root.

For more control over the process you can clone this repository with

`git clone git://github.com/openwebwork/ww_install.git`

and then run ` sudo perl ww_install.pl`.  

Contents
--------

### install_webwork.sh

This script is the 'controller' that ties together the other scripts.  It opens an install log, downloads this
repo and opens it in (typically) `/tmp`.  Then it installs any files needed to run `ww_install.pl` and then runs `ww_install.pl`.
When `ww_install.pl` exits, it attempts to open webwork in the system's default web browser, copies 
webwork_install.log to your top level webwork directory (e.g. `/opt/webwork`) and then deletes the downloaded installation package.

### bin/ww_install.pl

The goal of `ww_install.pl` is to install WeBWorK on any system with a properly set up distribution file in the `distros` folder.  

It is an interactive script based on the core perl module [Term::UI](http://perldoc.perl.org/Term/UI.html), and is written with the goal of being cross-platform.  It does use some linux built-ins, and work is needed to ensure that this script will work as well on unix machines. Again, contributions of work in this direction would be welcome.

### distros

This folder contains distribution files which `ww_install.pl` uses to install WeBWorK on various systems.  For example the file `distros/centos/7.pm` is used to install WeBWorK on CentOS version 7.  If you are interested in getting the installer working on your favorite distribution you would create the appropriate file in this folder and submit a pull request.  You can base your distro file off of `blankdistro.pm`.  In general you will need to set the following:
* The array of versions which you have tested the installer on.
* The list of packages which provide the binaries described by the hash keys
* The list of packages which provide the perl modules described by the hash keys.  Use 'CPAN' if you intend to get the package from CPAN
* The `apacheLayout` array which defines where various folders and configuration files are for your apache setup.
* The command for updating package sources.
* The command for updating packages.
* The command for installing packages.
* The command for installing packages from CPAN.
* The command for checking and configuring services post install.
* You can add code in various "hooks" which will be run at various stages of the installation.  This is an opportunity to perform any hacky fixes necessary for your distro.  

### old_distros
This folder contains obsolete distribution files which are no longer being supported.

### Other files

The `extra/` subdirectory contains scripts which help with optional post install tasks.  These are not currently 
hooked into the other scripts, so you'll need to run them separately.  Currently contains

* `iptables_rules.sh` 

  Sets up an iptables firewall which only allows network services necessary for running WeBWorK.

* `generate_ssl_cert.sh`

  Steps user through generating an ssl cert.  Under construction.

* `install_chromatic.pl`

  Standalone script to compile `pg/lib/chromatic/color.c` so the NAU library graph theory problems work. This
  functionality has been incorporated into `ww_install.pl`, so it should not be necessary to run this script. However,
  if you find the NAU graph theory problems are complaining that `pg/lib/chromatic/color` doesn't exist, then you 
  can run this script to compile it for you.

The `lib/` subdirectory contains copies of any perl modules the script uses but which don't need to be installed 
on your system for webwork to run.

The `conf/` subdirectory contains copies of config files or snippets of config files that this installation package
will ask to modify.

Other Resources
----------------

Please report any problems on the [issues page](https://github.com/openwebwork/ww_install/issues?state=open) for this
repository.

Questions and comments about this installer can be directed to me on the [webwork-devel](http://webwork.maa.org/mailman/listinfo/webwork-devel)
mailing list. For a recent discussion see [[1]](http://webwork.maa.org/pipermail/webwork-devel/2013-June/001089.html).

Information and documentation about WeBWorK itself can be found at http://webwork.maa.org/wiki

Author
--------

Jason Aubrey <aubreyja@gmail.com>

Small updates (for WeBWorK 2.13) made by Arnold Pizer <apizer@math.rochester.edu>

If you use the script, please email me to let me know what OS you installed it on so I can add a notation to
the list of tested distributions above and address any problems you run into. I'd also be happy to hear 
suggestions for improvement.  Seriously, though.  Send all your complaints to this guy.  

Acknowledgements
----------------

This script was inspired by Tom Haggedorn's [automatic installer for WeBWorK 2.4 on Mac OS 10.5 for Intel processors](http://webwork.maa.org/wiki/Automatic_Installer_for_2.4_on_Mac_OS_10.5_for_Intel_processors) bash script.
Valuable feedback and testing has been provided by [Danny Glin](https://github.com/dlglin), [Djun Kim](https://github.com/djun-kim),
[Geoff Gohle](https://github.com/goehle), [John Travis](https://github.com/drjt), [Peter Staab](https://github.com/pstaabp),
[Arnie Pizer](https://github.com/apizer), [Paul Pearson](https://github.com/paultpearson), [Christina Kayastha](https://github.com/christinakayastha), and
[Nathaniel Case (Qalthos)](https://github.com/Qalthos).

Copyright and Disclaimer
-------------------------

This program is Copyright 2016 by Jason Aubrey and in 2017 by Arnold Pizer.  This program is
free software; you can redistribute it and/or modify it under the terms
of the Perl Artistic License or the GNU General Public License as
published by the Free Software Foundation; either version 2 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
General Public License for more details.

If you do not have a copy of the GNU General Public License write to
the Free Software Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139,
USA.

