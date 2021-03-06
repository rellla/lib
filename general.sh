#!/bin/bash
#
# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.
#
# This file is a part of tool chain https://github.com/igorpecovnik/lib
#

# Functions:
# cleaning
# exit_with_error
# get_package_list_hash
# fetch_from_github
# display_alert
# grab_version
# fingerprint_image
# addtorepo
# prepare_host

# cleaning <target>
#
# target: what to clean
# "make" - "make clean" for selected kernel and u-boot
# "debs" - delete output/debs
# "cache" - delete output/cache
# "images" - delete output/images
# "sources" - delete output/sources
#
cleaning()
{
	case $1 in
		"make")	# clean u-boot and kernel sources
		[ -d "$SOURCES/$BOOTSOURCEDIR" ] && display_alert "Cleaning" "$SOURCES/$BOOTSOURCEDIR" "info" && cd $SOURCES/$BOOTSOURCEDIR && make -s ARCH=arm CROSS_COMPILE="$CROSS_COMPILE" clean >/dev/null
		[ -d "$SOURCES/$LINUXSOURCEDIR" ] && display_alert "Cleaning" "$SOURCES/$LINUXSOURCEDIR" "info" && cd $SOURCES/$LINUXSOURCEDIR && make -s ARCH=arm CROSS_COMPILE="$CROSS_COMPILE" clean >/dev/null
		;;

		"debs") # delete output/debs for current branch and family
		if [ -d "$DEST/debs" ]; then
			display_alert "Cleaning $DEST/debs for" "$BOARD $BRANCH" "info"
			# easier than dealing with variable expansion and escaping dashes in file names
			find $DEST/debs -name '*.deb' | grep -E "${CHOSEN_KERNEL/image/.*}|$CHOSEN_UBOOT" | xargs rm -f
			[[ -n $RELEASE ]] && rm -f $DEST/debs/$RELEASE/${CHOSEN_ROOTFS}_${REVISION}_${ARCH}.deb
		fi
		;;

		"alldebs") # delete output/debs
		[ -d "$DEST/debs" ] && display_alert "Cleaning" "$DEST/debs" "info" && rm -rf $DEST/debs/*
		;;

		"cache") # delete output/cache
		[ -d "$CACHEDIR" ] && display_alert "Cleaning" "$CACHEDIR" "info" && find $CACHEDIR/ -type f -delete
		;;

		"images") # delete output/images
		[ -d "$DEST/images" ] && display_alert "Cleaning" "$DEST/images" "info" && rm -rf $DEST/images/*
		;;

		"sources") # delete output/sources
		[ -d "$SOURCES" ] && display_alert "Cleaning" "$SOURCES" "info" && rm -rf $SOURCES/*
		;;

		*) # unknown
		display_alert "Cleaning: unrecognized option" "$1" "wrn"
		;;
	esac
}

# exit_with_error <message> <highlight>
#
# a way to terminate build process
# with verbose error message
#

exit_with_error()
{
	local _file=$(basename ${BASH_SOURCE[1]})
	local _line=${BASH_LINENO[0]}
	local _function=${FUNCNAME[1]}
	local _description=$1
	local _highlight=$2

	display_alert "ERROR in function $_function" "$_file:$_line" "err"
	display_alert "$_description" "$_highlight" "err"
	display_alert "Process terminated" "" "info"
	exit -1
}

# get_package_list_hash <package_list>
#
# outputs md5hash for space-separated <package_list>
# for rootfs cache

get_package_list_hash()
{
	echo $(printf '%s\n' $PACKAGE_LIST | sort -u | md5sum | cut -d' ' -f 1)
}

# fetch_from_github <URL> <directory> <tag> <tagsintosubdir>
#
# parameters:
# <URL>: Git repository
# <directory>: where to place under SOURCES
# <device>: cubieboard, cubieboard2, cubietruck, ...
# <description>: additional description text
# <tagintosubdir>: boolean

fetch_from_github (){
GITHUBSUBDIR=$3
[[ -z "$3" ]] && GITHUBSUBDIR="branchless"
[[ -z "$4" ]] && GITHUBSUBDIR="" # only kernel and u-boot have subdirs for tags
if [ -d "$SOURCES/$2/$GITHUBSUBDIR" ]; then
	cd $SOURCES/$2/$GITHUBSUBDIR
	git checkout -q $FORCE $3
	display_alert "... updating" "$2" "info"
	PULL=$(git pull)
else
	if [[ -n $3 && -n "$(git ls-remote $1 | grep "$tag")" ]]; then
		display_alert "... creating a shallow clone" "$2 $3" "info"
		# Toradex git's doesn't support shallow clone. Need different solution than this.
		git clone -n $1 $SOURCES/$2/$GITHUBSUBDIR -b $3 --depth 1 || git clone -n $1 $SOURCES/$2/$GITHUBSUBDIR -b $3
		cd $SOURCES/$2/$GITHUBSUBDIR
		git checkout -q $3
	else
		display_alert "... creating a shallow clone" "$2" "info"
		git clone -n $1 $SOURCES/$2/$GITHUBSUBDIR --depth 1
		cd $SOURCES/$2/$GITHUBSUBDIR
		git checkout -q
	fi

fi
cd $SRC
if [ $? -ne 0 ]; then
	exit_with_error "Github download failed" "$1"
fi
}


display_alert()
#--------------------------------------------------------------------------------------------------------------------------------
# Let's have unique way of displaying alerts
#--------------------------------------------------------------------------------------------------------------------------------
{
# log function parameters to install.log
echo "Displaying message: $@" >> $DEST/debug/install.log

if [[ $2 != "" ]]; then TMPARA="[\e[0;33m $2 \x1B[0m]"; else unset TMPARA; fi
if [ $3 == "err" ]; then
	echo -e "[\e[0;31m error \x1B[0m] $1 $TMPARA"
elif [ $3 == "wrn" ]; then
	echo -e "[\e[0;35m warn \x1B[0m] $1 $TMPARA"
elif [ $3 == "ext" ]; then
	echo -e "[\e[0;32m o.k. \x1B[0m] \e[1;32m$1\x1B[0m $TMPARA"
else
	echo -e "[\e[0;32m o.k. \x1B[0m] $1 $TMPARA"
fi
}

#---------------------------------------------------------------------------------------------------------------------------------
# grab_version <path> <var_name>
#
# <PATH>: Extract kernel or uboot version from Makefile
# <var_name>: write version to this variable
#---------------------------------------------------------------------------------------------------------------------------------
grab_version ()
{
	local var=("VERSION" "PATCHLEVEL" "SUBLEVEL" "EXTRAVERSION")
	local ver=""
	for dir in "${var[@]}"; do
		tmp=$(cat $1/Makefile | grep $dir | head -1 | awk '{print $(NF)}' | cut -d '=' -f 2)"#"
		[[ $tmp != "#" ]] && ver=$ver$tmp
	done
	ver=${ver//#/.}; ver=${ver%.}; ver=${ver//.-/-}
	eval $"$2"="$ver"
}

fingerprint_image (){
#--------------------------------------------------------------------------------------------------------------------------------
# Saving build summary to the image
#--------------------------------------------------------------------------------------------------------------------------------
display_alert "Fingerprinting" "$VERSION Linux" "info"

echo "--------------------------------------------------------------------------------" > $1
echo "" >> $1
echo "" >> $1
echo "" >> $1
echo "Title:			$VERSION (unofficial)" >> $1
echo "Kernel:			Linux $VER" >> $1
now="$(date +'%d.%m.%Y')" >> $1
printf "Build date:		%s\n" "$now" >> $1
echo "Author:			Igor Pecovnik, www.igorpecovnik.com" >> $1
echo "Sources: 		http://github.com/igorpecovnik" >> $1
echo "" >> $1
echo "Support: 		http://www.armbian.com" >> $1
echo "" >> $1
echo "" >> $1
echo "--------------------------------------------------------------------------------" >> $1
echo "" >> $1
cat $SRC/lib/LICENSE >> $1
echo "" >> $1
echo "--------------------------------------------------------------------------------" >> $1
}

addtorepo ()
{
# add all deb files to repository
# parameter "remove" dumps all and creates new
# function: cycle trough distributions
DISTROS=("wheezy" "jessie" "trusty")
IFS=" "
j=0
while [[ $j -lt ${#DISTROS[@]} ]]
        do
        # add each packet to distribution
		DIS=${DISTROS[$j]}

		# let's drop from publish if exits
		if [ "$(aptly publish list -config=config/aptly.conf -raw | awk '{print $(NF)}' | grep $DIS)" != "" ]; then
		aptly publish drop -config=config/aptly.conf $DIS > /dev/null 2>&1
		fi
		#aptly db cleanup -config=config/aptly.conf

		if [ "$1" == "remove" ]; then
		# remove repository
			aptly repo drop -config=config/aptly.conf $DIS > /dev/null 2>&1
			aptly db cleanup -config=config/aptly.conf > /dev/null 2>&1
		fi

		# create repository if not exist
		OUT=$(aptly repo list -config=config/aptly.conf -raw | awk '{print $(NF)}' | grep $DIS)
		if [[ "$OUT" != "$DIS" ]]; then
			display_alert "Creating section" "$DIS" "info"
			aptly repo create -config=config/aptly.conf -distribution=$DIS -component=main -comment="Armbian stable" $DIS > /dev/null 2>&1
		fi

		# add all packages
		aptly repo add -force-replace=true -config=config/aptly.conf $DIS $POT/*.deb

		# add all distribution packages
		if [ -d "$POT/$DIS" ]; then
			aptly repo add -force-replace=true -config=config/aptly.conf $DIS $POT/$DIS/*.deb
		fi

		aptly publish -passphrase=$GPG_PASS -force-overwrite=true -config=config/aptly.conf -component="main" --distribution=$DIS repo $DIS > /dev/null 2>&1

		#aptly repo show -config=config/aptly.conf $DIS

        j=$[$j+1]
done
}

# prepare_host
#
# * checks and installs necessary packages
# * creates directory structure
# * changes system settings
#
prepare_host() {

	display_alert "Preparing" "host" "info"

	if [[ $(dpkg --print-architecture) == armhf ]]; then
		display_alert "Please read documentation to set up proper compilation environment" "..." "info"
		display_alert "http://www.armbian.com/using-armbian-tools/" "..." "info"
		exit_with_error "Running this tool on board itself is not supported"
	fi

	# dialog may be used to display progress
	if [[ $(dpkg-query -W -f='${db:Status-Abbrev}\n' dialog 2>/dev/null) != *ii* ]]; then
		display_alert "Installing package" "dialog" "info"
		apt-get install -qq -y --no-install-recommends dialog >/dev/null 2>&1
	fi

	# wget is needed
	if [[ $(dpkg-query -W -f='${db:Status-Abbrev}\n' wget 2>/dev/null) != *ii* ]]; then
		display_alert "Installing package" "wget" "info"
		apt-get install -qq -y --no-install-recommends wget >/dev/null 2>&1
	fi

	# need lsb_release to decide what to install
	if [[ $(dpkg-query -W -f='${db:Status-Abbrev}\n' lsb-release 2>/dev/null) != *ii* ]]; then
		display_alert "Installing package" "lsb-release" "info"
		apt-get install -qq -y --no-install-recommends lsb-release >/dev/null 2>&1
	fi

	# packages list for host
	PAK="ca-certificates device-tree-compiler pv bc lzop zip binfmt-support build-essential ccache debootstrap ntpdate pigz \
	gawk gcc-arm-linux-gnueabihf gcc-arm-linux-gnueabi qemu-user-static u-boot-tools uuid-dev zlib1g-dev unzip libusb-1.0-0-dev ntpdate \
	parted pkg-config libncurses5-dev whiptail debian-keyring debian-archive-keyring f2fs-tools libfile-fcntllock-perl rsync libssl-dev \
	nfs-kernel-server btrfs-tools gcc-aarch64-linux-gnu ncurses-term p7zip-full"

	# warning: apt-cacher-ng will fail if installed and used both on host and in container/chroot environment with shared network
	# set NO_APT_CACHER=yes to prevent installation errors in such case
	if [[ $NO_APT_CACHER != yes ]]; then PAK="$PAK apt-cacher-ng"; fi

	local codename=$(lsb_release -sc)
	if [[ $codename == "" || "trusty wily xenial" != *"$codename"* ]]; then
		display_alert "Host system support was not tested" "${codename:-(unknown)}" "wrn"
		echo -e "Press \e[0;33m<Ctrl-C>\x1B[0m to abort compilation, \e[0;33m<Enter>\x1B[0m to ignore and continue"
		read
	fi

	if [[ $codename == trusty ]]; then
		PAK="$PAK libc6-dev-armhf-cross libc6-dev-armel-cross";
		if [[ ! -f /etc/apt/sources.list.d/aptly.list ]]; then
			display_alert "Adding repository for trusty" "aptly" "info"
			echo 'deb http://repo.aptly.info/ squeeze main' > /etc/apt/sources.list.d/aptly.list
			apt-key adv --keyserver keys.gnupg.net --recv-keys 9E3E53F19C7DE460
		fi
	fi

	if [[ $codename == wily || $codename == xenial ]]; then
		PAK="$PAK libc6-dev-armhf-cross libc6-dev-armel-cross"
	fi

	local deps=()
	local installed=$(dpkg-query -W -f '${db:Status-Abbrev}|${binary:Package}\n' '*' 2>/dev/null | grep '^ii' | awk -F '|' '{print $2}' | cut -d ':' -f 1)

	for packet in $PAK; do
		if ! grep -q -x -e "$packet" <<< "$installed"; then deps+=("$packet"); fi
	done

	if [[ ${#deps[@]} -gt 0 ]]; then
		eval '( apt-get update; apt-get -y --no-install-recommends install "${deps[@]}" )' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/output.log'} \
			${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Installing ${#deps[@]} host dependencies..." $TTY_Y $TTY_X'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}
	fi

	# install aptly separately
	if [[ $(dpkg-query -W -f='${db:Status-Abbrev}\n' aptly 2>/dev/null) != *ii* ]]; then
		apt-get install -qq -y --no-install-recommends aptly >/dev/null 2>&1
	fi

	# TODO: Check for failed installation process
	# test exit code propagation for commands in parentheses

	# enable arm binary format so that the cross-architecture chroot environment will work
	test -e /proc/sys/fs/binfmt_misc/qemu-arm || update-binfmts --enable qemu-arm
	test -e /proc/sys/fs/binfmt_misc/qemu-aarch64 || update-binfmts --enable qemu-aarch64

	# create directory structure
	mkdir -p $SOURCES $DEST/debug $CACHEDIR/rootfs $SRC/userpatches/overlay $SRC/toolchains
	find $SRC/lib/patch -type d ! -name . | sed "s%lib/patch%userpatches%" | xargs mkdir -p

	[[ ! -f $SRC/userpatches/customize-image.sh ]] && cp $SRC/lib/scripts/customize-image.sh.template $SRC/userpatches/customize-image.sh

	# TODO: needs better documentation
	echo 'Place your patches and kernel.config / u-boot.config / lib.config here.' > $SRC/userpatches/readme.txt
	echo 'They will be automatically included if placed here!' >> $SRC/userpatches/readme.txt
}
