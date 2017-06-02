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

# update the public/private key
private_key_path="/home/${target_user}/.ssh/id_rsa"
public_key_path="/home/${target_user}/.ssh/id_rsa.pub"

# Create public/private Keys
echo $public_key  > $public_key_path
exit_on_error "Unable to write public key data to ${public_key_path}"

echo $private_key > $private_key_path
exit_on_error "Unable to write private key data to ${private_key_path}"


# Setup permissions for public/private key
chmod 644 $public_key_path
exit_on_error "Unable set permissions for public key at ${public_key_path}"

chmod 600 $private_key_path
exit_on_error "Unable set permissions for private key at ${public_key_path}"


echo "Completed Key Rotation for ${target_user}"