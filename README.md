# Witty-Pi-4

Witty Pi is an add-on board that adds realtime clock and power management to your Raspberry Pi. It can define your Raspberry Pi’s ON/OFF sequence, and significantly reduce the energy usage. Witty Pi 4 is the fourth generation of Witty Pi and it has these hardware resources onboard:

*   Factory calibrated and temperature compensated realtime clock with ±2ppm accuracy.
*   Dedicated temperature sensor with 0.125 °C resolution.
*   On-board DC/DC converter that accepts up to 30V DC.
*   AVR 8-bit microcontroller (MCU) with 8 KB programmable flash.

![](https://user-images.githubusercontent.com/6317566/174240816-01f8ac49-55d1-486a-bfef-b6471371125b.png)

Witty Pi 4 supports all Raspberry Pi models with 40-pin header, including A+, B+, 2B, Zero, Zero W, Zero 2 W, 3B, 3B+ and 4B.

### **References:**

*   [Witty Pi 4 Product Page](https://www.uugear.com/product/witty-pi-4/)
*   [Witty Pi 4 User Manual](https://www.uugear.com/doc/WittyPi4_UserManual.pdf)


### Modify the Firmware:
If you want to change the behavior of Witty Pi 4, you can modify the firmware, compile it and upload to your Witty Pi 4.

To compile the firmware, you need to install [ATtinyCore (V1.5.2)](https://github.com/SpenceKonde/ATTinyCore) in your Arduino IDE.

Here are the configurations on your Arduino IDE:

![](https://github.com/uugear/Witty-Pi-4/raw/main/Firmware/WittyPi4_Arduino_Settings.png)

To upload the firmware to Witty Pi, you can follow [this document](https://www.uugear.com/doc/WittyPi3_UpdateFirmware.pdf).


### Use with Banana Pi M5 (and possibly with Odroid C4)

Use Raspbian:
-----
BPI-M5 BPI-M2 Pro new image:Raspbian image, 2022-4-09 update, Raspbian image for linux kernel 4.9 and 5.17. support 32bit and 64 bit,please choose the right image

Manufacturer google driver: https://drive.google.com/drive/folders/1oqamIMl5Kmb3LVYMPFw-1tilvwKQI6n-

`2022-04-09-raspios-bullseye-arm64-bpi-m5-m2pro-sd-emmc.img`
Use 64bit version with Kernel 4.9.x (I think I2C has a bug in newer kernels)


deactive UART:
----
Note: use `/boot/boot/boot.ini`, not `/boot/config.txt`!

	#setenv overlays "i2c0 spi0 uart1"
	setenv overlays "i2c0"

Install WiringPi:
-----

	$ git clone https://github.com/BPI-SINOVOIP/amlogic-wiringPi
	$ cd amlogic-wiringPi
	$ chmod a+x build
	$ sudo ./build

Modify WiringPi sources:
As given in the PR

Install WittyPi:
-----
Dont use the install shell script, but work yourself manually along `install.sh`...

Make Pin8 give power state:
------
Add a custom LED in device tree (under leds { ... }) that map to PIN-8, e.g. on second GPIO 0x12 number 78 (hex 0x4e) with pull-down 0x00. The Pin number in DT-counting, can be found by `cat /sys/kernel/debug/gpio` and count zero based until the desired GPIO pin.
This LED is used as the powering indication instead of the default UART_Tx signal.

Decompile DT: found in boot folder in boot partition on SD card: `<SD-boot part>/boot/`

	dtc -I dtb -O dts <SD-boot part>/boot/meson64_bananapi_m5.dtb -o ~/tmp/meson64_bananapi_m5.dtb.dts

Edit DT source by adding LED:

	wittypwr {
		label = "wittypwr";
		gpios = <0x12 0x4e 0x00>;
		linux,default-trigger = "default-on";
	};

Compile DT:

	dtc -I dts -O ~/tmp/dtb meson64_bananapi_m5.dtb.dts -o <SD-boot part>/boot/meson64_bananapi_m5.dtb