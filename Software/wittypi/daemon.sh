#!/bin/bash
# file: daemon.sh
#
# This script should be auto started, to support WittyPi hardware
#

# get current directory
cur_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# utilities
. "$cur_dir/utilities.sh"

TIME_UNKNOWN=1
log 'Witty Pi daemon (v4.21) is started.'

# system information
os=$(get_os)
kernel=$(get_kernel)
arch=$(get_arch)
log "System: $os, Kernel: $kernel, Architecture: $arch"

# log Raspberry Pi model
pi_model=$(get_pi_model)
log "Running on $pi_model"

# check 1-wire confliction
if one_wire_confliction ; then
  log "Confliction: 1-Wire interface is enabled on GPIO-$HALT_PIN, which is also used by Witty Pi."
  log 'Witty Pi daemon can not work until you solve this confliction and reboot Raspberry Pi.'
  exit
fi

# do not run further if wiringPi is not installed
if ! hash gpio 2>/dev/null; then
  log 'Seems wiringPi is not installed, please run again the latest installation script to fix this.'
  exit
fi

# make sure the halt pin is input with internal pull up
gpio -g mode $HALT_PIN up
gpio -g mode $HALT_PIN in


# check if micro controller presents
has_mc=$(is_mc_connected)
for i in {1..5}; do
  if [ $has_mc == 1 ] ; then
    break;
  fi
  # wait for MCU ready
  log 'Witty Pi is not detected, retry in one second...'
  sleep 1
  has_mc=$(is_mc_connected)
done


if [ $has_mc == 1 ] ; then

  # log the I2C_CONF_RTC_OFFSET
  offset=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_CONF_RTC_OFFSET)
  log "RTC offset register has value $offset"

  # make sure register I2C_RTC_CTRL1 is 0
  i2c_write 0x01 $I2C_MC_ADDRESS $I2C_RTC_CTRL1 0
  
  # synchronize system and RTC time
  if [ $(rtc_has_bad_time) == 1 ]; then
    log 'RTC has bad time, write system time into RTC'
    system_to_rtc
  else
    log 'Seems RTC has good time, write RTC time into system'
    rtc_to_system
  fi

  # check if system was shut down because of low-voltage
  recovery=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_LV_SHUTDOWN)
  if [ $recovery == '0x01' ]; then
    log 'System was previously shut down because of low-voltage.'
  fi
  # print out firmware ID
  firmwareID=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_ID)
  log "Firmware ID: $firmwareID"
  # print out firmware revision
  firmwareRev=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_FW_REVISION)
  log "Firmware Revison: $firmwareRev"
  # print out current voltages and current
  vout=$(get_output_voltage)
  iout=$(get_output_current)
  if [ $(get_power_mode) -eq 0 ]; then
    log "Current Vout=${vout}V, Iout=${iout}A"
  else
    vin=$(get_input_voltage)
    log "Current Vin=${vin}V, Vout=${vout}V, Iout=${iout}A"
  fi

  # if temperature sensor thresholds are not set, set them now
  btp=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_CONF_BELOW_TEMP_POINT)
  otp=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_CONF_OVER_TEMP_POINT)
  if [ $btp == '0x00' ] && [ $otp == '0x00' ]; then
    i2cset -y 0x01 $I2C_MC_ADDRESS $I2C_LM75B_THYST 0x004b w
    i2cset -y 0x01 $I2C_MC_ADDRESS $I2C_LM75B_TOS 0x0050 w
  fi
fi

# check and clear alarm flags
if [ $has_mc == 1 ] ; then
  flag1=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_CONF_FLAG_ALARM1)
  flag2=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_CONF_FLAG_ALARM2)
  if [ "$flag1" == "1" ]; then
    # woke up by alarm 1 (startup)
    log 'System startup as scheduled.'
  elif [ "$flag2" == "1" ] ; then
    # woke up by alarm 2 (shutdown), turn it off immediately, this should never happen
    log 'Seems I was unexpectedly woken up by shutdown alarm, must go back to sleep...'
    do_shutdown $HALT_PIN $has_mc
  fi
  clear_alarm_flags

  reason=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_ACTION_REASON)
  if [ "$reason" == $REASON_ALARM1 ]; then
    log 'System starts up because scheduled startup is due.'
  elif [ "$reason" == $REASON_CLICK ]; then
    log 'System starts up because the button is clicked.'
  elif [ "$reason" == $REASON_VOLTAGE_RESTORE ]; then
    log 'System starts up because the input voltage reaches the restore voltage.'
  elif [ "$reason" == $REASON_OVER_TEMPERATURE ]; then
    log 'System starts up because temperature is higher than preset value.'
    log "$(get_temperature)"
  elif [ "$reason" == $REASON_BELOW_TEMPERATURE ]; then
    log 'System starts up because temperature is lower than preset value.'
    log "$(get_temperature)"
  elif [ "$reason" == $REASON_ALARM1_DELAYED ]; then
    log 'System starts up because of the scheduled startup got delayed.'
    log 'Maybe the scheduled startup was due when Pi was running, or Pi had been shut down but TXD stayed HIGH to prevent the power cut.'
  elif [ "$reason" == $REASON_USB_5V_CONNECTED ]; then
    log 'System starts up because USB 5V is connected.'
  elif [ "$reason" == $REASON_POWER_CONNECTED ]; then
    log 'System starts up because power supply is newly connected.'
  elif [ "$reason" == $REASON_REBOOT ]; then
    log 'System starts up because it previously reboot.'
  else
    log "Unknown/incorrect startup reason: $reason"
  fi

else
  log 'Witty Pi is not connected, skip I2C communications...'
  TIME_UNKNOWN=2
fi

# L3V7 only: make sure CHRG_PIN and STDBY_PIN are input with internal pull-up
if [ $(($firmwareID)) -eq 55 ]; then
  gpio -g mode $CHRG_PIN up
  gpio -g mode $CHRG_PIN in
  gpio -g mode $STDBY_PIN up
  gpio -g mode $STDBY_PIN in
fi

# delay until GPIO pin state gets stable
counter=0
while [ $counter -lt 5 ]; do  # increase this value if it needs more time
  if [ $(gpio -g read $HALT_PIN) == '1' ] ; then
    counter=$(($counter+1))
  else
    counter=0
  fi
  sleep 1
done

# run beforeScript.sh
"$cur_dir/beforeScript.sh" >> "$cur_dir/wittyPi.log" 2>&1

# run schedule script
if [ $has_mc == 1 ] ; then
  "$cur_dir/runScript.sh" 0 revise >> "$cur_dir/schedule.log" &
else
  log 'Witty Pi is not connected, skip schedule script...'
fi

# run afterStartup.sh
"$cur_dir/afterStartup.sh" >> "$cur_dir/wittyPi.log" 2>&1

# indicates system is up
log "Send out the SYS_UP signal via GPIO-$SYSUP_PIN pin."
gpio -g mode $SYSUP_PIN out
gpio -g write $SYSUP_PIN 1
sleep 0.1
gpio -g write $SYSUP_PIN 0
sleep 0.1
gpio -g write $SYSUP_PIN 1
sleep 0.1
gpio -g write $SYSUP_PIN 0
sleep 0.1
gpio -g mode $SYSUP_PIN in

# wait for GPIO-4 (BCM naming) falling, or alarm 2 (shutdown)
log 'Pending for incoming shutdown command...'
gpio -g wfi $HALT_PIN falling

if [ $has_mc == 1 ] ; then
  reason=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_ACTION_REASON)
  if [ "$reason" == $REASON_ALARM2 ]; then
    log 'Shutting down system because scheduled shutdown is due.'
  elif [ "$reason" == $REASON_CLICK ]; then
    log "Shutting down system because button is clicked or GPIO-$HALT_PIN is pulled down."
  elif [ "$reason" == $REASON_LOW_VOLTAGE ]; then
    vin=$(get_input_voltage)
    vlow=$(get_low_voltage_threshold)
    log "Shutting down system because input voltge is too low: Vin=${vin}V, Vlow=${vlow}"
  elif [ "$reason" == $REASON_OVER_TEMPERATURE ]; then
    log 'Shutting down system because over temperature.'
    log "$(get_temperature)"
  elif [ "$reason" == $REASON_BELOW_TEMPERATURE ]; then
    log 'Shutting down system because below temperature.'
    log "$(get_temperature)"
  else
    log "Unknown/incorrect shutdown reason: $reason"
  fi
else
  log 'Witty Pi is not connected, skip I2C communications...'
fi

# run beforeShutdown.sh
"$cur_dir/beforeShutdown.sh" >> "$cur_dir/wittyPi.log" 2>&1

# shutdown Raspberry Pi
do_shutdown $HALT_PIN $has_mc
