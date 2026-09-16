@{
    Name = 'ESP32-S3-WROOM-1-N16R8'
    Type = 'ESP32-S3'
    FlashSize = '16MB'
    PsramSize = '8MB'
    CrystalFreq = '40MHz'
    ReservedPins = @(26, 27, 28, 29, 30, 31, 32, 33, 11, 12, 13, 14, 15, 16, 17)
    ReservedDesc = @{
        26 = 'SPI Flash CLK'
        27 = 'SPI Flash CS'
        28 = 'SPI Flash DIO'
        29 = 'SPI Flash DO'
        30 = 'SPI Flash DQS'
        31 = 'SPI Flash DATA1'
        32 = 'SPI Flash DATA2'
        33 = 'SPI Flash/PSRAM HD/hold'
        11 = 'SPI Flash CS0 (模组内部)'
        12 = 'SPI Flash D (模组内部)'
        13 = 'SPI Flash Q (模组内部)'
        14 = 'SPI Flash D0 (模组内部)'
        15 = 'SPI Flash D1 (模组内部)'
        16 = 'SPI Flash D2 (模组内部)'
        17 = 'SPI Flash D3 (模组内部)'
    }
    AvailablePins = @(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 18, 19, 20, 21, 22, 23, 24, 25, 35, 36, 37)
    DefaultUart = 'COM8'
    OpenOcdConfig = 'board/esp32s3-builtin.cfg'
    GdbTarget = 'xtensa-esp32s3-elf-gdb.exe'
}