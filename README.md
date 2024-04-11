**WARNING: The lustre-utils.sh script in this repository creates and REMOVES filesystems, partitions, logical volumes and volume groups with confirmation prompts disabled (e.g. -y option in lvremove). The programs are created to be used to evaluate Lustre, not to be used for production.**

# lustre-utils.sh

The script is written and tested on RHEL 8.9 with Lustre 2.15.4.

The basic idea is to create everything necessary for running a Lustre server on a single computer. A free block device is required. The Lustre targets (MGT, MDTs, OSTs) will all be mounted to directories under `/lustre`.

The following steps are typically required. The block device/physical disk, volume and filesystem names are given as example. 

- Create a volume group:

`sudo ./lustre_utils.sh create_vg lustre /dev/sdb`

- Create a Lustre MGT, MGT is given a default size of 1GB

`sudo ./lustre_utils.sh ./create_mgt`

- Create a Lustre Filesystem (MDTs and ODTs) called `users` with 1x 1GB MDT and 4x 2GB ODT:

`sudo ./lustre_utils.sh ./create_fs users 1 1 2 4`

- Start Lustre MGS:

`sudo ./lustre_utils.sh start_mgs`

- Start Lustre Filesystem `users`:

`sudo ./lustre_utils.sh start_fs users`
