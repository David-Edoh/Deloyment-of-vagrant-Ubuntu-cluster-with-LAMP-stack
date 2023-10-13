# Deloyment of vagrant Ubuntu cluster with LAMP stack

## Introduction

The Vagrant VM Setup script automates the creation and configuration of Virtual Machines (VMs) using Vagrant. It is designed to set up a master VM and a slave VM, configure user management, enable inter-node communication, copy files between VMs, install a LAMP stack, and validate PHP functionality with Apache.

## Usage

To use the script, follow these steps:

1. **Run the Script:**

   ```bash
   ./master_slave.sh
   ```


2. **Optional Arguments:**

   - `-u <username>`: Set the desired username for VMs (default: altschool).
   - `-p <password>`: Set the desired password for VMs (default: password123).

## Script Workflow

### 1. VM Creation and Provisioning

The script creates 'Master' and 'Slave' VMs using Vagrant. It defines VM names, memory, and box configurations in a Vagrantfile. VMs are then started, and their IP addresses are retrieved.

### 2. User Management

User 'altschool' is set up on both VMs with the specified username and password. SSH key-based authentication is configured between the master and slave VMs.

### 3. Inter-Node Communication

The public key of the master VM is copied to the authorized keys of the slave VM, enabling secure communication between them.

### 4. File Copying

Contents of the '/mnt/altschool' directory on the master VM are copied to '/mnt/altschool/slave' on the slave VM using SCP.

### 5. Process Monitoring

An overview of Linux process management is displayed on the master VM using the 'ps aux' command.

### 6. LAMP Stack Setup

A LAMP (Linux, Apache, MySQL, PHP) stack is installed on both master and slave VMs. MySQL root password is configured, and Apache is enabled.

### 7. PHP Functionality Validation

A PHP test file is created and moved to the Apache web server directory on both VMs. The script provides URLs to validate PHP functionality on both VMs.

## Error Handling

The script performs checks for VM status, directory existence, and file existence. If errors are encountered, appropriate error messages are displayed.

## Notes

- The script assumes VirtualBox as the provider and uses the 'ubuntu/bionic64' box.
- It is recommended to run the script in a clean environment to avoid conflicts.

## Conclusion

The Vagrant VM Setup script automates the process of creating, configuring, and interconnecting VMs for development purposes. It streamlines user management, inter-node communication, file copying, and LAMP stack setup, providing a comprehensive environment for development and testing.
