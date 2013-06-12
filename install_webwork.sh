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
  WWINSTALLDOWNLOAD="wget --no-check-certificate -nv -O $LOCALINSTALLER $WWINSTALLURL"
else
  echo "Need wget or curl to use $0"
  exit 1
fi

clean_exit () {
  [ -f $LOCALINSTALLER ] && rm $LOCALINSTALLER
  [ -d $TMPDIR/ww_install-master/ ] && rm -rf $TMPDIR/ww_install-master/ 
  exit $1
}

echo "## Download the latest webwork installer"
$WWINSTALLDOWNLOAD || clean_exit 1

echo "## Unzipping the installer"
unzip -f $LOCALINSTALLER
rm $LOCALINSTALLER
cd ww_install-master/

echo "## Now we're going to install the prerequisites"
./install_prerequisites.sh || clean_exit 1

echo "## OK, handing you to the webwork installation script."
sudo perl ww_install.pl

#echo
#echo "## Installing webwork"
#chmod +x $LOCALINSTALLER
#./$LOCALINSTALLER self-install || clean_exit 1

echo
echo "## Done." 
clean_exit 1
#rm ./$LOCALINSTALLER
