#!/bin/bash

# Initial system and user setup
dnf install -y python3-pip
dnf install -y python3-pip python3-libsemanage

sudo cp -a /root/.ssh/* /home/rhel/.ssh/.
sudo chown -R rhel:rhel /home/rhel/.ssh

mkdir -p /home/rhel/ansible
chown -R rhel:rhel /home/rhel/ansible
chmod 777 /home/rhel/ansible

# Git global configuration
git config --global user.email "student@redhat.com"
git config --global user.name "student"

# Create inventory file
cat <<EOF | tee /tmp/inventory.ini
[ctrlnodes]
controller.acme.example.com ansible_host=controller ansible_user=rhel ansible_connection=local

[ciservers]
jenkins ansible_user=root

[windowssrv]
windows ansible_host=domainctl ansible_user=instruqt ansible_password=Passw0rd! ansible_connection=winrm ansible_port=5986 ansible_winrm_server_cert_validation=ignore

[ciservers:vars]
ansible_become_method=su

[all:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF

# Create lab setup script
cat <<EOF | tee /tmp/lab-setup.sh
#!/bin/bash
dnf install git nano -y
mkdir -p /tmp/cache
git clone https://github.com/nmartins0611/windows_getting_started_instruqt.git /tmp/cache

# Configure Repo for builds
ansible-playbook /tmp/git-setup.yml -i localhost, -e @/tmp/track-vars.yml

# Configure Controller
ansible-playbook /tmp/controller-setup.yml -i /tmp/inventory.ini -e @/tmp/track-vars.yml
EOF

# Create variables file
cat <<EOF | tee /tmp/track-vars.yml
---
# config vars
controller_hostname: controller
controller_validate_certs: false
ansible_python_interpreter: /usr/bin/python3
controller_ee: windows workshop execution environment
student_user: student
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
EOF

# Create Gitea setup playbook (updated for showroom environment)
cat <<EOF | tee /tmp/git-setup.yml
# Gitea config for showroom environment - run from control VM
- name: Configure Gitea repository from control VM
  hosts: localhost
  gather_facts: false
  connection: local
  tags:
    - gitea-config

  tasks:
    - name: Wait for Gitea to be ready
      ansible.builtin.uri:
        url: http://gitea:3000/api/v1/version
        method: GET
        status_code: 200
      register: gitea_ready
      until: gitea_ready.status == 200
      retries: 30
      delay: 2

    - name: Create repo for project 
      ansible.builtin.uri:
        url: http://gitea:3000/api/v1/user/repos
        method: POST
        body_format: json
        body:
          name: workshop_project
          auto_init: false
          private: false
        force_basic_auth: true
        url_password: "{{ student_password }}"
        url_username: "{{ student_user }}"
        status_code: [201, 409]

    - name: Create repo dir
      ansible.builtin.file:
        path: "/tmp/workshop_project"
        state: directory
        mode: 0755

    - name: Configure git to use main repo by default
      community.general.git_config:
        name: init.defaultBranch
        scope: global
        value: main
      tags:
        - git

    - name: Initialise track repo
      ansible.builtin.command:
        cmd: /usr/bin/git init
        chdir: "/tmp/workshop_project"
        creates: "/tmp/workshop_project/.git" 

    - name: Configure git to store credentials
      community.general.git_config:
        name: credential.helper
        scope: global
        value: store --file /tmp/git-creds

    - name: Configure repo dir as git safe dir
      community.general.git_config:
        name: safe.directory
        scope: global
        value: "/tmp/workshop_project"

    - name: Store repo credentials in git-creds file
      ansible.builtin.copy:
        dest: /tmp/git-creds
        mode: 0644
        content: "http://{{ student_user }}:{{ student_password }}@gitea:3000"

    - name: Configure git username
      community.general.git_config:
        name: user.name
        scope: global
        value: "{{ ansible_user }}"

    - name: Configure git email address
      community.general.git_config:
        name: user.email
        scope: global
        value: "{{ ansible_user }}@local"

    - name: Copy workshop content to repository
      ansible.builtin.copy:
        src: "/tmp/cache/"
        dest: "/tmp/workshop_project/"
        mode: preserve
        owner: "{{ ansible_user }}"
        group: "{{ ansible_user }}"

    - name: Add remote origin to repo
      ansible.builtin.command:
        cmd: "{{ item }}"
        chdir: "/tmp/workshop_project"   
      register: __output
      changed_when: __output.rc == 0
      loop:
        - "git remote add origin http://gitea:3000/{{ student_user }}/workshop_project.git"
        - "git checkout -b main"
        - "git add ."
        - "git commit -m'Initial commit'"
        - "git push -u origin main --force"
EOF

############################ REVISED CONTROLLER CONFIG ############################

# cat <<EOF | tee /tmp/controller-setup.yml
# ## Controller setup
# - name: Controller config for Windows Getting Started
#   hosts: controller.acme.example.com
#   gather_facts: false
  
#   vars:
#     # Define common controller connection parameters here for reuse
#     controller_auth_params:
#       controller_host: "{{ controller_hostname }}"
#       validate_certs: "{{ controller_validate_certs }}"

#   tasks:
#     - name: Ensure controller is online and responsive
#       ansible.builtin.uri:
#         url: "https://{{ controller_hostname }}/api/v2/ping/"
#         method: GET
#         user: "{{ controller_admin_user }}"
#         password: "{{ controller_admin_password }}"
#         validate_certs: "{{ controller_validate_certs }}"
#         force_basic_auth: true
#       register: controller_online
#       until: controller_online.status == 200
#       retries: 10
#       delay: 5

#     - name: Create an OAuth2 token for automation
#       ansible.controller.token:
#         description: 'Token for lab setup automation'
#         scope: "write"
#         state: present
#         controller_username: "{{ controller_admin_user }}"
#         controller_password: "{{ controller_admin_password }}"
#         <<: *controller_auth_params # Merge in common connection params
#       register: oauth_token

#     # Now use the created token for all subsequent tasks
#     - name: Add Organization
#       ansible.controller.organization:
#         name: "{{ lab_organization }}"
#         description: "ACME Corp Organization"
#         state: present
#         controller_oauthtoken: "{{ oauth_token.token }}"
#         <<: *controller_auth_params

#     - name: Add Instruqt Windows EE
#       ansible.controller.execution_environment:
#         name: "{{ controller_ee }}"
#         image: "quay.io/nmartins/windows_ee"
#         pull: missing # Pulls if not present on the system
#         organization: "{{ lab_organization }}"
#         state: present
#         controller_oauthtoken: "{{ oauth_token.token }}"
#         <<: *controller_auth_params
        
#     - name: Create student admin user
#       ansible.controller.user:
#         username: "{{ student_user }}"
#         password: "{{ student_password }}"
#         email: "student@acme.example.com"
#         is_superuser: true
#         state: present
#         controller_oauthtoken: "{{ oauth_token.token }}"
#         <<: *controller_auth_params

#     - name: Create Workshop Inventory
#       ansible.controller.inventory:
#         name: "Workshop Inventory"
#         organization: "{{ lab_organization }}"
#         state: present
#         controller_oauthtoken: "{{ oauth_token.token }}"
#         <<: *controller_auth_params

#     - name: Create Host for Windows Server
#       ansible.controller.host:
#         name: "windows"
#         inventory: "Workshop Inventory"
#         state: present
#         controller_oauthtoken: "{{ oauth_token.token }}"
#         <<: *controller_auth_params

#     - name: Create Group for Windows Servers
#       ansible.controller.group:
#         name: "Windows Servers"
#         inventory: "Workshop Inventory"
#         state: present
#         variables: |
#           ansible_connection: winrm
#           ansible_port: 5986
#           ansible_winrm_server_cert_validation: ignore
#         controller_oauthtoken: "{{ oauth_token.token }}"
#         <<: *controller_auth_params
        
#     - name: Associate windows host with the Windows Servers group
#       ansible.controller.host:
#         name: "windows"
#         inventory: "Workshop Inventory"
#         groups:
#           - "Windows Servers"
#         state: present
#         controller_oauthtoken: "{{ oauth_token.token }}"
#         <<: *controller_auth_params
# EOF

# # Install necessary collections and packages
# ansible-galaxy collection install community.general
# ansible-galaxy collection install microsoft.ad
# ansible-galaxy collection install ansible.controller
# pip3 install pywinrm

# # Execute the setup
# chmod +x /tmp/lab-setup.sh
# sh /tmp/lab-setup.sh

# # Install additional tools
# sudo dnf clean all
# sudo dnf install -y ansible-navigator ansible-lint nc
# pip3.9 install yamllint

# # ANSIBLE_COLLECTIONS_PATH=/tmp/ansible-automation-platform-containerized-setup-bundle-2.5-9-x86_64/collections/:/root/.ansible/collections/ansible_collections/ ansible-playbook -i /tmp/inventory /tmp/setup.yml

# ###########################################











############################ CONTROLLER CONFIG

cat <<EOF | tee /tmp/controller-setup.yml
## Controller setup
- name: Controller config for Windows Getting Started
  hosts: controller.acme.example.com
  gather_facts: true
    
  tasks:
   # Create auth login token
    - name: get auth token and restart automation-controller if it fails
      block:
        - name: Refresh facts
          setup:

        - name: Create oauth token
          ansible.controller.token:
            description: 'Instruqt lab'
            scope: "write"
            state: present
            controller_host: controller
            controller_username: "{{ controller_admin_user }}"
            controller_password: "{{ controller_admin_password }}"
            validate_certs: false
          register: _auth_token
          until: _auth_token is not failed
          delay: 3
          retries: 5
      rescue:
        - name: In rescue block for auth token
          debug:
            msg: "failed to get auth token. Restarting automation controller service"

        - name: restart the controller service
          ansible.builtin.service:
            name: automation-controller
            state: restarted

        - name: Ensure tower/controller is online and working
          uri:
            url: https://localhost/api/v2/ping/
            method: GET
            user: "{{ admin_username }}"
            password: "{{ admin_password }}"
            validate_certs: false
            force_basic_auth: true
          register: controller_online
          until: controller_online is success
          delay: 3
          retries: 5

        - name: Retry getting auth token
          ansible.controller.token:
            description: 'Instruqt lab'
            scope: "write"
            state: present
            controller_host: controller
            controller_username: "{{ controller_admin_user }}"
            controller_password: "{{ controller_admin_password }}"
            validate_certs: false
          register: _auth_token
          until: _auth_token is not failed
          delay: 3
          retries: 5
      always:
        - name: Create fact.d dir
          ansible.builtin.file:
            path: "{{ custom_facts_dir }}"
            state: directory
            recurse: yes
            owner: "{{ ansible_user }}"
            group: "{{ ansible_user }}"
            mode: 0755
          become: true

        - name: Create _auth_token custom fact
          ansible.builtin.copy:
            content: "{{ _auth_token.ansible_facts }}"
            dest: "{{ custom_facts_dir }}/{{ custom_facts_file }}"
            owner: "{{ ansible_user }}"
            group: "{{ ansible_user }}"
            mode: 0644
          become: true
      check_mode: false
      when: ansible_local.custom_facts.controller_token is undefined
      tags:
        - auth-token

    - name: refresh facts
      setup:
        filter:
          - ansible_local
      tags:
        - always

    - name: create auth token fact
      ansible.builtin.set_fact:
        auth_token: "{{ ansible_local.custom_facts.controller_token }}"
        cacheable: true
      check_mode: false
      when: auth_token is undefined
      tags:
        - always
 
    - name: Ensure tower/controller is online and working
      uri:
        url: https://localhost/api/v2/ping/
        method: GET
        user: "{{ admin_username }}"
        password: "{{ admin_password }}"
        validate_certs: false
        force_basic_auth: true
      register: controller_online
      until: controller_online is success
      delay: 3
      retries: 5
      tags:
        - controller-config

# Controller objects
    - name: Add Organization
      ansible.controller.organization:
        name: "{{ lab_organization }}"
        description: "ACME Corp Organization"
        state: present
        controller_oauthtoken: "{{ auth_token }}"
        validate_certs: false
      tags:
        - controller-config
        - controller-org
  
    - name: Add Instruqt Windows EE
      ansible.controller.execution_environment:
        name: "{{ controller_ee }}"
        image: "quay.io/nmartins/windows_ee"
        pull: missing
        state: present
        controller_oauthtoken: "{{ auth_token }}"
        controller_host: "{{ controller_hostname }}"
        validate_certs: "{{ controller_validate_certs }}"
      tags:
        - controller-config
        - controller-ees

    - name: Create student admin user
      ansible.controller.user:
        superuser: true
        username: "{{ student_user }}"
        password: "{{ student_password }}"
        email: student@acme.example.com
        controller_oauthtoken: "{{ auth_token }}"
        controller_host: "{{ controller_hostname }}"
        validate_certs: "{{ controller_validate_certs }}"
      tags:
        - controller-config
        - controller-users

    - name: Create Inventory
      ansible.controller.inventory:
       name: "Workshop Inventory"
       description: "Our Server environment"
       organization: "Default"
       state: present
       controller_config_file: "/tmp/controller.cfg"

    - name: Create Host for Workshop
      ansible.controller.host:
       name: windows
       description: "Windows Group"
       inventory: "Workshop Inventory"
       state: present
       controller_config_file: "/tmp/controller.cfg"

    - name: Create Host for Workshop
      ansible.controller.host:
       name: student-ansible
       description: "Ansible node"
       inventory: "Workshop Inventory"
       state: present
       controller_config_file: "/tmp/controller.cfg"

    - name: Create Group for inventory
      ansible.controller.group:
       name: Windows
       description: Windows Server Group
       inventory: "Workshop Inventory"
       hosts:
        - windows
       variables:
         ansible_connection: winrm
         ansible_port: 5986
         ansible_winrm_server_cert_validation: ignore
       controller_config_file: "/tmp/controller.cfg"

     
       
EOF

cat <<EOF | tee /tmp/controller.cfg
host: localhost
username: student
password: learn_ansible
verify_ssl = false
EOF

# Install necessary collections and packages
ansible-galaxy collection install community.general
ansible-galaxy collection install microsoft.ad
ansible-galaxy collection install ansible.controller
pip3 install pywinrm

##### Executing:

chmod +x /tmp/lab-setup.sh

#sh /tmp/lab-setup.sh
sh /tmp/lab-setup.sh

sudo dnf clean all
sudo dnf install -y ansible-navigator
sudo dnf install -y ansible-lint
sudo dnf install -y nc
pip3.9 install yamllint