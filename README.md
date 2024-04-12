**WARNING: The lustre-utils.sh script in this repository creates and REMOVES filesystems, partitions, pools, logical volumes and volume groups with confirmation prompts DISABLED (e.g. -y option in lvremove). The script is created to make a quick Lustre setup, not to be used in production.**

# lustre-utils.sh

Configuring Lustre requires one to run a number of commands. The `lustre-utils.sh` script simplifies to create everything necessary for running a Lustre server on a single computer. 

To use this script, a free block device is required and a physical volume (PV) and a volume group (VG) will be created on this device. The Lustre targets (MGT, MDTs, OSTs) will all be mounted to directories under `/lustre`. Since a single computer is assumed, `--mgsnode` option for `mkfs.lustre` is taken from `hostname` output.

A few helper files are created under `/lustre`:

- `/lustre/.vg` holds the volume group name
- `/lustre/.osd.mgt` holds the backend type (zfs or ldiskfs) of MGT
- `/lustre/<FS>/.osd.mdt` holds the backend type (zfs or ldiskfs) of MDTs
- `/lustre/<FS>/.osd.ost` holds the backend type (zfs or ldiskfs) of OSTs

It is possible to use different backends for MGT, MDTs and OSTs. However, all MDTs and all OSTs should have the same backend.

When ZFS backend is used, a different pool for each target is created. The pool has the same name as the logical volume. The dataset on the pool is always called `lustre`.

The script is written and tested on RHEL 8.9 with Lustre 2.15.4. It is tested with ZFS (dkms) and LDISKFS (kmod) backends.

The outputs of the actual tools are not suppressed. Particularly when creating MGT, MDT and OST, mkfs.lustre output can be observed.

## Create the volume group

- Create a volume group:

```
$ sudo ./lustre-utils.sh create_vg lustre /dev/sdb
  Volume group "lustre" successfully created
INFO: lustre created on /dev/sdb
```

Since the name of the volume group is stored in `/lustre/.vg` file, there is no need to provide volume group name to any other command.

The physical volume (PV) is not explicitly created (with `pvcreate /dev/sdb` above). `vgcreate` called by `lustre-utils.sh` automatically creates the PV if there is none.

## Creating a Lustre filesystem

- Create a Lustre MGT, MGT is given a default size of 1GB

```
$ sudo ./lustre-utils.sh create_mgt zfs
...
some output
...
lrwxrwxrwx 1 root root 7 11. Apr 11:49 /dev/lustre/mgt -> ../dm-2
INFO: MGT0 (1G) created
```

This creates both `/dev/VGNAME/mgt` and `/lustre/mgt`. When ZFS backend is used, a pool named `zfs` and a dataset named `zfs/lustre` is created.

```
$ zfs list
NAME         USED  AVAIL     REFER  MOUNTPOINT
mgt          660K   831M       96K  /mgt
mgt/lustre    96K   831M       96K  /mgt/lustre
```

- Create a Lustre Filesystem (MDTs and ODTs) called `users` with 1x 2GB MDT and 4x 16GB ODT, use ZFS for both:

```
$ sudo ./lustre-utils.sh create_fs users zfs 2 1 zfs 16 4
...
lots of output
...
lrwxrwxrwx 1 root root 7 Apr 12 08:36 /dev/lustre/users_mdt0 -> ../dm-3
lrwxrwxrwx 1 root root 7 Apr 12 08:36 /dev/lustre/users_ost0 -> ../dm-4
lrwxrwxrwx 1 root root 7 Apr 12 08:36 /dev/lustre/users_ost1 -> ../dm-5
lrwxrwxrwx 1 root root 7 Apr 12 08:36 /dev/lustre/users_ost2 -> ../dm-6
lrwxrwxrwx 1 root root 7 Apr 12 08:36 /dev/lustre/users_ost3 -> ../dm-7
INFO: filesystem created: users
```

This creates the logical volumes listed above (`/dev/VGNAME/FSNAME_MDT<NUM>` and `/dev/VGNAME/FSNAME_OST<NUM)`) and also the corresponding folders under `/lustre/users` (`/lustre/<FSNAME>/<MDT<NUM>` and `/lustre/<FSNAME>/<OST<NUM>`).

When ZFS backend is used, the pools and the datasets are also created:

```
$ zfs list
NAME                USED  AVAIL     REFER  MOUNTPOINT
mgt                 660K   831M       96K  /mgt
mgt/lustre           96K   831M       96K  /mgt/lustre
users_mdt0          660K  1.75G       96K  /users_mdt0
users_mdt0/lustre    96K  1.75G       96K  /users_mdt0/lustre
users_ost0          660K  15.0G       96K  /users_ost0
users_ost0/lustre    96K  15.0G       96K  /users_ost0/lustre
users_ost1          672K  15.0G       96K  /users_ost1
users_ost1/lustre    96K  15.0G       96K  /users_ost1/lustre
users_ost2          660K  15.0G       96K  /users_ost2
users_ost2/lustre    96K  15.0G       96K  /users_ost2/lustre
users_ost3          660K  15.0G       96K  /users_ost3
users_ost3/lustre    96K  15.0G       96K  /users_ost3/lustre
```

- Status can be checked anytime:

```
$ sudo ./lustre-utils.sh status
VG name is lustre
MGT (zfs) is OK, MGS is NOT running
filesystem: users
  mdt0 (zfs) is OK, MDS is NOT running
  ost0 (zfs) is OK, OSS is NOT running
  ost1 (zfs) is OK, OSS is NOT running
  ost2 (zfs) is OK, OSS is NOT running
  ost3 (zfs) is OK, OSS is NOT running
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

Starting filesystem (starting MDS and OSS) means mounting logical volumes in LDISKFS backend and mounting datasets in ZFS backend.

At this point, Lustre is working with `users` filesystem. It can be mounted by the clients at `hostname:/users`.

It is possible to create other filesystems (with create_fs). There is only one MGT/MGS required.

## Stopping the Lustre filesystem

- Stop the Lustre filesystem (MDS and OSS) `users` (be patient, this might take some seconds or more):

```
$ sudo ./lustre-utils.sh stop_fs users
INFO: users MDS and OSS stopped. MGS can be stopped with stop_mgs command.
```

This unmounts MDT and OST mount points.

- If there is no other filesystem running, and if you want, you can stop Lustre MGS (be patient, this might take some seconds or more):

```
$ sudo ./lustre-utils.sh stop_mgs
INFO: MGS stopped
```

This unmounts the MGT (`/lustre/mgt`) mount point.

## Removing the Lustre filesystem

- Remove the filesystem:

```
 $ sudo ./lustre-utils.sh remove_fs users
  Logical volume "users_mdt0" successfully removed.
  Logical volume "users_ost0" successfully removed.
  Logical volume "users_ost1" successfully removed.
  Logical volume "users_ost2" successfully removed.
  Logical volume "users_ost3" successfully removed.
INFO: filesystem removed: users
```

This removes the corresponding logical volumes of MDTs and OSTs under `/dev/VGNAME/`. In ZFS backend, it also destroys the pools.

- Remove the MGT:

```
 $ sudo ./lustre-utils.sh remove_mgt
  Logical volume "mgt" successfully removed.
```

This removes the `/dev/VGNAME/mgt` logical volume.

## Removing the volume group

- Remove the volume group:

```
$ sudo ./lustre-utils.sh remove_vg
  Volume group "lustre" successfully removed
INFO: lustre removed
```

The physical volume (PV) is not explicitly deleted. If required, it can be deleted with `pvremove <DEVICE>`.
