# PeTOVe, a system virtualizer

This is a bash script that allows you to take a **P**hysical system and convert it **to** a **V**irtual clone, resembing the original as close as possible in all aspects or hardware. That includes processor name, motherboard and hard drive serial numbers, MAC and much more.
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

Next you will need to clone your original system's harddrive. If you have enough space on your host to accommodate the full size of your original's harddrive, you can proceed to the next section. If you want to have your clone consume less space on the host than the harddrive size of your original system, read on:

If you have *full disk encryption* enabled (bitlocker, symantec and such), you will need to use take a VDH snapshot of a live system with [disk2vhd](https://docs.microsoft.com/en-us/sysinternals/downloads/disk2vhd) and then convert the VHD into VDI with "vboxmanage covert". This will remove any encryption.

1. Remove all extra partitions you do not need. If you have a "System boot" partition, use Windows' Disk Management MMC to delete it and mark your "C:" partition as "boot". Reboot your system to force Windows to move all its systems files to the "C:" partition.
2. Reduce the size of your partition:
	1. Run a cleanup tool and remove any junk you may have.
    2. Disable hibernation to remove the hibernation file.
    3. Reduce or make the swap equal to 0 to minimize (or remove) the swap file.
    4. Use the Disk Management MMC to reduce your "C:" partition size to something that you can afford to have as a virtual disk. This will be the real size required on the host.
2. Make sure your only partition starts at the beginning of the disk. If it does not, use Disk Management or some other partition editing tool (gparted) to move it to the beginning of the disk.
3. If you don't have full disk encryption, run a free space zeroing tool like sdelete. This way you will be able to use virtualbox's disk reduce feature after it is converted to vdi, so the disk takes even less space on the host.

### Preparations on the host
1. Make a Linux based recovery OS. [SystemRescueCd](https://www.system-rescue-cd.org/SystemRescueCd_Homepage) is a decent option. Turning the SystemRescue ISO into a USB is a four step process: get the ISO, mount it with "-o loop,exec", plug usb without mounting it, run `./usb_inst.sh` from the mounted iso
2. Find enough space on your host where you will be saving the disk to, to accomodate the "C:" partition you will be cloning. It does not have to accomodate the whole disk of your original system, but should at the very least fit the partition you are copying. Make sure you can connect over the network to that space from the linux recovery usb. sshfs for Linux host or smbclient/smbfs for the Windows host should work.
3. Copy the code of this folder into the host folder you have mounted. If you are running the latest SystemRescueCD (5.1.1+) you do not need `biosdecode`, `dmidecode`, `lsusb`, while older versions of SystemRescueCD did not have it. You will need `nvme` if you have an SSD attache to PCI Express (NVMe) (your disk is /dev/nvme...). If you get "not found" message when running the script you would need 32 bit versions of the executables. Provided versions are 64 bit and even though your kernel may be 64 bit, systemrescue is running in a 32 bit userland.


### Take a snapshot of your source system
1. Shut the system down and boot into a Linux recovery OS.
2. Mount a remote folder via sshfs or smbfs to some folder, like /mnt/temp
3.  Take the fingerprint of the system by running
```
clone-physical-to-virtual.sh systemname
```
This will generate a bash script config_VMname.sh for creating the VM and setting the appropriate parameters
4. Take a snapshot of the disk. clone-physical-to-virtual.sh will give you correct command for the first partition. You only need to copy enough data to cover the size of your partition (i.e. no need to copy the empty space at the end of the disk). Make sure you are copying the full disk, not a partition (eg. /dev/sda not /dev/sda1). Here is how to copy a drive with a 50G partition:
```
dd if=/dev/sda of=/mnt/temp/fulldisk.dd bs=1M count=50000
```
Alternatively you can do the data cloning wiht disk2vhd

### Create the virtual clone on your host
1. Convert raw disk image to vdi:
```
vboxmanage convertfromraw fulldisk.dd fulldisk.vdi
```
2. Run the generated config_VMname.sh script.
You can modify the script as necessary, or recreate it by running clone-physical-to-virtual.sh with the data you captured before in the same folder.
If your target host is windows, convert bash to batch, or run bash under windows bash/cygwin.

3. The last step after your clone is running in the VM environment is to go in and clean all the remaining drivers. Make sure to also show hidden drivers and remove them. You could also use sysinternals 'autoruns' to stop drivers from running, although doing this overzealously will cause your system to stop booting.

## Troubleshooting
* The script is not tested thorougly, so if you run into issues, look through the code.
* OS is not detected, defaults to Win10. Full list is accessible via `VBoxManage list ostypes`. Grep the script for Windows10_64
* NVM Express (NVMe) i.e SSDs attached through the PCI Express requires VirtualBox 5.2+ and EFI BIOS enabled in the VM. Currently NVMe is converted to SATA, obviously changing the emulated hardware. To retain NVMe as the controller modify the following in the vm script:
** vboxmanage modifyvm ... --firmware efi
** change all reference from VBoxInternal/Devices/pcbios/0 to VBoxInternal/Devices/efi/0
** VBoxManage storagectl "$VMname"  --name "NVMe Controller" --add pcie --controller NVMe --portcount 2
* To see what was options were set on the VM run `vboxmanage getextradata VMname enumerate` or just crack open the .vbox file. It's an XML.
* SMC config is currently not supported (VBoxInternal/Devices/smc/0/Config/DeviceKey, VBoxInternal/Devices/smc/0/Config/GetKeyFromRealSMC that iOS uses)
* CPUID - Even thoguh processor ID is set, it does not seem to be passed to the guest correctly. You might need to set VBoxInternal/CPUM/HostCPUID registers. See this [stack post](https://superuser.com/questions/625648/virtualbox-how-to-force-a-specific-cpu-to-the-guest/774596) for more information.

## Notes on software re-activation

When comparing physical to virtual some differences will show up. They are not significant to cause windows re-activation, but they might cause MS Office to reactivate.
Windows does (re)install a bunch of drivers, including cpu, usb devices etc. and that might **triggered office reactivation warning.** Note though that this does not happen for all versions of office distributions. Some seems to be fine and do not need to be reactivated.
Looking at the Windows Device manager you might see the following differences:

Physical/Virtual:
* Disk drives: **SCSI** disk device/**ATA** Device
* Display Adapters - Intel(R) HD Graphics Family/VirtualBox Graphics Adapter
* HID - four hid devices/one USB hid
* IDA ATA/ATAPI - Intel(R) Chipset Family SATA AHCI Controller/Intel(R) ICH8M SATA AHCI Controller + ATA Channel 0, ATA Channel 1
* Keyboards - Standard 101/102 Key or Microsoft Natural/Standard PS/2 Keyboard
* Mice - Synaptics SMBus TouchPad/HID-compliant mouse, Micorsoft PS/2 mouse
* Monitors - generic PnP monitor/generic **Non-**Pnp monitor
* Netwirk adaptes - Intel Dual Band Wireless AC + Intel Ethernet Connection/Intel Pro/1000 MT Desktop Adapter
* CPU - 4 i7-4600U @ 2.10G — **although this was added into VBoxInternal/Devices/pcbios/0/Config/DmiProcVersion it did not come through the end system, instead the real processor type was exposed. Might need to set VBoxInternal/CPUM/HostCPUID**/2 i7-4790K @ 4G
* Sound - IDT High Dev Audio CODEC/High Definition Audio Device
* System devices - **Many** differences
* USB controllers - Generic Hub+Intel UBM EHC, Intel USB3 XHC,etc/USB Root hub and standart stuff

Only present in the Physical machine:
* Imaging Devices - Webcam
* Security devices - TPM 1.2

Only present on the VM clone:
* CD-Rom **for the vbox guest tools, you can remove it after the tools are installed**

## Other related projects
* [VBox Hardened loader](https://github.com/hfiref0x/VBoxHardenedLoader) (windows host only)
