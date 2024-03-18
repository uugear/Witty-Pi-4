#!/bin/bash
#
# file: gpio-util.sh
# version: 0.73
# author: Dun Cat B.V.
#
# This file defines a BASH function named "gpio", which can be used like a
# simplified version of "gpio" utility in wiringPi library. Please do not
# expect the same performance as the real "gpio" utility in wiringPi.
#
# Usage:
#    gpio [ -g | -1 ] mode/read/write
#    gpio readall
#    gpio wfi ...
#
# Below are some examples of usage:
#
# gpio mode 27 up     (set GPIO-27 to input mode and internal pulled up)
# gpio read 27        (read GPIO-27 state)
#
# gpio mode 27 out    (set GPIO-27 to output mode)
# gpio write 27 1     (write GPIO-27 state to high)
#
# gpio wfi 27 falling (wait until GPIO-27 falls)
#
# gpio readall        (print information for all GPIO pins)
#

# cache previously set pin pull mode (up or down)
declare -A PIN_PULL

# pin naming: BCM (default) or PHYSICAL
readonly BCM=0
readonly PHYSICAL=1
naming=$BCM

readonly PI_MODELS=(
'   Pi A   '  # 0
'   Pi B   '  # 1
'   Pi A+  '  # 2
'   Pi B+  '  # 3
'   Pi 2B  '  # 4
''
'  Pi CM1  '  # 6
''
'   Pi 3B  '  # 8
'  Pi Zero '  # 9
'  Pi CM3  '  # 10
''
' Pi ZeroW '  # 12
'  Pi 3B+  '  # 13
'  Pi 3A+  '  # 14
''
'  Pi CM3+ '  # 16
'   Pi 4B  '  # 17
'Pi Zero 2W'  # 18
'  Pi 400  '  # 19
'  Pi CM4  '  # 20
)

# mapping physical pins to BCM pins
readonly PHY_BCM=(
  -1
  -1  -1  #  1-2
   2  -1  #  3-4
   3  -1  #  5-6
   4  14  #  7-8
  -1  15  #  9-10
  17  18  # 11-12
  27  -1  # 13-14
  22  23  # 15-16
  -1  24  # 17-18
  10  -1  # 19-20
   9  25  # 21-22
  11  8   # 23-24
  -1  7   # 25-26
   0  1   # 27-28
   5  -1  # 29-30
   6  12  # 31-32
  13  -1  # 33-34
  19  16  # 35-36
  26  20  # 37-38
  -1  21  # 39-40
)

# mapping physical pins to WiringPi pins
readonly PHY_WPI=(
  -1
  -1	-1  #  1-2
   8	-1  #  3-4
   9	-1  #  5-6
   7	15  #  7-8
  -1	16  #  9-10
   0	1   # 11-12
   2	-1  # 13-14
   3	4   # 15-16
  -1	5   # 17-18
  12	-1  # 19-20
  13	6   # 21-22
  14	10  # 23-24
  -1	11  # 25-26
  30	31  # 27-28
  21	-1  # 29-30
  22	26  # 31-32
  23	-1  # 33-34
  24	27  # 35-36
  25	28  # 37-38
  -1	29  # 39-40
)

# pin names (ordered by physical pin number)
readonly PHY_NAMES=(
  ''
  '   3.3v'  '5v     '  #  1-2
  '  SDA.1'  '5v     '  #  3-4
  '  SCL.1'  '0v     '  #  5-6
  'GPIO. 7'  'TxD    '  #  7-8
  '     0v'  'RxD    '  #  9-10
  'GPIO. 0'  'GPIO. 1'  # 11-12
  'GPIO. 2'  '0v     '  # 13-14
  'GPIO. 3'  'GPIO. 4'  # 15-16
  '   3.3v'  'GPIO. 5'  # 17-18
  '   MOSI'  '0v     '  # 19-20
  '   MISO'  'GPIO. 6'  # 21-22
  '   SCLK'  'CE0    '  # 23-24
  '     0v'  'CE1    '  # 25-26
  '  SDA.0'  'SCL.0  '  # 27-28
  'GPIO.21'  '0v     '  # 29-30
  'GPIO.22'  'GPIO.26'  # 31-32
  'GPIO.23'  '0v     '  # 33-34
  'GPIO.24'  'GPIO.27'  # 35-36
  'GPIO.25'  'GPIO.28'  # 37-38
  '     0v'  'GPIO.29'  # 39-40
)

# pin modes
readonly MODES=('IN' 'OUT' 'ALT5' 'ALT4' 'ALT0' 'ALT1' 'ALT2' 'ALT3')


gpio()
{
  argc=$#
  argv=("$@")

  naming=$BCM
  if [[ "${argv[0]}" == "-1" ]]; then
    argv=("${argv[@]:1}")
    argc=${#argv[@]}
    naming=$PHYSICAL
  elif [[ "${argv[0]}" == "-g" ]]; then
    argv=("${argv[@]:1}")
    argc=${#argv[@]}
  elif [[ "${argv[0]}" == "readall" ]]; then
    doReadAll
    return
  elif [[ "${argv[0]}" == "-v" ]]; then
    doVersion
    return
  fi

  if [[ "${argv[0]}" == "mode" ]]; then
    doMode ${argv[@]}
  elif [[ "${argv[0]}" == "read" ]]; then
    doRead ${argv[@]}
  elif [[ "${argv[0]}" == "write" ]]; then
    doWrite ${argv[@]}
  elif [[ "${argv[0]}" == "wfi" ]]; then
    doWfi ${argv[@]}
  else
    echo "Unsupported command \"${argv[0]}\""
  fi
}


doVersion()
{
  echo 'Emulated gpio version: 0.72'
  echo 'Thank Gordon Henderson for the great work on WiringPi'
  echo 'Copyright (c) Dun Cat B.V. (UUGear)'
  echo 'This is free software with ABSOLUTELY NO WARRANTY.'
  echo ''
  echo 'Raspberry Pi Details:'
  echo "Model: $(cat /proc/cpuinfo | grep -Po 'Model\s*: \K.*')"
  echo "Revision: $(cat /proc/cpuinfo | grep -Po 'Revision\s*: \K.*')"
}


doMode()
{
  if [[ $naming -eq $PHYSICAL ]]; then
    pin=${PHY_BCM["$2"]}
  else
    pin=$2
  fi
  mode=$3
  if [[ "$mode" == "in" || "$mode" == "input" ]]; then
    raspi-gpio set $pin ip
  elif [[ "$mode" == "out" || "$mode" == "output" ]]; then
    raspi-gpio set $pin op
  elif [[ "$mode" == "up" ]]; then
    raspi-gpio set $pin pu
    PIN_PULL["$pin"]="$mode"
  elif [[ "$mode" == "down" ]]; then
    raspi-gpio set $pin pd
    PIN_PULL["$pin"]="$mode"
  elif [[ "$mode" == "alt0" ]]; then
    raspi-gpio set $pin a0
  elif [[ "$mode" == "alt1" ]]; then
    raspi-gpio set $pin a1
  elif [[ "$mode" == "alt2" ]]; then
    raspi-gpio set $pin a2
  elif [[ "$mode" == "alt3" ]]; then
    raspi-gpio set $pin a3
  elif [[ "$mode" == "alt4" ]]; then
    raspi-gpio set $pin a4
  elif [[ "$mode" == "alt5" ]]; then
    raspi-gpio set $pin a5
  else
    echo "Unsupported mode \"$mode\""
  fi
}


doRead()
{
  if [[ $naming -eq $PHYSICAL ]]; then
    pin=${PHY_BCM["$2"]}
  else
    pin=$2
  fi
  raspi-gpio get $pin | head -1 | sed 's/.*level=//' | sed 's/[^0-9].*$//'
}


doWrite()
{
  if [[ $naming -eq $PHYSICAL ]]; then
    pin=${PHY_BCM["$2"]}
  else
    pin=$2
  fi
  state=$3
  if [[ "$state" == "1" || "$state" == "up" || "$state" == "on" ]]; then
    raspi-gpio set $pin dh
  elif [[ "$state" == "0" || "$state" == "down" || "$state" == "off" ]]; then
    raspi-gpio set $pin dl
  fi
}


doWfi()
{
  if [[ $naming -eq $PHYSICAL ]]; then
    pin=${PHY_BCM["$2"]}
  else
    pin=$2
  fi
  edge=$3
  if ! python3 -c "import gpiozero" > /dev/null 2>&1 ; then
    echo 'Python 3 or GPIO Zero for Python 3 is not installed, using less efficient implementation now.'
    local running=1
    local prev=$(doRead '' $pin)
    while [[ $running -eq 1 ]]; do
	  local cur=$(doRead '' $pin)
	  if [[ ($edge == 'both' && $prev -ne $cur)
	     || ($edge == 'falling' && $prev -eq 1 && $cur -eq 0)
		 || ($edge == 'rising' && $prev -eq 0 && $cur -eq 1) ]]; then
	    running=0
	  fi
	  prev=$cur
	  sleep 0.2
    done
  else
# Python Code Begins
python3 - << EOF
from gpiozero import Button
import subprocess
getPin = subprocess.run(['printf', '$pin'], stdout=subprocess.PIPE)
pin = int(getPin.stdout.decode('utf-8'))
getPull = subprocess.run(['printf', '${PIN_PULL["$pin"]}'], stdout=subprocess.PIPE)
pull = getPull.stdout.decode('utf-8')
if pull == 'down':
  pull = False
else:
  pull = True
btn = Button(pin, pull_up=pull)
btn.wait_for_press()
EOF
# Python Code Ends
  fi
}


getPiModel()
{
  local rev="0x$(cat /proc/cpuinfo | grep -Po 'Revision\s*: \K.*')"
  if ((rev & 0x800000)); then
    local model=$((($rev&0x00000FF0)>>4))
  else
    rev=$(($rev&0x1F))
    r2t=(0 0 1 1 1 1 1 0 0 0 0 0 0 1 1 1 3 6 2 3 6 2)
    local model=${r2t[$rev]}
  fi
  echo $model
}


align_left()
{
  local text=$1
  local length=$2
  let trailing=$length-${#text}
  if [[ $trailing -lt 0 ]]; then
  	let trailing=0
  fi
  printf $text
  printf "%${trailing}s"
}


align_right()
{
  local text=$1
  local length=$2
  let leading=($length-${#text})
  if [[ $leading -lt 0 ]]; then
  	let leading=0
  fi
  printf "%${leading}s"
  printf $text
}


doReadAll()
{
  local model=$(getPiModel)
  local not_supported=(5 6 7 10 16 20)
  if [[ " ${not_supported[*]} " =~ " $model " ]]; then
    echo "Sorry, readall does not support this model: $model"
    return
  fi

  echo " +-----+-----+---------+------+---+${PI_MODELS[$model]}+---+------+---------+-----+-----+"
  echo ' | BCM | wPi |   Name  | Mode | V | Physical | V | Mode | Name    | wPi | BCM |'
  echo ' +-----+-----+---------+------+---+----++----+---+------+---------+-----+-----+'

  for ((i = 1 ; i < 40 ; i+=2)); do
    local pin1=$(printf %2d $i)
    local pin2=$(printf %-2d $(($i+1)))
    local bcm1=${PHY_BCM[$pin1]}
    local wpi1=${PHY_WPI[$pin1]}
    if [[ $bcm1 -eq -1 ]]; then
      bcm1='   '
      wpi1='   '
      local v1=' '
      local m1='    '
    else
      local info1=$(raspi-gpio get $bcm1 | head -1)
      bcm1=$(printf %3d $bcm1)
      wpi1=$(printf %3d $wpi1)
      local v1=$(echo $info1 | sed 's/^.*level=//' | sed 's/[^0-9].*$//')
      if [[ $info1 == *"fsel="* ]]; then
        local m1=$(align_right ${MODES[$(echo $info1 | sed 's/^.*fsel=//' | sed 's/ .*$//')]} 4)
      elif [[ $info1 == *"alt="* ]]; then
        local m1=$(align_right $(echo -n 'ALT'; echo $info1 | sed 's/^.*alt=//' | sed 's/ .*$//') 4)
      elif [[ $info1 == *"INPUT"* ]]; then
        local m1='  IN'
      elif [[ $info1 == *"OUTPUT"* ]]; then
        local m1=' OUT'
      else
        local m1='   ?'
      fi
    fi
    local bcm2=${PHY_BCM[$pin2]}
    local wpi2=${PHY_WPI[$pin2]}
    if [[ $bcm2 -eq -1 ]]; then
      bcm2='   '
      wpi2='   '
      local v2=' '
      local m2='    '
    else
      local info2=$(raspi-gpio get $bcm2 | head -1)
      bcm2=$(printf %-3d $bcm2)
      wpi2=$(printf %-3d $wpi2)
      local v2=$(echo $info2 | sed 's/^.*level=//' | sed 's/[^0-9].*$//')
      if [[ $info2 == *"fsel="* ]]; then
        local m2=$(align_left ${MODES[$(echo $info2 | sed 's/^.*fsel=//' | sed 's/ .*$//')]} 4)
      elif [[ $info2 == *"alt="* ]]; then
        local m2=$(align_left $(echo -n 'ALT'; echo $info2 | sed 's/^.*alt=//' | sed 's/ .*$//') 4)
      elif [[ $info2 == *"INPUT"* ]]; then
        local m2='IN  '
      elif [[ $info2 == *"OUTPUT"* ]]; then
        local m2='OUT '
      else
        local m2='?   '
      fi
    fi
    echo " | $bcm1 | $wpi1 | ${PHY_NAMES[$pin1]} | $m1 | $v1 | $pin1 || $pin2 | $v2 | $m2 | ${PHY_NAMES[$pin2]} | $wpi2 | $bcm2 |"                        
  done

  echo ' +-----+-----+---------+------+---+----++----+---+------+---------+-----+-----+'
  echo ' | BCM | wPi |   Name  | Mode | V | Physical | V | Mode | Name    | wPi | BCM |'
  echo " +-----+-----+---------+------+---+${PI_MODELS[$model]}+---+------+---------+-----+-----+"
}
