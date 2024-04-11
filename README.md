**WARNING: The lustre-utils.sh script in this repository creates and REMOVES filesystems, partitions, logical volumes and volume groups with confirmation prompts disabled (e.g. -y option in lvremove). The programs are created to be used to evaluate Lustre, not to be used in production.**

# lustre-utils.sh

The script is written and tested on RHEL 8.9 with Lustre 2.15.4.

The basic idea is to create everything necessary for running a Lustre server on a single computer. A free block device is required. The Lustre targets (MGT, MDTs, OSTs) will all be mounted to directories under `/lustre`. Since a single computer is assumed, `--mgsnode` option for `mkfs.lustre` is taken from `hostname`.

The outputs of the actual tools are not suppressed. Particularly when creating MGT, MDT and OST, mkfs.lustre output can be observed.

## Create the volume group

- Create a volume group:

```
$ sudo ./lustre-utils.sh create_vg lustre /dev/sdb
  Volume group "lustre" successfully created
INFO: lustre created on /dev/sdb
```

The name of the volume group is stored in `/lustre/.vg` file. This file is read in all other commands to know volume group name (and because of this there is no need to provide volume group name to any other command).

The physical volume (PV) is not explicitly created (with `pvcreate /dev/sdb` above). `vgcreate` called by `lustre-utils.sh` automatically creates the PV if there is none.

## Creating a Lustre filesystem

- Create a Lustre MGT, MGT is given a default size of 1GB

```
$ sudo ./lustre-utils.sh create_mgt
INFO: creating logical volume: mgt
  Wiping ext4 signature on /dev/lustre/mgt.
  Logical volume "mgt" created.
INFO: creating MGT fs: mgt
...
some more output
...
lrwxrwxrwx 1 root root 7 11. Apr 11:49 /dev/lustre/mgt -> ../dm-3
INFO: MGT0 (1G) created
```

This creates both `/dev/lustre/mgt` and `/lustre/mgt`.

- Create a Lustre Filesystem (MDTs and ODTs) called `users` with 1x 1GB MDT and 4x 2GB ODT:

```
$ sudo ./lustre-utils.sh ./create_fs users 1 1 2 4
...
lots of output
...
lrwxrwxrwx 1 root root 7 11. Apr 11:52 /dev/lustre/users_mdt0 -> ../dm-4
lrwxrwxrwx 1 root root 7 11. Apr 11:52 /dev/lustre/users_ost0 -> ../dm-5
lrwxrwxrwx 1 root root 7 11. Apr 11:52 /dev/lustre/users_ost1 -> ../dm-6
lrwxrwxrwx 1 root root 7 11. Apr 11:52 /dev/lustre/users_ost2 -> ../dm-7
lrwxrwxrwx 1 root root 7 11. Apr 11:52 /dev/lustre/users_ost3 -> ../dm-8
INFO: filesystem created: users
```

This creates the logical volumes listed above (`/dev/VGNAME/FSNAME_MDT<NUM>` and `/dev/VGNAME/FSNAME_OST<NUM)`) and also the corresponding folders under `/lustre/users` (`/lustre/<FSNAME>/<MDT<NUM>` and `/lustre/<FSNAME>/<OST<NUM>`).

- Status can be checked anytime:

```
$ sudo ./lustre-utils.sh status
VG name is lustre
MGT is OK, MGS is NOT running
filesystem: users
  mdt0 is OK, MDS is NOT running
  ost0 is OK, OSS is NOT running
  ost1 is OK, OSS is NOT running
  ost2 is OK, OSS is NOT running
  ost3 is OK, OSS is NOT running
```

## Starting the Lustre filesystem

- Start Lustre MGS:

```
$ sudo ./lustre-utils.sh start_mgs
INFO: MGS started
```

Starting MGS means mounting `/dev/lustre/mgt` to `/lustre/mgt`.

- Start the Lustre filesystem (MDS and OSS) `users`:

```
$ sudo ./lustre-utils.sh start_fs users
INFO: users MDS and OSS started
```

Starting filesystem (starting MDS and OSS) means mounting `/dev/lustre/users_mdt*` to `/lustre/users/mdt*` and `/dev/lustre/users_ost*` to `/lustre/users/ost*`.

At this point, Lustre is working with `users` filesystem. It can be mounted by the clients at `hostname:/users`.

It is possible to create other filesystems (with create_fs). There is only one MGT/MGS required.

### Stopping the Lustre filesystem

- Stop the Lustre filesystem (MDS and OSS) `users` (be patient, this might take some seconds or more):

```
$ sudo ./lustre-utils.sh stop_fs users
INFO: users MDS and OSS stopped. MGS can be stopped with stop_mgs command.
```

This unmounts mdt and ost mount points.

- If there is no other filesystem running, and if you want, stop Lustre MGS (be patient, this might take some seconds or more):

```
$ sudo ./lustre-utils.sh stop_mgs
INFO: MGS stopped
```

This unmount the mgt (`/lustre/mgt`) mount point.

### Removing the Lustre filesystem

- Remove the Lustre filesystem:

```
 $ sudo ./lustre-utils.sh remove_fs users
  Logical volume "users_mdt0" successfully removed.
  Logical volume "users_ost0" successfully removed.
  Logical volume "users_ost1" successfully removed.
  Logical volume "users_ost2" successfully removed.
  Logical volume "users_ost3" successfully removed.
INFO: filesystem removed (or did not exist): users
```

- Remove the Lustre MGT:

```
 $ sudo ./lustre-utils.sh remove_mgt
  Logical volume "mgt" successfully removed.
```

### Removing the volume group

- Remove the volume group:

```
sudo ./lustre-utils.sh remove_vg
ls: cannot access '/dev/lustre/*': No such file or directory
  Volume group "lustre" successfully removed
INFO: lustre removed
```

The physical volume (PV) is not explicitly deleted. If required, it can be deleted with `pvremove <DEVICE>`.
