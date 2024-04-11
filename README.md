**WARNING: The lustre-utils.sh script in this repository creates and REMOVES filesystems, partitions, logical volumes and volume groups with confirmation prompts disabled (e.g. -y option in lvremove). The programs are created to be used to evaluate Lustre, not to be used for production.**

# lustre-utils.sh

The script is written and tested on RHEL 8.9 with Lustre 2.15.4.

The basic idea is to create everything necessary for running a Lustre server on a single computer. A free block device is required. The Lustre targets (MGT, MDTs, OSTs) will all be mounted to directories under `/lustre`. Since a single computer is assumed, `--mgsnode` option for `mkfs.lustre` is taken from `hostname`.

The following steps are typically required to create a working Lustre filesystem. The block device/physical disk, volume and filesystem names are given as example. 

- Create a volume group:

```
$ sudo ./lustre_utils.sh create_vg lustre /dev/sdb
  Volume group "lustre" successfully created
INFO: lustre created on /dev/sdb
```

- Create a Lustre MGT, MGT is given a default size of 1GB

```
$ sudo ./lustre-util.sh create_mgt
INFO: creating logical volume: mgt
  Wiping ext4 signature on /dev/lustre/mgt.
  Logical volume "mgt" created.
INFO: creating MGT fs: mgt

   Permanent disk data:
Target:     MGS
Index:      unassigned
Lustre FS:  
Mount type: ldiskfs
Flags:      0x64
              (MGS first_time update )
Persistent mount opts: user_xattr,errors=remount-ro
Parameters:

device size = 1024MB
formatting backing filesystem ldiskfs on /dev/lustre/mgt
	target name   MGS
	kilobytes     1048576
	options        -q -O uninit_bg,dir_nlink,quota,project,huge_file,^fast_commit,flex_bg -E lazy_journal_init="0",lazy_itable_init="0" -F
mkfs_cmd = mke2fs -j -b 4096 -L MGS  -q -O uninit_bg,dir_nlink,quota,project,huge_file,^fast_commit,flex_bg -E lazy_journal_init="0",lazy_itable_init="0" -F /dev/lustre/mgt 1048576k
Writing CONFIGS/mountdata
lrwxrwxrwx 1 root root 7 11. Apr 11:49 /dev/lustre/mgt -> ../dm-3
INFO: MGT0 (1G) created
```

- Create a Lustre Filesystem (MDTs and ODTs) called `users` with 1x 1GB MDT and 4x 2GB ODT:

```
$ sudo ./lustre_utils.sh ./create_fs users 1 1 2 4
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

- Check status:

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

- Start Lustre MGS:

```
$ sudo ./lustre_utils.sh start_mgs
INFO: MGS started
```

- Start the Lustre filesystem (MDS and OSS) `users`:

```
$ sudo ./lustre_utils.sh start_fs users
INFO: users MDS and OSS started
```

At this point, Lustre is working with `users` filesystem. It can be mounted by the clients at `hostname:/users`.

It is possible to create other filesystems (with create_fs). There is only one MGT/MGS required.

In order to stop:

- Stop the Lustre filesystem (MDS and OSS) `users` (be patient, this might take some seconds or more):

```
$ sudo ./lustre_utils.sh stop_fs users
INFO: users MDS and OSS stopped. MGS can be stopped with stop_mgs command.
```

- If there is no other filesystem running, and if you want, stop Lustre MGS (be patient, this might take some seconds or more):

```
$ sudo ./lustre_utils.sh stop_mgs
INFO: MGS stopped
```
