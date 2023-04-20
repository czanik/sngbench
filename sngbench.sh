#!/bin/bash

# seting up some initial variables
INPUTFILE=input.txt
SNG=/usr/sbin/syslog-ng
SNGCTL=/usr/sbin/syslog-ng-ctl
OUTDIR=out

# test if syslog-ng starts by printing version info
echo "Printing syslog-ng version info..."
if ! $SNG -V ; then 
  echo "Oops. \"$SNG\" does not exist or returned with a error. Exiting..."
  exit 1
fi

# exit if the directory already exists 
# so we can save results in a clean directory
# without accidentally overwriting something
if [ ! -d "$OUTDIR" ]; then
  echo "Directory \"$OUTDIR\" does not exist. Exiting..."
  exit 1
fi
# creating output directory
OUTDIR="$OUTDIR/`date +%y%m%d_%H%M%S`"
mkdir "$OUTDIR"

# save version info 
$SNG -V > $OUTDIR/syslog-ng.version

# collect some system info
uname -a > $OUTDIR/uname
for i in /etc/os-release /proc/cpuinfo; do
  if [ -f "$i" ]; then
    echo copy $i
    cp $i $OUTDIR
  fi
done

echo "Stopping syslog-ng"
$SNGCTL stop
echo "Waiting 2 seconds for things to settle"
sleep 2

# main cycle doing the actual benchmarking
while read -r LINE; do
  echo "The whole line: $LINE"
  SNGCONF=`echo $LINE | cut -d, -f1`
  echo "Syslog-ng conf name: $SNGCONF"
  echo "starting syslog-ng"
  $SNG --no-caps -f `pwd`/conf/$SNGCONF
  echo "Waiting 2 seconds for things to settle"
  sleep 2
  REST=`echo $LINE | cut -d, -f2-`
  for i in `seq 1 4` ; do
    LOGGENPAR=`echo $REST | cut -d, -f$i`
    if ! [ -z "$LOGGENPAR" ]; then
      echo "$i. loggen parameters: $LOGGENPAR"
      LOGNAME=$SNGCONF.`echo $LOGGENPAR | sed 's/ /_/g' | sed 's/-//g'| sed 's/=/_/g'`.$i.csv
      echo "LOGNAME = $LOGNAME"
      loggen $LOGGENPAR &> $OUTDIR/$LOGNAME &
    fi
  done
  echo "Wating for tests to run, about 15 seconds"
  sleep 15
  echo "Stopping syslog-ng"
  $SNGCTL stop
  echo "Waiting 2 seconds for things to settle"
  sleep 2
  echo "Stopping syslog-ng 2"
  $SNGCTL stop
  echo "Waiting 2 seconds for things to settle 2"
  sleep 2
  echo "Removing log files"
  rm /var/log/fromnet*
  sync
  echo " "
done < $INPUTFILE
