# Petove, a system virtualizer

This is a bash script that allows you to take a **P**hysical syst**e**m and convert it **to** a **V**irtual clon**e**, resembling the original as close as possible in all aspects of hardware. That includes processor name, motherboard and hard drive serial numbers, MAC and much more.
Using this script you can create a system that is almost indistinguishable from the original from Microsoft Windows' and Office's standpoint, thereby avoiding reactivation of these products. It is also good for systems that have full disk encryption or other products tied to the hardware, like RSA key generators.

* Requires an ability to boot the original system with an external usb
* Uses VirtualBox as the target virtualization platform

## How it works

You run this script after booting your original system with a linux recovery usb. It takes a hardware snapshot and creates another script that you can then run on your VirtualBox host. That script creates the guest VM and configures its virtual hardware.
You will need to clone the source disk with `dd` or `disk2vhd` and then convert it to a format readable by VirtualBox. You don't have to clone blank space. By using the "grow-able" format for the virtual disk, the overall size will match the original, but only take enough space on the host to accommodate your data.

## How to use it

### Prep the source system
If your orignal system is Windows, make sure that AHCI drivers are installed and enabled, since VirtualBox requires them. Open regedit and set `start` to `0` under
````
HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\atapi
HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\iaStor
HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\iaStorV
HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\msahci
HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\pciide
````
Reboot, and go into your BIOS/EFI to make sure that the SATA mode is set to AHCI. Neither VirtualBox, not VMWare have virtual SCSI or RAID/Rapid Recovery interfaces.
Continue booting. Windows will install the missing AHCI drivers on boot.

If Windows fails to boot with the AHCI drivers try installing the drivers inside of the safe mode:

1. Change the BIOS/UEFI setting back to what it was before
2. Boot into Windows. Start cmd as an administrator and instruct windows to boot into the safe next time: `bcdedit /set {current} safeboot minimal`
3. Reboot into BIOS/UEFI and set SATA to AHCI. Reboot into Windows. You will now be in the safe mode with the AHCI drivers installed
4. Start cmd as an administrator and remove the safeboot parameter so the next time Windows loads normally `bcdedit /deletevalue {current} safeboot`

#### Preparing the disk
Next you will need to clone your original system's hard drive. If you have **full disk encryption** enabled (bitlocker, symantec and such), I recommend that you remove it first, since you **should** already be using full disk encryption on your host. This will also allow you to grow and shrink virtual disk using the hypervisor as it will recognize unencrypted blank space as blank space.

The easiest way to remove windows full disk encryption **of any kind** is to take a live snapshot with [disk2vhd](https://docs.microsoft.com/en-us/sysinternals/downloads/disk2vhd) and then convert the VHD into VDI with "vboxmanage convert". I'll not go into details here - look up posts on my [blog](https://securedmind.com) for more info.

Another advantage of disk2vhd is that it only copies used blocks, so the resulting VHD file is compact even before converting to VDI.

Most likely you will also want to shrink the main partition. so that your clone consumes less space on the host than the hard drive size of your original system. To do it clean it as follows:

1. Remove all the extra partitions you do not need. If you have a "System boot" partition, use Windows' Disk Management MMC to delete it and mark your "C:" partition as "boot". Reboot your system to force Windows to move all its systems files to the "C:" partition.
2. Reduce the size of your partition:
    1. Run a cleanup tool like bleachbit and remove any junk you may have.
    2. Disable hibernation to remove the hibernation file.
    3. Reduce or make the swap equal to 0 to minimize (or remove) the swap file.
    4. Use the Disk Management MMC to reduce your "C:" partition size to something that you can afford to have as a virtual disk. If it does not let you reduce the size to what you want, do a defragmentation first.
2. Make sure that your only partition starts at the beginning of the disk. If it does not, use Disk Management or some other partition editing tool (gparted) to move it to the beginning of the disk.
3. If you turned off full disk encryption, run a free space zeroing tool like sdelete or bleachbit's free space clean. This way you will be able to use virtualbox's disk reduce feature after it is converted to vdi, so the disk takes even less space on the host.

### Preparations on the host
1. Make a Linux based recovery OS. [SystemRescueCd](https://www.system-rescue-cd.org/SystemRescueCd_Homepage) is a decent option. Turning the SystemRescue ISO into a USB is a four step process:
    1. Get the ISO, mount it with "-o loop,exec"
    2. Plug the USB without mounting it
    3. Run `./usb_inst.sh` from the mounted iso
2. Copy the code from this repository to a folder on the Linux bootable recovery USB *
3. Find enough space on your host where you will be saving the disk to, to accomodate the "C:" partition you will be cloning. You dont need to fit the full disk of your original system, just the partition.
4. If your host is remote, map the free space to your guest with sshfs for Linux host or smbclient/smbfs for the Windows host.

* If you are running the latest SystemRescueCD (5.1.1+) you do not need `biosdecode`, `dmidecode`, `lsusb`. You will need `nvme` if you have an SSD attach to PCI Express (NVMe) (your disk is /dev/nvme...).
Also note that the executables here are 32 bit, because SystemRescueCD is running in a 32 bit userland even on a 64bit kernel on a 64bit system

### Take a snapshot of your source system
1. Shut the system down and boot into a Linux recovery OS.
2. Mount a remote folder via sshfs or smbfs to some folder, like /mnt/temp
3. Take the fingerprint of the system by running
```
clone-physical-to-virtual.sh systemname
```
This will generate a bash script config_VMname.sh for creating the VM and setting the appropriate parameters
4. Take a snapshot of the disk. clone-physical-to-virtual.sh will give you correct command for the first partition. You only need to copy enough data to cover the size of your partition (i.e. no need to copy the empty space at the end of the disk). Make sure you are copying the full disk, not a partition (eg. /dev/sda not /dev/sda1), so you get the partition table. Here is how to copy a drive with a 50G partition:
```
dd if=/dev/sda of=/mnt/temp/fulldisk.dd bs=1M count=50000
```
(Skip this step if you already took the disk snapshot with disk2vhd)

### Create the virtual clone on your host
1. Convert raw disk image to vdi:
```
vboxmanage convertfromraw fulldisk.dd fulldisk.vdi
```
2. Run the generated config_VMname.sh script.
You can modify the script as necessary, or recreate it by running clone-physical-to-virtual.sh with the data you captured before in the same folder.
If your target host is windows, convert bash to batch, or run bash under windows bash/cygwin.

3. The last step after your clone is running in the VM environment is to go in and clean all the remaining drivers. Make sure to also show hidden drivers and remove them. You could also use sysinternals 'autoruns' to stop drivers from running, although doing this overzealously will cause your system to stop booting.

## Limitations
* The script is not tested thorougly, so if you run into issues, look through the code.
* OS is not detected, defaults to Win10. Full list is accessible via `VBoxManage list ostypes`. Grep the script for Windows10_64 to change it
* TPM is not currently emulated by VirtualBox, so things that tie into it (e.g. win10 pin login, bitlocker) will stop functioning properly.
* NVM Express (NVMe), i.e SSDs attached through the PCI Express requires VirtualBox 5.2+ and EFI BIOS enabled in the VM. Currently NVMe is converted to SATA, obviously changing the emulated hardware. To retain NVMe as the controller modify the following in the vm script:
 * vboxmanage modifyvm ... --firmware efi
 * change all reference from VBoxInternal/Devices/pcbios/0 to VBoxInternal/Devices/efi/0
 * VBoxManage storagectl "$VMname"  --name "NVMe Controller" --add pcie --controller NVMe --portcount 2
* SMC config is currently not supported. To clone iOS add VBoxInternal/Devices/smc/0/Config/DeviceKey and VBoxInternal/Devices/smc/0/Config/GetKeyFromRealSMC manually
* CPUID - Even though processor ID is set via VBoxInternal/Devices/pcbios/0/Config/DmiProcVersion, it does not seem to be passed to the guest correctly. You might need to set VBoxInternal/CPUM/HostCPUID registers. See this [stack post](https://superuser.com/questions/625648/virtualbox-how-to-force-a-specific-cpu-to-the-guest/774596) for more information.

## Notes on software re-activation

When comparing physical to virtual some differences will show up. They are not significant to cause windows re-activation, but they might cause MS Office to reactivate.
Windows does reinstall a bunch of drivers when it detects virtual devices, including cpu, usb devices etc. and that might triggered office reactivation warning. Note though that this does not happen for all versions of office distributions. Some seems to be fine and do not need to be reactivated. Looking at the Windows Device manager you might see the following differences:

* Physical/Virtual: Disk drives, Display Adapters, IDE ATA/ATAPI, Keyboards, Mice, Monitors, Network adapters, CPU, Sound, System devices, USB controllers
* Not in the virtual clone: Imaging Devices (Webcam), Security devices (TPM)
* Not on the original: CD-ROM (used for the vbox guest tools, you can remove it after the tools are installed)

To see what was options were set on the VM run `vboxmanage getextradata VMname enumerate` or just crack open the .vbox file. It's an XML.

## Other related projects
* [VBox Hardened loader](https://github.com/hfiref0x/VBoxHardenedLoader) (windows host only)
