#!/bin/bash
# /etc/init.d/wittypi

### BEGIN INIT INFO
# Provides:          wittypi
# Required-Start:    $remote_fs $syslog
# Required-Stop:     $remote_fs $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Witty Pi 3 initialize script
# Description:       This service is used to manage Witty Pi 3 service
### END INIT INFO

case "$1" in
    start)
        echo "Starting Witty Pi 3 Daemon..."
        /home/pi/wittypi/daemon.sh &
	sleep 1
	daemonPid=$(ps --ppid $! -o pid=)
	echo $daemonPid > /var/run/wittypi_daemon.pid
        ;;
    stop)
        echo "Stopping Witty Pi 3 Daemon..."
	daemonPid=$(cat /var/run/wittypi_daemon.pid)
	kill -9 $daemonPid
        ;;
    *)
        echo "Usage: /etc/init.d/wittypi start|stop"
        exit 1
        ;;
esac

exit 0
