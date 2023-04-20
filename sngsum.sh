#!/bin/bash

if [ -z "$4" ] ; then
  echo "run from the directory containing results in its subdirectories"
  echo "$0 [results] [dir1] [dir2] [dir3]"
fi

if [ -f "$1" ] ; then
  echo "results file already exists, exiting"
  exit 1
fi

if [ -d "$2" ] ; then
  cd $2
  FILES=`echo *.csv`
  cd ..
else
  echo "1st directory does not exist, exiting"
  exit 1
fi

for i in `echo $FILES` ; do
  CONF=`echo $i | cut -d. -f 1`
  PARM=`echo $i | cut -d. -f 2-5`
  RUN=`echo $i | cut -d. -f 6`
  echo -n "$CONF,$PARM,$RUN," >> $1
  for j in $2 $3 $4 ; do
    echo -n "`cat $j/$i | tail -2 | head -1 | cut -d' ' -f 4`," >> $1
  done
  echo >> $1
done
