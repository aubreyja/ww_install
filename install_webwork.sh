#!/bin/sh

WWINSTALLURL=https://github.com/aubreyja/ww_install/archive/master.zip

if [ -z "$TMPDIR" ]; then
    if [ -d "/tmp" ]; then
        TMPDIR="/tmp"
    else
        TMPDIR="."
    fi
fi

echo "Working in $TMPDIR"
cd $TMPDIR || exit 1

LOCALINSTALLER="ww_install-$$.zip"

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
  [ -d $TMPDIR/ww_install-master/ ] && rm -rf $TMPDIR/ww_install-master/ 
  echo "Cleaning up...."
  exit $1
}

echo "## Download the latest webwork installer"
$WWINSTALLDOWNLOAD 

echo "## Unzipping the installer"
unzip $LOCALINSTALLER
rm $LOCALINSTALLER
cd ww_install-master/

source install_prerequisites.sh 
wait
sudo perl ww_install.pl
wait

if [ -f "launch_browser.sh" ]; then
  source launch_browser.sh
fi

echo
echo "## Done." 
clean_exit 1
