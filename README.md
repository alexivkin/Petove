# PeTOVe, a system virtualizer

This set of bash scripts allows you to take a **P**hysical system and convert it **to** a **V**irtual clone, resembing the original as close as possible in all aspects or hardware. That includes processor IDs, motherboard and hard drive serial numbers, MAC and much more.
Using this script you can create a system that is indistinguishable from the original from Microsoft Windows' and Office's standpoint from the original, thereby avoiding reactivation of these products. It also works on systems that have full disk encryption or other products tied to the hardware, like RSA key generators.

* Requires an ability to boot the original with an exteral usb
* Uses VirtualBox as the target virtualization platform

## How it works

You run this script after booting your original system with a linux recovery usb. It takes a hardware snapshot and creates another script that you can then run on your VirtualBox host. That script creates the guest VM and configures its virtual hardware.
You will need to clone the source disk with the dd and then convert it to a format readable by VirtualBox. You dont have to clone the blank space. By using the "growable" format the disk size will match the original on the guest system, but only take enough space on the host to accomodate your data.

## How to use it

### Prep the source system
If your orignal system is Windows, make sure that AHCI drivers are enabled. Open regedit and set start to 0 under
````
HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\atapi
HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\iaStor
HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\iaStorV
HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\msahci
HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\pciide
````
Reboot, and go into your Bios to make sure that the drives are set to AHCI. If they are SCSI, change to AHCI. Neither VirtualBox, not VMWare have virtual SCSI interfaces.
Continue booting. Windows will install the missing AHCI drivers on boot.

Now, everthing you do below is optional, but it greatly simplifies the clonning:

1. Remove all extra partitions but one ("C:"). Make sure your only partition starts at the beginning of the disk. If you have a "System boot" partition, delete it and mark your "C:" partition as boot. Reboot to force Windows to move all its systems files to the "C:" partition..
2. Run a cleanup tool and reduce your "C:" partition size to something that you can afford to have as a virtual disk. This will be the real size required on the hosts.
3. If you don't have a full disk encryption, run a free space zeroing tool like sdelete. This way you will be able to use virtualbox's disk reduce feature, so the disk takes even less space on the host.

### Prep the target host
1. Make a Linux based recovery OS. [SystemRescueCd](https://www.system-rescue-cd.org/SystemRescueCd_Homepage) is a decent option. Turning the SystemRescue ISO into a USB is a three step process: get the ISO, run `isohybrid` on it, flash with `dd if=hybredized.iso of=/dev/sd-`*usbdevice*
2. Copy this script to a folder on the USB. Copy `biosdecode`, `dmidecode`, `lsusb`, if they are missing from your linux recovery USB distro, to the same folder. They are missing in SystemRescueCD).
3. Find enough space on your host to accomodate the "C:" partition you will be cloning. It does not have to accomodate the whole disk of your original system, but should at the very least fit the partition you are copying. Make sure you can connect over the network to that space from the linux recovery. sshfs for Linux host or smbclient/smbfs for the Windows host should work.

### Take the snapshot
1. Shut the system down and boot into a Linux recovery OS.
2. Mount a remote folder via sshfs or smbfs to some folder, like /mnt/temp
3. Take a snapshot of the disk. You only need to copy enough data to cover the size of your partition (i.e. no need to copy the empty space at the end of the disk). Make sure you are copying the full disk, not a partition (eg. /dev/sda not /dev/sda1). Here is how to copy a drive with a 50G partition:
```
dd if=/dev/sda of=/mnt/temp/fulldisk.dd bs=1M count=50000
```
4.  Take the fingerprint of the system by running
```
clone-physical-to-virtual.sh systemname
```
This will generate a bash script config_VMname.sh for creating the VM and setting the appropriate parameters

### Create the virtual clone
1. Convert raw disk image to vdi:
```
vboxmanage convertfromraw fulldisk.dd fulldisk.vdi
```
2. Run the generated config_VMname.sh script.
You can modify the script as necessary, or recreate it by running clone-physical-to-virtual.sh with the data you captured before in the same folder.
If your target host is windows, convert bash to batch, or run bash under windows bash/cygwin.

## Troubleshooting

The script is not tested thorougly, so if you run into issues, look through the code.

To see what was set on the VM run `vboxmanage getextradata VMname enumerate` or just crack open the .vbox file. It's an XML.