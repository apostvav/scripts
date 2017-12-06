#!/bin/bash

# Purge mysql/mariadb binlog files

# default values
masterport=3306
user="root"
dryrun=0

declare -A slaveIO
declare -A slaveSQL
declare -A binlogfiles

# Usage function
usage(){
  echo "Usage: $0 -H HOST -P DBPORT -u DBUSER -p DBPASS"
}

# get binlog position
getpos() {
    local pos=$(cut -d. -f2 <<< "$1")
    echo $pos
}

# Parse arguments
while getopts ":H:P:u:p:ch" opt; do
  case $opt in
    H) # database hostname
      masterhost=$OPTARG
      ;;
    P) # database port
      masterport=$OPTARG
      ;;
    u) # database username
      user=$OPTARG
      ;;
    p) # database password
      pass=$OPTARG
      ;;
    c) # check mode
      dryrun=1
      ;;
    h) # help
      usage
      exit 0
      ;;
    \?)
      echo "ERROR: Invalid option: -$OPTARG"
      usage
      exit 1
      ;;
    :)
      echo "ERROR: Option -$OPTARG requires an argument."
      exit 1
      ;;
  esac
done

shift $(($OPTIND - 1))

if [ ! "$masterhost" ] || [ ! "$pass" ]
then
    echo "UNKNOWN: Mandatory options are missing"
    exit 1
fi

# get slaves "host:port"
output=$(mysql --host=$masterhost --port=$masterport --user=$user --password=$pass  -s -N -e "SHOW SLAVE HOSTS")
if [ "$?" -eq 1 ]; then
    echo "ERROR: No response from master"
    exit 1
elif [ -z "$output"]; then
    echo "No slave hosts returned"
    exit 0
fi
slaves=( $(printf "$output" | awk '{print $2":"$3}') )

# gather slaves info
for slave in "${slaves[@]}"
do
    IFS=":" read host port <<< "$slave"
    output=$(mysql --host=$host --port=$port --user=$user --password=$pass -e "SHOW SLAVE STATUS\G")

    if [ "$?" -eq 1 ]; then
        echo "ERROR: No response from slave $host"
        exit 1
    fi

    slaveIO[$slave]=$(grep "Slave_IO_Running" <<< "$output" | awk '{print $2}')
    slaveSQL[$slave]=$(grep "Slave_SQL_Running" <<< "$output" | awk '{print $2}')

    # check replication status
    if [ "$slaveIO[$slave]" == "NO" ] || [ "$slaveSQL[$slave]" == "NO" ]; then
        echo "ERROR: $slave replication stopped"
        exit 1
    fi

    binlogfiles[$slave]=$(grep "Relay_Master_Log_File" <<< "$output" | awk '{print $2}')

    # check binlog file name
    if ! [[ $binlogfiles[$slave] =~ ^mariadb-bin\.[0-9]+$ ]] && ! [[ $binlogfiles[$slave] =~ ^mysql-bin.[0-9]+$ ]]; then
        echo "ERROR: binlog $binlogfiles[$slave] file name is not valid"
        exit 1
    fi
done

# determine the earliest log file among all the slaves
binlog="$binlogfiles[$slaves[0]]"
for slave in "${slaves[@]}"
do
    tmp="$binlogfiles[$slave]"
    if [ "$(getpos $tmp)" -lt "$(getpos $binlog)" ]; then
        $binlog="$tmp"
    fi
done

if [ "$dryrun" -eq 1 ]; then
    echo "Running in dry mode, nothing will be purged"
    echo "command: PURGE BINARY LOGS TO '$binlog'"
    exit 0
else
    echo "Purgin binlogs to $binlog"
    mysql --host=$masterhost --port=$masterport --user=$user --password=$pass -e "PURGE BINARY LOGS TO '$binlog'"
    echo "Job is done"
fi
