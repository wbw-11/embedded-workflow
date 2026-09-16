@{
    Name = 'ESP32-WROOM-32'
    Type = 'ESP32'
    FlashSize = '4MB'
    PsramSize = '0MB'
    CrystalFreq = '40MHz'
    ReservedPins = @(6, 7, 8, 9, 10, 11)
    ReservedDesc = @{
        6 = 'SPI Flash CLK'
        7 = 'SPI Flash D0'
        8 = 'SPI Flash D1'
        9 = 'SPI Flash D2'
        10 = 'SPI Flash D3'
        11 = 'SPI Flash CS'
    }
    AvailablePins = @(0, 1, 2, 3, 4, 5, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23, 25, 26, 27, 32, 33, 34, 35, 36, 37)
    DefaultUart = 'COM3'
    OpenOcdConfig = 'board/esp32-wroom-32.cfg'
    GdbTarget = 'xtensa-esp32-elf-gdb.exe'
}