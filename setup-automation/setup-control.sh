#!/bin/bash

systemctl stop systemd-tmpfiles-setup.service
systemctl disable systemd-tmpfiles-setup.service

# Install collection(s)
ansible-galaxy collection install ansible.eda
ansible-galaxy collection install community.general
ansible-galaxy collection install ansible.windows
ansible-galaxy collection install microsoft.ad



# Create an inventory file for this environment
tee /tmp/inventory << EOF
[nodes]
node01
node02

[git_server]
gitea ansible_user=root ansible_become_method=su

[storage]
storage01

[all]
node01
node02
# eda-controller
# controller
aap

[all:vars]
ansible_user = rhel
ansible_password = ansible123!
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
ansible_python_interpreter=/usr/bin/python3

EOF

sudo chown rhel:rhel /tmp/inventory



# creates a playbook to setup environment
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
    SANDBOX_ID: "{{ lookup('env', '_SANDBOX_ID') | default('SANDBOX_ID_NOT_FOUND', true) }}"
    SN_HOST_VAR: "{{ '{{' }} SN_HOST {{ '}}' }}"
    SN_USER_VAR: "{{ '{{' }} SN_USERNAME {{ '}}' }}"
    SN_PASSWORD_VAR: "{{ '{{' }} SN_PASSWORD {{ '}}' }}"

  tasks:

###############CREDENTIALS###############

  - name: (EXECUTION) add App machine credential
    ansible.controller.credential:
      name: 'Application Nodes'
      organization: Default
      credential_type: Machine
      controller_host: "https://{{ ansible_host }}"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false
      inputs:
        username: rhel
        password: ansible123!

  - name: (EXECUTION) add Windows machine credential
    ansible.controller.credential:
      name: 'Windows DB Nodes'
      organization: Default
      credential_type: Machine
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false
      inputs:
        username: instruqt
        password: passw0rd!

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

  - name: add ServiceNow Type
    ansible.controller.credential_type:
      name: ServiceNow
      description: ServiceNow Credential
      kind: cloud
      inputs: 
        fields:
          - id: SN_HOST
            type: string
            label: SNOW Instance
          - id: SN_USERNAME
            type: string
            label: SNOW Username
          - id: SN_PASSWORD
            type: string
            secret: true
            label: SNOW Password
        required:
          - SN_HOST
          - SN_USERNAME
          - SN_PASSWORD
      injectors:
          env:
           SN_HOST: "{{ SN_HOST_VAR }}"
           SN_USERNAME: "{{ SN_USER_VAR }}"
           SN_PASSWORD: "{{ SN_PASSWORD_VAR }}"
      state: present
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: add snow credential
    ansible.controller.credential:
      name: 'ServiceNow'
      organization: Default
      credential_type: ServiceNow
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false
      inputs:
        SN_USERNAME: aap-roadshow
        SN_PASSWORD: Ans1ble123!
        SN_HOST: https://ansible.service-now.com

  - name: (EXECUTION) add Insights credential
    ansible.controller.credential:
      name: 'Insights'
      organization: Default
      credential_type: Insights
      controller_host: "https://{{ ansible_host }}"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false
      inputs:
        username: rhel
        password: ansible123!

###############EE###############

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

  - name: Add EE to the controller instance
    ansible.controller.execution_environment:
      name: "ServiceNow EE"
      image: quay.io/acme_corp/servicenow-ee:latest
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add EE to the controller instance
    ansible.controller.execution_environment:
      name: "RHEL EE"
      image: quay.io/acme_corp/rhel_90_ee:latest
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

###############INVENTORY###############

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
      variables:
        ansible_host: podman-host
    loop:
      - node01
  
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
      - node02

  - name: Add Streaming server group
    ansible.controller.group:
      name: "webservers"
      description: "Application Nodes"
      inventory: "Video Platform Inventory"
      hosts:
        - node01
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
      name: "ceos1"
      description: "Edge Leaf"
      inventory: "Edge Network"
      state: present
      enabled: true
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false
      variables:
        ansible_host: podman-host
        ansible_port: 2001

  - name: Add CEOS2
    ansible.controller.host:
      name: "ceos2"
      description: "Edge Leaf"
      inventory: "Edge Network"
      state: present
      enabled: true
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false
      variables:
        ansible_host: podman-host
        ansible_port: 2002

  - name: Add CEOS3
    ansible.controller.host:
      name: "ceos3"
      description: "Edge Leaf"
      inventory: "Edge Network"
      state: present
      enabled: true
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false
      variables:
        ansible_host: podman-host
        ansible_port: 2003

  - name: Add EOS Network Group
    ansible.controller.group:
      name: "Delivery_Network"
      description: "EOS Network"
      inventory: "Edge Network"
      hosts:
        - ceos1
        - ceos2
        - ceos3
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
      
  - name: Add CORE Network Group
    ansible.controller.group:
      name: "Core"
      description: "EOS Network"
      inventory: "Edge Network"
      hosts:
        - ceos1
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

  - name: Add Storage Infrastructure
    ansible.controller.inventory:
     name: "Cache Storage"
     description: "Edge NAS Storage"
     organization: "Default"
     state: present
     controller_host: "https://localhost"
     controller_username: admin
     controller_password: ansible123!
     validate_certs: false

  - name: Add Storage Node
    ansible.controller.host:
     name: "Storage01"
     description: "Edge NAS Storage"
     inventory: "Cache Storage"
     state: present
     enabled: true
     controller_host: "https://localhost"
     controller_username: admin
     controller_password: ansible123!
     validate_certs: false

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
     name: "WindowsAD01"
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
        
###############TEMPLATES###############

  - name: Add project roadshow
    ansible.controller.project:
      name: "Roadshow"
      description: "Roadshow Content"
      organization: "Default"
      scm_type: git
      scm_url: https://github.com/nmartins0611/aap25-roadshow-content.git 
  ##http://gitea:3000/student/aap25-roadshow-content.git ##https://github.com/nmartins0611/aap25-roadshow-content.git
      state: present
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add Desired Port Template
    ansible.controller.job_template:
      name: "Desired port state"
      job_type: "run"
      organization: "Default"
      inventory: "Edge Network"
      project: "Roadshow"
      playbook: "playbooks/section03/desired_port_state.yml"
      execution_environment: "Edge_Network_ee"
      credentials:
        - "Arista Network"
      state: "present"
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add Show port Template
    ansible.controller.job_template:
      name: "Show Port Config"
      job_type: "run"
      organization: "Default"
      inventory: "Edge Network"
      project: "Roadshow"
      playbook: "playbooks/section03/show_port_config.yml"
      execution_environment: "Edge_Network_ee"
      credentials:
        - "Arista Network"
      state: "present"
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add Disable Port Template
    ansible.controller.job_template:
      name: "Disable Port"
      job_type: "run"
      organization: "Default"
      inventory: "Edge Network"
      project: "Roadshow"
      playbook: "playbooks/section03/disable_port.yml"
      execution_environment: "Edge_Network_ee"
      credentials:
        - "Arista Network"
      state: "present"
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add New Connection Port Template
    ansible.controller.job_template:
      name: "New Port Configuration"
      job_type: "run"
      organization: "Default"
      inventory: "Edge Network"
      project: "Roadshow"
      playbook: "playbooks/section03/configure_new_port.yml"
      execution_environment: "Edge_Network_ee"
      credentials:
        - "Arista Network"
      state: "present"
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add New Port enable  Template
    ansible.controller.job_template:
      name: "Make Port Active"
      job_type: "run"
      organization: "Default"
      inventory: "Edge Network"
      project: "Roadshow"
      playbook: "playbooks/section03/new_connection.yml"
      execution_environment: "Edge_Network_ee"
      credentials:
        - "Arista Network"
      state: "present"
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add Webapp Template
    ansible.controller.job_template:
      name: "Restore Web-Application"
      job_type: "run"
      organization: "Default"
      inventory: "Video Platform Inventory"
      project: "Roadshow"
      playbook: "playbooks/section03/web_app.yml"
      execution_environment: "Edge_Network_ee"
      credentials:
        - "Application Nodes"
      state: "present"
      job_tags: "restore"
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add Break Webapp Template
    ansible.controller.job_template:
      name: "Break Web-Application"
      job_type: "run"
      organization: "Default"
      inventory: "Video Platform Inventory"
      project: "Roadshow"
      playbook: "playbooks/section03/web_app.yml"
      execution_environment: "Edge_Network_ee"
      credentials:
        - "Application Nodes"
      job_tags: "break"
      state: "present"
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add BGP Troubleshooting Template
    ansible.controller.job_template:
      name: "Network Troubleshooting"
      job_type: "run"
      organization: "Default"
      inventory: "Edge Network"
      project: "Roadshow"
      playbook: "playbooks/section03/bgp_trouble.yml"
      execution_environment: "Edge_Network_ee"
      credentials:
        - "ServiceNow"
      state: "present"
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add Register Insights Template
    ansible.controller.job_template:
      name: "Insights for RHEL"
      job_type: "run"
      organization: "Default"
      inventory: "Video Platform Inventory"
      project: "Roadshow"
      playbook: "playbooks/section03/register_system.yml"
      execution_environment: "RHEL EE"
      survey_enabled: true
      survey_spec:
           {
             "name": "Red Hat Insights Credentials",
             "description": "Please provide your details for Insights",
             "spec": [
               {
    	          "type": "text",
    	          "question_name": "Please Provide your username:",
              	"question_description": "Insights Username",
              	"variable": "rhsm_username",
              	"required": true,
               },
               {
    	          "type": "password",
    	          "question_name": "Please Provide your password:",
              	"question_description": "Insights Password",
              	"variable": "rhsm_password",
              	"required": true,
               }
             ]
           }
      credentials:
        - "Application Nodes"
      state: "present"
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add CVE Template
    ansible.controller.job_template:
      name: "CVE Advisory"
      job_type: "run"
      organization: "Default"
      inventory: "Video Platform Inventory"
      project: "Roadshow"
      playbook: "playbooks/section03/cve_details.yml"
      execution_environment: "RHEL EE"
      survey_enabled: true
      survey_spec:
           {
             "name": "Red Hat Insights Credentials",
             "description": "Please provide your details for Insights",
             "spec": [
               {
    	          "type": "text",
    	          "question_name": "Please Provide your username:",
              	"question_description": "Insights Username",
              	"variable": "rhsm_username",
              	"required": true,
               },
               {
    	          "type": "password",
    	          "question_name": "Please Provide your password:",
              	"question_description": "Insights Password",
              	"variable": "rhsm_password",
              	"required": true,
               },
               {
                "type": "text",
    	          "question_name": "Please provide the Advisory ID",
              	"question_description": "CVE Advisory ID",
              	"variable": "advisory_id",
              	"required": true,
               }
             ]
           }
      credentials:
        - "ServiceNow"
      state: "present"
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

###############WORKFLOW PORT STATUS###############

  - name: Create workflow Approval Port Use case
    ansible.controller.workflow_job_template:
      name: "Resolve Port Status"
      inventory: "Edge Network"    
      organization: "Default"
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add approval node for workflow
    ansible.controller.workflow_job_template_node:
      validate_certs: false
      organization: "Default"
      workflow_job_template: "Resolve Port Status"
      identifier: port_change_approval
      approval_node:
        description: "Port status change detected, would you like to remediate ?"
        name: port_change_approval
        timeout: 3600
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add remediation node for workflow
    ansible.controller.workflow_job_template_node:
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false
      organization: "Default"
      workflow_job_template: "Resolve Port Status"
      identifier: port-remediation
      unified_job_template: "Desired port state"

  - name: Link remediation and approval node
    ansible.controller.workflow_job_template_node:
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false
      organization: "Default"
      workflow_job_template: "Resolve Port Status"
      identifier: port_change_approval
      success_nodes:
        - port-remediation

###############WORKFLOW NEW PORT###############

  - name: Create workflow Approval Port Use case
    ansible.controller.workflow_job_template:
      name: "New Device Active"
      inventory: "Edge Network"    
      organization: "Default"
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add approval node for workflow
    ansible.controller.workflow_job_template_node:
      validate_certs: false
      organization: "Default"
      workflow_job_template: "New Device Active"
      identifier: new_device_approval
      approval_node:
        description: "New device connected, to you want to configure the network ?"
        name: new_device_approval
        timeout: 3600
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add remediation node for workflow
    ansible.controller.workflow_job_template_node:
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false
      organization: "Default"
      workflow_job_template: "New Device Active"
      identifier: new_port
      unified_job_template: "New Port Configuration"

  - name: Link remediation and approval node
    ansible.controller.workflow_job_template_node:
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false
      organization: "Default"
      workflow_job_template: "New Device Active"
      identifier: new_device_approval
      success_nodes:
        - new_port

# ###############EDA###############     

  - name: Create an AAP Credential
    ansible.eda.credential:
      name: "AAP"
      description: "To execute jobs from EDA"
      inputs:
        host: "https://control/api/controller/"
        username: "admin"
        password: "ansible123!"
      credential_type_name: "Red Hat Ansible Automation Platform"
      organization_name: Default
      controller_host: https://localhost
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Create EDA Decision Environment
    ansible.eda.decision_environment:
      name: "Network Telemetry"
      description: "Network/Kafka"
      image_url: "quay.io/nmartins/network_de"
   #   credential: "Example Credential"
      organization_name: Default
      state: present
      controller_host: https://localhost
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Create EDA Decision Environment
    ansible.eda.decision_environment:
      name: "Web Server"
      description: "Webserver/Kafka"
      image_url: "quay.io/nmartins/network_de"
   #   credential: "Example Credential"
      organization_name: Default
      state: present
      controller_host: https://localhost
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Create EDA Projects
    ansible.eda.project:
      name: "Roadshow"
      description: "Roadshow Rulebooks"
      url: https://github.com/ansible-tmm/aap25-roadshow.git
      organization_name: Default
      state: present
      controller_host: https://localhost
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

  - name: Add Insights Project
    ansible.controller.project:
      name: "Insights"
      description: "Red Hat Insights"
      organization: "Default"
      scm_type: insights
 #     scm_url: https://github.com/nmartins0611/aap25-roadshow-content.git
      credential: Insights
      state: present
      controller_host: "https://localhost"
      controller_username: admin
      controller_password: ansible123!
      validate_certs: false

EOF

# chown files
sudo chown rhel:rhel /tmp/setup.yml
sudo chown rhel:rhel /tmp/inventory

sleep 20


git clone https://github.com/ansible-tmm/aap25-roadshow.git /home/rhel/roadshow

chmod -R 777 /home/rhel/roadshow
chmod +x /home/rhel/roadshow/lab-resources/hackbot.sh
sudo chown rhel:rhel /home/rhel/roadshow/lab-resources/hackbot.sh

ANSIBLE_COLLECTIONS_PATH=/tmp/ansible-automation-platform-containerized-setup-bundle-2.5-9-x86_64/collections/:/root/.ansible/collections/ansible_collections/ ansible-playbook -i /tmp/inventory /tmp/setup.yml
