#!/bin/bash

echo "###############################################################"
echo "#                                                             #"
echo "#  You are about to setup a private-cloud all-in-one system.  #"
echo "#  Press [ENTER] to start the installation process            #"
echo "#  or press [CTRL+C] to exit                                  #"
echo "#                                                             #"
echo "###############################################################"

# Wait for the user to press [ENTER]
read

# Start the installation process
echo "Starting the installation process..."

##Define variables

echo "Enter Internal Network Interface Name (Example: ens160)"
read network_if

echo "Enter External Network Interface Name (Example: ens192)"
read neutron_ext_if

echo "Enter Internal VIP Address (Example: 192.168.10.10)" 
read int_vip_address

##Check privilege 
echo "Checking privileges"
die() {
  echo "ERROR: $1"
  exit 1
}

[ $(whoami) = "root" ] || die "This script must be run as root"

##Create cinder volumes
#Check cinder-volumes is exist
echo "Checking cinder-volumes"
if ! vgdisplay | grep -q "cinder-volumes"; then
	echo "Storage not setup. Please enter name of disk for cinder usage (Example: sdb)"
	read cinder_volumes_disk
	if mount | grep $cinder_volumes_disk; then
        umount /dev/$cinder_volumes_disk
        fi

        # Create a physical volume for LVM
        pvcreate /dev/$cinder_volumes_disk

        # Create a volume group
        vgcreate cinder-volumes /dev/$cinder_volumes_disk

        # Create a logical volume using all the free space on the disk
        lvcreate -l 100%FREE -n lv_cinder_volumes cinder-volumes

        # Format the logical volume with the ext4 file system
        mkfs.ext4 /dev/cinder-volumes/lv_cinder_volumes

        # Mount the logical volume to a directory
        mkdir /mnt/$cinder_volumes_disk
        mount /dev/cinder-volumes/lv_cinder_volumes /mnt/$cinder_volumes_disk
else
        echo "Cinder-volumes is ready for deploy"
fi

##Update system packages
echo "Updating your system packages"

apt update && sudo apt upgrade -y

apt autoremove -y

#Set date-time
echo "Setting date & time"

timedatectl set-timezone Asia/Ho_Chi_Minh

#Install python libraries & packages

echo "Install python libraries & packages"
apt install python3-pip python3-dev python3-docker libffi-dev gcc libssl-dev git -y

#Install virtualenv
echo "Setting up virtual environment"
apt install python3-venv python3-virtualenv -y

#Create virtual environment

if [ ! -d "$HOME/private-cloud" ]; then
python3 -m venv $HOME/private-cloud

else
	rm -rf "$HOME/private-cloud"
	python3 -m venv $HOME/private-cloud
fi

# Activate virtual environment
echo "Active venv & setting up kolla packages"
source $HOME/private-cloud/bin/activate

#Upgrade pip tools
pip install -U pip

#Install Ansible
pip install -U 'ansible>=4,<6'

#Install kolla-ansible and its dependencies using pip
pip install "kolla-ansible==15.0.0"

#pip install git+https://opendev.org/openstack/kolla-ansible@stable/zed

#Install Ansible Galaxy requirements
kolla-ansible install-deps

##Prepare configs file for deployment

#Create & tuning ansible
echo "Tunning ansible configs"

if [[ ! -e /etc/ansible/ansible.cfg ]]; then
    mkdir -p /etc/ansible
    touch /etc/ansible/ansible.cfg
fi

#Tunning ansible
cat << EOF > /etc/ansible/ansible.cfg
[defaults]
host_key_checking=False
pipelining=True
forks=100
EOF

#Create the /etc/kolla directory
echo "Create kolla config directory"
[ ! -d "/etc/kolla" ] && mkdir -p /etc/kolla
chown $USER:$USER /etc/kolla

#Copy file config template
echo "Copying config teplate files"
cp -r $HOME/private-cloud/share/kolla-ansible/etc_examples/kolla/* /etc/kolla/
cp -r $HOME/private-cloud/share/kolla-ansible/ansible/inventory/* /etc/kolla/

#Backup original config files
echo "Backing up config files"
cd /etc/kolla
cp all-in-one all-in-one.bak
cp globals.yml globals.bak

##Git clone config file template
echo "Clone config template files"
cd $HOME
[ -d "private-cloud-templates" ] && rm -rf private-cloud-templates
git clone https://github.com/nhanhd2702/private-cloud-templates.git
cp private-cloud-templates/libs/aio/all-in-one /etc/kolla/
cp private-cloud-templates/libs/aio/globals.yml /etc/kolla/

#Update globals.yml 
echo "Update global variables"
sed -i "s/int_if/$network_if/" /etc/kolla/globals.yml
sed -i "s/ext_if/$neutron_ext_if/" /etc/kolla/globals.yml
sed -i "s/int_vip_ip/$int_vip_address/" /etc/kolla/globals.yml
#
##Generate setup passwords
echo "Generate setup passwords"
kolla-genpwd

## Finish pre-config for openstack 
echo "+--------------------------------------------------------+"
echo "|                                                        |"
echo "|  Preparation is complete.                              |"
echo "|  Please run the deployment script to continue.         |"
echo "|                                                        |"
echo "+--------------------------------------------------------+"
echo "Press Enter to continue."
read -p ""
