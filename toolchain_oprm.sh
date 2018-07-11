#!/bin/bash
# toolchain_pt.sh
# (c) Markus Weber, 2017-02-23 02:50, License: AGPLv3
# with minor changes by Alexander Rapp
#
# This script cares about creating an overlay map.
# It loads and updates the map data and renders the tiles.
# The script will run endless in a loop.
# Start it with "nohup ./toolchain_oprm.sh &"
# To terminate it, delete the file "toolchain_oprm_running.txt".

OPRMROOT=/oprm2

PLANETURL=https://planet.openstreetmap.org/pbf/planet-latest.osm.pbf
PLANETMINSIZE=10000000000  # minimum size of OSM data file in .o5m format
BORDERS=
#
MAXPROCESS=2  # maximum number of concurrent processes for rendering
MAXMERGE=5  # number of files to be merged in parallel by osmupdate
OSM2PGSQLPARAM="-s -C 1500 -d ptgis -U ptuser -S ${OPRMROOT}/toolchain/osm2pgsql_oprm.style"
  # main parameters to be passed to osm2pgsql

# enter working directory and do some initializations
cd ${OPRMROOT}/data
echo >>${OPRMROOT}/log/tc.log
echo $(date)"  toolchain started." >>${OPRMROOT}/log/tc.log
PROCN=1000  # rendering-process number (range 1000..1999)
mkdir d_t 2>/dev/null

# publish that this script is now running
rm ${OPRMROOT}/log/toolchain_oprm_ended.txt 2>/dev/null
echo -e "The toolchain script has been started at "$(date)"\n"\
"and is currently running. To terminate it, delete this file and\n"\
"wait until the file \"toolchain_oprm_ended.txt\" has been created.\n"\
"This may take some minutes." \
>${OPRMROOT}/log/toolchain_oprm_running.txt

# clean up previous Mapnik processes
killall "mapnik_oprm.py" 2>/dev/null
while [ $(ls d_t/at* 2>/dev/null |wc -l) -gt 0 ]; do
    # there is at least one incompleted rendering process
  AT=$(ls -1 d_t/at* 2>/dev/null|head -1)  # tile list
  echo $(date)"  Cleaning up incomplete rendering: "$AT >>${OPRMROOT}/log/tc.log
  DT=${AT:0:4}d${AT:5:99}  # new name of the tile list
  mv $AT $DT  # rename this tile list file;
    # now the tile is is marked as 'to be rendered'
  done

# download and process planet file - if necessary
if [ "0"$(stat --print %s a.o5m 2>/dev/null) -lt $PLANETMINSIZE ]; then
  echo $(date)"  Missing file a.o5m, downloading it." >>${OPRMROOT}/log/tc.log
  rm -f fa.o5m
  wget -nv $PLANETURL -O - 2>>${OPRMROOT}/log/tc.log |osmconvert - \
    $BORDERS --drop-author -o=a.o5m 2>>${OPRMROOT}/log/tc.log
  echo $(date)"  Updating the downloaded planet file." >>${OPRMROOT}/log/tc.log
  rm -f b.o5m
  osmupdate -v a.o5m b.o5m --day --hour \
    --max-merge=$MAXMERGE $BORDERS --drop-author >>${OPRMROOT}/log/tc.log 2>&1
  if [ "0"$(stat --print %s b.o5m 2>/dev/null) -gt $PLANETMINSIZE ]; then
    echo $(date)"  Update was successful." >>${OPRMROOT}/log/tc.log
  else
    echo $(date)"  No update available. Dropping meta data." >>${OPRMROOT}/log/tc.log
    osmconvert -v a.o5m b.o5m --drop-author >>${OPRMROOT}/log/tc.log 2>&1
    fi
  mv -f b.o5m a.o5m
  if [ "0"$(stat --print %s a.o5m 2>/dev/null) -lt $PLANETMINSIZE ]; then
    echo $(date)"  toolchain Error: could not download"\
      $PLANETURL >>${OPRMROOT}/log/tc.log
    exit 1
    fi
  fi

# refill the database - if necessary
if [ "0"$(stat --print %s fa.o5m 2>/dev/null) -lt 5 ]; then
  echo $(date)"  Missing file fa.o5m, creating it." >>${OPRMROOT}/log/tc.log
  rm dirty_tiles d_t/* 2>/dev/null
  echo $(date)"  Filtering the downloaded planet file." >>${OPRMROOT}/log/tc.log
  osmfilter a.o5m --parameter-file=${OPRMROOT}/toolchain/toolchain_oprm.filter \
    -o=fa.o5m 2>>${OPRMROOT}/log/tc.log  # filter the planet file
  osmconvert fa.o5m -o=gis.o5m 2>>${OPRMROOT}/log/tc.log
    # convert to .o5m format
  echo $(date)"  Writing filtered data into the database." >>${OPRMROOT}/log/tc.log
  rm dirty_tiles 2>/dev/null
  osm2pgsql $OSM2PGSQLPARAM -c gis.o5m -e 0-14 -o dirty_tiles >/dev/null 2>&1
    # enter filtered planet data into the database
  echo $(date)"  All tiles need to be rerendered." >>${OPRMROOT}/log/tc.log
  echo $(date)"  If the tile directory is not empty, please remove" >>${OPRMROOT}/log/tc.log
  echo $(date)"  all outdated tile files." >>${OPRMROOT}/log/tc.log
  fi

# main loop
while [ -e "${OPRMROOT}/log/toolchain_oprm_running.txt" ]; do
  echo $(date)"  Processing main loop." >>${OPRMROOT}/log/tc.log

  # limit log file size
  if [ "0"$(stat --print %s ${OPRMROOT}/log/tc.log 2>/dev/null) -gt 6000000 ]; then
    echo $(date)"  Reducing logfile size." >>${OPRMROOT}/log/tc.log
    mv ${OPRMROOT}/log/tc.log ${OPRMROOT}/log/tc.log_temp
    tail -c +4000000 ${OPRMROOT}/log/tc.log_temp |tail -n +2 >${OPRMROOT}/log/tc.log
    rm ${OPRMROOT}/log/tc.log_temp 2>/dev/null
    fi

  #care about entries in dirty-tile list
  while [ $(ls dirty_tiles d_t/?t* 2>/dev/null |wc -l) -gt 0 -a \
      -e "${OPRMROOT}/log/toolchain_oprm_running.txt" ]; do
      # while still tiles to render

    # start as much rendering processes as allowed
    while [ $(ls d_t/dt* 2>/dev/null |wc -l) -gt 0 -a \
        $(ls -1 d_t/at* 2>/dev/null |wc -l) -lt $MAXPROCESS ]; do
        # while dirty tiles in list AND process slot(s) available
      DT=$(ls -1 d_t/dt* |head -1)  # tile list
      AT=${DT:0:4}a${DT:5:99}  # new name of the tile list
      touch -c $DT  # remember rendering start time
      mv $DT $AT  # rename this tile list file;
        # this is our way to mark a tile list as 'being rendered now'
      #echo $(date)"  Rendering "$DT >>${OPRMROOT}/log/tc.log
      PROCN=$(($PROCN + 1))
      if [ $PROCN -gt 1999 ]; then
        PROCN=1000;  # (force range to 1000..1999)
        fi
      N=${PROCN:1:99}  # get last 3 digits
      DTF=$AT PID=$N nohup ${OPRMROOT}/toolchain/mapnik_oprm.py >/dev/null 2>&1 &
        # render every tile in list
      echo $(date)"  Now rendering:"\
        $(ls -m d_t/at* 2>/dev/null|tr -d "d_t/a ") \
        >>${OPRMROOT}/log/tc.log
      sleep 2  # wait a bit
      tail -30 ${OPRMROOT}/log/tc.log >${OPRMROOT}/status1
      done

    # determine if we have rendered all tiles of all lists
    if (ls d_t/?t* >/dev/null 2>&1); then  # still tiles to render
      sleep 11  # wait some seconds
  continue  # care about rendering again
      fi
    # here: we have rendered all tiles of all lists

    # care about dirty-tiles master list and split it into parts
    if (ls dirty_tiles >/dev/null 2>&1); then
        # there is a dirty-tiles master list
      echo $(date)"  Expanding \"dirty_tiles\" file." >>${OPRMROOT}/log/tc.log
      ${OPRMROOT}/toolchain/dtexpand 0 14 <dirty_tiles >dirty_tiles_ex 2>/dev/null
      mv -f dirty_tiles_ex dirty_tiles 2>/dev/null
      echo $(date)"  Splitting dirty-tiles list" \
        "("$(cat dirty_tiles |wc -l)" tiles)" >>${OPRMROOT}/log/tc.log
      grep --color=never -e "tiles)" -e "newest hourly timestamp" ${OPRMROOT}/log/tc.log >${OPRMROOT}/status
      split -l 1000 -d -a 6 dirty_tiles d_t/dt
      echo "*** "$(date) >>dt.log
      cat dirty_tiles >>dt.log  # add list to dirty-tiles log
      rm dirty_tiles 2>/dev/null
      # limit dirty-tiles log file size
      if [ "0"$(stat --print %s dt.log 2>/dev/null) -gt 750000000 ]; then
        echo $(date)"  Reducing dirty-tiles logfile size." >>${OPRMROOT}/log/tc.log
        mv dt.log dt.log_temp
        tail -c +500000000 dt.log_temp |tail -n +2 >dt.log
        rm dt.log_temp 2>/dev/null
        fi
      fi

    done  # while still tiles to render
  if [ ! -e "${OPRMROOT}/log/toolchain_oprm_running.txt" ]; then  # script shall be terminated
continue;  # exit the main loop via while statement
    fi
  # here: all tiles have been rendered

  # update the local planet file
  echo $(date)"  Updating the local planet file." >>${OPRMROOT}/log/tc.log
  rm b.o5m fb.o5m a_old.o5m fa_old.o5m 2>/dev/null
  # for maintenance only:
  #echo $(date)"---> Waiting 24 hours." >>${OPRMROOT}/log/tc.log
  #sleep 86400
  #echo $(date)"---> Resuming work after wait." >>${OPRMROOT}/log/tc.log
  osmupdate -v a.o5m b.o5m --day --hour \
    --max-merge=$MAXMERGE $BORDERS --drop-author >>${OPRMROOT}/log/tc.log 2>&1

  if [ "0"$(stat --print %s b.o5m 2>/dev/null) -lt \
      $(expr "0"$(stat --print %s a.o5m 2>/dev/null) \* 9 / 10) ]; then
      # if new osm file smaller than 90% of the old file's length
    # wait a certain time and retry the update
    I=0
    while [ $I -lt 33 -a -e "${OPRMROOT}/log/toolchain_oprm_running.txt" ]; do  # (33 min)
      sleep 60
      I=$(( $I + 1 ))
      done
continue
    fi

  # filter the new planet file
  echo $(date)"  Filtering the new planet file." >>${OPRMROOT}/log/tc.log
  osmfilter b.o5m --parameter-file=${OPRMROOT}/toolchain/toolchain_oprm.filter -o=fb.o5m \
    2>>${OPRMROOT}/log/tc.log

  # calculate difference between old and new filtered file
  echo $(date)"  Calculating diffs between old and new filtered file."\
    >>${OPRMROOT}/log/tc.log
  osmconvert fa.o5m fb.o5m --diff-contents --fake-lonlat \
    --out-osc|gzip -1 >gis.osc.gz 2>>${OPRMROOT}/log/tc.log

  # check if the diff file is too small
  if [ "0"$(stat --print %s gis.osc.gz 2>/dev/null) -lt 10 ]; then
    echo $(date)"  Error: diff file is too small." >>${OPRMROOT}/log/tc.log
    exit 2
    fi

  # enter differences into the database
  echo $(date)"  Writing differential data into the database." >>${OPRMROOT}/log/tc.log
  osm2pgsql $OSM2PGSQLPARAM -a gis.osc.gz -e 0-14 >/dev/null 2>&1

  # replace old files by the new ones
  echo $(date)"  Replacing old files by the new ones." >>${OPRMROOT}/log/tc.log
  ls -lL a.o5m fa.o5m b.o5m fb.o5m gis.o5m gis.osc.gz >>${OPRMROOT}/log/tc.log
  mv -f a.o5m a_old.o5m
  mv -f fa.o5m fa_old.o5m
  mv -f b.o5m a.o5m
  mv -f fb.o5m fa.o5m

  # check if there are any tiles affected by this update
  if [ "0"$(stat --print %s dirty_tiles 2>/dev/null) -lt 5 ]; then
    echo $(date)"  There are no tiles affected by this update." >>${OPRMROOT}/log/tc.log
    rm -f dirty_tiles
    fi

  # wait a certain time to give other maps a chance for rendering
  I=0
  while [ $I -lt 30 -a -e "${OPRMROOT}/log/toolchain_oprm_running.txt" ]; do  # (30 min)
    sleep 60
    I=$(( $I + 1 ))
    done

  done  # main loop

# wait until every rendering process has terminated
while (ls d_t/at* 2>/dev/null) ; do sleep 30; done

# publish that this script has ended
rm ${OPRMROOT}/log/toolchain_oprm_running.txt 2>/dev/null
echo "The toolchain script ended at "$(date)"." \
  >${OPRMROOT}/log/toolchain_oprm_ended.txt
