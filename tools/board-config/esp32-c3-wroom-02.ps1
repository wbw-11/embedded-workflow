@{
    Name = 'ESP32-C3-WROOM-02'
    Type = 'ESP32-C3'
    FlashSize = '4MB'
    PsramSize = '0MB'
    CrystalFreq = '40MHz'
    ReservedPins = @(11, 12, 13, 14, 15, 16, 17, 18)
    ReservedDesc = @{
        11 = 'SPI Flash CS'
        12 = 'SPI Flash DIO'
        13 = 'SPI Flash DO'
        14 = 'SPI Flash CLK'
        15 = 'SPI Flash D3'
        16 = 'SPI Flash D2'
        17 = 'SPI Flash D1'
        18 = 'SPI Flash D0'
    }
    AvailablePins = @(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 19, 20, 21, 22, 23)
    DefaultUart = 'COM4'
    OpenOcdConfig = 'board/esp32c3-builtin.cfg'
    GdbTarget = 'riscv32-esp-elf-gdb.exe'
}