#! /bin/bash

dnf config-manager --add-repo=https://mirror.stream.centos.org/10-stream/AppStream/x86_64/os/ && dnf install -y --nogpgcheck afterburn e2fsprogs && dnf clean all && dnf config-manager --set-disabled "*centos*"
cat <<EOF > /etc/systemd/system/afterburn-checkin.service
[Unit]
ConditionKernelCommandLine=
ConditionVirtualization=microsoft

[Service]
ExecStart=
ExecStart=/usr/bin/afterburn --provider=azure --check-in
EOF
ln -s ../afterburn-checkin.service /etc/systemd/system/multi-user.target.wants/afterburn-checkin.service

tar -xzvf /tmp/podvm-binaries.tar.gz -C /
tar -xzvf /tmp/pause-bundle.tar.gz -C /
# set luks
# TODO: move to payload ?
tar -xzvf /tmp/luks-config.tar.gz -C /

# fixes a failure of the podns@netns service
semanage fcontext -a -t bin_t /usr/sbin/ip && restorecon -v /usr/sbin/ip

systemctl enable /etc/systemd/system/luks-scratch.service

# Configuration to make PCR values to be printed at boot
cat <<EOF > /usr/libexec/gen-issue
#!/usr/bin/env bash

set -euo pipefail

if ! tpm2_pcrread sha256:0 > /dev/null 2>&1; then
   echo "No vTPM detected"
   exit 0
fi

mkdir -p /run/issue.d

rm -f /etc/issue.net
rm -f /etc/issue
{
  echo "Detected vTPM PCR values:"
  /usr/bin/tpm2_pcrread sha256:all
  echo
} > /run/issue.d/30-pcrs.issue
EOF

# this will allow /run/issue and /run/issue.d to take precedence
mv /etc/issue.d /usr/lib/issue.d || true
rm -f /etc/issue.net
rm -f /etc/issue

chmod +x /usr/libexec/gen-issue
cat  <<EOF > /etc/systemd/system/gen-issue.service
[Unit]
Description=Generate issue to print to serial console at startup
Before=serial-getty@ttyS0.service
After=process-user-data.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/libexec/gen-issue

[Install]
WantedBy=multi-user.target
EOF
ln -s ../gen-issue.service /etc/systemd/system/multi-user.target.wants/gen-issue.service

# configuration to extend PCR8 with the initdata.digest
mkdir -p /etc/systemd/system/process-user-data.service.d/
cat  <<EOF > /etc/systemd/system/process-user-data.service.d/10-override.conf
[Service]
# mount config disk if available
ExecStartPre=-/bin/mount -t iso9660 -o ro /dev/disk/by-label/cidata /media/cidata
# The digest is a string in hex representation, we truncate it to a 32 bytes hex string
ExecStartPost=-/bin/bash -c 'tpm2_pcrextend 8:sha256=\$(head -c64 /run/peerpod/initdata.digest)'
EOF

#nv
export KERNEL_VERSION=$(rpm -q --qf "%{VERSION}" kernel-core)
export KERNEL_RELEASE=$(rpm -q --qf "%{RELEASE}" kernel-core | sed 's/\.el.\(_.\)*$//')
export ARCH=$(uname -m)
dnf install -y gcc kernel-devel-${KERNEL_VERSION}-${KERNEL_RELEASE} kernel-devel-matched-${KERNEL_VERSION}-${KERNEL_RELEASE}
dnf install -y 'dnf-command(config-manager)'
subscription-manager repos --enable codeready-builder-for-rhel-10-$(arch)-rpms
dnf install https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm -y
dnf config-manager --add-repo=https://developer.download.nvidia.com/compute/cuda/repos/rhel10/x86_64/cuda-rhel10.repo
dnf config-manager --best --nodocs --setopt install_weak_deps=False --save
dnf install -y nvidia-driver-cuda-${DRIVER_VERSION} kmod-nvidia-open-dkms-${DRIVER_VERSION} --exclude=kernel\*
export DRIVER_VERSION=${DRIVER_VERSION:-$(dkms status | grep -oP '\d+\.\d+\.\d+')}
echo "DRIVER_VERSION: ${DRIVER_VERSION}, KERNEL_VERSION-KERNEL_RELEASE: ${KERNEL_VERSION}-${KERNEL_RELEASE}"
sudo dkms build -m nvidia -v ${DRIVER_VERSION} -k ${KERNEL_VERSION}-${KERNEL_RELEASE}.${ARCH}
sudo dkms install -m nvidia -v ${DRIVER_VERSION} -k ${KERNEL_VERSION}-${KERNEL_RELEASE}.${ARCH}
dnf config-manager --add-repo=https://developer.download.nvidia.com/compute/cuda/repos/rhel9/x86_64/cuda-rhel9.repo
dnf install --nogpgcheck --repo cuda-rhel9-$(arch) -y nvidia-container-toolkit
dnf clean all
