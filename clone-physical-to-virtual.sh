#!/bin/bash
# a script to take a fingerprint of the hardware for the system it's run on and create a script that creates a VirtualBox VM with virtual hardware matching the real hardware
# VBoxManage documentation - https://www.virtualbox.org/manual/ch08.html

if [[ $# == 0 ]]; then
    echo $0  [-f] [name of the vm]
    echo "\t -f force to script to capture system information even if it's already present"
    exit 1
fi

if [[ $1 == -f || ! -f dmi0.report ]]; then
    echo Capturing current hardware configuration...
    PATH="./:$PATH" # use local commands if they are available
    dmidecode -t0 > dmi0.report
    dmidecode -t1 > dmi1.report
    dmidecode -t2 > dmi2.report #to get human readable info
    dmidecode -t2 -u  > dmi2.raw #to avoid overzealous decoding of numerical values into strings - virtualbox expects a number for DmiBoardBoardType, not a name)
    dmidecode -t3  > dmi3.report
    dmidecode -t3 -u  > dmi3.raw # same again, keep DmiChassisType numerical
    dmidecode -t4  > dmi4.report
    dmidecode -t11  > dmi11.report
    dmidecode -t11 -u > dmi11.raw
    hdparm -I /dev/sda > hdparm-sda.report 2>/dev/null # (capital i, not L)
    dd if=/sys/firmware/acpi/tables/SLIC of=SLIC.bin 2>/dev/null # (might want to get all others from the same acpi/tables table too)
    dd if=/sys/firmware/acpi/tables/DSDT of=DSDT_BIN 2>/dev/null # can also be done wiht  acpidump -t DSDT -o DSDT_BIN -b
    # lshw number of processor cores, ram, same (total) disk space and a network card, same video card memory
    lshw > lshw.report
    # disk partitions
    fdisk -l > fdisk.report
    # the following dumps are not strictly necessary, just in case
    dmidecode > dmi-all.report
    dmidecode --dump-bin dmi.bin
    biosdecode > bios.report
    lspci > lspci.report
    lsusb > lsusb.report
    #ifconfig > ifconfig.report
fi

if [[ $1 == -f ]]; then
    VMname=$2
else
    VMname=$1
fi
config_script=config_$VMname.sh


setParam() {
    # Config routine for file parsing and echoing proper commands
    # $1 - VM name
    # $2 - parsing type (regexp, hex, verbatim or string parsing)
    # $3 - argument for the parser
    # $4 - file name to parse
    if [[ $2 == "rgx" ]]; then  # use regexp verbatim
        val=$(sed -n "s/$3/\1/p" $4 | sed -e 's/^[[:space:]]*//;s/[[:space:]]*$//') # second sed is a trimmer
    elif [[ $2 == "hex" ]]; then # decode nth header hex into dec
        val=$(awk -Wposix '/Header and Data/{getline; printf("%d\n","0x" $'$3')}' $4)
    elif [[ $2 == "val" ]]; then # verbatim value
        val=$3
    else # standard parsing
        val=$(sed -n "s/.*$3: \(.*\)/\1/p" $4 | sed -e 's/^[[:space:]]*//;s/[[:space:]]*$//') # second sed is a trimmer
    fi
    if [[ -n $val && $val != "Not Specified" ]]; then
        if [[ $2 == "str" ]]; then
            val="string:$val"
        fi
        echo "VBoxManage setextradata \"$VMname\" \"$1\" \"$val\"" >> $config_script
    fi
}

echo Creating $config_script.
echo "#!/bin/bash" > $config_script
echo "set -euo pipefail" >> $config_script

# Sanity check
echo "if [[ ! -f \"$VMname.vdi\" ]]; then" >> $config_script
echo "  echo No disk clone \"$VMname.vdi\" found. Make sure to cloned the source with dd and convert with vboxmanage convertfromraw"  >> $config_script
# for disk size use LBA48 multiplied by 512
val=$(sed -nr "s/\s*LBA48  user addressable sectors:\s*(.*)/\1/p" hdparm-sda.report)
echo "  echo To create an empty disk of the same size as the source run"   >> $config_script
echo "  echo VBoxManage createmedium disk --filename \"$VMname.vdi\" --sizebyte $((val*512)) --format VDI --variant Standard"  >> $config_script
echo -e "  exit\nfi"   >> $config_script

# Create a VM with the same number of processors, same ram, same (total) disk space and a network card, same video card memory
echo "# Create VM" >> $config_script
# TODO detect ostype or select from vboxmanage list ostypes
echo "VBoxManage createvm --name \"$VMname\" --ostype \"Windows7_64\" --register" >> $config_script # Todo add  --ostype <ostype> from VBoxManage list ostypes

# Sets the amount of RAM, in MB, CPUs
memgib=$(sed -nr "/\s*\*-memory/,/size:/s/\s*size:\s*(.*)GiB/\1/ p" lshw.report)
# parse the lines between  *-cpu and configuration: cores=2 enabledcores=2 threads=4. threads is the number of "cpus" exposed to the os
threads=$(sed -nr "/\s*\*-cpu/,/configuration:/s/\s*configuration:.*threads=(.*)/\1/ p" lshw.report)
# todo may need to tweak other settings like PAE/VT-x, NX,CPU architecture, firmware (BIOS/EFI), APIC, HPET, ACPI etc.
echo "VBoxManage modifyvm \"$VMname\" --memory $((memgib*1024)) --cpus $threads --vram 64 --ioapic on --usb on --usbehci on" >> $config_script

# Audio settings depend highly on the vm host
echo "VBoxManage modifyvm \"$VMname\" --audio alsa --audiocontroller ac97" >> $config_script
echo "VBoxManage storagectl \"$VMname\"  --name \"SATA Controller\" --add sata --controller IntelAHCI --portcount 2" >> $config_script
echo "VBoxManage storageattach \"$VMname\" --storagectl \"SATA Controller\" --device 0 --port 0 --type hdd --medium \"$VMname.vdi\"" >> $config_script

# Network - get MACs, set the first as active, rest as disconnected
val=$(sed -nr "/\s*\*-network/,/serial:/s/\s*serial:\s*(..):(..):(..):(..):(..):(..)/\1\2\3\4\5\6/ p" lshw.report | awk '{print $1}')
j=1;
for i in $val; do
    if [[ $j == 1 ]]; then
        echo "VBoxManage modifyvm \"$VMname\" --nic1 nat --macaddress1 $i" >> $config_script
    else
        echo "VBoxManage modifyvm \"$VMname\" --nic$j null --macaddress$j $i" >> $config_script
    fi
    (( j++ ))
done

# If a DMI string is not set, the default value of VirtualBox is used. If the value is empty ignore it. You could try to set an empty you can string by using "<EMPTY>" but it might not do anything/
# All quoted parameters (DmiBIOSVendor, DmiBIOSVersion but not DmiBIOSReleaseMajor) are expected to be strings. If such a string is a valid number, the parameter is treated as number and the VM will most probably refuse to start with an VERR_CFGM_NOT_STRING error. In that case, use "string:<value>", for instance
# VBoxManage setextradata "$VMname" "VBoxInternal/Devices/pcbios/0/Config/DmiSystemSerial"      "string:1234"

echo "# BIOS (dmi type 0)" >> $config_script
setParam "VBoxInternal/Devices/pcbios/0/Config/DmiBIOSVendor"        str "Vendor" dmi0.report
setParam "VBoxInternal/Devices/pcbios/0/Config/DmiBIOSVersion"       str "Version" dmi0.report
setParam "VBoxInternal/Devices/pcbios/0/Config/DmiBIOSReleaseDate"   str "Release Date" dmi0.report
setParam "VBoxInternal/Devices/pcbios/0/Config/DmiBIOSReleaseMajor"  rgx ".*BIOS Revision:\s\(.*\)\..*" dmi0.report # grep BIOS Revision (first number)
setParam "VBoxInternal/Devices/pcbios/0/Config/DmiBIOSReleaseMinor"  rgx ".*BIOS Revision:\s.*\.\(.*\)" dmi0.report # grep BIOS Revision (second number)
setParam "VBoxInternal/Devices/pcbios/0/Config/DmiBIOSFirmwareMajor" rgx ".*Firmware Revision:\s\(.*\)\..*" dmi0.report # may not be in dmi0
setParam "VBoxInternal/Devices/pcbios/0/Config/DmiBIOSFirmwareMinor" rgx ".*Firmware Revision:\s.*\.\(.*\)" dmi0.report # may not be in dmi0

echo "# System (dmi type 1)" >> $config_script
setParam "VBoxInternal/Devices/pcbios/0/Config/DmiSystemVendor"    str "Manufacturer" dmi1.report
setParam "VBoxInternal/Devices/pcbios/0/Config/DmiSystemProduct"   str "Product Name" dmi1.report
setParam "VBoxInternal/Devices/pcbios/0/Config/DmiSystemVersion"   str "Version" dmi1.report
setParam "VBoxInternal/Devices/pcbios/0/Config/DmiSystemSerial"    str "Serial Number" dmi1.report
setParam "VBoxInternal/Devices/pcbios/0/Config/DmiSystemSKU"       str "SKU Number" dmi1.report
setParam "VBoxInternal/Devices/pcbios/0/Config/DmiSystemFamily"    str "Family" dmi1.report
setParam "VBoxInternal/Devices/pcbios/0/Config/DmiSystemUuid"      str "UUID" dmi1.report

echo "# Board (dmi type 2)" >> $config_script
setParam "VBoxInternal/Devices/pcbios/0/Config/DmiBoardVendor"       str "Manufacturer" dmi2.report
setParam "VBoxInternal/Devices/pcbios/0/Config/DmiBoardProduct"      str "Product Name" dmi2.report
setParam "VBoxInternal/Devices/pcbios/0/Config/DmiBoardVersion"      str "Version" dmi2.report
setParam "VBoxInternal/Devices/pcbios/0/Config/DmiBoardSerial"       str "Serial Number" dmi2.report
setParam "VBoxInternal/Devices/pcbios/0/Config/DmiBoardAssetTag"     str "Asset Tag" dmi2.report
setParam "VBoxInternal/Devices/pcbios/0/Config/DmiBoardLocInChass"   str "Location In Chassis" dmi2.report
setParam "VBoxInternal/Devices/pcbios/0/Config/DmiBoardBoardType"    hex 14 dmi2.raw   # 14th byte in the header of the undecoded dmi in a decimal form" >> $config_script

echo "# Chassis (system enclosure)    (dmi type 3)" >> $config_script
setParam "VBoxInternal/Devices/pcbios/0/Config/DmiChassisVendor"     str "Manufacturer" dmi3.report
setParam "VBoxInternal/Devices/pcbios/0/Config/DmiChassisType"       hex 6 dmi3.raw # 6th byte in the header of chassis dmi, in decimal" >> $config_script
setParam "VBoxInternal/Devices/pcbios/0/Config/DmiChassisVersion"    str "Version" dmi3.report
setParam "VBoxInternal/Devices/pcbios/0/Config/DmiChassisSerial"     str "Serial Number" dmi3.report
setParam "VBoxInternal/Devices/pcbios/0/Config/DmiChassisAssetTag"   str "Asset Tag" dmi3.report

echo "# Processor    (dmi type 4)" >> $config_script
setParam "VBoxInternal/Devices/pcbios/0/Config/DmiProcManufacturer"  str "Manufacturer" dmi4.report
setParam "VBoxInternal/Devices/pcbios/0/Config/DmiProcVersion"       str "Version" dmi4.report

echo "# OEM strings    (dmi type 11)" >> $config_script
setParam "VBoxInternal/Devices/pcbios/0/Config/DmiOEMVBoxVer"        str "String 1" dmi11.report
setParam "VBoxInternal/Devices/pcbios/0/Config/DmiOEMVBoxRev"        str "String 2" dmi11.report

echo "# Custom ACPI tables" >> $config_script
# Might thy DSDT table here instead of the SLIC table
echo 'vmscfgdir=$(VBoxManage showvminfo "'$VMname'" | sed -n "s/Config file:\s*\(.*\)\/.*/\1/p")' >> $config_script
echo 'if [[ ! -f "$vmscfgdir/SLIC.bin" ]]; then cp SLIC.bin "$vmscfgdir/SLIC.bin"; fi' >> $config_script
#setParam "VBoxInternal/Devices/acpi/0/Config/CustomTable"            val "$vmscfgdir/SLIC.bin"
setParam "VBoxInternal/Devices/acpi/0/Config/CustomTable"            val "\$vmscfgdir/SLIC.bin"

echo "# hdd - sata " >> $config_script
setParam "VBoxInternal/Devices/ahci/0/Config/Port0/ModelNumber"      str "Model Number" hdparm-sda.report
setParam "VBoxInternal/Devices/ahci/0/Config/Port0/SerialNumber"     str "Serial Number" hdparm-sda.report
setParam "VBoxInternal/Devices/ahci/0/Config/Port0/FirmwareRevision" str "Firmware Revision" hdparm-sda.report

# to use IDE  use the following variables instead:
#setParam "VBoxInternal/Devices/piix3ide/0/Config/PrimaryMaster/SerialNumber"
#setParam "VBoxInternal/Devices/piix3ide/0/Config/PrimaryMaster/FirmwareRevision"
#setParam "VBoxInternal/Devices/piix3ide/0/Config/PrimaryMaster/ModelNumber"

# to add cdrom from lshw (grep for cdrom)
#setParam "VBoxInternal/Devices/ahci/0/Config/Port0/ATAPIVendorId"
#setParam "VBoxInternal/Devices/ahci/0/Config/Port0/ATAPIProductId"
#setParam "VBoxInternal/Devices/ahci/0/Config/Port0/ATAPIRevision"

echo "# ACPI (bios)" >> $config_script
setParam "VBoxInternal/Devices/acpi/0/Config/AcpiOemId" str "OEM Identifier" bios.report

# other tables you can try (may not be very useful):
#echo "VBoxManage  setextradata \"$VMname\" \"VBoxInternal/Devices/acpi/0/Config/DsdtFilePath\" \"%vmscfgdir%ACPI-DSDT.bin
#echo "VBoxManage  setextradata \"$VMname\" \"VBoxInternal/Devices/acpi/0/Config/SsdtFilePath\" \"%vmscfgdir%ACPI-SSDT1.bin
#echo "VBoxManage  setextradata \"$VMname\" \"VBoxInternal/Devices/vga/0/Config/BiosRom\" \"$vmscfgdir/videorom.bin
#echo "VBoxManage  setextradata \"$VMname\" \"VBoxInternal/Devices/pcbios/0/Config/BiosRom\" \"$vmscfgdir/pcbios.bin
#echo "VBoxManage  setextradata \"$VMname\"  \"VBoxInternal/Devices/pcbios/0/Config/LanBootRom\" \"$vmscfgdir/pxerom.bin

echo "# Other usefull stuff (disabled by default)" >> $config_script
# useful for reading the bluescreen info
echo "#VBoxManage setextradata \"$VMname\" \"VBoxInternal/PDM/HaltOnReset\" 1" >> $config_script
echo "#VBoxManage setextradata \"$VMname\" CustomVideoMode1 1600x900x32" >> $config_script
echo "#VBoxManage modifyvm \"$VMname\" --bioslogoimagepath  \"\$vmscfgdir/splash.bmp\"" >> $config_script
chmod u+x $config_script

echo Now you need to clone the disk itself:
val=$(grep /dev/sda1 fdisk.report | awk '{print $4}')
# 512 is the default logical sector size, plus 1 for the rounding
echo dd if=/dev/sda of=\"$VMname.raw\" bs=1000000 count=$((val*512/1000000+1))
