#!/bin/bash
#
# Copyright (c) Microsoft Corporation. All Rights Reserved.
# Licensed under the MIT license. See LICENSE file on the project webpage for details.

#
# This script rotates the SSH key for the OXA STAMP OS Admin User.
#

set -x

# initialize required parameters
encoded_parameters=""
target_user=""
private_key=""
public_key=""

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
          --target-user)
            target_user="${arg_value}"
            ;;
          --private-key)
            private_key=`echo ${arg_value} | base64 --decode`
            ;;
          --public-key)
            public_key=`echo ${arg_value} | base64 --decode`
            ;;
        esac

        shift # past argument or value

        if [ $shift_once -eq 0 ]; 
        then
            shift # past argument or value
        fi

    done
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

# Script self-idenfitication
print_script_header "RotateAdminSshKey Installer"

# pass existing command line arguments
parse_args $@ 

# check if $parameters has been set. If not, bail out
if [ -z "$parameters" == "" ];
then
    log "Parameters not specified and is required"
    exit 3
fi

# process the decoded parameters
parse_args $parameters

# update the public/private key
echo $private_key > "/home/${target_user}/.ssh/id_rsa"
echo $public_key  > "/home/${target-user}/.ssh/id_rsa.pub"

# set the permissions on the public/private key
chmod 600 "/home/${target_user}/.ssh/id_rsa"
chmod 644 "/home/${target-user}/.ssh/id_rsa.pub"

echo "Entering Installer for 'mysqlfscleanup'"
touch /var/log/csx.upgrade.log