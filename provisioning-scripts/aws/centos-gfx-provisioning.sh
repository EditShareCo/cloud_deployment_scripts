Content-Type: multipart/mixed; boundary="//"
MIME-Version: 1.0

--//
Content-Type: text/cloud-config; charset="us-ascii"
MIME-Version: 1.0
Content-Transfer-Encoding: 7bit
Content-Disposition: attachment; filename="cloud-config.txt"

#cloud-config
cloud_final_modules:
- [scripts-user, always]

--//
Content-Type: text/x-shellscript; charset="us-ascii"
MIME-Version: 1.0
Content-Transfer-Encoding: 7bit
Content-Disposition: attachment; filename="userdata.txt"

#!/bin/bash

# Copyright (c) 2021 Teradici Corporation
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

######################
# Required Variables #
######################
# REQUIRED: You must fill in this value before running the script
PCOIP_REGISTRATION_CODE=""

######################
# Optional Variables #
######################
# NOTE: Fill both USERNAME and TEMP_PASSWORD to create login credential, 
# otherwise please SSH into workstation to add user and set password.
# Please change password upon first login.
USERNAME=""
TEMP_PASSWORD=""
# You can use the default value set here or change it
NVIDIA_DRIVER_URL="https://s3.amazonaws.com/ec2-linux-nvidia-drivers/grid-12.0/NVIDIA-Linux-x86_64-460.32.03-grid-aws.run"
TERADICI_DOWNLOAD_TOKEN="yj39yHtgj68Uv2Qf"

exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

LOG_FILE="/var/log/teradici/provisioning.log"
METADATA_IP="http://169.254.169.254"
TERADICI_REPO_SETUP_SCRIPT_URL="https://dl.teradici.com/$TERADICI_DOWNLOAD_TOKEN/pcoip-agent/cfg/setup/bash.rpm.sh"

log() {
    local message="$1"
    echo "[$(date)] $message"
}

# Try command until zero exit status or exit(1) when non-zero status after max tries
retry() {
    local retry="$1"         # number of retries
    local retry_delay="$2"   # delay between each retry, in seconds
    local shell_command="$3" # the shell command to run
    local err_message="$4"   # the message to show when the shell command was not successful

    local retry_num=0
    until eval $shell_command
    do
        local rc=$?
        local retry_remain=$((retry-retry_num))

        if [ $retry_remain -eq 0 ]
        then
            log $error_message
            return $rc
        fi

        log "$err_message Retrying in $retry_delay seconds... ($retry_remain retries remaining...)"

        retry_num=$((retry_num+1))
        sleep $retry_delay
    done
}

check_required_vars() {
    set +x
    if [[ -z "$PCOIP_REGISTRATION_CODE" ]]; then
        log "--> ERROR: Missing PCoIP Registration Code."
        missing_vars="true"
    fi

    set -x

    if [[ "$missing_vars" = "true" ]]; then
        log "--> Exiting..."
        exit 1
    fi
}

exit_and_restart() {
    log "--> Rebooting..."
    (sleep 1; reboot -p) &
    exit
}

install_kernel_header() {
    log "--> Installing kernel headers and development packages..."
    yum install kernel-devel kernel-headers -y
    if [[ $? -ne 0 ]]; then
        log "--> ERROR: Failed to install kernel header."
        exit 1
    fi

    yum install gcc -y
    if [[ $? -ne 0 ]]; then
        log "--> ERROR: Failed to install gcc."
        exit 1
    fi
}

remove_nouveau() {
        log "--> Disabling the Nouveau kernel driver..."
        for driver in vga16fb nouveau nvidiafb rivafb rivatv; do
            echo "blacklist $driver" >> /etc/modprobe.d/blacklist.conf
        done

        sed -i 's/\(^GRUB_CMDLINE_LINUX=".*\)"/\1 rdblacklist=nouveau"/' /etc/default/grub
        grub2-mkconfig -o /boot/grub2/grub.cfg
}

# Download installation script and run to install NVIDIA driver
install_gpu_driver() {
    # the first part to check if GPU is attached
    # NVIDIA VID = 10DE
    # Display class code = 0300
    # the second part to check if the NVIDIA driver is installed
    if [[ $(lspci -d '10de:*:0300' -s '.0' | wc -l) -gt 0 ]] && ! (modprobe --resolve-alias nvidia > /dev/null 2>&1)
    then
        log "--> Installing GPU driver..."

        local nvidia_driver_filename=$(basename $NVIDIA_DRIVER_URL)
        local gpu_installer="/root/$nvidia_driver_filename"

        log "--> Killing X server before installing driver..."
        systemctl stop gdm

        log "--> Downloading GPU driver $nvidia_driver_filename to $gpu_installer..."
        retry   3 `# 3 retries` \
                5 `# 5s interval` \
                "curl -f -o $gpu_installer $NVIDIA_DRIVER_URL" \
                "--> ERROR: Failed to download GPU driver installer."
        if [ $? -eq 1 ]; then
            exit 1
        fi
        log "--> GPU driver installer successfully downloaded"

        chmod u+x "$gpu_installer"
        log "--> Running GPU driver installer..."
        # -s, --silent Run silently; no questions are asked and no output is printed,
        # This option implies '--ui=none --no-questions'.
        # -X, --run-nvidia-xconfig
        # -Z, --disable-nouveau
        # --sanity Perform basic sanity tests on an existing NVIDIA driver installation.
        # --uninstall Uninstall the currently installed NVIDIA driver.
        # using dkms cause kernel rebuild and installation failure
        if "$gpu_installer" -s -Z -X
        then
            log "--> GPU driver installed successfully."
        else
            log "--> ERROR: Failed to install GPU driver."
            exit 1
        fi
    fi
}

# Enable persistence mode
enable_persistence_mode() {
    # the first part to check if the NVIDIA driver is installed
    # the second part to check if persistence mode is enabled
    if (modprobe --resolve-alias nvidia > /dev/null 2>&1) && [[ $(nvidia-smi -q | awk '/Persistence Mode/{print $NF}') != "Enabled" ]]
    then
        log "--> Enabling persistence mode..."

        # tar -xvjf /usr/share/doc/NVIDIA_GLX-1.0/sample/nvidia-persistenced-init.tar.bz2 -C /tmp
        # chmod +x /tmp/nvidia-persistenced-init/install.sh
        # /tmp/nvidia-persistenced-init/install.sh
        # local exitCode=$?
        # rm -rf /tmp/nvidia-persistenced-init
        # if [[ $exitCode -ne 0 ]]

        # Enable persistence mode
        # based on document https://docs.nvidia.com/deploy/driver-persistence/index.html,
        # Persistence Daemon shall be used in future
        if (nvidia-smi -pm ENABLED)
        then
            log "--> Persistence mode is enabled successfully"
        else
            log "--> ERROR: Failed to enable persistence mode."
            exit 1
        fi
    fi
}

install_pcoip_agent() {
    log "--> Getting Teradici PCoIP agent repo..."
    curl --retry 3 --retry-delay 5 -u "token:$TERADICI_DOWNLOAD_TOKEN" -1sLf $TERADICI_REPO_SETUP_SCRIPT_URL | bash
    if [ $? -ne 0 ]; then
        log "--> ERROR: Failed to install PCoIP agent repo."
        exit 1
    fi
    log "--> PCoIP agent repo installed successfully."

    log "--> Installing USB dependencies..."
    retry   3 `# 3 retries` \
            5 `# 5s interval` \
            "yum install -y usb-vhci" \
            "--> Warning: Failed to install usb-vhci."

    log "--> Installing PCoIP graphics agent..."
    retry   3 `# 3 retries` \
            5 `# 5s interval` \
            "yum -y install pcoip-agent-graphics" \
            "--> ERROR: Failed to download PCoIP agent."
    if [ $? -ne 0 ]; then
        exit 1
    fi
    log "--> PCoIP agent installed successfully."

    set +x
    if [[ "$PCOIP_REGISTRATION_CODE" ]]; then
        log "--> Registering PCoIP agent license..."
        n=0
        while true; do
            /usr/sbin/pcoip-register-host --registration-code="$PCOIP_REGISTRATION_CODE" && break
            n=$[$n+1]

            if [ $n -ge 10 ]; then
                log "--> ERROR: Failed to register PCoIP agent after $n tries."
                exit 1
            fi

            log "--> ERROR: Failed to register PCoIP agent. Retrying in 10s..."
            sleep 10
        done
        log "--> PCoIP agent registered successfully."

    else
        log "--> No PCoIP Registration Code provided. Skipping PCoIP agent registration..."
    fi
    set -x
}

# Open up firewall for PCoIP Agent. By default eth0 is in firewall zone "public"
update_firewall() {
    log "--> Adding 'pcoip-agent' service to public firewall zone..."
    firewall-offline-cmd --zone=public --add-service=pcoip-agent
    systemctl enable firewalld
    systemctl start firewalld
}

# A flag to indicate if this is run from reboot
RE_ENTER=0

if (rpm -q pcoip-agent-graphics); then
    exit
fi

if [[ ! -f "$LOG_FILE" ]]
then
    mkdir -p "$(dirname $LOG_FILE)"
    touch "$LOG_FILE"
    chmod +644 "$LOG_FILE"
else
    RE_ENTER=1
fi

log "$(date)"

# Print all executed commands to the terminal
set -x

# Redirect stdout and stderr to the log file
exec &>>$LOG_FILE

check_required_vars

if [[ $RE_ENTER -eq 0 ]]
then
    set +x
    # Add a user and give the user a password so a user can start 
    # a PCoIP session without having to first create password via SSH
    # if USERNAME and TEMP_PASSWORD were provided
    if [[ "$TEMP_PASSWORD" && "$USERNAME" ]]
    then
        useradd $USERNAME
        echo $USERNAME:$TEMP_PASSWORD | chpasswd
        log "--> User and TEMP_PASSWORD has been set."
    else
        log "--> USERNAME or TEMP_PASSWORD not provided. Skip creating user..."
    fi

    set -x
    # EPEL needed for GraphicsMagick-c++, required by PCoIP Agent
    yum -y install epel-release
    yum -y update
    yum install -y wget awscli jq

    # Install GNOME and set it as the desktop
    log "--> Installing Linux GUI..."
    yum -y groupinstall "GNOME Desktop" "Graphical Administration Tools"

    log "--> Setting default to graphical target..."
    systemctl set-default graphical.target

    remove_nouveau

    exit_and_restart
else
    install_kernel_header

    install_gpu_driver

    enable_persistence_mode
    
    if (rpm -q pcoip-agent-graphics)
    then
        log "--> pcoip-agent-graphics is already installed."
    else
        install_pcoip_agent
    fi

    update_firewall

    log "--> Installation is complete!"

    exit_and_restart
fi
