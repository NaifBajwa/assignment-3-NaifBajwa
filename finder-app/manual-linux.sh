#!/bin/bash
# Script outline to install and build kernel.
# Author: Siddhant Jajoo.

set -e
set -u

OUTDIR=/tmp/aeld
KERNEL_REPO=git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git
KERNEL_VERSION=v5.15.163
BUSYBOX_VERSION=1_33_1
FINDER_APP_DIR=$(realpath $(dirname $0))
ARCH=arm64
CROSS_COMPILE=aarch64-none-linux-gnu-

if [ $# -lt 1 ]
then
	echo "Using default directory ${OUTDIR} for output"
else
	OUTDIR=$1
	echo "Using passed directory ${OUTDIR} for output"
fi

mkdir -p ${OUTDIR}

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/linux-stable" ]; then
    #Clone only if the repository does not exist.
	echo "CLONING GIT LINUX STABLE VERSION ${KERNEL_VERSION} IN ${OUTDIR}"
	git clone ${KERNEL_REPO} --depth 1 --single-branch --branch ${KERNEL_VERSION}
fi
if [ ! -e ${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image ]; then
    cd linux-stable
    echo "Checking out version ${KERNEL_VERSION}"
    git checkout ${KERNEL_VERSION}

    # kernel build steps start here
    # Remove previous kernel build output and configuration files. 
    # ARCH tells make that we are building for ARM64. 
    # CROSS_COMPILE tells make which compiler-tool prefix to use. 
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} mrproper 
    # Generate the default ARM64 kernel configuration file named .config. 
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} defconfig 
    # Build the Linux kernel and its required components. 
    # -j$(nproc) runs one parallel build job per available CPU core. 
    make -j$(nproc) ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} all 
    # Copy the generated uncompressed ARM64 kernel image into OUTDIR. 
    # QEMU will use this file when booting the virtual ARM64 system. 
    cp arch/${ARCH}/boot/Image ${OUTDIR}/Image
fi

echo "Adding the Image in outdir"

echo "Creating the staging directory for the root filesystem"
cd "$OUTDIR"
if [ -d "${OUTDIR}/rootfs" ]
then
	echo "Deleting rootfs directory at ${OUTDIR}/rootfs and starting over"
    sudo rm  -rf ${OUTDIR}/rootfs
fi

# Create necessary base directories
# Create the standard Linux root filesystem directories. 
# -p creates parent directories and does not fail if directories already exist. 
# 
# bin = essential user commands 
# dev = device files 
# etc = system configuration 
# home = user files and assignment applications 
# lib = essential shared libraries 
# lib64 = 64-bit shared libraries and dynamic loader 
# proc = mount point for the proc virtual filesystem 
# sbin = essential system administration commands 
# sys = mount point for the sysfs virtual filesystem 
# tmp = temporary files 
# usr/bin = additional user commands 
# usr/lib = additional shared libraries 
# usr/sbin = additional system administration commands 
# var/log = system log files 
mkdir -p ${OUTDIR}/rootfs/{bin,dev,etc,home,lib,lib64,proc,sbin,sys,tmp,usr/bin,usr/lib,usr/sbin,var/log}

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/busybox" ]
then
git clone git://busybox.net/busybox.git
    cd busybox
    git checkout ${BUSYBOX_VERSION}
    # Configure busybox
    # Remove previous BusyBox build output and configuration. 
    # This ensures BusyBox is built from a clean state. 
    make distclean 
    # Generate BusyBox's default configuration. 
    # ARCH selects ARM64 as the target architecture. 
    # CROSS_COMPILE selects the ARM64 cross-compilation toolchain. 
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} defconfig
else
    cd busybox
fi

# Make and install busybox
# Compile BusyBox for the ARM64 target. 
# -j$(nproc) uses all available processor cores to speed up compilation. 
make -j$(nproc) ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} 
# Install BusyBox into the staged root filesystem. 
# CONFIG_PREFIX specifies where BusyBox should place its files. 
# 
# BusyBox installs: 
# bin/busybox 
# command symlinks such as bin/ls, bin/cat and bin/sh 
# utilities under sbin and usr/bin 
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} \ CONFIG_PREFIX=${OUTDIR}/rootfs install

echo "Library dependencies"
${CROSS_COMPILE}readelf -a ${OUTDIR}/rootfs/bin/busybox | grep "program interpreter"

${CROSS_COMPILE}readelf -a ${OUTDIR}/rootfs/bin/busybox | grep "Shared library"

# Add library dependencies to rootfs
# Ask the ARM64 cross-compiler for the location of its target sysroot. 
# The sysroot contains ARM64 libraries and header files. 
SYSROOT=$(${CROSS_COMPILE}gcc -print-sysroot) 
# Copy the ARM64 dynamic loader into rootfs/lib. 
# The dynamic loader starts dynamically linked ARM64 executables. 
# -L follows the symbolic link and copies the actual file. 
echo "SYSROOT"
echo $SYSROOT
cp -L "${SYSROOT}/lib/ld-linux-aarch64.so.1" "${OUTDIR}/rootfs/lib/" 
# Copy the ARM64 mathematics library. 
# BusyBox may depend on this library for mathematical operations. 
cp -L "${SYSROOT}/lib64/libm.so.6" "${OUTDIR}/rootfs/lib64/" 
# Copy the ARM64 DNS and hostname resolution library. 
# This provides functions used for network name resolution. 
cp -L "${SYSROOT}/lib64/libresolv.so.2" "${OUTDIR}/rootfs/lib64/" 
# Copy the ARM64 standard C library. 
# Most dynamically linked Linux applications depend on libc. 
cp -L "${SYSROOT}/lib64/libc.so.6" "${OUTDIR}/rootfs/lib64/"

# Make device nodes
# Create the /dev/null character device. 
# 
# sudo is required because creating device nodes requires root privileges. 
# mknod creates a special filesystem device node. 
# -m 666 gives read and write permission to everyone. 
# c means this is a character device. 
# 1 is the major device number. 
# 3 is the minor device number for /dev/null. 
sudo mknod -m 666 ${OUTDIR}/rootfs/dev/null c 1 3 
# Create the system console character device. 
# 
# -m 600 allows only root to read from and write to the console. 
# 5 is the major device number. 
# 1 is the minor device number for /dev/console. 
# 
# The kernel uses /dev/console for boot messages and the QEMU terminal. 
sudo mknod -m 600 ${OUTDIR}/rootfs/dev/console c 5 1

# Clean and build the writer utility
# Move to the finder-app directory containing writer.c and its Makefile. 
cd ${FINDER_APP_DIR} 
pwd
# Delete any writer executable or object files from an earlier build. 
make clean 
# Build writer using the ARM64 cross-compiler. 
# The Makefile should prepend CROSS_COMPILE to gcc. 
make CROSS_COMPILE=${CROSS_COMPILE} 
# Copy the generated ARM64 writer executable into /home in the target rootfs. 
cp writer ${OUTDIR}/rootfs/home/

# Copy the finder related scripts and executables to the /home directory
# on the target rootfs
# Copy finder.sh into the target's /home directory. 
# This script searches for files containing a requested string. 
cp finder.sh ${OUTDIR}/rootfs/home/ 
# Copy the assignment test script into the target's /home directory. 
cp finder-test.sh ${OUTDIR}/rootfs/home/ 
# Copy the script that automatically runs the tests after QEMU boots. 
cp autorun-qemu.sh ${OUTDIR}/rootfs/home/ 
# Create the configuration directory inside the target's /home directory. 
mkdir -p ${OUTDIR}/rootfs/home/conf 
# Copy the username configuration file into rootfs/home/conf. 
cp conf/username.txt ${OUTDIR}/rootfs/home/conf/ 
# Copy the assignment configuration file into rootfs/home/conf. 
cp conf/assignment.txt ${OUTDIR}/rootfs/home/conf/ 
# Modify finder-test.sh inside the staged rootfs. 
# 
# sed -i edits the file directly. 
# The substitution changes: 
# ../conf/assignment.txt 
# to: 
# conf/assignment.txt 
# 
# This is required because finder-test.sh will execute from /home 
# inside the QEMU target. 
sed -i 's|\.\./conf/assignment.txt|conf/assignment.txt|g' ${OUTDIR}/rootfs/home/finder-test.sh 
# Give finder.sh execute permission. 
chmod +x ${OUTDIR}/rootfs/home/finder.sh 
# Give finder-test.sh execute permission. 
chmod +x ${OUTDIR}/rootfs/home/finder-test.sh 
# Give autorun-qemu.sh execute permission. 
chmod +x ${OUTDIR}/rootfs/home/autorun-qemu.sh 
# Give the writer application execute permission. 
chmod +x ${OUTDIR}/rootfs/home/writer

# Chown the root directory
# Change the owner and group of every rootfs file to root. 
# 
# sudo is needed because changing ownership to root requires privileges. 
# -R applies the ownership change recursively to every file and directory. 
# root:root means: 
# owner = root 
# group = root 
# 
# Files in an initramfs should normally be owned by root. 
sudo chown -R root:root ${OUTDIR}/rootfs

# Create initramfs.cpio.gz
# Enter the staged root filesystem. 
# Using this directory as the current directory prevents absolute host paths 
# from being stored inside the initramfs archive. 
cd ${OUTDIR}/rootfs 
# Find all files and directories below the current rootfs directory. 
# 
# Pipe the resulting list into cpio. 
# 
# cpio -H newc: 
# creates an archive using the "newc" initramfs-compatible format. 
# 
# cpio -o: 
# selects archive creation/output mode. 
# 
# Pipe the uncompressed cpio archive into gzip. 
# 
# Redirect the compressed result into OUTDIR/initramfs.cpio.gz. 
# QEMU will load this file as the initial root filesystem. 
find . | cpio -H newc -o | gzip > ${OUTDIR}/initramfs.cpio.gz
