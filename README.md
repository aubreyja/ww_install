[WeBWorK](https://github.com/openwebwork) Installation Script(s)
===============================================================

This repository consists of a perl script `ww_install.pl`, along with some supporting bash scripts, 
config files, and perl modules designed to work together install the open source online homework system 
[WeBWorK](https://github.com/openwebwork).

It's been lightly tested on

* [CentOS 6.4](http://wiki.centos.org/Download) (7/2013)
* [Fedora 17 (Beefy Miracle)](http://docs.fedoraproject.org/en-US/Fedora/17/html/Release_Notes/) (11/2012)
* [Debian 7.0 (Wheezy) GNU/Linux](http://www.debian.org/releases/wheezy/) (6/2013)

It's been moderately well tested on

* [Ubuntu 12.04 (Precise Pangolin)](http://releases.ubuntu.com/precise/) (11/2012, 6/2013)
* [Ubuntu 13.04 (Raring Ringtail)](http://releases.ubuntu.com/raring/) (6/2013)

On these systems it did install webwork. 

Note that at this time (7/2013) WeBWorK does not work on Fedora 18 due to
changes in Apache 2.4.4 and mod_perl 2.0.8.

Usage
-------

To install [WeBWorK](https://github.com/openwebwork):

1. Get the `install_webwork.sh` script:

  `wget https://raw.github.com/aubreyja/ww_install/master/install_webwork.sh`
  
  or if you prefer
  
  `curl -ksSO https://raw.github.com/aubreyja/ww_install/master/install_webwork.sh`

2. As root (or with sudo) do

  `bash install_webwork.sh`

Note that if you use sudo, then you must be a sudoer with sufficient administrative rights 
(probabaly `ALL=(ALL) ALL`) for `install_webwork.sh` to work properly. If not, run this command as root.

For more control over the process you can clone this repository with

`git clone https://github.com/aubreyja/ww_install.git`

and then run the scripts individually as needed.

Contents
--------

### install_webwork.sh

This script is the 'conroller' that ties together the other scripts.  It opens an install log, downloads this
repo and opens it in (typically) tmp/.  Then it runs `install_prerequisites.sh` followed by `ww_install.pl`.
When `ww_install.pl` exits, it attempts to open webwork in the system's default web browser, copies 
webwork_install.log to `webwork2/logs` and then deletes the downloaded installation package.

### install_prerequisites.sh

If your system does not have all of the prerequisites installed, then the `install_prerequisites.sh` script 
might help.  The goal of that script is to install all of the software that WeBWorK depends on. This is also
the script most likely to be incomplete or fail in some way on your system.  For systems based on Debian 
(Ubuntu,etc.), it will do everything needed.  However, on systems based on Red Hat Linux (Fedora, 
CentOS, Scientific Linux) and on SUSE this script is only partially complete. We're working 
on getting it to install prereqs on other systems also, but for now other systems will need to have these 
prerequisites already installed.  If you would like to fill it out for your favorite linux distro or unix
system, I will happily accept pull requests.

### ww_install.pl

The goal of `ww_install.pl` is to install WeBWorK on any system on which the preqrequisites are already installed.  
It is an interactive script based on the core perl module Term::UI, and is written with the goal of being 
cross-platform.  It does use some linux built-ins, and work is needed to ensure that this script will work as 
well on unix machines. Again, contributions of work in this direction would be welcome.

### iptables_rules.sh

The `iptables_rules.sh` script sets up a firewall which only allows network services necessary for running WeBWorK.
This script is not currently hooked into the other scripts, so you'll need to run this separately as root if you
want to use it to set up a firewall.

### Other files

The `lib/` subdirectory contains copies of any perl modules the script uses but which don't need to be installed on your
system for webwork to run.

The `conf/` subdirectory contains copies of config files or snippets of config files that this installation package
will ask to modify.

Other Resources
----------------

Please report any problems on the [issues page](https://github.com/aubreyja/ww_install/issues?state=open) for this
repository.

Questions and comments about this installer can be directed to me on the [webwork-devel](http://webwork.maa.org/mailman/listinfo/webwork-devel)
mailing list. For a recent discussion see [[1]](http://webwork.maa.org/pipermail/webwork-devel/2013-June/001089.html).
