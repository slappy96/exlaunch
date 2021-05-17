#!/bin/sh
# exitvelocity boot script to install dwm + dotfiles
# adaptation of LARBS by Luke Smith <luke@lukesmith.xyz>
# License: GNU GPLv3

#=========================================================#
################### IMPORTANT i############################
# Before you run this script, at least have done:
# PARTITION DISK (boot and root)
# MOUNT THE PARTITIONS (/mnt, /mnt/boot)
# INSTALL BASE PACKAGES into /mnt
# pacstrap /mnt base linux linux-firmware git vim amd-ucode
# GENERATE THE FSTAB
# genfstab -U /mnt >> /mnt/etc/fstab
# CHROOT with arch-chroot /mnt
############################################################

### Initial -- timezone, clock, locale, host, root pass ###
#ln -sf /usr/share/zoneinfo/America/Chicago /etc/localtime
#hwclock --systohc
#sed -i 's/^#en_US/en_US/' /etc/locale.gen
#locale-gen
#printf "rocinante" > /etc/hostname
#printf "127.0.0.1 localhost\n\
#::1  localhost\n\
#127.0.1.1 rocinante.localdomain rocinante" > /etc/hosts
#echo root:password | chpasswd

### DEFINE Dotfiles, program csv, aurhelper ###
dotfilesrepo="https://github.com/slappy96/exvel.git"
progsfile="https://raw.githubusercontent.com/slappy96/exlaunch/master/progs.csv"
aurhelper="yay"
repobranch="master"

### FUNCTIONS ###
installpkg(){ pacman --noconfirm --needed -S "$1" ;}

error() { clear; printf "ERROR:\\n%s\\n" "$1"; exit 1;}

welcomemsg() { printf "Welcome to exitvelocity's install script\n\
	This script will automatically install a fully-featured Linux\
	desktop\n";}

getuserandpass() { \
	# Prompts user for new username an password.
	read -p "Please enter a name for user account: " name || exit 1
	while ! echo "$name" | grep -q "^[a-z_][a-z0-9_-]*$"; do
		read -p "Please enter a name for user account lowercase: " name
	done
	read -s -p "Please enter a password: " pass1
	read -s -p "Please retype password: " pass2
	while ! [ "$pass1" = "$pass2" ]; do
		unset pass2
		read -s -p "Please enter a password: " pass1
		read -s -p "Please retype password: " pass2
	done ;}

adduserandpass() { \
	# Adds user `$name` with password $pass1.
	printf "Adding user \$name\n";
	useradd -m -g wheel -s /bin/zsh "$name" >/dev/null 2>&1 ||
	usermod -a -G wheel "$name" && mkdir -p /home/"$name" && chown "$name":wheel /home/"$name"
	repodir="/home/$name/.local/src"; mkdir -p "$repodir"; chown -R "$name":wheel "$(dirname "$repodir")"
	echo "$name:$pass1" | chpasswd
	unset pass1 pass2 ;}

refreshkeys() { \
	echo "Refreshing Arch Keyring..."
	pacman --noconfirm -Sy archlinux-keyring >/dev/null 2>&1
	}

newperms() { # Set special sudoers settings for install (or after).
	sed -i "/#INTERLOPER/d" /etc/sudoers
	echo "$* #INTERLOPER" >> /etc/sudoers ;}

manualinstall() { # Installs $1 manually if not installed. Used only for AUR
	# helper here.
	[ -f "/usr/bin/$1" ] || (echo "Installing \"$1\", an AUR helper..."
	cd /tmp || exit 1
	rm -rf /tmp/"$1"*
	curl -sO https://aur.archlinux.org/cgit/aur.git/snapshot/"$1".tar.gz && sudo -u "$name" tar -xvf "$1".tar.gz >/dev/null 2>&1 &&
	cd "$1" &&
	sudo -u "$name" makepkg --noconfirm -si
	cd /tmp || return 1) ;}

maininstall() { # Installs all needed programs from main repo.
	echo "Installing \`$1\` ($n of $total). $1 $2"
	installpkg "$1"
	}

gitmakeinstall() {
	progname="$(basename "$1" .git)"
	dir="$repodir/$progname"
	echo "exvel Installation\nInstalling \`$progname\` ($n of $total) via \`git\` and \`make\`. $(basename "$1") $2"
	sudo -u "$name" git clone --depth 1 "$1" "$dir" >/dev/null 2>&1 || { cd "$dir" || return 1 ; sudo -u "$name" git pull --force origin master;}
	cd "$dir" || exit 1
	make
	make install
	cd /tmp || return 1 ;}

aurinstall() { \
	echo "exvel Installation--Installing \`$1\` ($n of $total) from the AUR. $1 $2"
	echo "$aurinstalled" | grep -q "^$1$" && return 1
	sudo -u "$name" $aurhelper -S --noconfirm "$1"
	}

pipinstall() { \
	echo "Installing the Python package \`$1\` ($n of $total). $1 $2"
	[ -x "$(command -v "pip")" ] || installpkg python-pip >/dev/null\
	yes | pip install "$1"
	}

installationloop() { \
	([ -f "$progsfile" ] && cp "$progsfile" /tmp/progs.csv) || curl -Ls "$progsfile" | sed '/^#/d' > /tmp/progs.csv
	total=$(wc -l < /tmp/progs.csv)
	aurinstalled=$(pacman -Qqm)
	while IFS=, read -r tag program comment; do
		n=$((n+1))
		echo "$comment" | grep -q "^\".*\"$" && comment="$(echo "$comment" | sed "s/\(^\"\|\"$\)//g")"
		case "$tag" in
			"A") aurinstall "$program" "$comment" ;;
			"G") gitmakeinstall "$program" "$comment" ;;
			"P") pipinstall "$program" "$comment" ;;
			*) maininstall "$program" "$comment" ;;
		esac
	done < /tmp/progs.csv ;}

putgitrepo() { # Downloads a gitrepo $1 and places the files in $2 only overwriting conflicts
	echo "Downloading and installing config files..."
	[ -z "$3" ] && branch="master" || branch="$repobranch"
	dir=$(mktemp -d)
	[ ! -d "$2" ] && mkdir -p "$2"
	chown -R "$name":wheel "$dir" "$2"
	sudo -u "$name" git clone --recursive -b "$branch" --depth 1 --recurse-submodules "$1" "$dir"
	sudo -u "$name" cp -rfT "$dir" "$2"
	}

systembeepoff() { echo "Removing beep sound..."
	echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf ;}

finalize(){ \
	echo "Congrats. You are ready to roll!"
	}

### THE ACTUAL SCRIPT ###

### This is how everything happens in an intuitive format and order.

# Check if user is root on Arch distro. Install dialog.
pacman --noconfirm --needed -Sy dialog || error "Please run as root"

# Welcome user and pick dotfiles.
welcomemsg || error "User exited."

# Get and verify username and password.
getuserandpass || error "User exited."

# Refresh Arch keyrings.
refreshkeys || error "Error automatically refreshing Arch keyring. Consider doing so manually."

for x in curl base-devel git ntp zsh; do
	echo "Exvel Installation--Installing \'$x\' which\
	is required to install cond configure other programs."
	installpkg "$x"
done

echo "Synchronizing system time to ensure successful and secure installation of software..."
ntpdate 0.us.pool.ntp.org >/dev/null 2>&1

adduserandpass || error "Error adding username and/or password."

[ -f /etc/sudoers.pacnew ] && cp /etc/sudoers.pacnew /etc/sudoers # Just in case

# Allow user to run sudo without password. Since AUR programs must be installed
# in a fakeroot environment, this is required for all builds with AUR.
newperms "%wheel ALL=(ALL) NOPASSWD: ALL"

# Make pacman and yay colorful and adds eye candy on the progress bar because
# why not.
grep -q "^Color" /etc/pacman.conf || sed -i "s/^#Color$/Color/" /etc/pacman.conf
grep -q "ILoveCandy" /etc/pacman.conf || sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf

# Use all cores for compilation.
sed -i "s/-j2/-j$(nproc)/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf

manualinstall $aurhelper || error "Failed to install AUR helper."


# The command that does all the installing. Reads the progs.csv file and
# installs each needed program the way required. Be sure to run this only after
# the user has been created and has priviledges to run sudo without a password
# and all build dependencies are installed.
installationloop

#echo "Finally, installing \`libxft-bgra\` to enable color emoji in suckless software without crashes."
#yes | sudo -u "$name" $aurhelper -S libxft-bgra-git >/dev/null 2>&1

# Install the dotfiles in the user's home directory
putgitrepo "$dotfilesrepo" "/home/$name" "$repobranch"
rm -f "/home/$name/README.md" "/home/$name/LICENSE"
# make git ignore deleted LICENSE & README.md files
git update-index --assume-unchanged "/home/$name/README.md" "/home/$name/LICENSE"

# Most important command! Get rid of the beep!
systembeepoff

# Make zsh the default shell for the user.
chsh -s /bin/zsh "$name" >/dev/null 2>&1
sudo -u "$name" mkdir -p "/home/$name/.cache/zsh/"

# Start/restart PulseAudio.
killall pulseaudio; sudo -u "$name" pulseaudio --start

## Install systemd boot
#sudo bootctl install
## create loader.conf for boot menu
#sudo printf "default arch\n\
#timeout 5" > /boot/loader/loader.conf
## Pull UUID or PART UUID and write boot entry
#MAIN_UUID="$(lsblk -f | grep '/$' | awk '{ print $4 }')"
#PART_UUID="$(blkid | grep "$MAIN_UUID" | awk '{ print $7 }' | tr -d '"' )"
##add "initrd /amd-ucode.img or /intel-ucode.img below
#sudo printf "title Archlinux\n\
#linux /vmlinuz-linux\n\
#initrd /initramfs-linux.img\n\
#options root="$PART_UUID" rw"\
#> /boot/loader/entries/arch.conf

systemctl enable NetworkManager

# This line, overwriting the `newperms` command above will allow the user to run
# serveral important commands, `shutdown`, `reboot`, updating, etc. without a
# password.
newperms "%wheel ALL=(ALL) ALL"
printf "slappy ALL=(ALL) ALL" > /etc/sudoers.d/slappy

# Last message! Install complete!
finalize
