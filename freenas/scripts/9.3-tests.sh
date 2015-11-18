#!/usr/local/bin/bash
# Author: Kris Moore
# License: BSD
# Location for tests into REST API of FreeNAS 9.3
# Resty Docs: https://github.com/micha/resty
# jsawk: https://github.com/micha/jsawk

# Where is the pcbsd-build program installed
PROGDIR="`realpath | sed 's|/scripts||g'`" ; export PROGDIR

# IP of client we are testing
if [ -n "$1" ] ; then
  ip="$1"
else
  ip="10.0.0.115"
fi

# Set the username / pass of FreeNAS for REST calls
if [ -n "$2" ] ; then
  fuser="$2"
else
  fuser="root"
fi
if [ -n "$3" ] ; then
  fpass="$3"
else
  fpass="testing"
fi

# Source our resty / jsawk functions
. ${PROGDIR}/../utils/resty -W "http://${ip}:80/api/v1.0" -H "Accept: application/json" -H "Content-Type: application/json" -u ${fuser}:${fpass}

# Log files
RESTYOUT=/tmp/resty.out
RESTYERR=/tmp/resty.err

#################################################################
# Run the tests now!
#################################################################

echo_ok()
{
  echo -e " - OK"
}

# Check for $1 REST response, error out if not found
check_rest_response()
{
  grep -q "$1" ${RESTYERR}
  if [ $? -ne 0 ] ; then
    cat ${RESTYERR}
    cat ${RESTYOUT}
    exit 1
  fi
}

check_rest_response_continue()
{
  grep -q "$1" ${RESTYERR}
  return $?
}

# $1 = Command to run
# $2 = Command to run if $1 fails
rc_halt()
{
  ${1} >/tmp/.cmdTest.$$ 2>/.cmdTest.$$
  if [ $? -ne 0 ] ; then
     echo -e " - FAILED"
     ${2}
     echo "Failed running: $1"
     cat /tmp/.cmdTest.$$
     rm /tmp/.cmdTest.$$
     exit 1
  fi
  rm /tmp/.cmdTest.$$
}

set_test_group_text()
{
  GROUPTEXT="$1"
  TOTALTESTS="$2"
  TCOUNT=0
}

echo_test_title()
{
  TCOUNT=`expr $TCOUNT + 1`
  echo -e "Running $GROUPTEXT ($TCOUNT/$TOTALTESTS) - $1\c"
}

storage_tests()
{
  # Set the group text and number of tests
  set_test_group_text "Storage tests" "4"

  # Check getting disks
  echo_test_title "Disks / API functionality"
  GET /storage/disk/ -v 2>${RESTYERR} >${RESTYOUT}
  check_rest_response "200 OK"
  echo_ok

  # Check creating a zpool
  echo_test_title "Creating volume"
  POST /storage/volume/ '{ "volume_name" : "tank", "layout" : [ { "vdevtype" : "stripe", "disks" : [ "ada1", "ada2" ] } ] }' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "201 CREATED"
  echo_ok

  # Check creating a dataset
  echo_test_title "Creating dataset"
  POST /storage/volume/1/datasets/ '{ "name": "share" }' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "201 CREATED"
  echo_ok

  # Set the permissions of the dataset
  echo_test_title "Changing permissions"
  PUT /storage/permission/ '{ "mp_path": "/mnt/tank", "mp_acl": "unix", "mp_mode": "777", "mp_user": "root", "mp_group": "wheel" }' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "201 CREATED"
  echo_ok
}

nfs_tests()
{
  # Set the group text and number of tests
  set_test_group_text "NFS tests" "9"

  # Enable NFS server
  echo_test_title "Creating the NFS server"
  PUT /services/nfs/ '{ "nfs_srv_bindip": "'"${ip}"'", "nfs_srv_mountd_port": 618, "nfs_srv_allow_nonroot": false, "nfs_srv_servers": 10, "nfs_srv_udp": false, "nfs_srv_rpcstatd_port": 871, "nfs_srv_rpclockd_port": 32803, "nfs_srv_v4": false, "id": 1 }' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "200 OK"
  echo_ok

  # Check creating a NFS share
  echo_test_title "Creating a NFS share on /mnt/tank"
  POST /sharing/nfs/ '{ "nfs_comment": "My Test Share", "nfs_paths": ["/mnt/tank"], "nfs_security": "sys" }' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "201 CREATED"
  echo_ok

  # Now start the service
  echo_test_title "Starting NFS service"
  PUT /services/services/nfs/ '{ "srv_enable": true }' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "200 OK"
  echo_ok

  # Now check if we can mount NFS / create / rename / copy / delete / umount
  echo_test_title "Mounting NFS"
  rc_halt "mkdir /tmp/nfs-mnt.$$"
  rc_halt "mount_nfs ${ip}:/mnt/tank /tmp/nfs-mnt.$$" "umount /tmp/nfs-mnt.$$ ; rmdir /tmp/nfs-mnt.$$"
  echo_ok

  echo_test_title "Creating NFS file"
  rc_halt "touch /tmp/nfs-mnt.$$/testfile" "umount /tmp/nfs-mnt.$$ ; rmdir /tmp/nfs-mnt.$$"
  echo_ok

  echo_test_title "Moving NFS file"
  rc_halt "mv /tmp/nfs-mnt.$$/testfile /tmp/nfs-mnt.$$/testfile2"
  echo_ok

  echo_test_title "Copying NFS file"
  rc_halt "cp /tmp/nfs-mnt.$$/testfile2 /tmp/nfs-mnt.$$/testfile"
  echo_ok

  echo_test_title "Deleting NFS file"
  rc_halt "rm /tmp/nfs-mnt.$$/testfile2"
  echo_ok

  echo_test_title "Unmounting NFS"
  rc_halt "umount /tmp/nfs-mnt.$$"
  rc_halt "rmdir /tmp/nfs-mnt.$$"
  echo_ok
}

iscsi_tests()
{
  # Set the group text and number of tests
  set_test_group_text "iSCSI tests" "1"

  # Enable iSCSI server
  echo_test_title "Creating iSCSI extent"
  POST /services/iscsi/extent/ '{ "iscsi_target_extent_type": "File", "iscsi_target_extent_name": "extent", "iscsi_target_extent_filesize": "50MB", "iscsi_target_extent_path": "/mnt/tank/iscsi" }' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "201 CREATED"
  echo_ok

}

cifs_tests()
{
  # Set the group text and number of tests
  set_test_group_text "CIFS tests" "9"

  echo_test_title "Enabling the CIFS service"
  PUT /services/nfs/ '{ "cifs_srv_description": "Test FreeNAS Server", "cifs_srv_guest": "nobody", "cifs_hostname_lookup": false, "cifs_srv_aio_enable": false }' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "200 OK"
  echo_ok

  echo_test_title "Creating a CIFS share on /mnt/tank"
  POST /sharing/cifs/ '{ "cfs_comment": "My Test CIFS Share", "cifs_path": "/mnt/tank", "cifs_name": "TestShare", "cifs_guestok": true, "cifs_vfsobjects": "streams_xattr" }' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "201 CREATED"
  echo_ok

  # Now start the service
  echo_test_title "Starting CIFS service"
  PUT /services/services/cifs/ '{ "srv_enable": true }' -v >${RESTYOUT} 2>${RESTYERR}
  check_rest_response "200 OK"
  echo_ok

  # Now check if we can mount NFS / create / rename / copy / delete / umount
  echo_test_title "Mounting CIFS"
  rc_halt "mkdir /tmp/cifs-mnt.$$"
  rc_halt "mount_smbfs -N -I ${ip} //guest@freenas/TestShare /tmp/cifs-mnt.$$" "umount -f /tmp/cifs-mnt.$$ ; rmdir /tmp/cifs-mnt.$$"
  echo_ok

  echo_test_title "Creating CIFS file"
  rc_halt "touch /tmp/cifs-mnt.$$/testfile" "umount /tmp/cifs-mnt.$$ ; rmdir /tmp/cifs-mnt.$$"
  echo_ok

  echo_test_title "Moving CIFS file"
  rc_halt "mv /tmp/cifs-mnt.$$/testfile /tmp/cifs-mnt.$$/testfile2"
  echo_ok

  echo_test_title "Copying CIFS file"
  rc_halt "cp /tmp/cifs-mnt.$$/testfile2 /tmp/cifs-mnt.$$/testfile"
  echo_ok

  echo_test_title "Deleting CIFS file"
  rc_halt "rm /tmp/cifs-mnt.$$/testfile2"
  echo_ok

  echo_test_title "Unmounting CIFS"
  rc_halt "umount /tmp/cifs-mnt.$$"
  rc_halt "rmdir /tmp/cifs-mnt.$$"
  echo_ok
}


# When running via Jenkins / ATF mode, it may take a variable
# time to boot the system and be ready for REST calls. We run
# an initial test to determine when the interface is up
echo -e "Testing access to REST API\c"
count=0
while :
do
  GET /storage/disk/ -v 2>${RESTYERR} >${RESTYOUT}
  check_rest_response_continue "200 OK"
  if [ $? -eq 0 ] ; then break; fi
  echo -e ".\c"
  sleep 60
  if [ $count -gt 10 ] ; then
     echo "FreeNAS API failed to respond!"
     exit 1
  fi
  count=`expr $count + 1`
done
echo_ok

# Run the storage tests
storage_tests

# Run the CIFS tests
cifs_tests

# Run the iSCSI tests
iscsi_tests

# Run the NFS tests
nfs_tests

# Made it to the end, exit with success!
echo "SUCCESS - REST API testing complete!"
exit 0
