#!/bin/bash

################################################################################
# proc_net_logger.sh - Periodically get network stats in /proc/net, send to rsyslog     
#  
# Copyright 2019 by David Brenner Jr <david.brenner.jr@gmail.com>
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation; either version 3 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
# details.
#
# You should have received a copy of the GNU General Public License along with
# this program. If not, see <http://www.gnu.org/licenses/>.
#
# Usage
# ./proc_net_logger.sh <update in seconds> <total runtime in seconds>
################################################################################

# check number of arguments
function check_args() {
  if [ "$BASH_ARGC" != "2" ]; then
    echo -e "FAILURE: Script has missing/invalid options\n"
    echo -e "Usage: ./proc_net_logger.sh <update in seconds> <total runtime in seconds>\n"
    echo 'Examples:'
    echo './proc_net_logger.sh 15 35      collect stats every 15 seconds, stop after 35 seconds'
    echo -e "./proc_net_logger.sh 30 14400   collect stats every 30 seconds, stop after 4 hours\n"
    exit 1
  fi
}
check_args || exit 1

# required tools must be installed. run test immediately.
function check_dependencies() {
  # required packages/tools 
  tools='coreutils bc procps grep rsyslog iproute2 util-linux debianutils lsb-release'
  # required installation status
  status='install ok installed'
  # check dpkg then other packages/tools
  if [ -x /usr/bin/dpkg ]; then
    for name in $tools; do
      # get package status
      package="$(dpkg-query -W --showformat='${Package} ${Status} ${Version}\n' $name | cut -d ' ' -f 1,2,3,4)"
      if [ "$package" != "$(echo $name $status)" ]; then
        echo "FAILURE: Script requires installation of $name"
        exit 1
      fi
    done
  else
    echo "FAILURE: Script requires installation of dpkg to check dependencies"
    exit 1
  fi     
}
check_dependencies || exit 1

# check distribution. run test immediately.
function check_distribution() {
  tested_os='Ubuntu 18'
  # required package to get system info
  package="$(dpkg-query -W --showformat='${Package} ${Status} ${Version}\n' lsb-release | cut -d ' ' -f 1,2,3,4)"
  if [ "$package" != "lsb-release install ok installed" ]; then
    echo -e "WARNING: Can't get OS name/version info using lsb-release"
  else
    # get OS name
    name="$(lsb_release -a 2>/dev/null | head -n 1 | tr ':\t' ' ' | cut -d ' ' -f 4)";
    # get OS version
    version="$(lsb_release -a 2>/dev/null | head -n 3 | tail -n 1 | tr ':\t' ' ' | cut -d ' ' -f 3 | cut -d '.' -f 1)"
    # check host
    if [ "$name $version" != "$tested_os" ]; then
      echo "WARNING: Distribution not supported $name $version"
      echo "Supported distributions: $tested_os"  
    fi
  fi
}
check_distribution

# rsyslog must be running. run test immediately.
function required_service() {
  if [ "$(ps axu | grep rsyslog | head -n 1 | cut -d ' ' -f 1)" = "syslog" ]; then
    if [ "$(ps axu | grep 'rsyslog' | head -n 1 | grep -o -E '/{1}[a-z]*\/{1}[a-z]*\/{1}[a-z]*')" != "/usr/sbin/rsyslogd" ]; then
      echo "FAILURE: Rsyslog service not running" 
      exit 1
    fi;
  fi
}
required_service || exit 1

# create new shell script with temp name
function procnet_logger() {
  # if files exist remove them. else suppress rm errors. always evaluates false
  if [ -e p1log* -a "$(trap 'rm -r -f p1log* 2>/dev/null' EXIT)" ]; then
    echo -n; # intentionally blank
  else
    tempfile -p p1log -d . > /dev/null
    SCRIPT=$(realpath $(ls -1 p1log*))
  fi
  # if files exist remove them. else suppress rm errors. always evaluates false 
  if [ -e p2log* -a "$(trap 'rm -r -f p2log* 2>/dev/null' EXIT)" ]; then
    echo -n; # intentionally blank
  else
    tempfile -p p2log -d . > /dev/null
    LOGS=$(realpath $(ls -1 p2log*))
  fi   
  echo -E '#!/bin/bash
  while sleep $1; do
    for i in $(find /proc/net/* -maxdepth 2 -type f); do
      cat $i | pr | sed -z "s/\n/ /g" >> '$LOGS';' > $SCRIPT
  echo 'done; logger -t SAVE_PROC_NET -f'$LOGS'; done;' >> $SCRIPT
  chmod +x $SCRIPT
}
procnet_logger || exit 1

# get all network statistics from files in directory "/proc/net". INTERVAL
# specifies the number of seconds lnstat gets stats and sends them to logger.
# RUNTIME specifies the maximum number of seconds the loop should be alive.
# DIE ensures timeout kills the loop. sends killed errors to /dev/null via
# tee so final exit code should be 0.
INTERVAL="$1"
RUNTIME="$2""s"
DIE=$(echo "$2 + 2" | bc -q)"s"
timeout -s SIGKILL -k $RUNTIME $DIE $SCRIPT $INTERVAL | tee 2>/dev/null

# cleanup
rm -f $SCRIPT
rm -f $LOGS
unset SCRIPT
unset LOGS
unset RUNTIME
unset DIE
unset INTERVAL

exit 0

