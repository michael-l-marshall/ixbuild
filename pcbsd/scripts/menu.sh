#!/bin/sh

# Where is the pcbsd-build program installed
PROGDIR="`realpath | sed 's|/scripts||g'`" ; export PROGDIR

# Source the config file
. ${PROGDIR}/pcbsd.cfg

cd ${PROGDIR}/scripts

# Source our functions
. ${PROGDIR}/scripts/functions.sh

# Check requirements
${PROGDIR}/scripts/checkprogs.sh

if [ `id -u` != "0" ] ; then
   exit_err "Whoops! Need to run me as root!"
fi

# Set answer file
ans="/tmp/.ans.$$"

upload_menu()
{
  sh ${PROGDIR}/scripts/upload.sh
}

ports_menu()
{
  cd ${PROGDIR}/scripts
  TITLE="Ports Menu"
  while :
  do
    cd ${PROGDIR}/scripts
    dialog --backtitle "$TITLE" --menu "Select a build option:" 14 40 40 merge "Update just PC-BSD ports" pup "Update entire ports tree" back "Back" 2>${ans}
  if [ $? -ne 0 ] ; then
     echo "Canceled!"
     exit 1
  fi
    case `cat $ans` in
        pup) ./portbuild.sh portsnap ; rtn ;;
      merge) ./portbuild.sh portmerge ; rtn ;;
       back) break ;;
          *) ;; 
    esac
  done

};


cd ${PROGDIR}/scripts


while :
do

TITLE="Main Menu"

cd ${PROGDIR}/scripts

if [ -e "upload.sh" ]; then
  # Start the main dialog
  dialog --backtitle "$TITLE" --menu "Select a build option:" 16 50 40 world "Rebuild World/Kernel" packages "Build packages (Poudriere)" iso "Create ISO Files" ports "Ports menu" upload "Upload menu" exit "Exit" 2>${ans}
else
  dialog --backtitle "$TITLE" --menu "Select a build option:" 16 50 40 world "Rebuild World/Kernel" packages "Build packages (Poudriere)" iso "Create ISO Files" ports "Ports menu" exit "Exit" 2>${ans}
fi

if [ $? -ne 0 ] ; then
   echo "Canceled!"
   exit 1
fi
case `cat $ans` in
    world) echo "Rebuild the FreeBSD world?"
           echo -e "(Y/N)\c"
           read tmp
           if [ "$tmp" = "Y" -o "$tmp" = "y" ] ; then 
	      ./build-iso.sh world
	   fi
           rtn
           ;;
      iso) rm ${PROGDIR}/log/.done_9 2>/dev/null
           ./build-iso.sh iso
           echo "ISO files created in ${PROGDIR}/iso"
           rtn ;;
 packages) ./build-iso.sh packages ; rtn ;;
    ports) ports_menu ;;
   upload) upload_menu ;;
     exit) exit 0 ;;
        *) ;; 
esac

done
