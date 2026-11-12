#!/bin/bash

retry() {
    for i in {1..3}; do
        echo "Attempt $i: $2"
        if $1; then
            return 0
        fi
        [ $i -lt 3 ] && sleep 5
    done
    echo "Failed after 3 attempts: $2"
    exit 1
}

retry "subscription-manager clean"
retry "curl -k -L https://${SATELLITE_URL}/pub/katello-server-ca.crt -o /etc/pki/ca-trust/source/anchors/${SATELLITE_URL}.ca.crt"
retry "update-ca-trust"
KATELLO_INSTALLED=$(rpm -qa | grep -c katello)
if [ $KATELLO_INSTALLED -eq 0 ]; then
  retry "rpm -Uhv https://${SATELLITE_URL}/pub/katello-ca-consumer-latest.noarch.rpm"
fi
subscription-manager status
if [ $? -ne 0 ]; then
    retry "subscription-manager register --org=${SATELLITE_ORG} --activationkey=${SATELLITE_ACTIVATIONKEY}"
fi
retry "dnf install -y python3-pip python3-libsemanage"

echo "=== Windows Workshop Setup ==="

# Create a writable workspace for the rhel user used by exercises
mkdir -p /home/rhel/ansible
chown -R rhel:rhel /home/rhel/ansible
chmod 755 /home/rhel/ansible

# Set a generic Git identity used in the lab environment
git config --global user.email "student@redhat.com"
git config --global user.name "student"

# Create Ansible inventory
cat <<EOF | tee /tmp/inventory.ini
[ctrlnodes]
localhost ansible_connection=local

[windowssrv]
windows ansible_host=windows ansible_user=Administrator ansible_password=Ansible123! ansible_connection=winrm ansible_port=5986 ansible_winrm_scheme=https ansible_winrm_transport=ntlm ansible_winrm_server_cert_validation=ignore

[all:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF

# Create lab variables
cat <<EOF | tee /tmp/track-vars.yml
---
# config vars
controller_hostname: localhost
controller_validate_certs: false
ansible_python_interpreter: /usr/bin/python3
controller_ee: Windows Workshop Execution Environment
student_user: student
win_student_password: Passw0rd!
student_password: learn_ansible
controller_admin_user: admin
controller_admin_password: "ansible123!"
host_key_checking: false
custom_facts_dir: "/etc/ansible/facts.d"
custom_facts_file: custom_facts.fact
admin_username: admin
admin_password: ansible123!
repo_user: rhel
default_tag_name: "0.0.1"
lab_organization: ACME
admin_windows_user: '.\\Administrator'
admin_windows_password: 'Ansible123!'
EOF

# Controller setup playbook
cat <<EOF | tee /tmp/controller-setup.yml
---
- name: Configure Windows Workshop Controller 
  hosts: localhost
  connection: local
  collections:
    - ansible.controller

  tasks:
    - name: Add Windows EE
      ansible.controller.execution_environment:
        name: "Windows Workshop Execution Environment"
        image: "quay.io/nmartins/windows_ee"
        controller_host: "https://localhost"
        controller_username: admin
        controller_password: ansible123!
        validate_certs: false

    - name: Create Inventory
      ansible.controller.inventory:
        name: "Workshop Inventory"
        description: "Our Server environment"
        organization: "Default"
        state: present
        controller_host: "https://localhost"
        controller_username: admin
        controller_password: ansible123!
        validate_certs: false

    - name: Create Host for Workshop
      ansible.controller.host:
        name: windows
        description: "Windows Group"
        inventory: "Workshop Inventory"
        state: present
        controller_host: "https://localhost"
        controller_username: admin
        controller_password: ansible123!
        validate_certs: false

    - name: Create Host for Workshop
      ansible.controller.host:
        name: student-ansible
        description: "Ansible node"
        inventory: "Workshop Inventory"
        state: present
        controller_host: "https://localhost"
        controller_username: admin
        controller_password: ansible123!
        validate_certs: false

    - name: Create Group for inventory
      ansible.controller.group:
        name: Windows_Servers
        description: Windows Server Group
        inventory: "Workshop Inventory"
        hosts:
          - windows
        variables:
          ansible_connection: winrm
          ansible_port: 5986
          ansible_winrm_server_cert_validation: ignore
        controller_host: "https://localhost"
        controller_username: admin
        controller_password: ansible123!
        validate_certs: false

    - name: Read the modules allowed for ad hoc jobs
      ansible.builtin.uri:
        url: https://localhost/api/controller/v2/settings/jobs/
        method: GET
        url_username: admin
        url_password: ansible123!
        force_basic_auth: true
        validate_certs: false
        return_content: true
      register: job_settings

    - name: Allow win_chocolatey in Run command
      ansible.builtin.uri:
        url: https://localhost/api/controller/v2/settings/jobs/
        method: PATCH
        url_username: admin
        url_password: ansible123!
        force_basic_auth: true
        validate_certs: false
        body_format: json
        status_code: 200
        body:
          AD_HOC_COMMANDS: "{{ job_settings.json.AD_HOC_COMMANDS + ['win_chocolatey'] }}"
      when: "'win_chocolatey' not in job_settings.json.AD_HOC_COMMANDS"
EOF

# Collections used by the setup playbooks. Student jobs use the Windows execution environment.
ansible-galaxy collection install ansible.windows ansible.controller

# Install pywinrm for Windows connectivity
pip3 install pywinrm

# Set collections path for playbook execution
export ANSIBLE_COLLECTIONS_PATH=/root/.ansible/collections/ansible_collections/


cat <<'EOF' | tee /tmp/windows-setup.yml
---
- hosts: windows
  gather_facts: false
  vars:
    ansible_connection: winrm
    ansible_port: 5986
    ansible_winrm_scheme: https
    ansible_winrm_transport: ntlm
    ansible_winrm_server_cert_validation: ignore
    ansible_user: "{{ admin_windows_user }}"
    ansible_password: "{{ admin_windows_password }}"
  tasks:
    - name: Ensure WinRM service is running
      ansible.windows.win_service:
        name: WinRM
        state: started
        start_mode: auto

    - name: Enable PowerShell remoting (idempotent)
      ansible.windows.win_shell: |
        try { Enable-PSRemoting -Force -SkipNetworkProfileCheck } catch { }
      args:
        executable: powershell.exe
      changed_when: false
      failed_when: false

    - name: Ensure student user exists
      ansible.windows.win_user:
        name: "{{ student_user }}"
        password: "{{ win_student_password }}"
        state: present
        password_never_expires: yes
    - name: Ensure student is local admin
      ansible.windows.win_group_membership:
        name: Administrators
        members:
          - "{{ student_user }}"
        state: present

    - name: Disable Server Manager auto-start at logon
      ansible.windows.win_regedit:
        path: HKLM:\SOFTWARE\Policies\Microsoft\Windows\Server\ServerManager
        name: DoNotOpenAtLogon
        data: 1
        type: dword
        state: present

    - name: Ensure .NET Framework 4.8 feature is installed
      ansible.windows.win_feature:
        name: NET-Framework-45-Features
        state: present
        include_sub_features: true
        include_management_tools: true
      register: dotnet_feature

    - name: Reboot when the .NET feature install requires it
      ansible.windows.win_reboot:
        msg: "Reboot to finish .NET feature installation"
        pre_reboot_delay: 5
      when: dotnet_feature.reboot_required | default(false)

    - name: Check whether Chocolatey is already installed
      ansible.windows.win_stat:
        path: C:\ProgramData\chocolatey\bin\choco.exe
      register: choco_bin

    - name: Install Chocolatey when first boot did not
      when: not choco_bin.stat.exists
      ansible.windows.win_shell: |
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
      args:
        executable: powershell.exe

    - name: Check whether Microsoft Edge is already installed
      ansible.windows.win_stat:
        path: C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe
      register: edge_bin

    - name: Install Microsoft Edge when first boot did not
      when: not edge_bin.stat.exists
      ansible.windows.win_shell: C:\ProgramData\chocolatey\bin\choco.exe install microsoft-edge -y --no-progress
      args:
        executable: powershell.exe
      register: edge_install
      retries: 3
      delay: 20
      until: edge_install.rc == 0

    - name: Confirm Microsoft Edge is installed
      ansible.windows.win_stat:
        path: C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe
      register: edge_installed

    - name: Fail if Edge is not installed
      ansible.builtin.fail:
        msg: 'Edge did not install; check Chocolatey logs on the VM'
      when: not edge_installed.stat.exists

    - name: Set MapsBroker to manual and stopped
      ansible.windows.win_service:
        name: MapsBroker
        start_mode: manual
        state: stopped

    - name: Check whether the Windows license is about to expire
      ansible.windows.win_shell: |
        $output = & cscript.exe //Nologo C:\Windows\System32\slmgr.vbs /xpr | Out-String
        Write-Output $output
        if ($output -match 'permanently activated') { exit 0 }
        if ($output -match 'Notification' -or $output -match 'grace period has expired') { exit 2 }
        if ($output -match '(\d{1,2}/\d{1,2}/\d{4})') {
          $expires = [datetime]::Parse($Matches[1], [cultureinfo]'en-US')
          if ($expires -lt (Get-Date).AddDays(2)) { exit 2 }
        }
        exit 0
      register: license_check
      changed_when: false
      failed_when: license_check.rc not in [0, 2]

    - name: Rearm Windows when the grace period is nearly over
      when: license_check.rc == 2
      ansible.windows.win_shell: cscript.exe //B //NoLogo C:\Windows\System32\slmgr.vbs /rearm

    - name: Reboot when a license rearm has to take effect
      when: license_check.rc == 2
      ansible.windows.win_reboot:
        msg: "Reboot to apply Windows license rearm"
        pre_reboot_delay: 5

    - name: Remove Windows Update policies that point at WSUS or block the service
      ansible.windows.win_regedit:
        path: "{{ item.path }}"
        name: "{{ item.name }}"
        state: absent
      loop:
        - path: HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate
          name: WUServer
        - path: HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate
          name: WUStatusServer
        - path: HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate
          name: DoNotConnectToWindowsUpdateInternetLocations
        - path: HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate
          name: DisableWindowsUpdateAccess
        - path: HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU
          name: UseWUServer
      failed_when: false

    - name: Leave Windows Update enabled without installing before the exercise
      ansible.windows.win_regedit:
        path: HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU
        name: "{{ item.name }}"
        data: "{{ item.data | int }}"
        type: dword
      loop:
        - name: NoAutoUpdate
          data: 0
        - name: AUOptions
          data: 2

    - name: Download Windows updates over HTTPS instead of peer caching
      ansible.windows.win_regedit:
        path: HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization
        name: DODownloadMode
        data: 0
        type: dword

    - name: Ensure services required by win_updates are running
      ansible.windows.win_service:
        name: "{{ item.name }}"
        start_mode: "{{ item.mode }}"
        state: started
      loop:
        - name: Schedule
          mode: auto
        - name: cryptsvc
          mode: auto
        - name: bits
          mode: manual
        - name: wuauserv
          mode: manual

    - name: Allow Administrators to run the Windows Update scheduled task
      ansible.windows.win_user_right:
        name: SeBatchLogonRight
        users:
          - Administrators
          - "{{ student_user }}"
        action: add
EOF


# Execute the setup playbooks
echo "=== Bootstrapping Windows local user (best effort) ==="
ansible-playbook /tmp/windows-setup.yml -e @/tmp/track-vars.yml -i /tmp/inventory.ini -v || true

echo "=== Running AAP Controller Setup ==="
ansible-playbook /tmp/controller-setup.yml -e @/tmp/track-vars.yml -i /tmp/inventory.ini -v
