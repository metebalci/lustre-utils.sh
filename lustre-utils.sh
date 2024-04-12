#!/bin/bash
# lustre-utils.sh is a collection of helper utilities to try Lustre
# Copyright (C) 2024 Mete Balci

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

VG=
MGSNODE=`hostname`
LVCREATEOPTIONS="--yes --wipesignatures y --zero y"
DEBUG=0

function error
{
  echo "ERROR: $1"
  exit 1
}

function info 
{
  echo "INFO: $1"
}

function debug
{
  if [ $DEBUG -ne 0 ]
  then
    echo "DEBUG: $1"
  fi
}

function check_osd
{
  OSD=$1
  if [ $OSD != "zfs" ] && [ $OSD != "ldiskfs" ]
  then
    error "wrong OSD: $OSD"
  fi
}

function read_vg_name
{
  if [ -f /lustre/.vg ]
  then
    VG=`cat /lustre/.vg`
    debug "VG (.vg)=$VG"
  else
    error "no /lustre/.vg file, this might be due to a bug or if it is deleted manually"
  fi
}

function create_vg
{
  VG=$1
  DEVICE=$2
  debug "create_vg VG=$VG DEVICE=$DEVICE"

  if [ -f /lustre/.vg ] 
  then
    read_vg_name
    error "there is already a volume group "$VG" created with lustre-utils"
  fi

  vgdisplay $VG > /dev/null 2>&1

  if [ $? -eq 0 ]
  then
    error "there is already a volume group named $VG"
  fi

  if [ ! -b $DEVICE ]
  then
    error "there is no such block device $DEVICE"
  fi

  vgcreate $VG $DEVICE
  mkdir -p /lustre || true
  echo $VG > /lustre/.vg

  info "$VG created on $DEVICE"
}

function remove_vg
{
  read_vg_name
  vgdisplay $VG > /dev/null 2>&1

  if [ $? -ne 0 ]
  then
    rm -rf /lustre/.vg || true
    error "there is no volume group named $VG, /lustre/.vg removed"
  fi

  if [ `ls -l /dev/$VG | wc -l` -ne 0 ]
  then
    error "there are logical volumes on $VG, you should remove them first"
  fi

  vgremove $VG
  rm -rf /lustre || true

  info "$VG removed"
}

function create_lustre_mgt
{
  read_vg_name
  OSD=$1
  debug "create_lustre_mgt OSD=$OSD"
  check_osd $OSD

  DEV=/dev/$VG/mgt

  if [ -e $DEV ]
  then
    error "there is an existing mgt logical volume: $DEV, maybe run remove_lustre_mgt first ?"
  else
    info "creating logical volume: mgt"
    lvcreate $LVCREATEOPTIONS -L 1G -n mgt $VG
  fi
  info "creating MGT fs: mgt"
  if [ $OSD == "zfs" ]
  then
    mkfs.lustre --mgs --backfstype=zfs --reformat mgt/lustre $VG/mgt
  else
    mkfs.lustre --mgs --backfstype=ldiskfs --reformat $DEV
  fi
  mkdir -p /lustre/mgt || true
  if [ $OSD == "zfs" ]
  then
    echo "zfs" > /lustre/.osd.mgt
  else
    echo "ldiskfs" > /lustre/.osd.mgt
  fi
  ls -l /dev/$VG/mgt
  info "MGT0 (1G) created"
}

function remove_lustre_mgt
{
  read_vg_name

  mount | grep /lustre/mgt > /dev/null 2>&1

  if [ $? -eq 0 ]
  then
    error "MGS is running, maybe run stop_mgs ?"
  fi

  NR=`ls -l /lustre/* | wc -l`

  if [ $NR -gt 1 ]
  then
    error "/lustre is not empty, please remove filesystems first"
  fi

  OSD=`cat /lustre/.osd.mgt`
  if [ $OSD == "zfs" ]
  then
    zpool destroy mgt
  fi
  rm -rf /lustre/.osd.mgt || true

  DEV=/dev/$VG/mgt

  if [ -e $DEV ]
  then
    lvremove -y $DEV
  else
    info "there is no MGT logical volume: $DEV"
  fi

  rm -rf /lustre/mgt || true
}

function create_lustre_mdt_or_ost
{
  TYPE=$1
  FS=$2
  OSD=$3
  SIZE=$4
  NUM=$5
  debug "TYPE=$TYPE FS=$FS OSD=$OSD SIZE=$SIZE NUM=$NUM"
  check_osd $OSD
  SIZE="${SIZE}G"

  read_vg_name

  if [ "$TYPE" != "mdt" ] && [ "$TYPE" != "ost"]
  then
    error "wrong type $TYPE, this is a bug"
  fi

  # type in uppercase
  TYPEUS=${TYPE^^}
  debug "TYPEUS=$TYPEUS"

  for ((IDX=0; IDX<$NUM; IDX++))
  do
    DEV=/dev/$VG/${FS}_${TYPE}${IDX}
    if [ -e $DEV ]
    then
      error "the logical volume already exist: $DEV, maybe run remove_fs first ?"
    fi
  done

  for ((IDX=0; IDX<$NUM; IDX++))
  do

    DEV=/dev/$VG/${FS}_${TYPE}${IDX}
    DEVBN=$(basename $DEV)
    echo "creating $TYPEUS logical volume: $DEV"
    lvcreate $LVCREATEOPTIONS -L $SIZE -n $DEVBN $VG || error "cannot create the logical volume: $DEV"
    echo "creating $TYPEUS fs: $DEVBN"
    TYPEOPTION="--$TYPE"
    if [ $OSD == "zfs" ]
    then
      mkfs.lustre $TYPEOPTION --backfstype=zfs --reformat --fsname=$FS --index=$IDX --mgsnode=$MGSNODE ${FS}_${TYPE}${IDX}/lustre $VG/${FS}_${TYPE}${IDX} || error "cannot create $TYPEUS lustre fs on $DEV"
    else
      mkfs.lustre $TYPEOPTION --backfstype=ldiskfs --reformat --fsname=$FS --index=$IDX --mgsnode=$MGSNODE $DEV || error "cannot create $TYPEUS lustre fs on $DEV"
    fi
    mkdir -p /lustre/${FS}/${TYPE}${IDX} || true
    if [ $OSD == "zfs" ]
    then
      echo "zfs" > /lustre/${FS}/.osd.${TYPE}
    else
      echo "ldiskfs" > /lustre/${FS}/.osd.${TYPE}
    fi

    info "${TYPEUS}${IDX} ($SIZE) created"

  done
}

function create_lustre_fs
{
  FS=$1
  MDT_OSD=$2
  MDT_SIZE=$3
  MDT_NUM=$4
  OST_OSD=$5
  OST_SIZE=$6
  OST_NUM=$7
  debug "create_lustre_fs FS=$FS MDT_OSD=$MDT_OSD MDT_SIZE=$MDT_SIZE MDT_NUM=$MDT_NUM OST_OSD=$OST_OSD OST_SIZE=$OST_SIZE OST_NUM=$OST_NUM"
  check_osd $MDT_OSD
  check_osd $OST_OSD

  create_lustre_mdt_or_ost mdt $FS $MDT_OSD $MDT_SIZE $MDT_NUM
  create_lustre_mdt_or_ost ost $FS $OST_OSD $OST_SIZE $OST_NUM

  ls -l /dev/$VG/${FS}_mdt*
  ls -l /dev/$VG/${FS}_ost*

  info "filesystem created: $FS"
}

function remove_lustre_fs
{
  FS=$1
  debug "remove_lustre_fs FS=$FS"

  read_vg_name

  MDT_OSD=`cat /lustre/${FS}/.osd.mdt`
  if [ $MDT_OSD == "zfs" ]
  then
    for pool in `zpool list -H | cut -f1 | grep ${FS}_mdt`
    do
      zpool destroy $pool
    done
  fi
  rm -rf /lustre/${FS}/.osd.mdt || true

  OST_OSD=`cat /lustre/${FS}/.osd.ost`
  if [ $OST_OSD == "zfs" ]
  then
    for pool in `zpool list -H | cut -f1 | grep ${FS}_ost`
    do
      zpool destroy $pool
    done
  fi
  rm -rf /lustre/${FS}/.osd.ost || true

  shopt -s nullglob
  for dev in /dev/$VG/${FS}_*
  do
    lvremove -y $dev || error "cannot remove logical volume: $dev"
  done
  shopt -u nullglob
  rm -rf /lustre/$FS || true
  info "filesystem removed (or did not exist): $FS"
}

# https://wiki.lustre.org/Starting_and_Stopping_Lustre_Services
function start_lustre_mgs
{
  read_vg_name

  DEV=/dev/$VG/mgt

  mount | grep $DEV > /dev/null 2>&1

  if [ $? -eq 0 ]
  then
    error "MGS is already running"
  fi

  if [ ! -e $DEV ]
  then
    error "there is no MGT logical volume: $DEV"
  fi

  if [ ! -d /lustre/mgt ]
  then
    error "no /lustre/mgt directory, this is either due to a bug or if the directory is manually deleted"
  fi

  mount -t lustre $DEV /lustre/mgt

  info "MGS started"
}

function start_lustre_fs
{
  FS=$1
  debug "start_lustre_fs FS=$FS"

  read_vg_name

  mount | grep /lustre/mgt > /dev/null 2>&1

  if [ $? -ne 0 ]
  then
    error "first MGS should be started, maybe run start_mgs ?"
  fi

  for mdt in /lustre/$FS/mdt*
  do
    DEV=/dev/$VG/${FS}_$(basename $mdt)
    if [ ! -e $DEV ]
    then
      error "cannot find MDT logical volume: $DEV"
    fi
    mount -t lustre $DEV $mdt
  done

  for ost in /lustre/$FS/ost*
  do
    DEV=/dev/$VG/${FS}_$(basename $ost)
    if [ ! -e $DEV ]
    then
      error "cannot find OST logical volume: $DEV"
    fi
    mount -t lustre $DEV $ost
  done

  info "$FS MDS and OSS started"
}

# https://wiki.lustre.org/Starting_and_Stopping_Lustre_Services
function stop_lustre_mgs
{
  read_vg_name

  mount | grep /lustre/mgt > /dev/null 2>&1

  if [ $? -eq 0 ]
  then
    umount /lustre/mgt
  fi

  info "MGS stopped"
}

function stop_lustre_fs
{
  FS=$1
  debug "stop_lustre_fs FS=$FS"

  read_vg_name

  for mdt in /lustre/$FS/mdt*
  do

    mount | grep $mdt > /dev/null 2>&1

    if [ $? -eq 0 ]
    then
      umount $mdt
    fi

  done

  for ost in /lustre/$FS/ost*
  do

    mount | grep $ost > /dev/null 2>&1

    if [ $? -eq 0 ]; then
      umount $ost
    fi

  done

  info "$FS MDS and OSS stopped. MGS can be stopped with stop_mgs command."
}

function display_status
{
  if [ -d /lustre ]
  then
    if [ -f /lustre/.vg ]
    then

      read_vg_name
      echo "VG name is $VG"

      if [ -d /lustre/mgt ]
      then
        if [ -e /dev/$VG/mgt ]
        then
          MGT_OSD=`cat /lustre/.osd.mgt`
          echo -n "MGT ($MGT_OSD) is OK, "
          mount | grep /lustre/mgt > /dev/null 2>&1
          if [ $? -eq 0 ]
          then
            echo "MGS is running"
          else
            echo "MGS is NOT running"
          fi
        else
          echo "MGT is NOT OK"
        fi
      else
        echo "No MGS"
      fi

      shopt -s nullglob
      for dir in /lustre/*
      do
        FS=$(basename $dir)
        if [ "$FS" != "mgt" ]
        then
          echo "filesystem: $FS"
          for mdt in /lustre/${FS}/mdt*
          do
            DEV=/dev/$VG/${FS}_$(basename $mdt)
            if [ -e $DEV ] 
            then
              MDT_OSD=`cat /lustre/${FS}/.osd.mdt`
              echo -n "  $(basename $mdt) ($MDT_OSD) is OK, "
              mount | grep $mdt > /dev/null 2>&1
              if [ $? -eq 0 ]
              then
                echo "MDS is running"
              else
                echo "MDS is NOT running"
              fi
            else
              echo "  $(basename $mdt) is not OK, no logical volume"
            fi
          done
          for ost in /lustre/${FS}/ost*
          do
            DEV=/dev/$VG/${FS}_$(basename $ost)
            if [ -e $DEV ] 
            then
              OST_OSD=`cat /lustre/${FS}/.osd.ost`
              echo -n "  $(basename $ost) ($OST_OSD) is OK, "
              mount | grep $ost > /dev/null 2>&1
              if [ $? -eq 0 ]
              then
                echo "OSS is running"
              else
                echo "OSS is NOT running"
              fi
            else
              echo "  $(basename $ost) is not OK, no logical volume"
            fi
          done
        fi
      done
      shopt -u nullglob

    else
      echo "No VG"
    fi
  fi
}

function usage
{
  echo ""
  echo "lustre-utils.sh is a collection of Lustre ldiskfs/zfs utilities"
  echo ""
  echo "Usage: lustre-utils.sh COMMAND OPTIONS?"
  echo ""
  echo "Commands:"
  echo ""
  echo "  create_vg <VG> <DEVICE>: create volume group" 
  echo "  remove_vg: remove volume group"
  echo ""
  echo "  create_mgt <MGT_OSD>: create one 1G MGT"
  echo "  remove_mgt: remove the MGT"
  echo ""
  echo "  create_fs <FSNAME> <MDT_OSD> <MDT_SIZE_IN_GB> <MDT_NUM> <ODT_OSD> <ODT_SIZE_IN_GB> <ODT_NUM>: create MDTs and OSTs"
  echo "  remove_fs <FSNAME>: remove MDTs and OSTs"
  echo ""
  echo "  start_mgs:  start MGS"
  echo "  stop_mgs:   stop MGS"
  echo ""
  echo "  start_fs  <FSNAME>: start MDS then OSS"
  echo "  stop_fs   <FSNAME>: stop MDS then OSS"
  echo ""
  echo "  status: display current status"
  echo ""
  echo "  <_OSD> can be zfs or ldiskfs"
  echo "  <_NUM> should be >= 1"
  exit 1
}

if [ "$#" -eq 0 ]
then
  usage
fi

if [ "$EUID" -ne 0 ]
then
  echo "Please run lustre-utils.sh as root or sudo" 
  exit 1
fi

COMMAND=$1

debug "COMMAND=$COMMAND"

case "$COMMAND" in

  create_mgt)
    if [ "$#" -ne 2 ]
    then
      usage
    fi
    OSD=$2
    create_lustre_mgt $OSD
    ;;

  remove_mgt)
    remove_lustre_mgt
    ;;

  start_mgs)	
    start_lustre_mgs
    ;;

  stop_mgs)
    stop_lustre_mgs
    ;;

  create_fs)
    if [ "$#" -ne 8 ]
    then
      usage
    fi
    FS=$2
    MDT_OSD=$3
    MDT_SIZE=$4
    MDT_NUM=$5
    OST_OSD=$6
    OST_SIZE=$7
    OST_NUM=$8
    create_lustre_fs $FS $MDT_OSD $MDT_SIZE $MDT_NUM $OST_OSD $OST_SIZE $OST_NUM
    ;;

  remove_fs)
    if [ "$#" -ne 2 ]
    then
      usage
    fi
    FS=$2
    remove_lustre_fs $FS
    ;;

  start_fs)
    if [ "$#" -ne 2 ]
    then
      usage
    fi
    FS=$2
    start_lustre_fs $FS
    ;;

  stop_fs)
    if [ "$#" -ne 2 ]
    then
      usage
    fi
    FS=$2
    stop_lustre_fs $FS
    ;;

  create_vg)
    if [ "$#" -ne 3 ]
    then
      usage
    fi
    VG=$2
    DEVICE=$3
    create_vg $VG $DEVICE
    ;;

  remove_vg)
    remove_vg
    ;;

  status)
    display_status
    ;;

  *)
    usage
    ;;

esac

exit 0
