@{
    Name = 'STC8H8K64U'
    Type = 'STC8H'
    FlashSize = '64KB'
    RamSize = '8KB'
    CrystalFreq = '24MHz'
    ReservedPins = @(24, 25, 36)
    ReservedDesc = @{
        24 = 'P3.0/RxD (默认串口接收)'
        25 = 'P3.1/TxD (默认串口发送)'
        36 = 'P5.4/RST (复位引脚)'
    }
    AvailablePins = @(
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
        16, 17, 18, 19, 20, 21, 22, 23, 26, 27, 28, 29, 30, 31,
        32, 33, 34, 35, 37, 38, 39
    )
    DefaultUart = 'COM6'
    Toolchain = 'Keil C51'
    ProjectExtension = '.uvproj'
}

