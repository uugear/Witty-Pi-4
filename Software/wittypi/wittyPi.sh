[ -z $BASH ] && { exec bash "$0" "$@" || exit; }
#!/bin/bash
# file: wittyPi.sh
#
# Run this application to interactly configure your Witty Pi
#

echo '================================================================================'
echo '|                                                                              |'
echo '|   Witty Pi - Realtime Clock + Power Management for Raspberry Pi              |'
echo '|                                                                              |'
echo '|            < Version 4.21 >     by Dun Cat B.V. (UUGear)                     |'
echo '|                                                                              |'
echo '================================================================================'

# include utilities scripts in same directory
my_dir="`dirname \"$0\"`"
my_dir="`( cd \"$my_dir\" && pwd )`"
if [ -z "$my_dir" ] ; then
  exit 1
fi
. $my_dir/utilities.sh

if [ $(is_mc_connected) -ne 1 ]; then
  echo ''
  log 'Seems Witty Pi board is not connected? Quitting...'
  echo ''
  exit
fi

if one_wire_confliction ; then
	echo ''
	log 'Confliction detected:'
	log "1-Wire interface is enabled on GPIO-$HALT_PIN, which is also used by Witty Pi."
	log 'You may solve this confliction by moving 1-Wire interface to another GPIO pin.'
	echo ''
	exit
fi

# do not run further if wiringPi is not installed
if ! hash gpio 2>/dev/null; then
  echo ''
  log 'Seems wiringPi is not installed, please run again the latest installation script to fix this.'
  echo ''
  exit
fi

if [ $(is_mc_connected) -eq 1 ]; then
  firmwareID=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_ID)
  firmwareRev=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_FW_REVISION)
fi

# interactive actions
synchronize_with_network_time()
{
  if $(has_internet) ; then
    log '  Internet detected, apply network time to system and Witty Pi...'
    net_to_system
    system_to_rtc
  else
    log '  Internet not accessible, skip time synchronization.'
  fi
}

schedule_startup()
{
  local startup_time=$(get_startup_time)
  if [ "$startup_time" == "0 0:0:0" ]; then
    echo '  Auto startup time is not set yet.'
  else
    echo "  Auto startup time is currently set to \"$startup_time\""
  fi
  if [ -f "$my_dir/schedule.wpi" ]; then
      echo '  [WARNING] Your manual scheduling may disturb the running schedule script!'
  fi
  read -p '  When do you want your Raspberry Pi to auto startup? (dd HH:MM:SS) ' when
  if [[ $when =~ ^[0-3][0-9][[:space:]][0-2][0-9]:[0-5][0-9]:[0-5][0-9]$ ]]; then
    IFS=' ' read -r date timestr <<< "$when"
    IFS=':' read -r hour minute second <<< "$timestr"
    if [ $((10#$date>31)) == '1' ] || [ $((10#$date<1)) == '1' ]; then
      echo '  Day value should be 01~31.'
    elif [ $((10#$hour>23)) == '1' ]; then
      echo '  Hour value should be 00~23.'
    else
      local res=$(check_sys_and_rtc_time)
      if [ -z "$res" ]; then
        log "  Seting startup time to \"$when\""
        IFS=' ' read -r date timestr <<< "$when"
        IFS=':' read -r hour minute second <<< "$timestr"
        set_startup_time $date $hour $minute $second
        log '  Done :-)'
      else
        log "$res"
      fi
    fi
  else
    echo "  Sorry I don't recognize your input :-("
  fi
}

schedule_shutdown()
{
  local shutdown_time=$(get_shutdown_time)
  if [ "$shutdown_time" == "0 0:0:0" ]; then
    echo  '  Auto shutdown time is not set yet.'
  else
    echo -e "  Auto shutdown time is currently set to \"$shutdown_time\""
  fi
  if [ -f "$my_dir/schedule.wpi" ]; then
      echo '  [WARNING] Your manual scheduling may disturb the running schedule script!'
  fi
  read -p '  When do you want your Raspberry Pi to auto shutdown? (dd HH:MM:SS) ' when
  if [[ $when =~ ^[0-3][0-9][[:space:]][0-2][0-9]:[0-5][0-9]:[0-5][0-9]$ ]]; then
    IFS=' ' read -r date timestr <<< "$when"
    IFS=':' read -r hour minute second <<< "$timestr"
    if [ $((10#$date>31)) == '1' ] || [ $((10#$date<1)) == '1' ]; then
      echo '  Day value should be 01~31.'
    elif [ $((10#$hour>23)) == '1' ]; then
      echo '  Hour value should be 00~23.'
    else
      local res=$(check_sys_and_rtc_time)
      if [ -z "$res" ]; then
        log "  Seting shutdown time to \"$when\""
        IFS=' ' read -r date timestr <<< "$when"
        IFS=':' read -r hour minute second <<< "$timestr"
        set_shutdown_time $date $hour $minute $second
        log '  Done :-)'
      else
        log "$res"
      fi
    fi
  else
    echo "  Sorry I don't recognize your input :-("
  fi
}

choose_schedule_script()
{
  local res=$(check_sys_and_rtc_time)
  if [ -z "$res" ]; then
    local files=($my_dir/schedules/*.wpi)
    local count=${#files[@]}
    echo "  I can see $count schedule scripts in the \"schedules\" directory:"
    for (( i=0; i<$count; i++ ));
    do
      echo "  [$(($i+1))] ${files[$i]##*/}"
    done
    read -p "  Which schedule script do you want to use? (1~$count) " index
    if [[ $index =~ [0-9]+ ]] && [ $(($index >= 1)) == '1' ] && [ $(($index <= $count)) == '1' ] ; then
      local script=${files[$((index-1))]};
      log "  Copying \"${script##*/}\" to \"schedule.wpi\"..."
      cp ${script} "$my_dir/schedule.wpi"
      log '  Running the script...'
      . "$my_dir/runScript.sh" | tee -a "$my_dir/schedule.log"
      log '  Done :-)'
    else
      echo "  \"$index\" is not a good choice, I need a number from 1 to $count"
    fi
  else
    log "$res"
  fi
}

configure_low_voltage_threshold()
{
  if [ $(($firmwareID)) -eq 55 ]; then
    read -p 'Input low voltage (3.0~4.2, value in volts, 0=Disabled): ' threshold
    if (( $(awk "BEGIN {print ($threshold >= 3.0 && $threshold <= 4.2)}") )); then
      local t=$(calc $threshold*10)
      set_low_voltage_threshold ${t%.*}
      local ts=$(printf 'Low voltage threshold set to %.1fV!\n' $threshold)
      log "  $ts" && sleep 2
    elif (( $(awk "BEGIN {print ($threshold == 0)}") )); then
      i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_LOW_VOLTAGE 0xFF
      log 'Disabled low voltage threshold!' && sleep 2
    else
      echo 'Please input from 3.0 to 4.2 ...' && sleep 2
    fi
  else
    read -p 'Input low voltage (2.0~25.0, value in volts, 0=Disabled): ' threshold
    if (( $(awk "BEGIN {print ($threshold >= 2.0 && $threshold <= 25.0)}") )); then
      local t=$(calc $threshold*10)
      set_low_voltage_threshold ${t%.*}
      local ts=$(printf 'Low voltage threshold set to %.1fV!\n' $threshold)
      log "  $ts" && sleep 2
    elif (( $(awk "BEGIN {print ($threshold == 0)}") )); then
      i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_LOW_VOLTAGE 0xFF
      log 'Disabled low voltage threshold!' && sleep 2
    else
      echo 'Please input from 2.0 to 25.0 ...' && sleep 2
    fi
  fi
}

configure_recovery_voltage_threshold()
{
  if [ $(($firmwareID)) -eq 55 ]; then
    # Witty Pi 4 L3V7
    read -p 'Turn on RPi when USB 5V is connected (0=No, 1=Yes): ' action
    if [ "$action" == '0' ]; then
      i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_RECOVERY_VOLTAGE 0
      echo '  Will do nothing when USB 5V is connected.'
      sleep 2
    elif [ "$action" == '1' ]; then
      i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_RECOVERY_VOLTAGE 1
      echo '  Will turn on RPi when USB 5V is connected.'
      sleep 2
    else
      echo 'Please input 0 or 1'
    fi
  else
    # Witty Pi 4 and Mini
    read -p 'Input recovery voltage (2.0~25.0, value in volts, 0=Disabled): ' threshold
    if (( $(awk "BEGIN {print ($threshold >= 2.0 && $threshold <= 25.0)}") )); then
      local t=$(calc $threshold*10)
      set_recovery_voltage_threshold ${t%.*}
      local ts=$(printf 'Recovery voltage threshold set to %.1fV!\n' $threshold)
      log "  $ts" && sleep 2
    elif (( $(awk "BEGIN {print ($threshold == 0)}") )); then
      i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_RECOVERY_VOLTAGE 0xFF
      log 'Disabled recovery voltage threshold!' && sleep 2
    else
      echo 'Please input from 2.0 to 25.0 ...' && sleep 2
    fi
  fi
}

configure_over_temperature_action()
{
  read -p 'Choose action for over temperature (0=None, 1=Shutdown, 2=Startup): ' oa
  if [ "$oa" == '0' ]; then
    clear_over_temperature_action
    sleep 2
  elif [ "$oa" == '1' ] || [ "$oa" == '2' ]; then
    read -p 'Input over temperature point (-30~80, value in Celsius degree): ' ot
    if [[ $ot =~ ^-?[0-9]+$ ]] && [ $(($ot>=-30)) == '1' ] && [ $(($ot<=80)) == '1' ]; then
      set_over_temperature_action $oa $ot
      local action=$(over_temperature_action $oa $ot)
      log "  Over temperature action is set: $action"
      sleep 2
    else
      echo 'Please input integer between -30 and 80...'
    fi
  else
    echo 'Please input 0, 1 or 2...' && sleep 2
  fi
}

configure_below_temperature_action()
{
  read -p 'Choose action for below temperature (0=None, 1=Shutdown, 2=Startup): ' ba
  if [ "$ba" == '0' ]; then
    clear_below_temperature_action
    sleep 2
  elif [ "$ba" == '1' ] || [ "$ba" == '2' ]; then
    read -p 'Input below temperature point (-30~80, value in Celsius degree): ' bt
    if [[ $bt =~ ^-?[0-9]+$ ]] && [ $(($bt>=-30)) == '1' ] && [ $(($bt<=80)) == '1' ]; then
      set_below_temperature_action $ba $bt
      local action=$(below_temperature_action $ba $bt)
      log "  Below temperature action is set: $action"
      sleep 2
    else
      echo 'Please input integer between -30 and 80...'
    fi
  else
    echo 'Please input 0, 1 or 2...' && sleep 2
  fi
}

set_default_state()
{
  read -p 'Input new default state (1 or 0: 1=ON, 0=OFF): ' state
  case $state in
    0) i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_DEFAULT_ON 0x00 && log 'Set to "Default OFF"!' && sleep 2;;
    1) i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_DEFAULT_ON 0x01 && log 'Set to "Default ON"!' && sleep 2;;
    *) echo 'Please input 1 or 0 ...' && sleep 2;;
  esac
}

set_power_cut_delay()
{
  local maxVal='8.0';
	if [ $(($firmwareID)) -ge 38 ]; then
    maxVal='25.0'
  fi
  read -p "Input new delay (0.0~$maxVal: value in seconds): " delay
  if (( $(awk "BEGIN {print ($delay >= 0 && $delay <= $maxVal)}") )); then
    local d=$(calc $delay*10)
    i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_POWER_CUT_DELAY ${d%.*}
    log "Power cut delay set to $delay seconds!" && sleep 2
  else
    echo "Please input from 0.0 to $maxVal ..." && sleep 2
  fi
}

set_pulsing_interval()
{
	read -p 'Input new interval (value in seconds, 1~20): ' interval
	if [ $interval -ge 1 ] && [ $interval -le 20 ]; then
	  i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_PULSE_INTERVAL $interval
	  log "Pulsing interval set to $interval seconds!" && sleep 2
	else
	  echo 'Please input from 1 to 20' && sleep 2
	fi
}

set_white_led_duration()
{
	read -p 'Input new duration for white LED (value in milliseconds, 0~254): ' duration
	if [ $duration -ge 0 ] && [ $duration -le 254 ]; then
		i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_BLINK_LED $duration
		log "White LED duration set to $duration!" && sleep 2
	else
	  echo 'Please input from 0 to 254' && sleep 2
	fi
}

set_dummy_load_duration()
{
	read -p 'Input new duration for dummy load (value in milliseconds, 0~254): ' duration
	if [ $duration -ge 0 ] && [ $duration -le 254 ]; then
		i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_DUMMY_LOAD $duration
		log "Dummy load duration set to $duration!" && sleep 2
	else
	  echo 'Please input from 0 to 254' && sleep 2
	fi
}

set_vin_adjustment()
{
	read -p 'Input Vin adjustment (-1.27~1.27: value in volts): ' vinAdj
  if (( $(awk "BEGIN {print ($vinAdj >= -1.27 && $vinAdj <= 1.27)}") )); then
    local adj=$(calc $vinAdj*100)
    if (( $(awk "BEGIN {print ($adj < 0)}") )); then
    	adj=$((255+$adj))
    fi
    i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_ADJ_VIN ${adj%.*}
    local setting=$(printf 'Vin adjustment set to %.2fV!\n' $vinAdj)
    log "$setting" && sleep 2
  else
    echo 'Please input from -1.27 to 1.27 ...' && sleep 2
  fi
}

set_vout_adjustment()
{
	read -p 'Input Vout adjustment (-1.27~1.27: value in volts): ' voutAdj
  if (( $(awk "BEGIN {print ($voutAdj >= -1.27 && $voutAdj <= 1.27)}") )); then
    local adj=$(calc $voutAdj*100)
    if (( $(awk "BEGIN {print ($adj < 0)}") )); then
    	adj=$((255+$adj))
    fi
    i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_ADJ_VOUT ${adj%.*}
    local setting=$(printf 'Vout adjustment set to %.2fV!\n' $voutAdj)
    log "$setting" && sleep 2
  else
    echo 'Please input from -1.27 to 1.27 ...' && sleep 2
  fi
}

set_iout_adjustment()
{
	read -p 'Input Iout adjustment (-1.27~1.27: value in amps): ' ioutAdj
  if (( $(awk "BEGIN {print ($ioutAdj >= -1.27 && $ioutAdj <= 1.27)}") )); then
    local adj=$(calc $ioutAdj*100)
    if (( $(awk "BEGIN {print ($adj < 0)}") )); then
    	adj=$((255+$adj))
    fi
    i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_ADJ_IOUT ${adj%.*}
    local setting=$(printf 'Iout adjustment set to %.2fA!\n' $ioutAdj)
    log "$setting" && sleep 2
  else
    echo 'Please input from -1.27 to 1.27 ...' && sleep 2
  fi
}

set_default_on_delay()
{
  if [ $(($firmwareRev)) -ge 2 ]; then
    read -p 'Wait how many seconds before Auto-ON (0~10): ' delay
  	if [ $delay -ge 0 ] && [ $delay -le 10 ]; then
  	  i2c_write 0x01 $I2C_MC_ADDRESS $I2C_CONF_DEFAULT_ON_DELAY $delay
  	  log "Default ON delay set to $delay seconds!" && sleep 2
  	else
  	  echo 'Please input from 0 to 10' && sleep 2
  	fi
  else
    echo 'Please choose from 1 to 8';
  fi
}

other_settings()
{
  echo 'Here you can set:'
  echo -n '  [1] Default state when powered'
  local ds=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_CONF_DEFAULT_ON)
  if [[ $ds -eq 0 ]]; then
    echo ' [default OFF]'
	else
    echo ' [default ON]'
  fi
  echo -n '  [2] Power cut delay after shutdown'
  local pcd=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_CONF_POWER_CUT_DELAY)
  pcd=$(calc $(($pcd))/10)
  printf ' [%.1f Seconds]\n' "$pcd"
  echo -n '  [3] Pulsing interval during sleep'
  local pi=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_CONF_PULSE_INTERVAL)
  pi=$(hex2dec $pi)
  echo " [$pi Seconds]"
  echo -n '  [4] White LED duration'
  local led=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_CONF_BLINK_LED)
  printf ' [%d]\n' "$led"
  echo -n '  [5] Dummy load duration'
  local dload=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_CONF_DUMMY_LOAD)
  printf ' [%d]\n' "$dload"
  echo -n '  [6] Vin adjustment'
  local vinAdj=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_CONF_ADJ_VIN)
  if [[ $vinAdj -gt 127 ]]; then
  	vinAdj=$(calc $(($vinAdj-255))/100)
 	else
 		vinAdj=$(calc $(($vinAdj))/100)
  fi
  printf ' [%.2fV]\n' "$vinAdj"
  echo -n '  [7] Vout adjustment'
  local voutAdj=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_CONF_ADJ_VOUT)
  if [[ $voutAdj -gt 127 ]]; then
  	voutAdj=$(calc $(($voutAdj-255))/100)
 	else
 		voutAdj=$(calc $(($voutAdj))/100)
  fi
  printf ' [%.2fV]\n' "$voutAdj"
  echo -n '  [8] Iout adjustment'
  local ioutAdj=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_CONF_ADJ_IOUT)
  if [[ $ioutAdj -gt 127 ]]; then
  	ioutAdj=$(calc $(($ioutAdj-255))/100)
 	else
 		ioutAdj=$(calc $(($ioutAdj))/100)
  fi
  printf ' [%.2fA]\n' "$ioutAdj"
  local optionCount=8;
  if [ $(($firmwareRev)) -ge 2 ]; then
    echo -n '  [9] Default ON delay'
    local dod=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_CONF_DEFAULT_ON_DELAY)
    dod=$(hex2dec $dod)
    echo " [$dod Seconds]"
    optionCount=9;
  fi
  read -p "Which parameter to set? (1~$optionCount) " action
  case $action in
      [1]* ) set_default_state;;
      [2]* ) set_power_cut_delay;;
      [3]* ) set_pulsing_interval;;
      [4]* ) set_white_led_duration;;
      [5]* ) set_dummy_load_duration;;
      [6]* ) set_vin_adjustment;;
      [7]* ) set_vout_adjustment;;
      [8]* ) set_iout_adjustment;;
      [9]* ) set_default_on_delay;;
      * ) echo "Please choose from 1 to $optionCount";;
  esac
}

reset_startup_time()
{
  log '  Clearing auto startup time...' '-n'
  clear_startup_time
  log ' done :-)'
}

reset_shutdown_time()
{
  log '  Clearing auto shutdown time...' '-n'
  clear_shutdown_time
  log ' done :-)'
}

delete_schedule_script()
{
  log '  Deleting "schedule.wpi" file...' '-n'
  if [ -f "$my_dir/schedule.wpi" ]; then
    rm "$my_dir/schedule.wpi"
    log ' done :-)'
  else
    log ' file does not exist'
  fi
}

reset_low_voltage_threshold()
{
  log '  Clearing low voltage threshold...' '-n'
  clear_low_voltage_threshold
  log ' done :-)'
}

reset_recovery_voltage_threshold()
{
  log '  Clearing recovery voltage threshold...' '-n'
  clear_recovery_voltage_threshold
  log ' done :-)'
}

reset_over_temperature_action()
{
  log '  Clearing over temperature action...' '-n'
  clear_over_temperature_action
  log ' done :-)'
}

reset_below_temperature_action()
{
  log '  Clearing below temperature action...' '-n'
  clear_below_temperature_action
  log ' done :-)'
}

reset_all()
{
  reset_startup_time
  reset_shutdown_time
  delete_schedule_script
  reset_low_voltage_threshold
  reset_recovery_voltage_threshold
  reset_over_temperature_action
  reset_below_temperature_action
}

reset_data()
{
  echo 'Here you can reset some data:'
  echo '  [1] Clear scheduled startup time'
  echo '  [2] Clear scheduled shutdown time'
  echo '  [3] Stop using schedule script'
  echo '  [4] Clear low voltage threshold'
  if [ $(($firmwareID)) -eq 55 ]; then
    echo '  [5] Restore action when USB power is connected'
  else
    echo '  [5] Clear recovery voltage threshold'
  fi
  echo '  [6] Clear over temperature action'
  echo '  [7] Clear below temperature action'
  echo '  [8] Perform all actions above'
  read -p "Which action to perform? (1~8) " action
  case $action in
      [1]* ) reset_startup_time;;
      [2]* ) reset_shutdown_time;;
      [3]* ) delete_schedule_script;;
      [4]* ) reset_low_voltage_threshold;;
      [5]* ) reset_recovery_voltage_threshold;;
      [6]* ) clear_over_temperature_action;;
      [7]* ) clear_below_temperature_action;;
      [8]* ) reset_all;;
      * ) echo 'Please choose from 1 to 8';;
  esac
}

# ask user for action
while true; do
  # output temperature
  temperature='>>> Current temperature: '
  temperature+="$(get_temperature)"
  echo "$temperature"

  # output system time
  systime='>>> Your system time is: '
  systime+="$(get_sys_time)"
  echo "$systime"

  # output RTC time
  rtctime='>>> Your RTC time is:    '
  rtctime+="$(get_rtc_time)"
  echo "$rtctime"

  # voltages report
  if [ $(is_mc_connected) -eq 1 ]; then
    vin=$(get_input_voltage)
    vout=$(get_output_voltage)
    iout=$(get_output_current)
    voltages=">>> "
    if [ $(get_power_mode) -ne 0 ]; then
		  voltages+="Vin=$(printf %.02f $vin)V, "
		fi
    voltages+="Vout=$(printf %.02f $vout)V, Iout=$(printf %.02f $iout)A"
    
    if [ $(($firmwareID)) -eq 55 ]; then
      chrg=$(gpio -g read $CHRG_PIN)
      stdby=$(gpio -g read $STDBY_PIN)
      if [ "$chrg" == "1" ] && [ "$stdby" == "1" ]; then
        voltages+=" (discharging battery...)"
      elif [ "$chrg" == "0" ] && [ "$stdby" == "1" ]; then
        voltages+=" (charging battery...)"  
      fi
    fi
    
    echo "$voltages"
  fi

  # let user choose action
  echo 'Now you can:'
  echo '  1. Write system time to RTC'
  echo '  2. Write RTC time to system'
  echo '  3. Synchronize with network time'
  echo -n '  4. Schedule next shutdown'
  shutdown_time=$(get_shutdown_time)
  if [ "$shutdown_time" == "00 00:00:00" ]; then
    echo ''
  else
    echo " [$shutdown_time]";
  fi
  echo -n '  5. Schedule next startup'
  startup_time=$(get_startup_time)
  if [ "$startup_time" == "00 00:00:00" ]; then
    echo ''
  else
    echo "  [$startup_time]";
  fi
  echo -n '  6. Choose schedule script'
  if [ -f "$my_dir/schedule.wpi" ]; then
    echo ' [in use]'
  else
    echo ''
  fi
  echo -n '  7. Set low voltage threshold'
	lowVolt=$(get_low_voltage_threshold)
  if [ ${#lowVolt} == '8' ]; then
    echo ''
  else
    echo "  [$lowVolt]";
  fi
  if [ $(($firmwareID)) -eq 55 ]; then
    echo -n '  8. Auto-On when USB 5V is connected'
    recV=$(i2c_read 0x01 $I2C_MC_ADDRESS $I2C_CONF_RECOVERY_VOLTAGE)
    if [ $(($recV)) -gt 0 ]; then
      echo "  [Yes]";
    else
      echo "  [No]";
    fi
  else
    echo -n '  8. Set recovery voltage threshold'
    recVolt=$(get_recovery_voltage_threshold)
    if [ ${#recVolt} == '8' ]; then
      echo ''
    else
      echo "  [$recVolt]";
    fi
  fi
  echo -n '  9. Set over temperature action'
  ota=$(over_temperature_action)
  if [ "$ota" != '' ]; then
    echo "  [$ota]"
  else
    echo
  fi
  echo -n ' 10. Set below temperature action'
  bta=$(below_temperature_action)
  if [ "$bta" != '' ]; then
    echo "  [$bta]"
  else
    echo
  fi
  echo ' 11. View/change other settings...'
  echo ' 12. Reset data...'
  echo ' 13. Exit'
  read -p 'What do you want to do? (1~13) ' action
  case $action in
      1 ) system_to_rtc;;
      2 ) rtc_to_system;;
      3 ) synchronize_with_network_time;;
      4 ) schedule_shutdown;;
      5 ) schedule_startup;;
      6 ) choose_schedule_script;;
      7 ) configure_low_voltage_threshold;;
      8 ) configure_recovery_voltage_threshold;;
      9 ) configure_over_temperature_action;;
     10 ) configure_below_temperature_action;;
     11 ) other_settings;;
     12 ) reset_data;;
     13 ) exit;;
      * ) echo 'Please choose from 1 to 13';;
  esac
  echo ''
  echo '================================================================================'
done
