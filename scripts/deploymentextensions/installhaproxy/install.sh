#!/bin/bash
#
# Copyright (c) Microsoft Corporation. All Rights Reserved.
# Licensed under the MIT license. See LICENSE file on the project webpage for details.

#
# This script installs and configures HAProxy for Mysql Load Balancing and supporting seamless failover.
# It also installs the xinetd service for providing a custom status check on the mysql backends to ensure
# that HAProxy only communicates with the Mysql Master (since we have a master-slave setup)
#

package_name="installhaproxy"

# Oxa Tools
# Settings for the OXA-Tools public repository 
oxa_tools_public_github_account="Microsoft"
oxa_tools_public_github_projectname="oxa-tools"
oxa_tools_public_github_projectbranch="oxa/master.fic"
oxa_tools_public_github_branchtag=""
oxa_tools_repository_path="/oxa/oxa-tools"

# Initialize required parameters
# this is the server that will run HA Proxy
target_server="10.0.0.16"

# this is a space-separated list (originally base64-encoded) of mysql servers in the replicated topology. The master is listed first followed by 2 slaves
mysql_master_server_ip=""
mysql_slave1_server_ip=""
mysql_slave2_server_ip=""
mysql_server_list=""
mysql_server_port="3306"

mysql_admin_username=""
mysql_admin_password=""

# haproxy settings
haproxy_port="3308"
haproxy_username="haproxy_check"
haproxy_initscript="/etc/default/haproxy"
haproxy_configuration_file="/etc/haproxy/haproxy.cfg"
haproxy_configuration_template_file="${oxa_tools_repository_path}/scripts/deploymentextensions/${package_name}/haproxy.template.cfg"

# operation mode: 0=local, 1=remote via ssh
remote_mode=0

# Email Notifications
notification_email_subject="Move Mysql Data Directory"
admin_email_address=""

# probe Settings
network_services_file="/etc/services"

xinet_service_description="# Mysql Master Probe"
xinet_service_port_regex="${probe_port}\/tcp"
xinet_service_line_regex="^${xinet_service_name}.*${xinet_service_port_regex}.*"
xinet_service_line="${xinet_service_name} \t ${probe_port} \t\t ${xinet_service_description}"
xinet_service_name="mysqlmastercheck"

probe_source_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
probe_service_configuration_template="${oxa_tools_repository_path}/scripts/deploymentextensions/${package_name}/service_configuration.template.sh"
probe_script_source="${oxa_tools_repository_path}/scripts/deploymentextensions/${package_name}/${xinet_service_name}.sh"
probe_script_installation_directory="/opt"
probe_script="${probe_script_installation_directory}/${xinet_service_name}"
probe_port=12010

service_user=""

#############################################################################
# parse the command line arguments

parse_args() 
{
    while [[ "$#" -gt 0 ]]
    do
        arg_value="${2}"
        shift_once=0

        if [[ "${arg_value}" =~ "--" ]]; 
        then
            arg_value=""
            shift_once=1
        fi

         # Log input parameters to facilitate troubleshooting
        echo "Option '${1}' set with value '"${arg_value}"'"

        case "$1" in
          --oxatools-public-github-accountname)
            oxa_tools_public_github_account="${arg_value}"
            ;;
          --oxatools-public-github-projectname)
            oxa_tools_public_github_projectname="${arg_value}"
            ;;
          --oxatools-public-github-projectbranch)
            oxa_tools_public_github_projectbranch="${arg_value}"
            ;;
          --oxatools-public-github-branchtag)
            oxa_tools_public_github_branchtag="${arg_value}"
            ;;
          --oxatools-repository-path)
            oxa_tools_repository_path="${arg_value}"
            ;;
          --admin-email-address)
            admin_email_address="${arg_value}"
            ;;
          --target-server)
            target_server="${arg_value}"
            ;;
          --mysql-server-port)
            mysql_server_port="${arg_value}"
            ;;
          --mysql-admin-username)
            mysql_admin_username="${arg_value}"
            ;;
          --mysql-admin-password)
            mysql_admin_password="${arg_value}"
            ;;
          --haproxy-server-port)
            haproxy_port="${arg_value}"
            ;;
          --mysql-server-list)
            mysql_server_list=(`echo ${arg_value} | base64 --decode`)
            ;;
          --component)
            component="${arg_value}"
            ;;
          --probe-port)
            probe_port="${arg_value}"
            ;;
          --service-user)
            service_user="${arg_value}"
            ;;
          --remote)
            remote_mode=1
            ;;
        esac

        shift # past argument or value

        if [ $shift_once -eq 0 ]; 
        then
            shift # past argument or value
        fi

    done
}


copy_bits()
{

    bitscopy_target_server=$1

    # copy the installer & the utilities files to the target server & ssh/execute the Operations
    scp $current_path/install.sh "${bitscopy_target_server}":~/
    exit_on_error "Unable to copy installer script to '${bitscopy_target_server}' from '${HOSTNAME}' !" $ERROR_HAPROXY_INSTALLER_FAILED, $notification_email_subject $admin_email_address

    scp $current_path/utilities.sh "${bitscopy_target_server}":~/
    exit_on_error "Unable to copy utilities to '${bitscopy_target_server}' from '${HOSTNAME}' !" $ERROR_HAPROXY_INSTALLER_FAILED, $notification_email_subject $admin_email_address

}

execute_remote_command()
{
    remote_execution_server_target=$1

    # build the command for remote execution (basically: pass through all existing parameters)
    $encoded_server_list=`echo ${mysql_server_list} | base64`
    
    repository_parameters="--oxatools-public-github-accountname ${oxa_tools_public_github_account} --oxatools-public-github-projectname ${oxa_tools_public_github_projectname} --oxatools-public-github-projectbranch ${oxa_tools_public_github_projectbranch} --oxatools-public-github-branchtag ${oxa_tools_public_github_branchtag} --oxatools-repository-path ${oxa_tools_repository_path}"
    mysql_parameters="--mysql-server-port ${mysql_server_port} --mysql-admin-username ${mysql_admin_username} --mysql-admin-password ${mysql_admin_password} --haproxy-server-port ${haproxy_port} --mysql-server-list ${encoded_server_list}"
    misc_parameters="--admin-email-address ${admin_email_address} --target-server ${target_server} --probe-port ${probe_port} --service-user ${service_user} --component ${component} --remote"

    remote_command="sudo bash ~/install.sh ${repository_parameters} ${mysql_parameters} ${misc_parameters}"

    # run the remote command
    ssh "${remote_execution_server_target}":~/ $remote_command
    exit_on_error "Could not execute the installer on the remote target: ${remote_execution_server_target} from '${HOSTNAME}' !" $ERROR_HAPROXY_INSTALLER_FAILED, $notification_email_subject $admin_email_address
}

###############################################
# START CORE EXECUTION
###############################################

# Source our utilities for logging and other base functions (we need this staged with the installer script)
# the file needs to be first downloaded from the public repository
current_path="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
utilities_path=$current_path/utilities.sh

# check if the utilities file exists. If not, bail out.
if [[ ! -e $utilities_path ]]; 
then  
    echo :"Utilities not present"
    exit 3
fi

# source the utilities now
source $utilities_path

# Script self-identification
print_script_header "HA Proxy Installer"

# pass existing command line arguments
parse_args $@

# sync the oxa-tools repository
repo_url=`get_github_url "$oxa_tools_public_github_account" "$oxa_tools_public_github_projectname"`
sync_repo $repo_url $oxa_tools_public_github_projectbranch $oxa_tools_repository_path $access_token $oxa_tools_public_github_branchtag


# execute the installer remotely
if [[ $remote == 0 ]];
then
    # at this point, we are on the jumpbox attempting to execute the installer on the remote target 

    # Install Xinetd
    # As a supporting requirement, install & configure xinetd on all mysql servers specified (the members of the replication topology)
    # this is triggered from the JB but executed remotely on each mysql server specified
    if [[ "${component,,}" != "xinetd" ]]; 
    then

        log "Initiating report installation of xinetd"

        # turn on component deployment
        component="xinetd"

        for server in "${mysql_server_list[@]}"
        do
            # copy the bits
            copy_bits $server

            # execute the component deployment
            execute_remote_command $server
        done

        # turn off component deployment
        component=""

        log "Completed xinetd installation"
        exit
    fi

    # Install HAProxy
    log "Initiating remote installation of haproxy"

    # copy the installer & the utilities files to the target server & ssh/execute the Operations
    copy_bits $target_server

    # execute the component deployment
    execute_remote_command $server

    log "Completed Remote execution successfully"
    exit
fi

#############################################
# Main Operations
# this should run on the target server
#############################################

# check for component installation mode
if [[ "${component,,}" == "xinetd" ]]; 
then

    # 1. install the service
    log "Installing & Configuring xinetd"

    install-xinetd
    exit_on_error "Could not install xinetd on ${HOSTNAME} }' !" $ERROR_XINETD_INSTALLER_FAILED, $notification_email_subject $admin_email_address

    # 2. Copy custom probe script to /opt & update the permissions
    log "Copying the probe script and updating its permissions"

    cp  $probe_script_source $probe_script
    exit_on_error "Could not copy the probe script '${probe_script_source}' to the target directory '${probe_script_installation_directory}' xinetd on ${HOSTNAME}' !" $ERROR_XINETD_INSTALLER_FAILED, $notification_email_subject $admin_email_address

    chmod 700 $probe_script
    exit_on_error "Could not update permissions for the probe script '${probe_script}' on '${HOSTNAME}' !" $ERROR_XINETD_INSTALLER_FAILED, $notification_email_subject $admin_email_address

    chown $service_user:$service_user $probe_script
    exit_on_error "Could not update ownership for the probe script '${probe_script}' on '${HOSTNAME}' !" $ERROR_XINETD_INSTALLER_FAILED, $notification_email_subject $admin_email_address

    # inject the parameter overrides
    sed -i "s/^mysql_user=.*/${mysql_admin_username}/I" $probe_script
    sed -i "s/^mysql_user_password=.*/${mysql_admin_password}/I" $probe_script
    sed -i "s/^replication_serverlist.*/${mysql_server_list}/I" $probe_script

    # 3. Add probe port to /etc/services
    log "Adding the probe service to network service configuration"

    # backup the services file
    cp "${network_services_file}"{,.backup}
    exit_on_error "Could not backup the network service file at '${network_services_file}' on ${HOSTNAME}' !" $ERROR_XINETD_INSTALLER_FAILED, $notification_email_subject $admin_email_address

    # check if the port is used, if it is, test if it is used for our service, if so, remove the existing line and add the new one
    existing_service_line=`grep "${xinet_service_port_regex}" "${network_services_file}"`
    if [[ -z $existing_service_line ]] || ( [[ ! -z $existing_service_line ]] && [[ `echo ${existing_service_line} | grep ${xinet_service_line_regex}` ]] );
    then
        if [[ ! -z $existing_service_line ]]; 
        then
            # this is a previous version of the mysql probe, remove it
            sed -i "/${xinet_service_line_regex}/ d" $network_services_file
        fi

        # append a new line to the file
        echo "${xinet_service_line}" >> $network_services_file
        exit_on_error "Could not append network service configuration for the probe.' !" $ERROR_XINETD_INSTALLER_FAILED, $notification_email_subject $admin_email_address
    else
        # some other service is using the port
        log "${probe_port} is in use by another service: ${existing_service_line}"
        exit $ERROR_XINETD_INSTALLER_FAILED
    fi

    # 4. Setup xinetd config for the probe service
    log "Setting up probe service configuration"

    xinetd_service_configuration_file="/etc/xinetd.d/${xinet_service_name}"
    cp "${probe_source_dir}/service_configuration.template" $xinetd_service_configuration_file
    exit_on_error "Could not copy the service configuration to '${xinetd_service_configuration_file}' on ${HOSTNAME}' !" $ERROR_HAPROXY_INSTALLER_FAILED, $notification_email_subject $admin_email_address

    sed -i "s/{service_port}/${probe_port}/I" $xinetd_service_configuration_file
    sed -i "s/{service_user}/${service_user}/I" $xinetd_service_configuration_file
    sed -i "s/{script_path}/${probe_script}/I" $xinetd_service_configuration_file

    # 5. Restart xinetd
    log "Restarting xinetd"

    restart_xinetd
    exit_on_error "Could not restart xinet after updating the service configuration on ${HOSTNAME}' !" $ERROR_HAPROXY_INSTALLER_FAILED, $notification_email_subject $admin_email_address

    log "Completed Remote execution successfully"
    exit
fi


log "Starting HAProxy installation on ${HOSTNAME}"

# setup the server references
mysql_master_server_ip=${mysql_server_list[0]}
mysql_slave1_server_ip=${mysql_server_list[1]}
mysql_slave2_server_ip=${mysql_server_list[2]}

# 1. Create the HA Proxy Mysql account on the master mysql server
mysql -u ${mysql_admin_username} -p${mysql_admin_password} -h ${mysql_master_server_ip} -e "INSERT INTO mysql.user (Host,User) values ('${target_server}','${haproxy_username}') ON DUPLICATE KEY UPDATE Host='${target_server}', User='${haproxy_username}'; FLUSH PRIVILEGES;"
exit_on_error "Unable to create HA Proxy Mysql account on '${HOSTNAME}' !" $ERROR_HAPROXY_INSTALLER_FAILED, $notification_email_subject $admin_email_address

# Validate user access
database_list=`mysql -u ${haproxy_username} -N -h ${mysql_master_server_ip} -e "SHOW DATABASES"`
exit_on_error "Unable to access the target server using ${haproxy_username}@${mysql_master_server_ip} without password from '${HOSTNAME}' !" $ERROR_HAPROXY_INSTALLER_FAILED, $notification_email_subject $admin_email_address

# 2. Install HA Proxy
stop_haproxy
install_haproxy

# 3. Configure HA Proxy

# 3.1 Enable HA Proxy to be initialized from startup script
enabled_regex="^ENABLED=.*"

if grep -Gxq $enabled_regex $haproxy_initscript;
then
    # Existing Alias: Override it
    sed -i "s/${enabled_regex}/ENABLED=1/I" $haproxy_initscript
else
    # Alias doesn't exist: Append It
    cat "ENABLED=1" >> $haproxy_initscript
fi

# 3.2 Update the HA Proxy configuration
if [ -f "${haproxy_configuration_file}" ];
then
    mv "${haproxy_configuration_file}"{,.bak}
    exit_on_error "Unable to backup the HA Proxy configuration file at ${haproxy_configuration_file} !" $ERROR_HAPROXY_INSTALLER_FAILED, $notification_email_subject $admin_email_address
fi

cp  "${haproxy_configuration_template_file}" "${haproxy_configuration_file}"
exit_on_error "Unable to copy the HA Proxy configuration template from  the target server using ${haproxy_username}@${mysql_master_server_ip} without password from '${HOSTNAME}' !" $ERROR_HAPROXY_INSTALLER_FAILED, $notification_email_subject $admin_email_address

log "Replacing template variables"

# we are doing the installation locally on the haproxy target server. Limit access to the proxy to the local network
haproxy_server_ip=`ifconfig | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p'`

sed -i "s/{HAProxyIpAddress}/${haproxy_server_ip}/I" "${haproxy_configuration_file}"
sed -i "s/{HAProxyPort}/${haproxy_port}/I" "${haproxy_configuration_file}"
sed -i "s/{ProbePort}/${probe_port}/I" "${haproxy_configuration_file}"
sed -i "s/{MysqlServerPort}/${mysql_server_port}/I" "${haproxy_configuration_file}"
sed -i "s/{MysqlMasterServerIP}/${mysql_master_server_ip}/I" "${haproxy_configuration_file}"
sed -i "s/{MysqlSlave1ServerIP}/${mysql_slave1_server_ip}/I" "${haproxy_configuration_file}"
sed -i "s/{MysqlSlave2ServerIP}/${mysql_slave2_server_ip}/I" "${haproxy_configuration_file}"


# 3.3 Start HA Proxy
start_haproxy
exit_on_error "Unable to start HA Proxy on '${HOSTNAME}' !" $ERROR_HAPROXY_INSTALLER_FAILED, $notification_email_subject $admin_email_address

# 3.4 Final validation
database_list=`mysql -u ${mysql_admin_username} -p${mysql_admin_password} -h ${mysql_master_server_ip} -P ${haproxy_port} -e "SHOW DATABASES;"`
exit_on_error "Unable to access the target server using ${mysql_admin_username}@${mysql_master_server_ip} from '${HOSTNAME}' !" $ERROR_HAPROXY_INSTALLER_FAILED, $notification_email_subject $admin_email_address

if [[ -z "${database_list// }" ]];
then    
    log "The database list returned is empty: '${database_list}'"
    exit $ERROR_HAPROXY_INSTALLER_FAILED
fi

log "Completed HA Proxy installation ${target_user}"