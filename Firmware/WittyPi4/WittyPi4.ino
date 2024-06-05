/**
 * Firmware for WittyPi 4
 * 
 * Revision: 6
 */
 
#define SDA_PIN 2
#define SDA_PORT PORTB
#define SCL_PIN 0
#define SCL_PORT PORTA
#include "SoftWireMaster.h"

#include <WireS.h>
#include <core_timers.h>
#include <avr/sleep.h>
#include <EEPROM.h>

#define PIN_SYS_UP                0   // pin to listen to SYS_UP
#define PIN_LED                   0   // pin to drive white LED
#define PIN_BUTTON                1   // pin to button
#define PIN_CTRL                  3   // pin to control output
#define PIN_TX_UP                 5   // pin to listen to Raspberry Pi's TXD
#define PIN_VIN                   A1  // pin to ADC1
#define PIN_VOUT                  A2  // pin to ADC2
#define PIN_VK                    A3  // pin to ADC3

#define PIN_SDA                   4   // pin to SDA for I2C (ATtiny841 as slave)
#define PIN_SCL                   6   // pin to SCL for I2C (ATtiny841 as slave)

#define PIN_I_SDA                 2   // pin to SDA for internal I2C (ATtiny841 as master)
#define PIN_I_SCL                 10  // pin to SCL for internal I2C (ATtiny841 as master)

#define ADDRESS_LM75B           0x48  // LM75B address in internal I2C bus
#define ADDRESS_RTC             0x51  // PCF85063 address in internal I2C bus

/*
 * I2C registers
 * 
 * Registers with index 0~15 are readonly
 * Registers with index 16~49 can be read/wrote
 * Registers with index >= 50 are vitual registers
 */

/*
 * read-only registers
 */
#define I2C_ID                      0   // firmware id
#define I2C_VOLTAGE_IN_I            1   // integer part for input voltage
#define I2C_VOLTAGE_IN_D            2   // decimal part (x100) for input voltage
#define I2C_VOLTAGE_OUT_I           3   // integer part for output voltage
#define I2C_VOLTAGE_OUT_D           4   // decimal part (x100) for output voltage
#define I2C_CURRENT_OUT_I           5   // integer part for output current
#define I2C_CURRENT_OUT_D           6   // decimal part (x100) for output current
#define I2C_POWER_MODE              7   // 1 if Witty Pi is powered via the DC input, 0 if direclty use 5V input
#define I2C_LV_SHUTDOWN             8   // 1 if system was shutdown by low voltage, otherwise 0
#define I2C_ALARM1_TRIGGERED        9   // 1 if alarm1 (startup) has been triggered
#define I2C_ALARM2_TRIGGERED        10  // 1 if alarm2 (shutdown) has been triggered
#define I2C_ACTION_REASON           11  // the latest action reason: 1-alarm1; 2-alarm2; 3-click; 4-low voltage; 5-voltage restored; 6-over temperature; 7-below temperature; 8-alarm1 delayed; 10-power connected; 11-reboot
#define I2C_FW_REVISION             12  // the firmware revision
#define I2C_RFU_1                   13  // reserve for future usage
#define I2C_RFU_2                   14  // reserve for future usage
#define I2C_RFU_3                   15  // reserve for future usage

/*
 * readable/writable registers
 */
#define I2C_CONF_ADDRESS            16  // I2C slave address: defaul=0x08
#define I2C_CONF_DEFAULT_ON         17  // turn on RPi when power is connected: 1=yes, 0=no
#define I2C_CONF_PULSE_INTERVAL     18  // pulse interval (in seconds, for LED and dummy load): default=4 (4 sec)
#define I2C_CONF_LOW_VOLTAGE        19  // low voltage threshold (x10), 255=disabled
#define I2C_CONF_BLINK_LED          20  // how long the white LED should stay on (in ms), 0 if white LED should not blink.
#define I2C_CONF_POWER_CUT_DELAY    21  // the delay (x10) before power cut: default=70 (7 sec)
#define I2C_CONF_RECOVERY_VOLTAGE   22  // voltage (x10) that triggers recovery, 255=disabled
#define I2C_CONF_DUMMY_LOAD         23  // how long the dummy load should be applied (in ms), 0 if dummy load is off.
#define I2C_CONF_ADJ_VIN            24  // adjustment for measured Vin (x100), range from -127 to 127
#define I2C_CONF_ADJ_VOUT           25  // adjustment for measured Vout (x100), range from -127 to 127
#define I2C_CONF_ADJ_IOUT           26  // adjustment for measured Iout (x100), range from -127 to 127

#define I2C_CONF_SECOND_ALARM1      27  // Second_alarm register for startup alarm (BCD format)
#define I2C_CONF_MINUTE_ALARM1      28  // Minute_alarm register for startup alarm (BCD format)
#define I2C_CONF_HOUR_ALARM1        29  // Hour_alarm register for startup alarm (BCD format)
#define I2C_CONF_DAY_ALARM1         30  // Day_alarm register for startup alarm (BCD format)
#define I2C_CONF_WEEKDAY_ALARM1     31  // Weekday_alarm register for startup alarm (BCD format)

#define I2C_CONF_SECOND_ALARM2      32  // Second_alarm register for shutdown alarm (BCD format)
#define I2C_CONF_MINUTE_ALARM2      33  // Minute_alarm register for shutdown alarm (BCD format)
#define I2C_CONF_HOUR_ALARM2        34  // Hour_alarm register for shutdown alarm (BCD format)
#define I2C_CONF_DAY_ALARM2         35  // Day_alarm register for shutdown alarm (BCD format)
#define I2C_CONF_WEEKDAY_ALARM2     36  // Weekday_alarm register for shutdown alarm (BCD format)

#define I2C_CONF_RTC_OFFSET         37  // standard value for RTC offset register
#define I2C_CONF_RTC_ENABLE_TC      38  // set to 1 to enable temperature compensation
#define I2C_CONF_FLAG_ALARM1        39  // a flag that indicates alarm1 is triggered and not processed
#define I2C_CONF_FLAG_ALARM2        40  // a flag that indicates alarm2 is triggered and not processed

#define I2C_CONF_IGNORE_POWER_MODE  41  // set 1 to ignore I2C_POWER_MODE for low voltage shutdown and recovery
#define I2C_CONF_IGNORE_LV_SHUTDOWN 42  // set 1 to ignore I2C_LV_SHUTDOWN for low voltage shutdown and recovery

#define I2C_CONF_BELOW_TEMP_ACTION  43  // action for below temperature: 0-do nothing; 1-shutdown; 2-startup
#define I2C_CONF_BELOW_TEMP_POINT   44  // set point for below temperature
#define I2C_CONF_OVER_TEMP_ACTION   45  // action for over temperature: 0-do nothing; 1-shutdown; 2-startup
#define I2C_CONF_OVER_TEMP_POINT    46  // set point for over temperature

#define I2C_CONF_DEFAULT_ON_DELAY   47  // the delay (in second) between MCU initialization and turning on Raspberry Pi, when I2C_CONF_DEFAULT_ON = 1
#define I2C_CONF_MISC               48  // 8 bits for miscellaneous configuration. bit-0: set to 1 to disable alarm1 (startup) delay
#define I2C_CONF_RFU_3              49  // reserve for future usage

#define I2C_REG_COUNT               50  // number of (non-virtual) I2C registers

/*
 * virtual registers (mapped to LM75B or RCF85063)
 */
#define I2C_LM75B_TEMPERATURE       50  // mapped to temperature register in LM75B (2 bytes, readonly)
#define I2C_LM75B_CONF              51  // mapped to configuration register in LM75B
#define I2C_LM75B_THYST             52  // mapped to hysteresis temperature register in LM75B (2 bytes)
#define I2C_LM75B_TOS               53  // mapped to overtemperature register in LM75B (2 bytes)

#define I2C_RTC_CTRL1               54  // mapped to Control_1 register in PCF85063
#define I2C_RTC_CTRL2               55  // mapped to Control_2 register in PCF85063
#define I2C_RTC_OFFSET              56  // mapped to Offset register in PCF85063
#define I2C_RTC_RAM_BYTE            57  // mapped to RAM_byte register in PCF85063
#define I2C_RTC_SECONDS             58  // mapped to Seconds register in PCF85063
#define I2C_RTC_MINUTES             59  // mapped to Minutes register in PCF85063
#define I2C_RTC_HOURS               60  // mapped to Hours register in PCF85063
#define I2C_RTC_DAYS                61  // mapped to Days register in PCF85063
#define I2C_RTC_WEEKDAYS            62  // mapped to Weekdays register in PCF85063
#define I2C_RTC_MONTHS              63  // mapped to Months register in PCF85063
#define I2C_RTC_YEARS               64  // mapped to Years register in PCF85063
#define I2C_RTC_SECOND_ALARM        65  // mapped to Second_alarm register in PCF85063
#define I2C_RTC_MINUTE_ALARM        66  // mapped to Minute_alarm register in PCF85063
#define I2C_RTC_HOUR_ALARM          67  // mapped to Hour_alarm register in PCF85063
#define I2C_RTC_DAY_ALARM           68  // mapped to Day_alarm register in PCF85063
#define I2C_RTC_WEEKDAY_ALARM       69  // mapped to Weekday_alarm register in PCF85063
#define I2C_RTC_TIMER_VALUE         70  // mapped to Timer_value register in PCF85063
#define I2C_RTC_TIMER_MODE          71  // mapped to Timer_mode register in PCF85063

/**
 * Reason for latest action (used by I2C_ACTION_REASON register)
 */
#define REASON_ALARM1             1
#define REASON_ALARM2             2
#define REASON_CLICK              3
#define REASON_LOW_VOLTAGE        4
#define REASON_VOLTAGE_RESTORE    5
#define REASON_OVER_TEMPERATURE   6
#define REASON_BELOW_TEMPERATURE  7
#define REASON_ALARM1_DELAYED     8
#define REASON_POWER_CONNECTED    10
#define REASON_REBOOT             11

volatile byte i2cReg[I2C_REG_COUNT];

volatile char i2cIndex = 0;

volatile boolean buttonPressed = false;

volatile boolean powerIsOn = false;

volatile boolean listenToTxd = false;

volatile boolean systemIsUp = false;

volatile boolean turningOff = false;

volatile boolean wakeupByWatchdog = false;

volatile boolean ledIsOn = false;

volatile unsigned long buttonStateChangeTime = 0;

volatile unsigned long voltageQueryTime = 0;

volatile unsigned int powerCutDelay = 0;

volatile byte skipAdjustRtcCount = 0;

volatile byte skipTempShutdownCount = 0;

volatile boolean isButtonClickEmulated = false;

volatile byte skipPulseCount = 0;

volatile byte alarm1Delayed = 0;

volatile byte ledUpTime = 0;

volatile byte lastButton = 1;

volatile byte lastSystemUp = 0;

volatile boolean turnOffFromTXD = false;

volatile unsigned long guaranteedWakeCounter = 0;

const unsigned long guaranteedWakeTreshold = 86400; // 24 hours

SoftWireMaster softWireMaster;  // software I2C master


void setup() {
  // initialize software I2C master
  softWireMaster.begin();

  // initialize pin states and make sure power is cut
  pinMode(PIN_SYS_UP, INPUT);
  pinMode(PIN_BUTTON, INPUT_PULLUP);
  pinMode(PIN_CTRL, OUTPUT);
  pinMode(PIN_TX_UP, INPUT);
  pinMode(PIN_VIN, INPUT);
  pinMode(PIN_VOUT, INPUT);
  pinMode(PIN_VK, INPUT);
  pinMode(PIN_SDA, INPUT_PULLUP);
  pinMode(PIN_SCL, INPUT_PULLUP);
  cutPower();

  // use internal 1.1V reference
  analogReference(INTERNAL1V1);

  // initlize registers
  initializeRegisters();

  // i2c initialization
  TinyWireS.begin((i2cReg[I2C_CONF_ADDRESS] <= 0x07 || i2cReg[I2C_CONF_ADDRESS] >= 0x78) ? 0x08 : i2cReg[I2C_CONF_ADDRESS]);
  TinyWireS.onAddrReceive(addressEvent);
  TinyWireS.onReceive(receiveEvent);
  TinyWireS.onRequest(requestEvent);

  // disable global interrupts
  cli();

  // enable pin change interrupts
  GIMSK = _BV (PCIE0) | _BV (PCIE1);
  PCMSK1 = _BV (PCINT8) | _BV (PCINT9);
  PCMSK0 = _BV (PCINT5);

  // enable Timer1
  timer1_enable();

  // enable watchdog
  watchdog_enable(0);
  
  // enable all interrupts
  sei();

  // power on or sleep
  bool defaultOn = (i2cReg[I2C_CONF_DEFAULT_ON] == 1);
  if (defaultOn) {
    delay(i2cReg[I2C_CONF_DEFAULT_ON_DELAY] * 1000);  // delay if the value is configured
    updateRegister(I2C_ACTION_REASON, REASON_POWER_CONNECTED);
    powerOn();  // power on directly
  } else {
    sleep();    // sleep and wait for button action
  }  
}


void loop() {
  // we don't put anything here
}


// initialize the registers and synchronize with EEPROM
void initializeRegisters() {
  i2cReg[I2C_ID] = 0x26;
  i2cReg[I2C_FW_REVISION] = 0x06;
  
  i2cReg[I2C_CONF_ADDRESS] = 0x08;

  i2cReg[I2C_CONF_PULSE_INTERVAL] = 4;
  i2cReg[I2C_CONF_LOW_VOLTAGE] = 255;
  i2cReg[I2C_CONF_BLINK_LED] = 100;
  i2cReg[I2C_CONF_POWER_CUT_DELAY] = 70;
  i2cReg[I2C_CONF_RECOVERY_VOLTAGE] = 255;

  i2cReg[I2C_CONF_ADJ_VIN] = 20;
  i2cReg[I2C_CONF_ADJ_VOUT] = 20;

  i2cReg[I2C_CONF_RTC_ENABLE_TC] = 0x01;

  i2cReg[I2C_CONF_BELOW_TEMP_POINT] = 0x4b;
  i2cReg[I2C_CONF_OVER_TEMP_POINT] = 0x50;

  // synchronize configuration with EEPROM
  for (byte i = 0; i < I2C_REG_COUNT; i ++) {
    byte val = EEPROM.read(i);
    if (val == 255) {
      EEPROM.update(i, i2cReg[i]);
    } else {
      i2cReg[i] = val;
    } 
  }

  // copy some EEPROM backed data to PCF85063 and LM75B
  writeToDevice(ADDRESS_LM75B, I2C_LM75B_TOS - I2C_LM75B_TEMPERATURE, &i2cReg[I2C_CONF_OVER_TEMP_POINT], 1);
  writeToDevice(ADDRESS_LM75B, I2C_LM75B_THYST - I2C_LM75B_TEMPERATURE, &i2cReg[I2C_CONF_BELOW_TEMP_POINT], 1);
  writeToDevice(ADDRESS_RTC, I2C_RTC_OFFSET - I2C_RTC_CTRL1, &i2cReg[I2C_CONF_RTC_OFFSET], 1);
}


// enable watchdog timer with specified wdp (or get it from I2C_CONF_PULSE_INTERVAL)
void watchdog_enable(byte wdp) {
  cli();
  WDTCSR |= _BV(WDIE);
  WDTCSR |= 6;  // trigger every second
  sei();
}


// enable timer1 (for power cut delay)
void timer1_enable() {
  // set entire TCCR1A and TCCR1B register to 0
  TCCR1A = 0;
  TCCR1B = 0;
  
  // set 1024 prescaler
  bitSet(TCCR1B, CS12);
  bitSet(TCCR1B, CS10);

  // clear overflow interrupt flag
  bitSet(TIFR1, TOV1);

  // set timer counter
  TCNT1 = getPowerCutPreloadTimer(true);

  // enable Timer1 overflow interrupt
  bitSet(TIMSK1, TOIE1);
}


// disable timer1
void timer1_disable() {
  // disable Timer1 overflow interrupt
  bitClear(TIMSK1, TOIE1);
}


// put MCU into sleep to save power
void sleep() {
  timer1_disable();                       // disable Timer1
  ADCSRA &= ~_BV(ADEN);                   // ADC off
  set_sleep_mode(SLEEP_MODE_PWR_DOWN);    // power-down mode 
  sleep_enable();                         // sets the Sleep Enable bit in the MCUCR Register (SE BIT)
  
  GIMSK = _BV (PCIE1);                    // only enable interrupt for switch (PCINT9)
  PCMSK1 = _BV (PCINT9);
  sei();

  wakeupByWatchdog = true;
  do {
    sleep_cpu();                          // sleep
    if (wakeupByWatchdog) {               // wake up by watch dog
      skipPulseCount ++;
      guaranteedWakeCounter ++;
      if (guaranteedWakeCounter >= guaranteedWakeTreshold) {
        wakeupByWatchdog = false;
        updateRegister(I2C_ACTION_REASON, REASON_REBOOT); // TODO Maybe implement a new reason for this
      } else if (skipPulseCount >= i2cReg[I2C_CONF_PULSE_INTERVAL]) {
        skipPulseCount = 0;

        // blink white LED
        if (i2cReg[I2C_CONF_BLINK_LED] > 0) {
          byte ms = i2cReg[I2C_CONF_BLINK_LED];
          ledOn();
          delay(ms);
          ledOff();
        }
  
        // dummy load
        if (i2cReg[I2C_CONF_DUMMY_LOAD] > 0) {
          byte ms = i2cReg[I2C_CONF_DUMMY_LOAD];
          digitalWrite(PIN_CTRL, 1);
          delay(ms);
          cutPower();
        }

        // update power mode and get input voltage
        float vin = updatePowerMode();
  
        // check input voltage if shutdown because of low voltage, and recovery voltage has been set
        // will skip checking I2C_LV_SHUTDOWN if I2C_CONF_LOW_VOLTAGE is set to 0xFF
        if ((i2cReg[I2C_POWER_MODE] == 1 || i2cReg[I2C_CONF_IGNORE_POWER_MODE] == 1) 
            && (i2cReg[I2C_LV_SHUTDOWN] == 1 || i2cReg[I2C_CONF_LOW_VOLTAGE] == 255 || i2cReg[I2C_CONF_IGNORE_LV_SHUTDOWN] == 1) 
            && i2cReg[I2C_CONF_RECOVERY_VOLTAGE] != 255) {
          float vrec = ((float)i2cReg[I2C_CONF_RECOVERY_VOLTAGE]) / 10;
          if (vin >= vrec) {
            wakeupByWatchdog = false;       // recovery from low voltage shutdown
            updateRegister(I2C_ACTION_REASON, REASON_VOLTAGE_RESTORE);
          }
        }
      }
    }
  } while (wakeupByWatchdog);             // quit sleeping if wake up by button

  cli();                                  // disable interrupts
  sleep_disable();                        // clear SE bit
  ADCSRA |= _BV(ADEN);                    // ADC on
  timer1_enable();                        // enable Timer1

  GIMSK = _BV (PCIE0) | _BV (PCIE1);
  PCMSK1 = _BV (PCINT8) | _BV (PCINT9); 
  sei();                                  // enable all required interrupts

  // tap the button to wake up
  listenToTxd = false;
  systemIsUp = false;
  turningOff = false;
  powerOn();
  TCNT1 = getPowerCutPreloadTimer(true);
}


// cut 5V output on GPIO header 
void cutPower() {
  powerIsOn = false;
  digitalWrite(PIN_CTRL, 0);
  turnOffFromTXD = false;
}


// output 5V to GPIO header
void powerOn() {
  powerIsOn = true;
  skipTempShutdownCount = 0;
  guaranteedWakeCounter = 0;
  digitalWrite(PIN_CTRL, 1);
  updatePowerMode();
}


// turn on white LED
void ledOn() {
  ledIsOn = true;
  pinMode(PIN_LED, OUTPUT);
  digitalWrite(PIN_LED, 1);
  ledUpTime = 0;
}


// turn off white LED
void ledOff() {
  digitalWrite(PIN_LED, 0);
  pinMode(PIN_LED, INPUT);
  ledIsOn = false;
}


// get voltage at specific pin
float getAdcVoltageAtPin(byte pin) {
  return 0.061290322580645 * analogRead(pin);    // 57*1.1/1023~=0.06129
}


// get voltage at cathode
float getCathVoltage() {
  return 0.001075268817204 * analogRead(PIN_VK);   // 1.1/1023~=0.001075  
}


// get actual adjust value for given register
float getAdjustValue(byte regId) {
  return (float)((char)i2cReg[regId]) / 100.0f;
}


// update power mode according to input voltage, and return the input voltage
float updatePowerMode() {
  byte bk = ADCSRA;
  ADCSRA |= _BV(ADEN);
  float vin = getAdcVoltageAtPin(PIN_VIN);
  ADCSRA = bk;  
  updateRegister(I2C_POWER_MODE, (vin > 5.25f) ? 1 : 0);
  return vin;
}


// get input voltage
float getInputVoltage() {
  float v = getAdcVoltageAtPin(PIN_VIN);
  v += getAdjustValue(I2C_CONF_ADJ_VIN);
  updateRegister(I2C_VOLTAGE_IN_I, getIntegerPart(v));
  updateRegister(I2C_VOLTAGE_IN_D, getDecimalPart(v));
  return v;
}


// get output voltage
float getOutputVoltage() {
  float v = getAdcVoltageAtPin(PIN_VOUT);
  float vk = getCathVoltage();
  v = v - vk + getAdjustValue(I2C_CONF_ADJ_VOUT);
  updateRegister(I2C_VOLTAGE_OUT_I, getIntegerPart(v));
  updateRegister(I2C_VOLTAGE_OUT_D, getDecimalPart(v));
  return v;
}


// get output current
float getOutputCurrent() {
  float v = getCathVoltage();
  float i = v / 0.05 + getAdjustValue(I2C_CONF_ADJ_IOUT);
  updateRegister(I2C_CURRENT_OUT_I, getIntegerPart(i));
  updateRegister(I2C_CURRENT_OUT_D, getDecimalPart(i));
  return i;
}


// get temperature
char getTemperature() {
  return readFromDevice(ADDRESS_LM75B, I2C_LM75B_TEMPERATURE - I2C_LM75B_TEMPERATURE);
}


// get integer part of given number
byte getIntegerPart(float v) {
  return (byte)v;  
}


// get decimal part of given number
byte getDecimalPart(float v) {
  return (byte)((v - getIntegerPart(v)) * 100);
}


// get the preload timer value for power cut
unsigned int getPowerCutPreloadTimer(boolean reset) {
  if (reset) {
    powerCutDelay = i2cReg[I2C_CONF_POWER_CUT_DELAY];
  }
  unsigned int actualDelay = 0;
  if (powerCutDelay > 83) {
    actualDelay = 83;
  } else {
    actualDelay = powerCutDelay;
  }
  powerCutDelay -= actualDelay;
  return 65535 - 781 * actualDelay;
}


// receives a sequence of start|address|direction bit from i2c master
boolean addressEvent(uint16_t slaveAddress, uint8_t startCount) {
  if (startCount > 0 && TinyWireS.available()) {
    i2cIndex = TinyWireS.read();
  }
  return true;
}


// receives a sequence of data from i2c master (master writes to this device)
void receiveEvent(int count) {
  if (TinyWireS.available()) {
    i2cIndex = TinyWireS.read();
    if (i2cIndex >= I2C_LM75B_TEMPERATURE && i2cIndex <= I2C_LM75B_TOS) {  // mapped to LM75B's register
      softWireMaster.beginTransmission(ADDRESS_LM75B);
      softWireMaster.write(i2cIndex - I2C_LM75B_TEMPERATURE);
      if (i2cIndex == I2C_LM75B_CONF) {
        softWireMaster.write(TinyWireS.read());
      } else if (i2cIndex != I2C_LM75B_TEMPERATURE) {
        softWireMaster.write(TinyWireS.read());
        softWireMaster.write(TinyWireS.read());
      }
      softWireMaster.endTransmission();    
    } else if (i2cIndex >= I2C_RTC_CTRL1 && i2cIndex <= I2C_RTC_TIMER_MODE) {  // mapped to RTC's register
      softWireMaster.beginTransmission(ADDRESS_RTC);
      softWireMaster.write(i2cIndex - I2C_RTC_CTRL1);
      softWireMaster.write(TinyWireS.read());
      softWireMaster.endTransmission();
    } else if (i2cIndex >= I2C_CONF_ADDRESS && i2cIndex < I2C_REG_COUNT) {  // non-virtual, writable i2c register
      if (TinyWireS.available()) {
        // clear alarm triggered flag if alam is changed
        if (i2cIndex >= I2C_CONF_SECOND_ALARM1 && i2cIndex <= I2C_CONF_WEEKDAY_ALARM1) {
          updateRegister(I2C_ALARM1_TRIGGERED, 0);
        }
        if (i2cIndex >= I2C_CONF_SECOND_ALARM2 && i2cIndex <= I2C_CONF_WEEKDAY_ALARM2) {
          updateRegister(I2C_ALARM2_TRIGGERED, 0);
        }

        // update the register value
        updateRegister(i2cIndex, TinyWireS.read());

        // if RTC offset value is changed, immediately update to RTC
        if (i2cIndex == I2C_CONF_RTC_OFFSET) {
          updateRegister(I2C_RTC_OFFSET, i2cReg[I2C_CONF_RTC_OFFSET]);
          writeToDevice(ADDRESS_RTC, I2C_RTC_OFFSET - I2C_RTC_CTRL1, &i2cReg[I2C_CONF_RTC_OFFSET], 1);
        }
      }
    }
  }
}


// i2c master requests data from this device (master reads from this device)
void requestEvent() {
  float v = 0.0;
  switch (i2cIndex) {
    case I2C_VOLTAGE_IN_I:
      getInputVoltage();
      break;
    case I2C_VOLTAGE_OUT_I:
      getOutputVoltage();
      break;
    case I2C_CURRENT_OUT_I:
      getOutputCurrent();
      break;
    case I2C_POWER_MODE:
      updatePowerMode();
      break;
  }

  if (i2cIndex >= I2C_LM75B_TEMPERATURE && i2cIndex <= I2C_LM75B_TOS) {  // mapped to LM75B's register
    softWireMaster.beginTransmission(ADDRESS_LM75B);
    softWireMaster.write(i2cIndex - I2C_LM75B_TEMPERATURE);
    if (i2cIndex == I2C_LM75B_CONF) {
      softWireMaster.requestFrom(ADDRESS_LM75B, 1);
      TinyWireS.write(softWireMaster.read());
    } else {
      softWireMaster.requestFrom(ADDRESS_LM75B, 2);
      TinyWireS.write(softWireMaster.read());
      TinyWireS.write(softWireMaster.read());
      softWireMaster.endTransmission();
    }
  } else if (i2cIndex >= I2C_RTC_CTRL1 && i2cIndex <= I2C_RTC_TIMER_MODE) {  // mapped to RTC's register
    softWireMaster.beginTransmission(ADDRESS_RTC);
    softWireMaster.write(i2cIndex - I2C_RTC_CTRL1);
    softWireMaster.requestFrom(ADDRESS_RTC, 1);
    TinyWireS.write(softWireMaster.read());
    softWireMaster.endTransmission();
  } else {
    TinyWireS.write(i2cReg[i2cIndex]);  // direct i2c register
  }
}


// watchdog interrupt routine
ISR (WDT_vect) {
  // turn off white LED after delay
  ledUpTime++;
  if (ledUpTime == 3) {
    ledUpTime = 0;
    ledOff();
  }

  // process low voltage
  processLowVoltageIfNeeded();

  // handle temperature related actions
  handleTemperatureActtonsIfNeeded();

  // process RTC alarms
  processAlarmIfNeeded();

  // adjust RTC
  adjustRTCIfNeeded();

  // process delayed Alarm1 (startup)
  if (!powerIsOn && alarm1Delayed > 0) {
    alarm1Delayed ++;
    if (alarm1Delayed == 4) {
      alarm1Delayed = 0;
      updateRegister(I2C_ACTION_REASON, REASON_ALARM1_DELAYED);
      emulateButtonClick();
    }
  }
}


// pin state change interrupt routine for PCINT0_vect (PCINT0~7) 
ISR (PCINT0_vect) {
  if (digitalRead(PIN_TX_UP) == 1) {
    if (!listenToTxd) {
      // start listen to TXD pin;
      listenToTxd = true;
    }
  } else {
    if (listenToTxd && systemIsUp) {
     listenToTxd = false;
     systemIsUp = false;
     turningOff = true;
     turnOffFromTXD = true;
     ledOff(); // turn off the white LED
     TCNT1 = getPowerCutPreloadTimer(true);
    }
  }
}


// pin state change interrupt routine for PCINT1_vect (PCINT8~15)
ISR (PCINT1_vect) {
  byte button = digitalRead(PIN_BUTTON);
  byte systemUp = digitalRead(PIN_SYS_UP);

  if (button != lastButton) {
    if (button == 0) {   // button is pressed, PCINT9
      // restore from emulated button clicking
      digitalWrite(PIN_BUTTON, 1);
      pinMode(PIN_BUTTON, INPUT_PULLUP);
      
      // turn on the white LED
      ledOn();
      
      if (!buttonPressed) {
        buttonPressed = true;
        if (!isButtonClickEmulated) {
          updateRegister(I2C_ACTION_REASON, REASON_CLICK);
        }
        if (powerIsOn) {
          if (systemIsUp) {
            turningOff = true;
            systemIsUp = false;
          }
        } else {
          wakeupByWatchdog = false; // will quit sleeping
          powerOn();
        }
      }
      TCNT1 = getPowerCutPreloadTimer(true);
      isButtonClickEmulated = false;
    } else {  // button is released
      buttonPressed = false;
    } 
  }
  
  if (systemUp != lastSystemUp) {
    if (!ledIsOn && powerIsOn && !turningOff && !systemIsUp && systemUp == 1)  {  // system is up, PCINT8
      // clear the low-voltage shutdown flag when sys_up signal arrives
      updateRegister(I2C_LV_SHUTDOWN, 0);
    
      // mark system is up
      systemIsUp = true;
    }
  }

  lastButton = button;
  lastSystemUp = systemUp;
}


// timer1 overflow interrupt routine
ISR (TIM1_OVF_vect) {
  if (powerCutDelay == 0) {
    // cut the power after delay
    TCNT1 = getPowerCutPreloadTimer(true);
    forcePowerCutIfNeeded();
    if (turningOff) {
      if (turnOffFromTXD && digitalRead(PIN_TX_UP) == 1) {  // if it is rebooting
        turningOff = false;
        updateRegister(I2C_ACTION_REASON, REASON_REBOOT);
        ledOn();
      } else {  // cut the power and enter sleep
        cutPower();
        sleep();
      }
    }
  } else {
    TCNT1 = getPowerCutPreloadTimer(false);
    forcePowerCutIfNeeded();
  }
}


// update I2C register and save to EEPROM
void updateRegister(byte index, byte value) {
  i2cReg[index] = value;
  if (index < I2C_REG_COUNT) {
    EEPROM.update(index, value);
  }
}


// emulate button clicking
void emulateButtonClick() {
  isButtonClickEmulated = true;
  pinMode(PIN_BUTTON, OUTPUT);
  digitalWrite(PIN_BUTTON, 0);
}


// temporarily turn on ADC to get input voltage 
float turnOnAdcAndGetInputVoltage() {
  byte bk = ADCSRA;
  ADCSRA |= _BV(ADEN);
  float vin = getInputVoltage();
  ADCSRA = bk;
  return vin;
}


// check wether alarm can be triggered
boolean canTriggerAlarm() {
  if (powerIsOn || i2cReg[I2C_POWER_MODE] == 0) {
    return true;
  }
  float vin = turnOnAdcAndGetInputVoltage();
  float vlow = ((float)i2cReg[I2C_CONF_LOW_VOLTAGE]) / 10;
  if (i2cReg[I2C_LV_SHUTDOWN] == 1) {
    if (vin > vlow) {
      float vrec = ((float)i2cReg[I2C_CONF_RECOVERY_VOLTAGE]) / 10;
      if (i2cReg[I2C_CONF_RECOVERY_VOLTAGE] == 255 || vin > vrec) {
        return true;
      }
    }
  } else {
    if (vin > vlow || i2cReg[I2C_CONF_LOW_VOLTAGE] == 255) {
      return true;
    } else {
      // this will update the I2C_LV_SHUTDOWN flag when Vin drop under Vlow after shutdown
      updateRegister(I2C_LV_SHUTDOWN, 1);
    }
  }
  return false;
}


// process the alarm from RTC, if exists
void processAlarmIfNeeded() {
  // get current time from RTC
  byte seconds = bcd2dec(readFromDevice(ADDRESS_RTC, I2C_RTC_SECONDS - I2C_RTC_CTRL1) & 0x7F);
  byte minutes = bcd2dec(readFromDevice(ADDRESS_RTC, I2C_RTC_MINUTES - I2C_RTC_CTRL1));
  byte hours = bcd2dec(readFromDevice(ADDRESS_RTC, I2C_RTC_HOURS - I2C_RTC_CTRL1));
  byte date = bcd2dec(readFromDevice(ADDRESS_RTC, I2C_RTC_DAYS - I2C_RTC_CTRL1));
  long cur_ts = getTimestamp(date, hours, minutes, seconds);
  
  // get startup (alarm1) time
  seconds = bcd2dec(i2cReg[I2C_CONF_SECOND_ALARM1]);
  minutes = bcd2dec(i2cReg[I2C_CONF_MINUTE_ALARM1]);
  hours = bcd2dec(i2cReg[I2C_CONF_HOUR_ALARM1]);
  date = bcd2dec(i2cReg[I2C_CONF_DAY_ALARM1]);
  long alarm1_ts = getTimestamp(date, hours, minutes, seconds);

  // get shutdown (alarm2) time
  seconds = bcd2dec(i2cReg[I2C_CONF_SECOND_ALARM2]);
  minutes = bcd2dec(i2cReg[I2C_CONF_MINUTE_ALARM2]);
  hours = bcd2dec(i2cReg[I2C_CONF_HOUR_ALARM2]);
  date = bcd2dec(i2cReg[I2C_CONF_DAY_ALARM2]);
  long alarm2_ts = getTimestamp(date, hours, minutes, seconds);

  boolean canTrigger = canTriggerAlarm();
  boolean alarm1HasTriggered = (alarm1_ts == 0 || i2cReg[I2C_ALARM1_TRIGGERED] == 1);
  boolean alarm2HasTriggered = (alarm2_ts == 0 || i2cReg[I2C_ALARM2_TRIGGERED] == 1);

  long overdue_alarm1 = cur_ts - alarm1_ts;
  long overdue_alarm2 = cur_ts - alarm2_ts;
  
  if (canTrigger && !alarm1HasTriggered && overdue_alarm1 >= 0 && overdue_alarm1 < 2) {  // Alarm 1: startup
    updateRegister(I2C_ALARM1_TRIGGERED, 1);
    updateRegister(I2C_CONF_FLAG_ALARM1, 1);
    if (!powerIsOn) {
      updateRegister(I2C_ACTION_REASON, REASON_ALARM1);
      emulateButtonClick();
    } else {
      // power is not cut yet, will power on later if alarm1 delay is allowed
      if ((i2cReg[I2C_CONF_MISC] & 0x01) == 0) {
        alarm1Delayed = 1;
      }
    }
  } else if (canTrigger && !alarm2HasTriggered && overdue_alarm2 >= 0 && overdue_alarm2 < 2) {  // Alarm 2: shutdown
    updateRegister(I2C_ALARM2_TRIGGERED, 1);
    updateRegister(I2C_CONF_FLAG_ALARM2, 1);
    if (powerIsOn && !turningOff) {
      updateRegister(I2C_ACTION_REASON, REASON_ALARM2);
      emulateButtonClick();
      turningOff = true;
      systemIsUp = false;
    }
  } else if (!alarm1HasTriggered && overdue_alarm1 < 0 && overdue_alarm1 >= -2) {
    reset_rtc_alarm();
    copyAlarm(I2C_CONF_SECOND_ALARM1);
  } else if (!alarm2HasTriggered && overdue_alarm2 < 0 && overdue_alarm2 >= -2) {
    reset_rtc_alarm();
    copyAlarm(I2C_CONF_SECOND_ALARM2);
  }
}


// enable alarm and clear the alarm flag (if exists)
void reset_rtc_alarm() {
  byte data = 0x80;
  writeToDevice(ADDRESS_RTC, 0x01, &data, 1);
}


// copy alarm data to RTC's alarm registers
void copyAlarm(byte offset) {
  for (byte i = 0; i < 4; i ++) {
    writeToDevice(ADDRESS_RTC, 0x0B + i, &i2cReg[offset + i], 1);
  }
}


// handle temperature related actions (if configured)
void handleTemperatureActtonsIfNeeded() {
  // this counter makes sure not turning off your Pi too quickly
  if (skipTempShutdownCount < 120) {
    skipTempShutdownCount ++;
  }
  char t = getTemperature();
  char ot = i2cReg[I2C_CONF_OVER_TEMP_POINT];
  char ht = i2cReg[I2C_CONF_BELOW_TEMP_POINT];
  if (t > ot) {
    if (i2cReg[I2C_CONF_OVER_TEMP_ACTION] == 1) {
      updateRegister(I2C_ACTION_REASON, REASON_OVER_TEMPERATURE);
      turnOffIfPowerOn();
    } else if (i2cReg[I2C_CONF_OVER_TEMP_ACTION] == 2) {
      updateRegister(I2C_ACTION_REASON, REASON_OVER_TEMPERATURE);
      turnOnIfPowerOff();
    }
  } else if (t < ht) {
    if (i2cReg[I2C_CONF_BELOW_TEMP_ACTION] == 1) {
      updateRegister(I2C_ACTION_REASON, REASON_BELOW_TEMPERATURE);
      turnOffIfPowerOn();
    } else if (i2cReg[I2C_CONF_BELOW_TEMP_ACTION] == 2) {
      updateRegister(I2C_ACTION_REASON, REASON_BELOW_TEMPERATURE);
      turnOnIfPowerOff();
    }
  }
}


// process low voltage
void processLowVoltageIfNeeded() {
  // if input voltage is not fixed 5V, detect low voltage
  if (powerIsOn && systemIsUp 
      && (i2cReg[I2C_POWER_MODE] == 1 || i2cReg[I2C_CONF_IGNORE_POWER_MODE] == 1)
      && (i2cReg[I2C_LV_SHUTDOWN] == 0 || i2cReg[I2C_CONF_IGNORE_LV_SHUTDOWN] == 1)
      && i2cReg[I2C_CONF_LOW_VOLTAGE] != 255) {
    float vin = getInputVoltage();
    float vlow = ((float)i2cReg[I2C_CONF_LOW_VOLTAGE]) / 10;
    if (vin < vlow) {  // input voltage is below the low voltage threshold
      updateRegister(I2C_LV_SHUTDOWN, 1);
      updateRegister(I2C_ACTION_REASON, REASON_LOW_VOLTAGE);
      emulateButtonClick();
      turningOff = true;
      systemIsUp = false;
    }
  }
}


// turn off Raspberry Pi only if it is on
void turnOffIfPowerOn() {
  if (skipTempShutdownCount >= 120 && powerIsOn && !turningOff) {
    emulateButtonClick();
    turningOff = true;
    systemIsUp = false;
  }
}


// turn on Raspberry Pi only if it is off
void turnOnIfPowerOff() {
   if (!powerIsOn) {
    emulateButtonClick();
  }
}


// software I2C master read data from device on internal I2C bus
byte readFromDevice(byte address, byte index) {
  softWireMaster.beginTransmission(address);
  softWireMaster.write(index);
  softWireMaster.requestFrom((int)address, 1);
  byte data = softWireMaster.read();
  softWireMaster.endTransmission();
  return data;
}


// software I2C master write data to device on internal I2C bus
void writeToDevice(byte address, byte index, byte* data, byte count) {
  softWireMaster.beginTransmission(address);
  softWireMaster.write(index);
  for (byte i = 0; i < count; i ++) {
    softWireMaster.write(data[i]);
  }
  softWireMaster.endTransmission();
}


// convert BCD data to DEC data
byte bcd2dec(byte bcd) {
  return (bcd / 16 * 10) + (bcd % 16);
}


// get timestamp for given date and time
long getTimestamp(byte date, byte hours, byte minutes, byte seconds) {
  return (long)date * 86400 + (long)hours * 3600 + (long)minutes * 60 + seconds;
}


// force power cut, if button is pressed and hold for a few seconds
void forcePowerCutIfNeeded() {
 if (buttonPressed && digitalRead(PIN_BUTTON) == 0) {
    systemIsUp = false;
    cutPower();
    sleep();
  }
}


// adjust the RTC with offset value and the temperature compensation data (when TC is enabled)
void adjustRTCIfNeeded() {
  skipAdjustRtcCount ++;
  if (skipAdjustRtcCount == 255) {  // no need to adjust too frequently
    skipAdjustRtcCount = 0;
  
    if (i2cReg[I2C_CONF_RTC_ENABLE_TC] == 1) {
      char t = getTemperature();
      char adj = 0;
      if (t < 26) {
        adj = (t - 26) * 0.126728111f;
      } else if (t > 32 && t <= 42) {
        adj = (t - 32) * -0.092165899f;
      } else if (t > 42) {
        adj = -0.921658986f + (t - 42) * -0.276497696f;
      }
      byte data = value2Offset(offset2Value(i2cReg[I2C_CONF_RTC_OFFSET]) + adj);
      writeToDevice(ADDRESS_RTC, I2C_RTC_OFFSET - I2C_RTC_CTRL1, &data, 1);
    } else {
      writeToDevice(ADDRESS_RTC, I2C_RTC_OFFSET - I2C_RTC_CTRL1, &i2cReg[I2C_CONF_RTC_OFFSET], 1);
    }
  }
}


// convert stored offset value to actual signed value
char offset2Value(byte offset) {
  if ( (offset & 0x40) == 0) {
    return (offset & 0x3F);
  } else {
    return (offset & 0x3F) - 0x40;
  }
}


// convert actual signed value to offset value
byte value2Offset(char value) {
  if (value >= 0) {
    return (byte)value;
  } else {
    return (0x80 + value);
  }
}
