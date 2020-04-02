#!/bin/bash
# Install files related to making sound work

PROG_PATH=${PROG_PATH:-$(readlink -e $0)}
PROG_DIR=${PROG_DIR:-$(dirname ${PROG_PATH})}
PROG_NAME=${PROG_NAME:-$(basename ${PROG_PATH})}

VBOX_DIR=${PROG_DIR}/../virtualbox

if [ ! -d ${VBOX_DIR} ]; then
    echo "VBOX_DIR not a directory: $VBOX_DIR"
    exit 0
fi
VBOX_DIR=$(readlink -e $VBOX_DIR)
test "$(ls -A $VBOX_DIR)"
if [ $? -ne 0 ]; then
    echo "No files to copy: $VBOX_DIR"
    exit 0
fi
for svc_file in vbox_client_integration.service virt_what_virtualbox.service
do
    svc_file_path=${VBOX_DIR}/virtualbox/services/$svc_file
    if [ ! -f "$svc_file_path" ]; then
        echo "service file not found: $svc_file_path"
        exit 0
    fi
done

mkdir -p /root
cp -r ${VBOX_DIR}/virtualbox /root/

# On Ubuntu 17.10 systemd provides the system-wide DNS resolver
# On such distributions, /etc/resolv.conf inside the ISO points
# at ../run/systemd/resolve/stub-resolv.conf and the target will not
# exist IFF you are remastering on an older distribution

# We detect that there is no nameserver line in /etc/resolv.conf
# and if so, we move the existing /etc/resolv.conf aside and 
# replace it with a file pointing at Google Public DNS
# At the end of the script we restore the original /etc/resolv.conf

function install_virtualbox_guest_dkms() {
    local EXISTING_DEB="${VBOX_DIR}/virtualbox-guest-dkms.deb"
    if [ -f "$EXISTING_DEB" ]; then
        echo "Installing downloaded DEB: $EXISTING_DEB"
        dpkg -i "$EXISTING_DEB"
        if [ $? -ne 0 ]; then
            apt-get -f install --no-install-recommends --no-install-suggests
            return $?
        fi
    else
        echo "DEB not found: $EXISTING_DEB"
        local REQUIRED_PKGS="virtualbox-guest-dkms"
        apt-get update 2>/dev/null
        echo "Installing $REQUIRED_PKGS"
        apt-get install -y $REQUIRED_PKGS 2>/dev/null
        local ret=$?
        if [ $ret -ne 0 ]; then
            echo "Install failed: $REQUIRED_PKGS"
            apt-get -f install 2>/dev/null
            return 1
        fi
    fi
}

ORIG_RESOLV_CONF=/etc/resolv.conf.remaster_orig
cat /etc/resolv.conf 2>/dev/null | grep -q '^nameserver'
if [ $? -ne 0 ]; then
    echo "Replacing /etc/resolv.conf"
    mv /etc/resolv.conf $ORIG_RESOLV_CONF
    echo -e "nameserver   8.8.8.8\nnameserver  8.8.4.4" > /etc/resolv.conf
fi

install_virtualbox_guest_dkms

# Restore original /etc/resolv.conf if we had moved it
if [ -f  $ORIG_RESOLV_CONF -o -L $ORIG_RESOLV_CONF ]; then
    echo "Restoring original /etc/resolv.conf"
    \rm -f /etc/resolv.conf
    mv  $ORIG_RESOLV_CONF /etc/resolv.conf
fi

# Setup and enable services
# First copy the new service files (anyway)
VBOX_DIR=/root/virtualbox
if [ ! -d ${VBOX_DIR}/services ]; then
    echo "virtualbox integration services dir not found: ${VBOX_DIR}/services"
    exit 0
fi
svc_dir=${VBOX_DIR}/services
for svc_file in vbox_client_integration.service virt_what_virtualbox.service
do
    if [ ! -f ${svc_dir}/$svc_file ]; then
        echo "Service file not found: ${svc_dir}/svc_file"
        continue
    fi
    cp ${svc_dir}/$svc_file /etc/systemd/system/
done    

# Another check - using systemd
SYSTEMD_PAGER="" systemctl --plain list-unit-files virtualbox-guest-utils.service | grep -q virtualbox-guest-utils.service
if [ $? -ne 0 ]; then
    echo "virtualbox-guest-utils.service not found"
    exit 0
fi
cd /etc/systemd/system
systemctl daemon-reload
for svc in vbox_client_integration.service virt_what_virtualbox.service
do
    systemctl enable $svc
done
