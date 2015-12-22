#!/bin/sh

PREREQUISITES=1
VERBOSE=''
INTERACTIVE=''
MYSQL_ROOT_PW=''
WEBWORK_DB_PW=''

BRANCH=master
WWINSTALLURL=https://github.com/openwebwork/ww_install/archive/$BRANCH.tar.gz
THISDIR="$( pwd )"


usage () {
echo "
NAME

  install_webwork.sh

SYNOPSIS

  install_webwork.sh [OPTIONS]

DESCRIPTION

install_webwork.sh is the 'controller' that ties together the other scripts 
in the ww_install package. It opens an install log, downloads this repo and 
opens it in (typically) tmp/. Then it optionally runs install_prerequisites.sh 
followed by ww_install.pl. When ww_install.pl exits, install_webwork.sh attempts 
to open webwork in the system's default web browser, copies webwork_install.log 
to webwork2/logs and then deletes the downloaded installation package.

  --h, --help, --usage

  Print this help message.

  -np, --no-prerequisites (not implemented)

  Do not run install_prerequisites.sh before running ww_install.pl. Note that
  ww_install.pl will fail if WeBWorK's dependencies are not installed so be
  sure that you know all of WeBWorK's prerequisites are installed before using
  this option.

  -nv, --no-verbose (not implemented)

  Turns off vebose output. By default all commands that have the option to provide
  verbose output will produce verbose output. This output goes to stdout and to
  webwork_install.log and is helpful for debugging if problems arise. If you
  want to be all cowboy and throw caution into the wind, then this option will
  silence verbose output.

  -ni, --no-interactive (not implemented)

  Run ww_install.pl non-interactively. This option requires setting both
  --mysql_root_pw and --webwork_db_pw.  All other webwork configuration 
  questions asked by ww_install.pl will be answered for you with their 
  default replies. 

  --mysql_root_pw PASSWORD (not implemented)

  Passes the mysql root password to ww_install.pl. Needed to create the webwork
  database. Only required if --no_interactive is set. Otherwise ww_install.pl
  will ask you for it.

  --webwork_db_pw PASSWORD (not implemented)

  Passes the password to use for the webwork database to ww_install.pl. Needed 
  to grant rights to the webwork db to the webwork db user. Only required 
  if --no_interactive is set. Otherwise ww_install.pl will ask you for it.

  AUTHOR

  Written by Jason Aubrey.

  REPORTING BUGS

  View and report bugs at https://github.com/openwebwork/ww_install/issues
  ww_install home page: https://github.com/openwebwork/ww_install

  COPYRIGHT

  This program is Copyright 2013 by Jason Aubrey. This program is free 
  software; you can redistribute it and/or modify it under the terms of 
  the Perl Artistic License or the GNU General Public License as published 
  by the Free Software Foundation; either version 2 of the License, or 
  (at your option) any later version.

  This program is distributed in the hope that it will be useful, but 
  WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY 
  or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for 
  more details.

  If you do not have a copy of the GNU General Public License write to the Free 
  Software Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
" | less
}

while :
do
    case $1 in
        -h | --h | --help | -help | --usage | -usage | -\?)
            #  Call your Help() or usage() function here.
            usage
            exit 0      # This is not an error, User asked help. Don't do "exit 1"
            ;;
        -np | --no-prerequisites | --no-prereqs)
            PREREQUISITES=0
            shift
            ;;
        -nv | --no-verbose)
            VERBOSE='--no-verbose' 
            shift
            ;;
        -ni | --no-interactive)
            INTERACTIVE='--no-interactive' 
            shift
            ;;
        --mysql_root_pw)
            MYSQL_ROOT_PW="--mysql_root_pw $2"
            shift 2
            ;;
        --webwork_db_pw)
            WEBWORK_DB_PW="--webwork_db_pw $2"
            shift 2
            ;;
        --) # End of all options
            shift
            break
            ;;
        -*)
            echo "WARN: Unknown option (ignored): $1" >&2
            shift
            ;;
        *)  # no more options. Stop while loop
            break
            ;;
    esac
done

if [ "$INTERACTIVE" == "--no-interactive" ]
  then
    if [ ! "$MYSQL_ROOT_PW" ]
      then
        echo "ERROR: option --no-interactive requires setting both 
        --mysql_root_pw and --webwork_db_pw"
        exit 1
      fi
    if [ ! "$WEBWORK_DB_PW" ]
      then
        echo "ERROR: option --no-interactive requires setting both 
        --mysql_root_pw and --webwork_db_pw"
        exit 1
    fi
fi

if [ -z "$TMPDIR" ]; then
    if [ -d "/tmp" ]; then
        TMPDIR="/tmp"
    else
        TMPDIR="."
    fi
fi


cd $TMPDIR || exit 1

#stdbuf -i0 -o0 -e0 exec 1> >(tee -a webwork_install.log) 2> >(tee -a webwork_install.log >&2)

date
echo "
-----------------------------
This is the WeBWorK installer.  
-----------------------------

Please report problems to the issue tracker 
at

https://github.com/openwebwork/ww_install

When reporting problems, please include any 
relevant output from the webwork_install.log
"

sleep 2

echo "Working in $TMPDIR"

LOCALINSTALLER="ww_install.tar.gz"

echo
if type curl >/dev/null 2>&1; then
  WWINSTALLDOWNLOAD="curl -k -f -sS -Lo $LOCALINSTALLER $WWINSTALLURL"
elif type fetch >/dev/null 2>&1; then
  WWINSTALLDOWNLOAD="fetch -o $LOCALINSTALLER $WWINSTALLURL"
elif type wget >/dev/null 2>&1; then
  WWINSTALLDOWNLOAD="wget --no-check-certificate -O $LOCALINSTALLER $WWINSTALLURL"
else
  echo "Need wget or curl to use $0"
  exit 1
fi

clean_exit () {
  echo "Cleaning up..."
  [ -f $LOCALINSTALLER ] && rm $LOCALINSTALLER
  [ -d $TMPDIR/ww_install-$BRANCH/ ] && rm -rf $TMPDIR/ww_install-$BRANCH/
  exit $1
}

echo "## Installing cpan, and friends just to be sure."  
if [ -e "/etc/redhat-release" ]
then 
    yum -y install perl-CPAN perl-IPC-Cmd
elif [ -e "/etc/debian_version" ]
then 
    apt-get --yes --allow-unauthenticated install perl-modules
fi    

echo "## Download the latest webwork installer"
$WWINSTALLDOWNLOAD 

echo "## Extracting the installer"
tar -xzf $LOCALINSTALLER
rm $LOCALINSTALLER
cd ww_install-$BRANCH/
#mv $TMPDIR/webwork_install.log .

perl ./bin/ww_install.pl $VERBOSE $INTERACTIVE $MYSQL_ROOT_PW $WEBWORK_DB_PW $PREREQUISITES
wait

if [ -f "launch_browser.sh" ]; then
  echo "Running launch_browser.sh"
  bash launch_browser.sh 
fi

move_install_log () {
if [ -d "$WEBWORK_ROOT" ]; then
    mv $TMPDIR/webwork_install.log $WEBWORK_ROOT/logs
    echo "webwork_install.log can be found in $WEBWORK_ROOT/logs"
elif [ -d "$HOME" ]; then
    cp  $TMPDIR/webwork_install.log $HOME
    echo "webwork_install.log can be found in $HOME"
else
    echo "webwork_install.log can be found in $TMPDIR"
fi
}

echo
echo "## Done."
move_install_log
clean_exit 1
