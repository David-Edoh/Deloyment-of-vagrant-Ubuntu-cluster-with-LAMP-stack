#!/bin/bash

# Default username and password
default_username="altschool"
default_password="password123"

master_ip="192.168.56.5"
slave_ip="192.168.56.6"
load_balancer_ip="192.168.56.7"

# Function to display script usage
usage() {
    echo "Usage: $0 [-u <username>] [-p <password>]"
    echo "Options:"
    echo "  -u <username>  Specify the username for creating the VMs (default: $default_username)"
    echo "  -p <password>  Specify the password for creating the VMs (default: $default_password)"
    exit 1
}

# Parse command-line arguments
while getopts "u:p:" opt; do
    case $opt in
        u)
            username="$OPTARG"
            ;;
        p)
            password="$OPTARG"
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            usage
            ;;
    esac
done

# Use default username and password if not provided
username="${username:-$default_username}"
password="${password:-$default_password}"

# Define VM names
master_vm="master"
slave_vm="slave"
load_balancer_vm="lb"

# Define VM configurations
vm_memory="512"
vm_box="ubuntu/bionic64"

# Function to SSH into a VM and execute commands
ssh_exec() {
    vm_name="$1"
    command="$2"
    vagrant ssh "$vm_name" -c "$command"
}

#############################################################
# 1. Create 'Master' and 'Slave' VMs
# Create a Vagrantfile for both 'Master' and 'Slave' VMs
#############################################################
cat <<EOL > Vagrantfile
Vagrant.configure("2") do |config|
  config.vm.define "$master_vm" do |$master_vm|
    $master_vm.vm.box = "$vm_box"
    $master_vm.vm.network "private_network", type: "static", ip: "$master_ip"
    $master_vm.vm.provider "virtualbox" do |vb|
      vb.memory = "$vm_memory"
      vb.cpus = 1
    end
  end

  config.vm.define "$slave_vm" do |$slave_vm|
    $slave_vm.vm.box = "$vm_box"
    $slave_vm.vm.network "private_network", type: "static", ip: "$slave_ip"
    $slave_vm.vm.provider "virtualbox" do |vb|
      vb.memory = "$vm_memory"
      vb.cpus = 1
    end
  end

  config.vm.define "$load_balancer_vm" do |$load_balancer_vm|
    $load_balancer_vm.vm.box = "$vm_box"
    $load_balancer_vm.vm.network "private_network", type: "static", ip: "$load_balancer_ip"
    $load_balancer_vm.vm.provider "virtualbox" do |vb|
      vb.memory = "$vm_memory"
      vb.cpus = 1
    end
  end
  
end
EOL
# Start both master and slave VMs
echo "Creating and provisioning '$master_vm' and '$slave_vm' VMs..."
vagrant up

# Check if all VMs are up and running else exit....
if [ "$(vagrant status | grep -c 'running')" -ne 3 ]; then
    echo "Error: Not all VMs are running."
    echo "Error may be due to dhcp clash or Host's BIOS vtx settings"
    echo "Exiting...."
    exit 1
fi

# Get the IP address of the 'Slave' VM
slave_ip_addr=$(ssh_exec "$slave_vm" "hostname -I | awk '{print \$2}'" | tr -d '\r')


#############################################################
# 2. (User Managemant) Setup altschool user for both VMs
# SSH into VMs and execute common provisioning steps
#############################################################
for vm in "$master_vm" "$slave_vm"; do
    echo "Provisioning '$vm' node with username: $username, password: xxxxxx..."
    ssh_exec "$vm" "sudo useradd -m $username"
    ssh_exec "$vm" "echo '$username ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/$username"
    ssh_exec "$vm" "echo \"$username:$password\" | sudo chpasswd"
    ssh_exec "$vm" "sudo usermod -aG sudo $username"
    ssh_exec "$vm" "sudo chmod 777 /mnt"
    ssh_exec "$vm" "sudo su - $username -c 'mkdir -p ~/.ssh'"
    ssh_exec "$vm" "sudo su - $username -c 'chmod 700 ~/.ssh'"
    ssh_exec "$vm" "sudo su - $username -c 'touch ~/.ssh/authorized_keys'"
    ssh_exec "$vm" "sudo su - $username -c 'chmod 600 ~/.ssh/authorized_keys'"
    ssh_exec "$vm" "sudo su - $username -c 'touch ~/.ssh/id_rsa'"
    ssh_exec "$vm" "sudo su - $username -c 'chmod 400 ~/.ssh/id_rsa'"
    ssh_exec "$vm" "sudo su - $username -c 'touch ~/.ssh/id_rsa.pub'"
    ssh_exec "$vm" "yes | sudo ssh-keygen -t rsa -N '' -f /home/$username/.ssh/id_rsa"
    ssh_exec "$vm" "sudo su - $username -c 'cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys'"
done


#############################################################
# 3. (Inter-Node Communitcation)
# Copy Master's public key to Slave
#############################################################
echo "Copying $master_vm public key to $slave_vm"
master_public_key=$(vagrant ssh $master_vm -c "sudo su - $username -c 'cat ~/.ssh/id_rsa.pub'")
vagrant ssh $slave_vm -c "echo '$master_public_key' | sudo su - $username -c 'tee -a ~/.ssh/authorized_keys'"
echo "SSH key-based authentication configured."


###########################################################################################
# 4. Copy the content of /mnt/altschool on master to /mnt/altschool/slave on slave node
###########################################################################################

# Check if the parent directory /mnt/altschool exists on the master VM; if not, create it
echo "Checking if /mnt/altschool exists on '$master_vm'..."
if ! ssh_exec "$master_vm" "sudo su - altschool -c '[ -d /mnt/altschool ]'"; then
    echo "Creating /mnt/altschool directory on '$master_vm'..."
    ssh_exec "$master_vm" "sudo su - altschool -c 'mkdir -p /mnt/altschool'"
    ssh_exec "$master_vm" "sudo su - altschool -c 'sudo chmod 777 /mnt/altschool'"
fi

# Check if the parent directory /mnt/altschool/slave exists on the slave VM; if not, create it
echo "Checking if /mnt/altschool/slave exists on '$slave_vm'..."
if ! ssh_exec "$master_vm" "sudo su - altschool -c 'ssh -o StrictHostKeyChecking=no $username@$slave_ip_addr [ -d /mnt/altschool/slave ]'"; then
    echo "Creating /mnt/altschool/slave directory on '$slave_vm'..."
    ssh_exec "$master_vm" "sudo su - altschool -c 'ssh -o StrictHostKeyChecking=no $username@$slave_ip_addr sudo mkdir -p /mnt/altschool/slave'"
    ssh_exec "$master_vm" "sudo su - altschool -c 'ssh -o StrictHostKeyChecking=no $username@$slave_ip_addr sudo chmod 777 /mnt/altschool'"
    ssh_exec "$master_vm" "sudo su - altschool -c 'ssh -o StrictHostKeyChecking=no $username@$slave_ip_addr sudo chmod 777 /mnt/altschool/slave'"
fi

# Create a dummy file on 'Master' VM
dummy_file_path="/mnt/altschool/dummy_file.txt"
if ! ssh_exec "$master_vm" "sudo su - altschool -c '[ -f $dummy_file_path ]'"; then
    echo "Creating a dummy file on '$master_vm' in /mnt/altschool..."
    ssh_exec "$master_vm" "sudo su - altschool -c 'sudo touch $dummy_file_path'"
else
    echo "Dummy file '$dummy_file_path' already exists on '$master_vm'. Skipping creation."
fi

# Copy /mnt/altschool contents from Master to Slave using scp
echo "Copying contents from /mnt/altschool on '$master_vm' to /mnt/altschool/slave on '$slave_vm'..."
ssh_exec "$master_vm" "sudo su - altschool -c 'yes | scp -o StrictHostKeyChecking=no -r /mnt/altschool/ $username@$slave_ip_addr:/mnt/altschool/slave'"


###################################################################################
# 5. (Process monitoring) Display overview of Linux process management on 'Master'
###################################################################################
echo "Overview of Linux process management on '$master_vm':"
ssh_exec "$master_vm" "ps aux"


#############################################################
# 6. Setting up LAMP Stack on Master and Slave node
#############################################################

# Function to set MySQL root password using debconf-set-selections
set_mysql_root_password() {
    local target_vm="$1"
    local target_user="$2"
    local target_ip="$3"
    local password="$4"

    local command="echo 'mysql-server mysql-server/root_password password $password' | sudo debconf-set-selections"
    command+=" && echo 'mysql-server mysql-server/root_password_again password $password' | sudo debconf-set-selections"

    ssh_exec "$target_vm" "sudo su - $target_user -c 'ssh -o StrictHostKeyChecking=no $target_user@$target_ip $command'"
}

# Install LAMP stack on Master VM
echo "Installing LAMP stack on '$master_vm'..."
ssh_exec "$master_vm" "sudo apt-get update"
ssh_exec "$master_vm" "sudo debconf-set-selections <<< 'mysql-server mysql-server/root_password password $password'"
ssh_exec "$master_vm" "sudo debconf-set-selections <<< 'mysql-server mysql-server/root_password_again password $password'"
ssh_exec "$master_vm" "sudo apt-get install -y apache2 mysql-server php libapache2-mod-php php-mysql"
ssh_exec "$master_vm" "sudo systemctl enable apache2"

# Installing LAMP stack on 'Slave' VM orchestrated by 'altschool' user from 'Master' VM
echo "Installing LAMP stack on '$slave_vm' orchestrated by '$username' user from '$master_vm'..."
ssh_exec "$master_vm" "sudo su - $username -c 'ssh -o StrictHostKeyChecking=no $username@$slave_ip_addr sudo apt-get update'"
set_mysql_root_password "$master_vm" "$username" "$slave_ip_addr" "$password"
ssh_exec "$master_vm" "sudo su - $username -c 'ssh -o StrictHostKeyChecking=no $username@$slave_ip_addr sudo apt-get install -y apache2 mysql-server php libapache2-mod-php php-mysql'"
ssh_exec "$master_vm" "sudo su - $username -c 'ssh -o StrictHostKeyChecking=no $username@$slave_ip_addr sudo systemctl enable apache2'"

echo "LAMP stack installed and configured on both nodes."

#############################################################
# 7. Validate PHP functionality with Apache
#############################################################

echo "Testing PHP functionality with Apache on both nodes..."

master_php_content="<h3>PHP setup on the master node</h3></br> <?php phpinfo(); ?>"
ssh_exec "$master_vm" "touch test.php"
ssh_exec "$master_vm" "echo '${master_php_content}' > test.php"
ssh_exec "$master_vm" "sudo mv test.php /var/www/html/"

slave_php_content="<h3>PHP setup on the slave node</h3></br> <?php phpinfo(); ?>"
ssh_exec "$slave_vm" "touch test.php"
ssh_exec "$slave_vm" "echo '${slave_php_content}' > test.php"
ssh_exec "$slave_vm" "sudo mv test.php /var/www/html/"

echo "PHP test files moved to /var/www/html/"

# Get IP addresses of testing php on 'Master' and 'Slave' VMs
master_ip_list=$(ssh_exec "$master_vm" "hostname -I")
slave_ip_list=$(ssh_exec "$slave_vm" "hostname -I")
load_balancer_ip_list=$(ssh_exec "$load_balancer_vm" "hostname -I")

master_ip=$(echo "$master_ip_list" | awk '{print $2}')
slave_ip=$(echo "$slave_ip_list" | awk '{print $2}')
load_balancer_ip=$(echo "$load_balancer_ip_list" | awk '{print $2}')

###############################################################################
# 8. Install and Configure Nginx as a Load Balancer on the load balancer node
###############################################################################

# Install and configure Nginx as a load balancer on the 'load_balancer' VM
echo "Installing and configuring Nginx as a load balancer on '$load_balancer_vm'..."
ssh_exec "$load_balancer_vm" "sudo apt-get update"
ssh_exec "$load_balancer_vm" "sudo apt-get install -y nginx"

# Create an Nginx configuration file for load balancing
nginx_config_file="/etc/nginx/sites-available/load_balancer"
nginx_config_content=$(cat <<EOL
upstream backend {
    server $master_ip weight=1;
    server $slave_ip weight=1;
}

server {
    listen 8080;
    server_name load_balancer;

    location / {
        proxy_pass http://backend;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOL
)
ssh_exec "$load_balancer_vm" "echo '${nginx_config_content}' | sudo tee $nginx_config_file"

# Create a symbolic link to enable the Nginx configuration
ssh_exec "$load_balancer_vm" "sudo ln -s $nginx_config_file /etc/nginx/sites-enabled/"

# Test Nginx configuration and reload Nginx
ssh_exec "$load_balancer_vm" "sudo nginx -t"
ssh_exec "$load_balancer_vm" "sudo systemctl reload nginx"

echo "Nginx load balancer configuration completed."

GREEN=`tput setaf 2`
echo -e ${GREEN}"
###############################################
#           Deployment Successful             #
############################################### \n"

echo "PHP test"
echo "Visit: http://$master_ip/test.php to validate the '$master_vm' PHP setup"
echo -e "Visit: http://$slave_ip/test.php to validate the '$slave_vm' PHP setup \n"

echo "Load balancer test link"
echo "Visit: http://$load_balancer_ip:8080/test.php"
