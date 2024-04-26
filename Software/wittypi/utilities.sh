#!/bin/bash
# file: utilities.sh
#
# This script provides some useful utility functions
#

export LC_ALL=en_GB.UTF-8

if [ -z ${I2C_MC_ADDRESS+x} ]; then
  readonly I2C_MC_ADDRESS=0x08

  readonly I2C_ID=0
  readonly I2C_VOLTAGE_IN_I=1
  readonly I2C_VOLTAGE_IN_D=2
  readonly I2C_VOLTAGE_OUT_I=3
  readonly I2C_VOLTAGE_OUT_D=4
  readonly I2C_CURRENT_OUT_I=5
  readonly I2C_CURRENT_OUT_D=6
  readonly I2C_POWER_MODE=7
  readonly I2C_LV_SHUTDOWN=8
  readonly I2C_ALARM1_TRIGGERED=9
  readonly I2C_ALARM2_TRIGGERED=10
  readonly I2C_ACTION_REASON=11
  readonly I2C_FW_REVISION=12

  readonly I2C_CONF_ADDRESS=16
  readonly I2C_CONF_DEFAULT_ON=17
  readonly I2C_CONF_PULSE_INTERVAL=18
  readonly I2C_CONF_LOW_VOLTAGE=19
  readonly I2C_CONF_BLINK_LED=20
  readonly I2C_CONF_POWER_CUT_DELAY=21
  readonly I2C_CONF_RECOVERY_VOLTAGE=22
  readonly I2C_CONF_DUMMY_LOAD=23
  readonly I2C_CONF_ADJ_VIN=24
  readonly I2C_CONF_ADJ_VOUT=25
  readonly I2C_CONF_ADJ_IOUT=26

  readonly I2C_CONF_SECOND_ALARM1=27
  readonly I2C_CONF_MINUTE_ALARM1=28
  readonly I2C_CONF_HOUR_ALARM1=29
  readonly I2C_CONF_DAY_ALARM1=30
  readonly I2C_CONF_WEEKDAY_ALARM1=31

  readonly I2C_CONF_SECOND_ALARM2=32
  readonly I2C_CONF_MINUTE_ALARM2=33
  readonly I2C_CONF_HOUR_ALARM2=34
  readonly I2C_CONF_DAY_ALARM2=35
  readonly I2C_CONF_WEEKDAY_ALARM2=36

  readonly I2C_CONF_RTC_OFFSET=37
  readonly I2C_CONF_RTC_ENABLE_TC=38
  readonly I2C_CONF_FLAG_ALARM1=39
  readonly I2C_CONF_FLAG_ALARM2=40

  readonly I2C_CONF_IGNORE_POWER_MODE=41
  readonly I2C_CONF_IGNORE_LV_SHUTDOWN=42

  readonly I2C_CONF_BELOW_TEMP_ACTION=43
  readonly I2C_CONF_BELOW_TEMP_POINT=44
  readonly I2C_CONF_OVER_TEMP_ACTION=45
  readonly I2C_CONF_OVER_TEMP_POINT=46
  readonly I2C_CONF_DEFAULT_ON_DELAY=47

  readonly I2C_LM75B_TEMPERATURE=50
  readonly I2C_LM75B_CONF=51
  readonly I2C_LM75B_THYST=52
  readonly I2C_LM75B_TOS=53

  readonly I2C_RTC_CTRL1=54
  readonly I2C_RTC_CTRL2=55
  readonly I2C_RTC_OFFSET=56
  readonly I2C_RTC_RAM_BYTE=57
  readonly I2C_RTC_SECONDS=58
  readonly I2C_RTC_MINUTES=59
  readonly I2C_RTC_HOURS=60
  readonly I2C_RTC_DAYS=61
  readonly I2C_RTC_WEEKDAYS=62
  readonly I2C_RTC_MONTHS=63
  readonly I2C_RTC_YEARS=64
  readonly I2C_RTC_SECOND_ALARM=65
  readonly I2C_RTC_MINUTE_ALARM=66
  readonly I2C_RTC_HOUR_ALARM=67
  readonly I2C_RTC_DAY_ALARM=68
  readonly I2C_RTC_WEEKDAY_ALARM=69
  readonly I2C_RTC_TIMER_VALUE=70
  readonly I2C_RTC_TIMER_MODE=71

  readonly HALT_PIN=4    # halt by GPIO-4 (BCM naming)
  readonly SYSUP_PIN=17  # output SYS_UP signal on GPIO-17 (BCM naming)
  readonly CHRG_PIN=5    # input to detect charging status
  readonly STDBY_PIN=6   # input to detect standby status

  readonly INTERNET_SERVER='http://google.com' # check network accessibility and get network time

  # reasons for startup/shutdown
  readonly REASON_ALARM1='0x01'
  readonly REASON_ALARM2='0x02'
  readonly REASON_CLICK='0x03'
  readonly REASON_LOW_VOLTAGE='0x04'
  readonly REASON_VOLTAGE_RESTORE='0x05'
  readonly REASON_OVER_TEMPERATURE='0x06'
  readonly REASON_BELOW_TEMPERATURE='0x07'
  readonly REASON_ALARM1_DELAYED='0x08'
  readonly REASON_USB_5V_CONNECTED='0x09'
  readonly REASON_POWER_CONNECTED='0x0a'
  readonly REASON_REBOOT='0x0b'

  # config file
  if [ "$(lsb_release -si)" == "Ubuntu" ]; then
    # Ubuntu
    readonly BOOT_CONFIG_FILE="/boot/firmware/usercfg.txt"
  else
    # Raspberry Pi OS ("$(lsb_release -si)" == "Debian") and others
    readonly BOOT_CONFIG_FILE="/boot/config.txt"
  fi

  TIME_UNKNOWN=0
fi


one_wire_confliction()
{
  if [[ $HALT_PIN -eq 4 ]]; then
    if grep -qe "^\s*dtoverlay=w1-gpio\s*$" ${BOOT_CONFIG_FILE}; then
      return 0
    fi
    if grep -qe "^\s*dtoverlay=w1-gpio-pullup\s*$" ${BOOT_CONFIG_FILE}; then
      return 0
    fi
  fi
  if grep -qe "^\s*dtoverlay=w1-gpio,gpiopin=$HALT_PIN\s*$" ${BOOT_CONFIG_FILE}; then
    return 0
  fi
  if grep -qe "^\s*dtoverlay=w1-gpio-pullup,gpiopin=$HALT_PIN\s*$" ${BOOT_CONFIG_FILE}; then
    return 0
  fi
  return 1
}

has_internet()
{
  resp=$(curl -s --head $INTERNET_SERVER)
  if [[ ${#resp} -ne 0 ]] ; then
    return 0
  else
    return 1
  fi
}

get_network_timestamp()
{
  if $(has_internet) ; then
    local t=$(curl -s --head $INTERNET_SERVER | grep ^Date: | sed 's/Date: //g')
    if [ ! -z "$t" ]; then
      echo $(date -d "$t" +%s)
    else
      echo -1
    fi
  else
    echo -1
  fi
}

is_mc_connected()
{
  local result=$(i2cdetect -y 1)
  if [[ $result == *"$(printf '%02x' $I2C_MC_ADDRESS)"* ]] ; then
    echo 1
  else
    echo 0
  fi
}

get_pi_model()
{
  IFS= read -r -d '' model </proc/device-tree/model
  echo $model;
}

get_os()
{
  echo $(hostnamectl | grep 'Operating System:' | sed 's/.*Operating System: //')
}

get_kernel()
{
  echo $(uname -sr)
}

get_arch()
{
  echo $(dpkg --print-architecture)
}

get_sys_time()
{
  echo $(date +'%Y-%m-%d %H:%M:%S %Z')
}

get_sys_timestamp()
{
  echo $(date +%s)
}

rtc_has_bad_time()
{
  year=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_RTC_YEARS)
  if [[ $year -eq 0 ]]; then
    echo 1
  else
    echo 0
  fi
}

get_rtc_timestamp()
{
  sec=$(bcd2dec $((0x7F&$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_RTC_SECONDS))))
  min=$(bcd2dec $(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_RTC_MINUTES))
  hour=$(bcd2dec $(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_RTC_HOURS))
  date=$(bcd2dec $(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_RTC_DAYS))
  month=$(bcd2dec $(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_RTC_MONTHS))
  year=$(bcd2dec $(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_RTC_YEARS))
  echo $(date --date="$year-$month-$date $hour:$min:$sec" +%s)
}

get_rtc_time()
{
  local rtc_ts=$(get_rtc_timestamp)
  if [ "$rtc_ts" == "" ] ; then
    echo 'N/A'
  else
    echo $(date +'%Y-%m-%d %H:%M:%S %Z' -d @$rtc_ts)
  fi
}

calc()
{
  awk "BEGIN { print $*}";
}

bcd2dec()
{
  local result=$(($1/16*10+($1&0xF)))
  echo $result
}

dec2bcd()
{
  local result=$((10#$1/10*16+(10#$1%10)))
  echo $result
}

dec2hex()
{
  printf "0x%02x" $1
}

hex2dec()
{
  printf "%d" $1
}

get_startup_time()
{
  sec=$(bcd2dec $(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_CONF_SECOND_ALARM1))
  min=$(bcd2dec $(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_CONF_MINUTE_ALARM1))
  hour=$(bcd2dec $(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_CONF_HOUR_ALARM1))
  date=$(bcd2dec $(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_CONF_DAY_ALARM1))
  printf '%02d %02d:%02d:%02d\n' $date $hour $min $sec
}

set_startup_time()
{
  sec=$(dec2bcd $4)
  i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_SECOND_ALARM1 $sec
  min=$(dec2bcd $3)
  i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_MINUTE_ALARM1 $min
  hour=$(dec2bcd $2)
  i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_HOUR_ALARM1 $hour
  date=$(dec2bcd $1)
  i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_DAY_ALARM1 $date
}

clear_startup_time()
{
  i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_SECOND_ALARM1 0x00
  i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_MINUTE_ALARM1 0x00
  i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_HOUR_ALARM1 0x00
  i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_DAY_ALARM1 0x00
}

get_shutdown_time()
{
  sec=$(bcd2dec $(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_CONF_SECOND_ALARM2))
  min=$(bcd2dec $(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_CONF_MINUTE_ALARM2))
  hour=$(bcd2dec $(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_CONF_HOUR_ALARM2))
  date=$(bcd2dec $(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_CONF_DAY_ALARM2))
  printf '%02d %02d:%02d:%02d\n' $date $hour $min $sec
}

set_shutdown_time()
{
  sec=$(dec2bcd $4)
  i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_SECOND_ALARM2 $sec
  min=$(dec2bcd $3)
  i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_MINUTE_ALARM2 $min
  hour=$(dec2bcd $2)
  i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_HOUR_ALARM2 $hour
  date=$(dec2bcd $1)
  i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_DAY_ALARM2 $date
}

clear_shutdown_time()
{
  i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_SECOND_ALARM2 0x00
  i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_MINUTE_ALARM2 0x00
  i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_HOUR_ALARM2 0x00
  i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_DAY_ALARM2 0x00
}

net_to_system()
{
  local net_ts=$(get_network_timestamp)
  if [[ "$net_ts" != "-1" ]]; then
    log '  Applying network time to system...'
    sudo date -u -s @$net_ts >/dev/null
    log '  Done :-)'
  else
    log '  Can not get legit network time.'
  fi
}

system_to_rtc()
{
  log '  Writing system time to RTC...'
  local sys_ts=$(get_sys_timestamp)
  local sec=$(date -d @$sys_ts +%S)
  local min=$(date -d @$sys_ts +%M)
  local hour=$(date -d @$sys_ts +%H)
  local day=$(date -d @$sys_ts +%u)
  local date=$(date -d @$sys_ts +%d)
  local month=$(date -d @$sys_ts +%m)
  local year=$(date -d @$sys_ts +%y)
  i2c_write 0x01 $I2C_MC_ADDRESS 58 $(dec2bcd $sec)
  i2c_write 0x01 $I2C_MC_ADDRESS 59 $(dec2bcd $min)
  i2c_write 0x01 $I2C_MC_ADDRESS 60 $(dec2bcd $hour)
  i2c_write 0x01 $I2C_MC_ADDRESS 61 $(dec2bcd $date)
  i2c_write 0x01 $I2C_MC_ADDRESS 62 $(dec2bcd $day)
  i2c_write 0x01 $I2C_MC_ADDRESS 63 $(dec2bcd $month)
  i2c_write 0x01 $I2C_MC_ADDRESS 64 $(dec2bcd $year)
  TIME_UNKNOWN=2
  log '  Done :-)'
}

rtc_to_system()
{
  log '  Writing RTC time to system...'
  local rtc_ts=$(get_rtc_timestamp)
  sudo timedatectl set-ntp 0 >/dev/null
  sudo date -s @$rtc_ts >/dev/null
  TIME_UNKNOWN=0
  log '  Done :-)'
}

trim()
{
  local result=$(echo "$1" | sed -n '1h;1!H;${;g;s/^[ \t]*//g;s/[ \t]*$//g;p;}')
  echo $result
}

current_timestamp()
{
  local rtctimestamp=$(get_rtc_timestamp)
  if [ "$rtctimestamp" == "" ] ; then
    echo $(date +%s)
  else
    echo $rtctimestamp
  fi
}

wittypi_home="`dirname \"$0\"`"
wittypi_home="`( cd \"$wittypi_home\" && pwd )`"
log2file()
{
  local datetime='[xxxx-xx-xx xx:xx:xx]'
  if [ $TIME_UNKNOWN -eq 0 ]; then
    datetime=$(date +'[%Y-%m-%d %H:%M:%S]')
  elif [ $TIME_UNKNOWN -eq 2 ]; then
    datetime=$(date +'<%Y-%m-%d %H:%M:%S>')
  fi
  local msg="$datetime $1"
  echo $msg >> $wittypi_home/wittyPi.log
}

log()
{
  if [ $# -gt 1 ] ; then
    echo $2 "$1"
  else
    echo "$1"
  fi
  log2file "$1"
}

i2c_read()
{
  local retry=0
  if [ $# -gt 3 ] ; then
    retry=$4
  fi
  local result=$(i2cget -y $1 $2 $3)
  if [[ $result =~ ^0x[0-9a-fA-F]{2}$ ]] ; then
    echo $result;
  else
    retry=$(( $retry + 1 ))
    if [ $retry -eq 4 ] ; then
      log "I2C read $1 $2 $3 failed (result=$result), and no more retry."
    else
      sleep 1
      log2file "I2C read $1 $2 $3 failed (result=$result), retrying $retry ..."
      i2c_read $1 $2 $3 $retry
    fi
  fi
}

i2c_write()
{
  local retry=0
  if [ $# -gt 4 ] ; then
    retry=$5
  fi
  i2cset -y $1 $2 $3 $4
  local result=$(i2c_read $1 $2 $3)
  if [ "$result" != $(dec2hex "$4") ] ; then
    retry=$(( $retry + 1 ))
    if [ $retry -eq 4 ] ; then
      log "I2C write $1 $2 $3 $4 failed (result=$result), and no more retry."
    else
      sleep 1
      log2file "I2C write $1 $2 $3 $4 failed (result=$result), retrying $retry ..."
      i2c_write $1 $2 $3 $4 $retry
    fi
  fi
}

get_temperature()
{
  local data=$(i2cget -y 1 $I2C_MC_ADDRESS $I2C_LM75B_TEMPERATURE w)

  #if [[ $data =~ ^0x[0-9a-fA-F]{4}$ && $data != 0xffff ]]; then
  if [[ $data =~ ^0x[0-9a-fA-F]{4}$ ]]; then
    data=$(( ((($data&0xFF)<<8)|(($data&0xFF00)>>8))>>5 ))
    if [[ $data -ge 0x400 ]] ; then
      data=$(( ($data&0x3FF)-1024 ))
    fi
    local c=$(calc $data*0.125)
    echo -n "$c$(echo $'\xc2\xb0'C)"
    if hash awk 2>/dev/null; then
      local f=$(awk "BEGIN { print $c*1.8+32 }")
      echo " / $f$(echo $'\xc2\xb0'F)"
    else
      echo ''
    fi
  else
    sleep 0.1
    get_temperature
  fi
}

clear_alarm_flags()
{
  local ctrl2=0x0
  if [ -z "$1" ]; then
    ctrl2=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_RTC_CTRL2)
  else
    ctrl2=$1
  fi
  ctrl2=$(($ctrl2&0xBF))
  i2c_write 0x01 $I2C_MC_ADDRESS $I2C_RTC_CTRL2 $ctrl2
  i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_FLAG_ALARM1 0
  i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_FLAG_ALARM2 0
}

do_shutdown()
{
  local halt_pin=$1
  local has_mc=$2

  # restore halt pin
  gpio -g mode $halt_pin in
  gpio -g mode $halt_pin up

  # clear alarm flags
  if [ $has_mc == 1 ] ; then
    clear_alarm_flags
  fi

  log 'Halting all processes and then shutdown Raspberry Pi...'

  # halt everything and shutdown
  if [ ! -f /boot/wittypi.lock ]; then
    shutdown -h now
  else
    rm /boot/wittypi.lock
  fi
}

schedule_script_interrupted()
{
  local startup_time=$(get_startup_time)
  local shutdown_time=$(get_shutdown_time)
  if [ "$startup_time" != '00 00:00:00' ] && [ "$shutdown_time" != '00 00:00:00' ] ; then
    local st_timestamp=$(date --date="$(date +%Y-%m-)$startup_time" +%s)
    local sd_timestamp=$(date --date="$(date +%Y-%m-)$shutdown_time" +%s)
    local cur_timestamp=$(date +%s)
    if [ $st_timestamp -gt $cur_timestamp ] && [ $sd_timestamp -lt $cur_timestamp ] ; then
      return 0
    fi
  fi
  return 1
}

get_power_mode()
{
  local mode=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_POWER_MODE)
  echo $(($mode))
}

get_input_voltage()
{
  local i=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_VOLTAGE_IN_I)
  local d=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_VOLTAGE_IN_D)
  calc $(($i))+$(($d))/100
}

get_output_voltage()
{
  local i=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_VOLTAGE_OUT_I)
  local d=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_VOLTAGE_OUT_D)
  calc $(($i))+$(($d))/100
}

get_output_current()
{
  local i=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_CURRENT_OUT_I)
  local d=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_CURRENT_OUT_D)
  calc $(($i))+$(($d))/100
}

get_low_voltage_threshold()
{
  local lowVolt=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_CONF_LOW_VOLTAGE)
  if [ $(($lowVolt)) == 255 ]; then
    lowVolt='disabled'
  else
    lowVolt=$(calc $(($lowVolt))/10)
    lowVolt+='V'
  fi
  echo $lowVolt;
}

get_recovery_voltage_threshold()
{
  local recVolt=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_CONF_RECOVERY_VOLTAGE)
  if [ $(($recVolt)) == 255 ]; then
    recVolt='disabled'
  else
    recVolt=$(calc $(($recVolt))/10)
    recVolt+='V'
  fi
  echo $recVolt;
}

set_low_voltage_threshold()
{
  i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_LOW_VOLTAGE $1
}

set_recovery_voltage_threshold()
{
  i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_RECOVERY_VOLTAGE $1
}

clear_low_voltage_threshold()
{
  i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_LOW_VOLTAGE 0xFF
}

clear_recovery_voltage_threshold()
{
  i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_RECOVERY_VOLTAGE 0xFF
}

get_over_temperature_action()
{
  hex2dec $(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_CONF_OVER_TEMP_ACTION)
}

get_over_temperature_point()
{
  local t=$(hex2dec $(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_LM75B_TOS))
  if [ $(($t>127)) == '1' ]; then
    t=$(($t-256))
  fi
  printf "%d" $t
}

get_below_temperature_action()
{
  hex2dec $(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_CONF_BELOW_TEMP_ACTION)
}

get_below_temperature_point()
{
  local t=$(hex2dec $(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_LM75B_THYST))
  if [ $(($t>127)) == '1' ]; then
    t=$(($t-256))
  fi
  printf "%d" $t
}

over_temperature_action()
{
  if [ $# -eq 0 ]; then
    over_temperature_action $(get_over_temperature_action) $(get_over_temperature_point)
  else
    local action='None'
    if [ "$1" == '1' ]; then
      action='Shutdown'
    elif [ "$1" == '2' ]; then
      action='Startup'
    fi
    if [ "$action" != 'None' ]; then
      echo -n "T>$2$(echo $'\xc2\xb0'C) $(echo -e '\u2794') $action"
    fi
  fi
}

below_temperature_action()
{
  if [ $# -eq 0 ]; then
    below_temperature_action $(get_below_temperature_action) $(get_below_temperature_point)
  else
    local action='None'
    if [ "$1" == '1' ]; then
      action='Shutdown'
    elif [ "$1" == '2' ]; then
      action='Startup'
    fi
    if [ "$action" != 'None' ]; then
      echo -n "T<$2$(echo $'\xc2\xb0'C) $(echo -e '\u2794') $action"
    fi
  fi
}

set_over_temperature_action()
{
  i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_OVER_TEMP_ACTION $1
  local t=$2
  if [ $(($2<0)) == '1' ]; then
    t=$(($2+256))
  fi
  i2c_write 0x01 $I2C_MC_ADDRESS $I2C_LM75B_TOS $t
  i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_OVER_TEMP_POINT $t
}

set_below_temperature_action()
{
  i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_BELOW_TEMP_ACTION $1
  local t=$2
  if [ $(($2<0)) == '1' ]; then
    t=$(($2+256))
  fi
  i2c_write 0x01 $I2C_MC_ADDRESS $I2C_LM75B_THYST $t
  i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_BELOW_TEMP_POINT $t
}

clear_over_temperature_action()
{
  i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_OVER_TEMP_ACTION 0x00
}

clear_below_temperature_action()
{
  i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_BELOW_TEMP_ACTION 0x00
}

check_sys_and_rtc_time()
{
  local rtc_ts=$(get_rtc_timestamp)
  local sys_ts=$(get_sys_timestamp)
  local delta=$((rtc_ts-sys_ts))
  if [ "${delta#-}" -gt 10 ]; then
    local rtc_t=$(date +'%Y-%m-%d %H:%M:%S %Z' -d @$rtc_ts)
    local sys_t=$(date +'%Y-%m-%d %H:%M:%S %Z' -d @$sys_ts)
    echo "[Warning] System and RTC time seems not synchronized, difference is ${delta#-}s."
    echo "System time is \"$sys_t\", while RTC time is \"$rtc_t\"."
    echo 'Please synchronize the time first.'
  fi
}
