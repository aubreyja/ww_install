#!/bin/bash

BRANCH=master
WWINSTALLURL=https://github.com/aubreyja/ww_install/archive/$BRANCH.zip

if [ -z "$TMPDIR" ]; then
    if [ -d "/tmp" ]; then
        TMPDIR="/tmp"
    else
        TMPDIR="."
    fi
fi


cd $TMPDIR || exit 1

exec 1> >(tee -a webwork_install.log) 2> >(tee -a webwork_install.log >&2)

date
echo "
-----------------------------
This is the WeBWorK installer.  
-----------------------------

Please report problems to the issue tracker 
at

https://github.com/aubreyja/ww_install

When reporting problems, please include any 
relevant output from the webwork_install.log
"

sleep 2

echo "Working in $TMPDIR"

LOCALINSTALLER="ww_install.zip"

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
  [ -f $LOCALINSTALLER ] && rm $LOCALINSTALLER
  [ -d $TMPDIR/ww_install-$BRANCH/ ] && rm -rf $TMPDIR/ww_install-$BRANCH/ 
  echo "Cleaning up...."
  exit $1
}

echo "## Download the latest webwork installer"
$WWINSTALLDOWNLOAD 

echo "## Unzipping the installer"
unzip $LOCALINSTALLER
rm $LOCALINSTALLER
cd ww_install-$BRANCH/
mv $TMPDIR/webwork_install.log .

echo "Installing prerequisites..."
source install_prerequisites.sh 
wait
sudo perl ww_install.pl
wait

if [ -f "launch_browser.sh" ]; then
  echo "Running launch_browser.sh"
  source launch_browser.sh 
fi

move_install_log () {
if [ -d "$WEBWORK_ROOT" ]; then
    sudo mv webwork_install.log $WEBWORK_ROOT/logs
    echo "webwork_install.log can be found in $WEBWORK_ROOT/logs"
elif [ -d "$HOME" ]; then
    cp webwork_install.log $HOME
    echo "webwork_install.log can be found in $HOME"
else
    sudo mv webwork_install.log $TMPDIR
    echo "webwork_install.log can be found in $TMPDIR"
fi
}

echo
echo "## Done."
move_install_log
clean_exit 1
