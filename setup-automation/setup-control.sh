#!/bin/bash

# Initial system and user setup
# dnf install -y python3-pip
dnf install -y python3-pip python3-libsemanage

systemctl stop systemd-tmpfiles-setup.service
systemctl disable systemd-tmpfiles-setup.service

# Install collection(s)
ansible-galaxy collection install ansible.controller
ansible-galaxy collection install ansible.eda
ansible-galaxy collection install community.general
ansible-galaxy collection install ansible.windows
ansible-galaxy collection install microsoft.ad

# # ## setup rhel user
# touch /etc/sudoers.d/rhel_sudoers
# echo "%rhel ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers.d/rhel_sudoers
# cp -a /root/.ssh/* /home/$USER/.ssh/.
# chown -R rhel:rhel /home/$USER/.ssh

# Create an inventory file for this environment
tee /tmp/inventory << EOF
[nodes]
node01
node02

[storage]
storage01

[all]
node01
node02

[all:vars]
ansible_user = rhel
ansible_password = ansible123!
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
ansible_python_interpreter=/usr/bin/python3

EOF
# sudo chown rhel:rhel /tmp/inventory


# # # creates a playbook to setup environment
tee /tmp/setup.yml << EOF
---
### Automation Controller setup 
###
- name: Setup Controller 
  hosts: localhost
  connection: local
  collections:
    - ansible.controller
  vars:
    GUID: "{{ lookup('env', 'GUID') | default('GUID_NOT_FOUND', true) }}"
    DOMAIN: "{{ lookup('env', 'DOMAIN') | default('DOMAIN_NOT_FOUND', true) }}"
  tasks:

  - name: (EXECUTION) add App machine credential
    ansible.controller.credential:
      name: 'Application Nodes'
      organization: Default
      credential_type: Machine
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false
      inputs:
        username: rhel
        password: ansible123!

  - name: (EXECUTION) add Windows machine credential
    ansible.controller.credential:
      name: 'Windows Nodes'
      organization: Default
      credential_type: Machine
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false
      inputs:
        username: Administrator
        password: Ansible123!

  - name: (EXECUTION) add Arista credential
    ansible.controller.credential:
      name: 'Arista Network'
      organization: Default
      credential_type: Machine
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false
      inputs:
        username: ansible
        password: ansible

  - name: Add Network EE
    ansible.controller.execution_environment:
      name: "Edge_Network_ee"
      image: quay.io/acme_corp/network-ee
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add Windows EE
    ansible.controller.execution_environment:
      name: "Windows_ee"
      image: quay.io/acme_corp/windows-ee
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add RHEL EE
    ansible.controller.execution_environment:
      name: "Rhel_ee"
      image: quay.io/acme_corp/rhel_90_ee
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add Video platform inventory
    ansible.controller.inventory:
      name: "Video Platform Inventory"
      description: "Nodes used for streaming"
      organization: "Default"
      state: present
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add Streaming Server hosts
    ansible.controller.host:
      name: "{{ item }}"
      description: "Application Nodes"
      inventory: "Video Platform Inventory"
      state: present
      enabled: true
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false
    loop:
      - node01
      - node02
      - node03
 
  - name: Add Streaming server group
    ansible.controller.group:
      name: "Streaming_Infrastucture"
      description: "Streaming Nodes"
      inventory: "Video Platform Inventory"
      hosts:
        - node01
        - node02
        - node03
      variables:
        ansible_user: rhel
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add Streaming server group
    ansible.controller.group:
      name: "Reporting"
      description: "Report Servers"
      inventory: "Video Platform Inventory"
      hosts:
        - node03
      variables:
        ansible_user: rhel
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false


  #   # Network
 
  - name: Add Edge Network Devices
    ansible.controller.inventory:
      name: "Edge Network"
      description: "Network for delivery"
      organization: "Default"
      state: present
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add CEOS1
    ansible.controller.host:
      name: "ceos01"
      description: "Edge Leaf"
      inventory: "Edge Network"
      state: present
      enabled: true
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false
      variables:
        ansible_host: node02
        ansible_port: 2001

  - name: Add CEOS2
    ansible.controller.host:
      name: "ceos02"
      description: "Edge Leaf"
      inventory: "Edge Network"
      state: present
      enabled: true
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false
      variables:
        ansible_host: node02
        ansible_port: 2002

  - name: Add CEOS3
    ansible.controller.host:
      name: "ceos03"
      description: "Edge Leaf"
      inventory: "Edge Network"
      state: present
      enabled: true
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false
      variables:
        ansible_host: node02
        ansible_port: 2003

  - name: Add EOS Network Group
    ansible.controller.group:
      name: "Delivery_Network"
      description: "EOS Network"
      inventory: "Edge Network"
      hosts:
        - ceos01
        - ceos02
        - ceos03
      variables:
        ansible_user: ansible
        ansible_connection: ansible.netcommon.network_cli 
        ansible_network_os: arista.eos.eos 
        ansible_password: ansible 
        ansible_become: yes 
        ansible_become_method: enable
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false
      
  #   ## Extra Inventories 

  # - name: Add Storage Infrastructure
  #   ansible.controller.inventory:
  #    name: "Cache Storage"
  #    description: "Edge NAS Storage"
  #    organization: "Default"
  #    state: present
  #    controller_host: "https://localhost"
  #    controller_username: admin
  #    controller_password: ansible123!
  #    validate_certs: false

  # - name: Add Storage Node
  #   ansible.controller.host:
  #    name: "Storage01"
  #    description: "Edge NAS Storage"
  #    inventory: "Cache Storage"
  #    state: present
  #    enabled: true
  #    controller_host: "https://localhost"
  #    controller_username: admin
  #    controller_password: ansible123!
  #    validate_certs: false

  - name:  Add Windows Inventory
    ansible.controller.inventory:
     name: "Windows Directory Servers"
     description: "AD Infrastructure"
     organization: "Default"
     state: present
     controller_host: "https://localhost"
     controller_username: admin
     controller_password: ansible123!
     validate_certs: false

  - name: Add Windows Inventory Host
    ansible.controller.host:
     name: "windows"
     description: "Directory Servers"
     inventory: "Windows Directory Servers"
     state: present
     enabled: true
     controller_host: "https://localhost"
     controller_username: admin
     controller_password: ansible123!
     validate_certs: false
     variables:
       ansible_host: windows

  - name: Create group with extra vars
    ansible.controller.group:
      name: "domain_controllers"
      inventory: "Windows Directory Servers"
      hosts:
        - windows
      state: present
      variables:
        ansible_connection: winrm
        ansible_port: 5986
        ansible_winrm_server_cert_validation: ignore
        ansible_winrm_transport: credssp
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false
        
  - name: (EXECUTION) Add project
    ansible.controller.project:
      name: "Roadshow"
      description: "Roadshow Content"
      organization: "Default"
      scm_type: git
      scm_url: http://gitea:3000/student/aap25-roadshow-content.git       ##ttps://github.com/nmartins0611/aap25-roadshow-content.git
      state: present
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  #- name: (DECISIONS) Create an AAP Credential
  #  ansible.eda.credential:
  #    name: "AAP"
  #    description: "To execute jobs from EDA"
  #    inputs:
  #      host: "https://control-{{ GUID }}.{{ DOMAIN }}/api/controller/"
  #      username: "admin"
  #      password: "ansible123!"
  #    credential_type_name: "Red Hat Ansible Automation Platform"
  #    organization_name: Default
  #    controller_host: https://localhost
  #    controller_username: admin
  #    controller_password: ansible123!
  #    validate_certs: false

###############TEMPLATES###############

  # - name: Add System Report
  #   ansible.controller.job_template:
  #     name: "System Report"
  #     job_type: "run"
  #     organization: "Default"
  #     inventory: "Video Platform Inventory"
  #     project: "Roadshow"
  #     playbook: "playbooks/section01/server_re[ort].yml"
  #     execution_environment: "RHEL EE"
  #     credentials:
  #       - "Application Nodes"
  #     state: "present"
  #     controller_host: "https://localhost"
  #     controller_username: admin
  #     controller_password: ansible123!
  #     validate_certs: false

  # - name: Add Windows Setup Template
  #   ansible.controller.job_template:
  #     name: "Windows Patching Report"
  #     job_type: "run"
  #     organization: "Default"
  #     inventory: "Windows Directory Servers"
  #     project: "Roadshow"
  #     playbook: "playbooks/section01/windows_report.yml"
  #     execution_environment: "Windows_ee"
  #     credentials:
  #       - "Windows Nodes"
  #     state: "present"
  #     controller_host: "https://localhost"
  #     controller_username: admin
  #     controller_password: ansible123!
  #     validate_certs: false

  - name: Add Rhel Report Template
    ansible.controller.job_template:
      name: "Application Server Report"
      job_type: "run"
      organization: "Default"
      inventory: "Video Platform Inventory"
      project: "Roadshow"
      playbook: "playbooks/section01/rhel_report.yml"
      execution_environment: "Rhel_ee"
      credentials:
        - "Application Nodes"
      state: "present"
      survey_enabled: true
      survey_spec:
           {
             "name": "Report Details",
             "description": "Report components needed",
             "spec": [
               {
    	          "type": "multiplechoice",
    	          "question_name": "What data are you looking for ?",
              	"question_description": "Defined data",
              	"variable": "report_type",
                "choices": ["All","Storage Usage","User List","OS Versions"],
                "required": true
               }
             ]
           }
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add OSCAP Setup Template
    ansible.controller.job_template:
      name: "OpenSCAP Report"
      job_type: "run"
      organization: "Default"
      inventory: "Video Platform Inventory"
      project: "Roadshow"
      playbook: "playbooks/section01/rhel_compliance_report.yml"
      execution_environment: "Rhel_ee"
      credentials:
        - "Application Nodes"
      state: "present"
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add Windows Update Report Template
    ansible.controller.job_template:
      name: "Windows Update Report"
      job_type: "run"
      organization: "Default"
      inventory: "Windows Directory Servers"
      project: "Roadshow"
      playbook: "playbooks/section01/windows_update_report.yml"
      execution_environment: "Windows_ee"
      credentials:
        - "Windows Nodes"
      state: "present"
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add RHEL Backup
    ansible.controller.job_template:
      name: "Server Backup - XFS/RHEL"
      job_type: "run"
      organization: "Default"
      inventory: "Video Platform Inventory"
      project: "Roadshow"
      playbook: "playbooks/section01/xfs_backup.yml"
      execution_environment: "Rhel_ee"
      credentials:
        - "Application Nodes"
      state: "present"
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add RHEL Backup Check
    ansible.controller.job_template:
      name: "Check RHEL Backup"
      job_type: "run"
      organization: "Default"
      inventory: "Video Platform Inventory"
      project: "Roadshow"
      playbook: "playbooks/section01/check_backups.yml"
      execution_environment: "Rhel_ee"
      credentials:
        - "Application Nodes"
      state: "present"
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false


  - name: Add Windows Backup 
    ansible.controller.job_template:
      name: "Server Backup - VSS/Windows"
      job_type: "run"
      organization: "Default"
      inventory: "Windows Directory Servers"
      project: "Roadshow"
      playbook: "playbooks/section01/vss_windows.yml"
      execution_environment: "Windows_ee"
      credentials:
        - "Windows Nodes"
      state: "present"
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add Windows Backup Check
    ansible.controller.job_template:
      name: "Check Windows Backups"
      job_type: "run"
      organization: "Default"
      inventory: "Windows Directory Servers"
      project: "Roadshow"
      playbook: "playbooks/section01/check_windowsvss.yml"
      execution_environment: "Windows_ee"
      credentials:
        - "Windows Nodes"
      state: "present"
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

EOF

# # # chown files
# sudo chown rhel:rhel /tmp/setup.yml
# sudo chown rhel:rhel /tmp/inventory
# sudo chown rhel:rhel /tmp/git-setup.yml

# # # execute above playbook



ANSIBLE_COLLECTIONS_PATH=/tmp/ansible-automation-platform-containerized-setup-bundle-2.5-9-x86_64/collections/:/root/.ansible/collections/ansible_collections/ ansible-playbook -i /tmp/inventory /tmp/setup.yml
