#!/bin/sh

PATH=/sbin:/bin:/usr/sbin:/usr/bin

ROOT_MOUNT="/rootfs"
MOUNT="/bin/mount"
UMOUNT="/bin/umount"

# Copied from initramfs-framework. The core of this script probably should be
# turned into initramfs-framework modules to reduce duplication.
udev_daemon() {
	OPTIONS="/sbin/udev/udevd /sbin/udevd /lib/udev/udevd /lib/systemd/systemd-udevd"

	for o in $OPTIONS; do
		if [ -x "$o" ]; then
			echo $o
			return 0
		fi
	done

	return 1
}

_UDEV_DAEMON=`udev_daemon`

early_setup() {
    mkdir -p /proc
    mkdir -p /sys
    mount -t proc proc /proc
    mount -t sysfs sysfs /sys
    mount -t devtmpfs none /dev

    # support modular kernel
#    modprobe isofs
#    modprobe raid0

    mkdir -p /run
    mkdir -p /var/run

    $_UDEV_DAEMON --daemon
    udevadm trigger --action=add

    if [ -x /sbin/mdadm ]; then
	/sbin/mdadm -v --assemble --scan --auto=md
    fi
}

read_args() {
    [ -z "$CMDLINE" ] && CMDLINE=`cat /proc/cmdline`
    for arg in $CMDLINE; do
        optarg=`expr "x$arg" : 'x[^=]*=\(.*\)'`
        case $arg in
            root=*)
                ROOT_DEVICE=$optarg ;;
            init=*)
                INIT=$optarg ;;
        esac
    done
}

fatal() {
    echo $1 >$CONSOLE
    echo >$CONSOLE
    exec sh
}



#######################################

early_setup

read_args

[ -z "$CONSOLE" ] && CONSOLE="/dev/console"
[ -z "$INIT" ] && INIT="/sbin/init"


udevadm settle --timeout=3 --quiet
killall "${_UDEV_DAEMON##*/}" 2>/dev/null

mkdir -p $ROOT_MOUNT/

if ! mount -o rw,noatime $ROOT_DEVICE $ROOT_MOUNT ; then
    fatal "Could not mount rootfs device \"$ROOT_DEVICE\"."
fi

# Move the mount points of some filesystems over to
# the corresponding directories under the real root filesystem.
for dir in `cat /proc/mounts | grep -v rootfs | awk '{print $2}'` ; do
    mkdir -p  ${ROOT_MOUNT}/${dir##*/}
    mount -n --move $dir ${ROOT_MOUNT}/${dir##*/}
done

cd $ROOT_MOUNT

# busybox switch_root supports -c option
exec switch_root -c /dev/console $ROOT_MOUNT $INIT $CMDLINE ||
    fatal "Couldn't switch_root, dropping to shell"
